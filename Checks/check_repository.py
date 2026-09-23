"""Offline repository checks. Invoked by Swift Testing; also usable without its runner."""

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import unicodedata


def dependency_issues(manifest, resolved=None):
    approved_urls = {"https://github.com/groue/GRDB.swift", "https://github.com/groue/GRDB.swift.git"}
    issues = []
    for dependency in manifest["dependencies"]:
        sources = dependency.get("sourceControl", [])
        approved = False
        if len(sources) == 1 and set(dependency) == {"sourceControl"}:
            source = sources[0]
            remote = source.get("location", {}).get("remote", [])
            approved = (source.get("identity") == "grdb.swift" and len(remote) == 1
                        and remote[0].get("urlString") in approved_urls)
        if not approved:
            issues.append("dependency is not the approved GRDB source")
    for target in manifest.get("targets", []):
        if target.get("type") in {"binary", "system", "plugin", "macro"}:
            issues.append("non-core dependency target: " + target["name"])
    if resolved is not None:
        if resolved.get("version") not in {2, 3}:
            issues.append("unsupported dependency lockfile version")
        else:
            for pin in resolved["pins"]:
                if (pin.get("identity") != "grdb.swift" or pin.get("kind") != "remoteSourceControl"
                        or pin.get("location") not in approved_urls):
                    issues.append("resolved dependency is not the approved GRDB source")
    return issues


def swift_code(text):
    """Mask comments/string text, keeping executable interpolation expressions."""
    string_start = re.compile(r'(#+)?("""|")')

    def scan(i, interpolation=False):
        output = []
        depth = 1
        while i < len(text):
            if interpolation:
                if text[i] == "(":
                    depth += 1
                elif text[i] == ")":
                    depth -= 1
                    if depth == 0:
                        return "".join(output), i + 1
            if text.startswith("//", i):
                end = text.find("\n", i)
                i = len(text) if end < 0 else end
                output.append(" ")
            elif text.startswith("/*", i):
                i += 2
                comment_depth = 1
                while i < len(text) and comment_depth:
                    if text.startswith("/*", i):
                        comment_depth += 1
                        i += 2
                    elif text.startswith("*/", i):
                        comment_depth -= 1
                        i += 2
                    else:
                        i += 1
                output.append(" ")
            else:
                string = string_start.match(text, i)
                if not string:
                    output.append(text[i])
                    i += 1
                    continue
                hashes, quote = string.group(1) or "", string.group(2)
                i = string.end()
                output.append(" ")
                while i < len(text):
                    if text.startswith("\\" + hashes + "(", i):
                        expression, i = scan(i + len(hashes) + 2, interpolation=True)
                        output.extend((" ", expression, " "))
                    elif text.startswith("\\" + hashes, i):
                        i += len(hashes) + 2
                    elif text.startswith(quote + hashes, i):
                        i += len(quote + hashes)
                        break
                    else:
                        i += 1
                output.append(" ")
        return "".join(output), i

    return scan(0)[0]


def import_issues(files):
    issues = []
    for path, text in sorted(files.items()):
        if not path.startswith("Sources/") or not path.endswith(".swift"):
            continue
        code = swift_code(text).replace("`", "")
        imports = re.findall(r'\bimport\s+(?:(?:struct|class|enum|protocol|typealias|func|var|let)\s+)?(\w+)', code)
        storage_adapter = path.startswith("Sources/FrisketCore/StorageAdapter/")
        for module in imports:
            if module in {"AppKit", "SwiftUI"} or (
                module == "GRDB" and not storage_adapter
            ):
                issues.append(f"{path}: forbidden import {module}")
        if not storage_adapter and "GRDB" not in imports and re.search(r'\bGRDB\s*\.', code):
            issues.append(f"{path}: concrete GRDB reference outside storage adapter")
    return issues


def upstream_identity(text):
    normalized = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().casefold()
    normalized = " ".join(normalized.split())
    return any(name in normalized for name in ("snapzy", "trong duong duc", "duong duc trong", "duongductrong"))


def licence_header(text):
    leading = re.match(r'\s*(?:(?://[^\n]*(?:\n|$)|/\*[\s\S]*?\*/)\s*)+', text)
    header = leading.group() if leading else ""
    if "copyright" in header.casefold() and any(
        marker in header.casefold() for marker in (
            "spdx-license-identifier:", "redistribution and use", "permission is hereby granted"
        )
    ):
        return header
    return ""


def is_notice(path):
    return pathlib.PurePosixPath(path).name in {
        "LICENSE", "LICENSE.txt", "NOTICE", "NOTICE.txt", "THIRD-PARTY-NOTICES.md"
    }


