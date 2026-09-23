"""Offline tests for the C3 release label. Host commands are synthetic."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import label


class ReleaseLabelTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.app = Path(temporary.name) / "Frisket.app"
        self.app.mkdir()
        (self.app / "Contents/MacOS").mkdir(parents=True)
        (self.app / "Contents/MacOS/Frisket").write_bytes(b"")
        self.output = Path(temporary.name) / "label.json"
        self.host = {
            ("/usr/bin/lipo", "-archs", str(self.app / "Contents/MacOS/Frisket")): "x86_64 arm64\n",
            ("/usr/bin/codesign", "-dv", "--verbose=4", str(self.app)): (
                "Identifier=io.github.prateeksingh1092.frisket\n"
                "TeamIdentifier=9M43Q952NK\n"
                "CDHash=0123456789abcdef0123456789abcdef01234567\n"
            ),
        }

        def command(args, **kwargs):
            key = tuple(str(a) for a in args)
            if key not in self.host:
                raise AssertionError(f"Unexpected host command: {args}")
            return self.host[key]

        mock = patch("label.command", command)
        mock.start()
        self.addCleanup(mock.stop)

    def test_label_records_universal_signed_and_never_executed(self):
        document = label.write(self.app, self.output)
        self.assertEqual(document["label"], "arm64 built and signed, never executed")
        self.assertEqual(document["architectures"], ["arm64", "x86_64"])
        self.assertEqual(document["identifier"], "io.github.prateeksingh1092.frisket")
        self.assertEqual(document["team"], "9M43Q952NK")
        self.assertIs(document["distributed"], False)
        self.assertIs(document["arm64_executed"], False)
        self.assertEqual(json.loads(self.output.read_text()), document)

    def test_label_rejects_a_native_only_binary_and_the_debug_identity(self):
        self.host[("/usr/bin/lipo", "-archs", str(self.app / "Contents/MacOS/Frisket"))] = "x86_64\n"
        with self.assertRaisesRegex(ValueError, "universal"):
            label.write(self.app, self.output)
        self.host[("/usr/bin/lipo", "-archs", str(self.app / "Contents/MacOS/Frisket"))] = "x86_64 arm64\n"
        self.host[("/usr/bin/codesign", "-dv", "--verbose=4", str(self.app))] = (
            "Identifier=io.github.prateeksingh1092.frisket.debug\n"
            "TeamIdentifier=9M43Q952NK\n"
            "CDHash=0123456789abcdef0123456789abcdef01234567\n"
        )
        with self.assertRaisesRegex(ValueError, "identity"):
            label.write(self.app, self.output)

    def test_label_refuses_install_or_launch(self):
        with self.assertRaisesRegex(ValueError, "install"):
            label.write(self.app, self.output, install=True)
        with self.assertRaisesRegex(ValueError, "launch"):
            label.write(self.app, self.output, launch=True)


if __name__ == "__main__":
    unittest.main()
