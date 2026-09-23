"""Offline first-run record tests. Host commands, clocks and files are synthetic."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import record


class FirstRunRecordTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.output = Path(temporary.name) / "record.json"
        self.app = Path(temporary.name) / "Frisket.app"
        self.app.mkdir()
        self.host = {
            ("/usr/bin/sw_vers", "-productVersion"): "26.7\n",
            ("/usr/bin/sw_vers", "-buildVersion"): "25G229\n",
            ("/usr/bin/uname", "-m"): "x86_64\n",
            ("/usr/bin/git", "-C", "/repo", "rev-parse", "HEAD"): "a" * 40 + "\n",
            ("/usr/bin/lipo", "-archs", str(self.app)): "x86_64\n",
            ("/usr/bin/codesign", "-dv", "--verbose=4", str(self.app)): (
                "Identifier=io.github.prateeksingh1092.frisket.debug\n"
                "TeamIdentifier=9M43Q952NK\n"
                "CDHash=0123456789abcdef0123456789abcdef01234567\n"
            ),
            ("/usr/sbin/system_profiler", "SPDisplaysDataType", "-json"): json.dumps({
                "SPDisplaysDataType": [{
                    "sppci_model": "Intel Iris Plus Graphics",
                    "spdisplays_ndrvs": [{
                        "_name": "Color LCD",
                        "_spdisplays_pixels": "2880 x 1800",
                        "spdisplays_resolution": "1440 x 900 @ 60 Hz",
                        "_spdisplays_display-serial-number": "SECRET123",
                        "spdisplays_main": "spdisplays_yes",
                        "_spdisplays_display-origin": "(-1920, 0)",
                    }]
                }]
            }) + "\n",
        }

        def command(args, **kwargs):
            key = tuple(str(a) for a in args)
            if key not in self.host:
                raise AssertionError(f"Unexpected host command: {args}")
            return self.host[key]

        mock = patch("record.command", command)
        mock.start()
        self.addCleanup(mock.stop)
        mock = patch("record.utc", lambda: "2026-09-23T14:00:00+00:00")
        mock.start()
        self.addCleanup(mock.stop)

    def header(self, permission="granted"):
        return record.header(app=self.app, permission=permission, output=self.output,
                             repository=Path("/repo"))

    def test_header_records_required_fields_and_no_serial_or_pixels(self):
        document = self.header()
        self.assertEqual(document["schema"], 1)
        self.assertEqual(document["kind"], "first-run")
        self.assertEqual(document["date"], "2026-09-23T14:00:00+00:00")
        self.assertEqual(document["os_product"], "26.7")
        self.assertEqual(document["os_build"], "25G229")
        self.assertEqual(document["commit"], "a" * 40)
        self.assertEqual(document["architecture"], "x86_64")
        self.assertEqual(document["architectures"], ["x86_64"])
        self.assertIs(document["arm64_executed"], False)
        self.assertEqual(document["permission_state"], "granted")
        self.assertEqual(document["signature"], {
            "identifier": "io.github.prateeksingh1092.frisket.debug",
            "team": "9M43Q952NK",
            "cdhash": "0123456789abcdef0123456789abcdef01234567",
        })
        self.assertEqual(document["pattern"], {
            "width_points": 320,
            "height_points": 180,
            "placement": "display-center",
            "verify": "FrisketTestPattern --verify PATH SCALE",
        })
        display = document["display_layout"][0]
        self.assertEqual(display["index"], 0)
        self.assertEqual(display["pixel_width"], 2880)
        self.assertEqual(display["pixel_height"], 1800)
        self.assertEqual(display["point_width"], 1440)
        self.assertEqual(display["point_height"], 900)
        self.assertEqual(display["origin_x"], -1920)
        self.assertEqual(display["origin_y"], 0)
        self.assertIs(display["retina"], True)
        self.assertNotIn("serial", json.dumps(document))
        self.assertNotIn("SECRET123", json.dumps(document))
        self.assertNotIn("png", json.dumps(document).lower())
        self.assertEqual(set(document["cases"]), set(record.CASES))
        self.assertTrue(all(result == "pending" for result in document["cases"].values()))
        self.assertEqual(document["status"], "partial")
        self.assertEqual(json.loads(self.output.read_text()), document)

    def test_header_rejects_unknown_permission_and_bad_commit(self):
        with self.assertRaisesRegex(ValueError, "permission"):
            self.header(permission="maybe")
        self.host[("/usr/bin/git", "-C", "/repo", "rev-parse", "HEAD")] = "not-a-commit\n"
        with self.assertRaisesRegex(ValueError, "commit"):
            self.header()

    def test_case_accepts_closed_results_and_rejects_free_text(self):
        self.header()
        document = record.case(self.output, "esc-without-activation", "pass")
        self.assertEqual(document["cases"]["esc-without-activation"], "pass")
        with self.assertRaisesRegex(ValueError, "case"):
            record.case(self.output, "invented-case", "pass")
        with self.assertRaisesRegex(ValueError, "result"):
            record.case(self.output, "esc-without-activation", "looks good")
        with self.assertRaisesRegex(ValueError, "note"):
            record.case(self.output, "esc-without-activation", "pass", note="copied CANARY")

    def test_finish_requires_every_case_and_refuses_image_bytes(self):
        self.header()
        with self.assertRaisesRegex(ValueError, "pending"):
            record.finish(self.output)
        for name in record.CASES:
            record.case(self.output, name, "pass")
        document = record.finish(self.output)
        self.assertEqual(document["status"], "complete")
        polluted = json.loads(self.output.read_text())
        polluted["smuggled"] = "\x89PNG\r\n\x1a\n"
        self.output.write_text(json.dumps(polluted))
        with self.assertRaisesRegex(ValueError, "pixels"):
            record.finish(self.output)


if __name__ == "__main__":
    unittest.main()
