"""Offline orchestration tests with synthetic host commands, clocks and operator input."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import measure


class MeasurementTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.args = SimpleNamespace(log=Path(temporary.name) / "app.jsonl",
                                    output=Path(temporary.name) / "result.json")
        self.mono = self.wall = 0
        self.armed = 0
        self.on_sleep = lambda: None
        self.on_armed = lambda: self.append_row(self.armed)
        for target, replacement in (
            ("measure.time.monotonic", lambda: self.mono),
            ("measure.time.time", lambda: self.wall),
            ("measure.time.sleep", self.sleep),
            ("measure.subprocess.check_output", self.host_command),
            ("builtins.input", lambda prompt: ""),
            ("builtins.print", self.operator_output),
        ):
            mock = patch(target, replacement)
            mock.start()
            self.addCleanup(mock.stop)

    def sleep(self, seconds):
        self.mono += seconds
        self.wall += seconds
        self.on_sleep()

    def host_command(self, args, **kwargs):
        if args[0] == "/usr/bin/pmset":
            return "Now drawing from 'AC Power'" if args[-1] == "batt" else "No thermal warning"
        if args[-1] == "thermal":
            return '{"thermal_state": 0}'
        if args[0] == "/usr/sbin/system_profiler":
            return '{}'
        if args[0] == "/usr/bin/sw_vers":
            return "25G229"
        raise AssertionError(f"Unexpected host command: {args}")

    def operator_output(self, message, **kwargs):
        if message.startswith("ARMED:"):
            self.armed += 1
            self.on_armed()

    def append_row(self, run, newline=True):
        with self.args.log.open("a") as log:
            log.write(json.dumps(dict(run=run, start_ns=100, end_ns=1000100)))
            if newline:
                log.write("\n")

    def test_app_latency_rejects_capture_written_during_cooldown(self):
        def premature_capture():
            if not self.args.log.exists():
                self.append_row(1)

        self.on_sleep = premature_capture
        self.on_armed = lambda: None
        with self.assertRaisesRegex(ValueError, "before ARMED"):
            measure.app_latency(self.args)
        record = json.loads(self.args.output.read_text())
        self.assertEqual(record["status"], "partial")
        self.assertEqual(record["runs"], [])

    def test_app_latency_rejects_partial_next_capture_before_arming(self):
        def capture_with_premature_next_row():
            self.append_row(self.armed)
            self.append_row(self.armed + 1, newline=False)

        self.on_armed = capture_with_premature_next_row
        with self.assertRaisesRegex(ValueError, "before ARMED"):
            measure.app_latency(self.args)
        self.assertEqual(self.armed, 1)
        self.assertEqual(len(json.loads(self.args.output.read_text())["runs"]), 1)

    def test_cooldown_rejects_stalls_and_wall_clock_discontinuities(self):
        for mono_jump, wall_jump in ((300, 300), (0, 300), (0, -300)):
            with self.subTest(mono_jump=mono_jump, wall_jump=wall_jump):
                self.mono = self.wall = 0

                def jump():
                    self.mono += mono_jump
                    self.wall += wall_jump

                self.on_sleep = jump
                with self.assertRaisesRegex(ValueError, "stalled sampler"):
                    measure.cool_down()

    def test_app_latency_rejects_boolean_run_before_accepting_any_capture(self):
        self.on_armed = lambda: self.append_row(True)
        with self.assertRaisesRegex(ValueError, "run numbers"):
            measure.app_latency(self.args)
        self.assertEqual(self.armed, 1)
        self.assertEqual(json.loads(self.args.output.read_text())["runs"], [])

    def test_app_latency_completes_twenty_captures_after_continuous_cooldowns(self):
        measure.app_latency(self.args)
        record = json.loads(self.args.output.read_text())
        self.assertEqual(record["status"], "complete")
        self.assertEqual(len(record["runs"]), 20)
        self.assertEqual(self.mono, 6000)
        self.assertEqual(record["runs"][-1]["interval"],
                         dict(start_low_ns=100, start_high_ns=100,
                              end_low_ns=1000100, end_high_ns=1000100))

    def test_cooldown_rejects_a_stalled_final_condition_probe(self):
        def stalled_command(args, **kwargs):
            if args[-1] == "thermal" and self.mono >= 300:
                self.mono += 30
                self.wall += 30
            return self.host_command(args, **kwargs)

        with patch("measure.subprocess.check_output", stalled_command):
            with self.assertRaisesRegex(ValueError, "stalled sampler"):
                measure.cool_down()


if __name__ == "__main__":
    unittest.main()
