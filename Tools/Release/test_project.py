"""Offline checks of Development vs Release project settings. No build or launch."""
import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "Frisket.xcodeproj" / "project.pbxproj"
DEBUG_ID = "io.github.prateeksingh1092.frisket.debug"
RELEASE_ID = "io.github.prateeksingh1092.frisket"


def objects():
    result = subprocess.run(
        ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(PROJECT)],
        capture_output=True, text=True, timeout=30, check=True,
    )
    return json.loads(result.stdout)["objects"]


def configurations():
    found = {}
    for item in objects().values():
        if item.get("isa") != "XCBuildConfiguration":
            continue
        name = item["name"]
        settings = item.get("buildSettings", {})
        found.setdefault(name, []).append(settings)
    return found


class ReleaseProjectTests(unittest.TestCase):
    def test_development_follows_the_build_machine(self):
        rows = configurations()["Development"]
        self.assertTrue(rows)
        for settings in rows:
            if "ARCHS" in settings:
                self.assertEqual(settings["ARCHS"], "$(NATIVE_ARCH_64_BIT)")
                self.assertEqual(settings["ONLY_ACTIVE_ARCH"], "YES")
            if "PRODUCT_BUNDLE_IDENTIFIER" in settings:
                self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], DEBUG_ID)

    def test_release_is_universal_and_uses_the_production_identity(self):
        rows = configurations()["Release"]
        self.assertTrue(rows)
        project = settings_for_archs(rows)
        self.assertIn("x86_64", project["ARCHS"])
        self.assertIn("arm64", project["ARCHS"])
        self.assertEqual(project["ONLY_ACTIVE_ARCH"], "NO")
        identifiers = [s["PRODUCT_BUNDLE_IDENTIFIER"] for s in rows if "PRODUCT_BUNDLE_IDENTIFIER" in s]
        self.assertEqual(identifiers, [RELEASE_ID])


def settings_for_archs(rows):
    for settings in rows:
        if "ARCHS" in settings:
            return settings
    raise AssertionError("Release ARCHS missing")


if __name__ == "__main__":
    unittest.main()
