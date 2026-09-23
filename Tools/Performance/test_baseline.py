"""Offline tests at the ticket-37 parsing/statistics/conditions/report seams."""
import json
import unittest

import baseline


class BaselineTests(unittest.TestCase):
    def test_gpu_parser_distinguishes_scanout_from_render_gpu_and_drops_serials(self):
        source = {"SPDisplaysDataType": [
            {"sppci_model": "Intel UHD Graphics 630", "spdisplays_ndrvs":
             [{"_name": "Color LCD", "_spdisplays_display-serial-number": "CANARY"}]},
            {"sppci_model": "AMD Radeon Pro 5500M"}]}
        parsed = baseline.parse_gpu(json.dumps(source))
        self.assertEqual(parsed, "Intel UHD Graphics 630 (1 attached displays); AMD Radeon Pro 5500M (0 attached displays); render GPU unconfirmed")
        self.assertNotIn("CANARY", parsed)
        self.assertEqual(baseline.parse_gpu('{}'), "GPU inventory unavailable; render GPU unconfirmed")

    def test_report_formats_known_metrics_marks_dry_run_and_drops_private_metadata(self):
        metadata = dict(date="2026-09-23T12:00:00Z", os_build="25G229",
                        architecture="x86_64", tool="macos", private_title="CANARY",
                        gpu="unknown", low_power_confirmed=False)
        idle = dict(seconds=600, cpu_percent_one_core=0.5,
                    package_wakeups_per_second=0.1, interrupt_wakeups_per_second=0.2,
                    footprint_end_bytes=2097152, footprint_peak_sampled_bytes=3145728)
        interval = dict(start_low_ns=0, start_high_ns=10000000,
                        end_low_ns=100000000, end_high_ns=110000000)
        report = baseline.format_report(metadata, [idle] * 20, [interval] * 20,
                                        "external-window", dry_run=True)
        self.assertIn("DRY RUN — synthetic counters, not a baseline", report)
        self.assertIn("25G229", report)
        self.assertIn("x86_64", report)
        self.assertIn("2026-09-23", report)
        self.assertIn("| cpu_percent_one_core | 0.5 | 0.5 |", report)
        self.assertIn("±10.000 ms", report)
        self.assertIn("low-power GPU unconfirmed", report)
        self.assertNotIn("CANARY", report)
        self.assertIn("arm64 not executed", report)
        with self.assertRaises(ValueError):
            baseline.format_report(metadata, [idle] * 19, [interval] * 20, "external-window")

    def test_latency_intervals_and_frisket_log_parser_preserve_clock_uncertainty(self):
        external = dict(start_low_ns=10000000, start_high_ns=20000000,
                        end_low_ns=110000000, end_high_ns=120000000)
        self.assertEqual(baseline.latency_metrics(external),
                         {"low_ms": 90, "high_ms": 110, "mid_ms": 100, "error_ms": 10})
        lines = '\n'.join(json.dumps(dict(run=i, start_ns=100, end_ns=1000100))
                          for i in range(1, 21))
        self.assertEqual(baseline.parse_app_log(lines)[0],
                         {"start_low_ns": 100, "start_high_ns": 100,
                          "end_low_ns": 1000100, "end_high_ns": 1000100})
        for bad in (dict(external, start_low_ns=30000000),
                    dict(external, end_high_ns=5000000)):
            with self.assertRaises(ValueError):
                baseline.latency_metrics(bad)
        for bad in (lines + '\n' + lines, '{}', lines.replace('"run": 1,', '"image": 1,')):
            with self.assertRaises(ValueError):
                baseline.parse_app_log(bad)

    def test_idle_uses_cpu_time_delta_and_rejects_restart_short_or_reset_counters(self):
        start = dict(pid=42, identity=100, monotonic_ns=1000000000,
                     cpu_ns=1000000000, package_wakeups=10, interrupt_wakeups=20,
                     phys_footprint=1048576)
        end = dict(start, monotonic_ns=601000000000, cpu_ns=4000000000,
                   package_wakeups=70, interrupt_wakeups=140, phys_footprint=2097152)
        result = baseline.idle_metrics([start, end])
        self.assertEqual(result, {"seconds": 600, "cpu_percent_one_core": 0.5,
                                 "package_wakeups_per_second": 0.1,
                                 "interrupt_wakeups_per_second": 0.2,
                                 "footprint_end_bytes": 2097152,
                                 "footprint_peak_sampled_bytes": 2097152})
        for bad in (dict(end, identity=101), dict(end, monotonic_ns=2000000000),
                    dict(end, cpu_ns=0), dict(end, package_wakeups=0)):
            with self.assertRaises(ValueError):
                baseline.idle_metrics([start, bad])

    def test_conditions_fail_closed_for_battery_thermal_unknown_and_short_cooldown(self):
        good = "Now drawing from 'AC Power'\n -InternalBattery-0 100%; charged"
        speed = "CPU_Speed_Limit = 100\nCPU_Scheduler_Limit = 100"
        self.assertEqual(baseline.condition_issues(good, speed, 0, 300), [])
        for power, thermal, state, cooldown in (
            ("Now drawing from 'Battery Power'", speed, 0, 300),
            ("", speed, 0, 300), (good, speed, 1, 300),
            (good, speed, 99, 300), (good, speed, 0, 299),
            (good, "CPU_Speed_Limit = 80", 0, 300),
            (good, "CPU_Speed_Limit = unknown", 0, 300)):
            self.assertTrue(baseline.condition_issues(power, thermal, state, cooldown))
        self.assertEqual(baseline.condition_issues(good, "No thermal warning", 0, 300), [])

    def test_statistics_use_median_and_nearest_rank_p95_with_twenty_runs(self):
        self.assertEqual(baseline.statistics(list(range(1, 21))),
                         {"count": 20, "median": 10.5, "p95": 19})
        for bad in ([], [1] * 19, [1] * 21, [float("nan")] * 20, [-1] * 20):
            with self.assertRaises(ValueError):
                baseline.statistics(bad)

    def test_sample_parser_accepts_counters_and_rejects_missing_negative_or_pixels(self):
        sample = dict(pid=42, identity=100, monotonic_ns=1000000000,
                      cpu_ns=4000000, package_wakeups=3, interrupt_wakeups=7,
                      phys_footprint=4096)
        self.assertEqual(baseline.parse_sample(json.dumps(sample)), sample)
        for bad in ({}, dict(sample, cpu_ns=-1), dict(sample, image="private"),
                    dict(sample, pid=True)):
            with self.assertRaises(ValueError):
                baseline.parse_sample(json.dumps(bad))


if __name__ == "__main__":
    unittest.main()