def identity_issues(files):
    issues = []
    for path, text in sorted(files.items()):
        if is_notice(path):
            continue
        body = text[len(licence_header(text)):]
        if upstream_identity(path) or upstream_identity(body):
            issues.append(f"{path}: upstream identity outside a licence header or notice")
    return issues


def provenance_issues(files, entries):
    issues = []
    registered = set()
    for entry in entries:
        path = entry["path"]
        if path in registered:
            issues.append(f"{path}: duplicate provenance entry")
        registered.add(path)
        if path not in files:
            issues.append(f"{path}: provenance file is missing")
            continue
        if (not re.fullmatch(r'https://[^\s]+', entry.get("upstreamURL", ""))
                or not re.fullmatch(r'[0-9a-f]{40}', entry.get("revision", ""))
                or not entry.get("originalPath")):
            issues.append(f"{path}: incomplete provenance")
        header = entry.get("licenseHeader", "")
        if not licence_header(header) or not files[path].startswith(header):
            issues.append(f"{path}: original licence header missing or changed")
    for path, text in sorted(files.items()):
        if is_notice(path):
            continue
        if (upstream_identity(licence_header(text)) or "Frisket-Port:" in text) and path not in registered:
            issues.append(f"{path}: port has no provenance entry")
    return issues


def check_fixture(path):
    fixture = json.loads(path.read_text())
    if fixture["check"] == "dependencies":
        actual = dependency_issues(fixture["manifest"], fixture.get("resolved"))
    elif fixture["check"] == "imports":
        actual = import_issues(fixture["files"])
    elif fixture["check"] == "identity":
        actual = identity_issues(fixture["files"])
    elif fixture["check"] == "provenance":
        actual = provenance_issues(fixture["files"], fixture["entries"])
    else:
        raise ValueError("unknown fixture check")
    if actual != fixture["expected"]:
        raise ValueError(f"{path.name}: expected {fixture['expected']!r}; got {actual!r}")


def product_files(root):
    # Planning/reference material and checker fixtures are not product inputs.
    # Tests are included for port attribution, but excluded from identity scrub.
    paths = [root / "Package.swift"]
    for directory in ("Sources", "Frisket", "Resources", "Tests"):
        folder = root / directory
        if folder.exists():
            paths.extend(sorted(path for path in folder.rglob("*") if path.is_file()))
    files = {}
    for path in paths:
        if path.is_symlink():
            raise ValueError(f"product symlink must be reviewed: {path.relative_to(root)}")
        # Binary assets still have their paths and embedded ASCII identity scanned.
        files[path.relative_to(root).as_posix()] = path.read_bytes().decode("utf-8", errors="replace")
    return files


def dumped_manifest(root):
    scratch = root / ".build" / "repository-checks"
    environment = dict(os.environ, DEVELOPER_DIR="/Library/Developer/CommandLineTools")
    environment["CLANG_MODULE_CACHE_PATH"] = str(root / ".build" / "clang-cache")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(root / ".build" / "module-cache")
    command = [
        "/Library/Developer/CommandLineTools/usr/bin/swift", "package", "--package-path", str(root),
        "--disable-sandbox", "--disable-keychain", "--disable-netrc",
        "--cache-path", str(root / ".build" / "cache"),
        "--scratch-path", str(scratch), "--config-path", str(root / ".build" / "config"),
        "--security-path", str(root / ".build" / "security"), "dump-package"
    ]
    # dump-package evaluates the local manifest; it neither resolves nor fetches dependencies.
    result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise ValueError(result.stderr.strip())
    return json.loads(result.stdout)


def repository_issues(root, check):
    if check == "dependencies":
        lockfile = root / "Package.resolved"
        resolved = json.loads(lockfile.read_text()) if lockfile.exists() else None
        return dependency_issues(dumped_manifest(root), resolved)
    files = product_files(root)
    if check == "imports":
        return import_issues(files)
    if check == "identity":
        return identity_issues({path: text for path, text in files.items() if not path.startswith("Tests/")})
    entries = json.loads((root / "docs" / "ported-files.json").read_text())
    return provenance_issues(files, entries)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--fixture", type=pathlib.Path)
    mode.add_argument("--root", type=pathlib.Path)
    parser.add_argument("--check", choices=["dependencies", "imports", "identity", "provenance"])
    args = parser.parse_args()
    try:
        if args.fixture:
            check_fixture(args.fixture)
        else:
            if not args.check:
                parser.error("--root requires --check")
            issues = repository_issues(args.root.resolve(), args.check)
            if issues:
                raise ValueError("\n".join(issues))
    except (ValueError, KeyError, TypeError, OSError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
