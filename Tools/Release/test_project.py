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


class BuildGraphTests(unittest.TestCase):
    """Ticket 42: the app and the package tests compile the core from one graph."""

    def test_app_links_the_package_core_product_and_compiles_no_core_copy(self):
        items = objects()
        targets = [item for item in items.values() if item.get("isa") == "PBXNativeTarget"]
        self.assertEqual([target["name"] for target in targets], ["Frisket"])
        products = [items[ref]["productName"] for ref in targets[0].get("packageProductDependencies", [])]
        self.assertEqual(products, ["FrisketCore"])
        packages = [item for item in items.values() if "SwiftPackageReference" in item.get("isa", "")]
        self.assertEqual([(p["isa"], p.get("relativePath")) for p in packages],
                         [("XCLocalSwiftPackageReference", ".")])
        folders = [item.get("path") for item in items.values()
                   if item.get("isa") == "PBXFileSystemSynchronizedRootGroup"]
        self.assertNotIn("Sources/FrisketCore", folders)

    def test_sdk_follows_xcode_and_signing_identity_is_not_tracked(self):
        for name, rows in configurations().items():
            for settings in rows:
                if "SDKROOT" in settings:
                    self.assertEqual(settings["SDKROOT"], "macosx", name)
                for key in ("DEVELOPMENT_TEAM", "CODE_SIGN_IDENTITY", "CODE_SIGN_STYLE", "OTHER_LDFLAGS"):
                    self.assertNotIn(key, settings, f"{name}: {key} belongs in Config/*.xcconfig or the package")
        base = (ROOT / "Config" / "Frisket.xcconfig").read_text()
        self.assertIn("CODE_SIGN_IDENTITY = -", base)
        self.assertIn('#include? "Signing.xcconfig"', base)
        ignored = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "-q", "Config/Signing.xcconfig"])
        self.assertEqual(ignored.returncode, 0, "Config/Signing.xcconfig must stay untracked")

    def test_repository_checks_run_from_ci_not_from_every_build(self):
        items = objects()
        scripts = [item.get("shellScript", "") for item in items.values()
                   if item.get("isa") == "PBXShellScriptBuildPhase"]
        self.assertFalse([s for s in scripts if "check_repository.py" in s])
        self.assertIn("input-monitoring", (ROOT / "scripts" / "ci.sh").read_text())

    def test_one_package_resolved(self):
        workspace = PROJECT.parent / "project.xcworkspace" / "xcshareddata" / "swiftpm" / "Package.resolved"
        self.assertTrue(workspace.is_symlink())
        self.assertEqual(workspace.resolve(), (ROOT / "Package.resolved").resolve())


def settings_for_archs(rows):
    for settings in rows:
        if "ARCHS" in settings:
            return settings
    raise AssertionError("Release ARCHS missing")


if __name__ == "__main__":
    unittest.main()
