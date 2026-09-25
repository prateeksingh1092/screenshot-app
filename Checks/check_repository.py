"""Frisket's repository checks (ticket 80), run by scripts/ci.sh.

The six named invariants (plan O12), plus the rules CLAUDE.md and ticket 77 rely on:

  finalization      (1) `AuthorizedFinalization` is built only by the coordinator
  app-writes        (2) the app writes nothing outside finalization
  storage-pixels    (3) storage never receives original pixels
  core-io           (4) the core does no disk I/O and imports only its allowlist
  input-monitoring  (5) no event taps or global monitors
  network           (6) no network APIs
  app-sources       (ticket 77) the app target compiles no adapter source

`--root DIR` runs every check (or those named by `--check`); `--self-test` runs every fixture
in Checks/Fixtures and requires each check to have a passing and a failing one.
The checks are lexical: comments and string literals are masked before matching.
"""

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

COORDINATOR = "Sources/FrisketCore/CaptureLifecycleCoordinator.swift"
STORAGE = "Sources/FrisketCore/StorageAdapter/"
# DA-1 (decision 57): the core may render with these frameworks, in memory only.
CORE_IMPORTS = {"Foundation", "Synchronization", "CoreGraphics", "CoreText", "ImageIO", "Accelerate"}
# The storage adapter is the one part of the core that touches disk, after finalization.
STORAGE_IMPORTS = CORE_IMPORTS | {"GRDB", "Darwin"}
WRITE_ROUTES = (r'\b(?:createDirectory|createFile|removeItem|FileHandle|OutputStream|fopen|open|openat|mkdir|unlink|rename)\b'
                r'|\.\s*write\s*\(\s*to\s*:')
IMPORT = r'\bimport\s+(?:(?:struct|class|enum|protocol|typealias|func|var|let)\s+)?(\w+)'


def swift_code(text):
    """Mask comments and string text, keeping executable interpolation expressions."""
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


def product_code(files, prefixes=("Sources/", "Frisket/")):
    for path, text in sorted(files.items()):
        if path.startswith(prefixes) and path.endswith(".swift"):
            yield path, swift_code(text).replace("`", "")


def finalization_issues(files):
    """(1) Only the coordinator constructs the capability that lets storage persist a capture."""
    return [f"{path}: AuthorizedFinalization is built outside the coordinator"
            for path, code in product_code(files)
            if path != COORDINATOR and re.search(r'\bAuthorizedFinalization\s*\(', code)]


def app_write_issues(files):
    """(2) The app has no filesystem write route; storage writes only through finalization."""
    issues = []
    for path, code in product_code(files, ("Frisket/",)):
        # Recovery opens Settings and sends the relaunch helper's I/O to /dev/null.
        code = re.sub(r'\bNSWorkspace\s*\.\s*shared\s*\.\s*open\b', 'workspaceLaunch', code)
        code = re.sub(r'\bFileHandle\s*\.\s*nullDevice\b', 'nullDeviceHandle', code)
        # Ticket 38's opt-in latency rows go to inherited stdout, never to a file.
        if path == "Frisket/Adapters/CaptureLatencyLog.swift":
            code = re.sub(r'\bFileHandle\s*\.\s*standardOutput\b', 'latencyOutput', code)
        if re.search(WRITE_ROUTES, code):
            issues.append(f"{path}: app filesystem write outside authorized finalization")
    return issues


def storage_pixel_issues(files):
    """(3) Storage accepts only finalized, redacted images, never the source or an original."""
    return [f"{path}: storage accepts source or original pixels"
            for path, code in product_code(files, (STORAGE,))
            if re.search(r'\b(?:CapturePixelSource|CaptureImage|original\w*|unredacted\w*)\b', code, re.I)]


def core_io_issues(files):
    """(4) The core imports only its allowlist; outside the storage adapter it has no file route."""
    issues = []
    disk_symbols = (r'\b(?:URL|NSURL|FileManager|FileHandle|OutputStream|InputStream|UserDefaults|Process|Bundle'
                    r'|NSFileCoordinator|StorageAdapter|GRDB|Darwin|Glibc|POSIX|fopen|freopen|open|openat|creat'
                    r'|fwrite|pwrite|writev|unlink|rename|mkdir|mmap)\b')
    file_routes = r'\b(?:CG|CT|CF)\w*(?:URL|Filename)\w*|\burl\s*:|\.\s*write\s*\(\s*to\s*:'
    for path, code in product_code(files, ("Sources/",)):
        storage = path.startswith(STORAGE)
        allowed = STORAGE_IMPORTS if storage else CORE_IMPORTS
        for module in re.findall(IMPORT, code):
            if module not in allowed:
                issues.append(f"{path}: forbidden import {module}")
        if not storage and (re.search(disk_symbols, code) or re.search(file_routes, code)):
            issues.append(f"{path}: filesystem capability in the memory-only core")
    return issues


def input_monitoring_issues(files):
    """(5) Hot keys use Carbon registration; nothing observes other apps' input."""
    pattern = r'\b(?:CGEventTap\w*|CGEvent\s*\.\s*tap\w*|tapCreate\w*|tapEnable|tapIsEnabled|addGlobalMonitorForEvents\w*)\b'
    return [f"{path}: event tap or global event monitor is forbidden"
            for path, code in product_code(files) if re.search(pattern, code)]


def network_issues(files):
    """(6) Spec story 74: Frisket makes no network connections."""
    modules = {"Network", "CFNetwork", "NetworkExtension", "WebKit", "MultipeerConnectivity", "CloudKit"}
    symbols = (r'\b(?:URLSession\w*|NSURLSession\w*|NSURLConnection|NSURLDownload|NW(?:Connection|Listener|Browser|PathMonitor|Endpoint)\w*'
               r'|CFSocket\w*|CFStreamCreatePairWithSocket\w*|CFHTTPMessage\w*|SCNetworkReachability\w*|WKWebView'
               r'|getStreamsToHost\w*)\b'
               r'|(?<![\w.])(?:socket|connect|sendto|recvfrom|getaddrinfo|gethostbyname)\s*\(')
    issues = []
    for path, code in product_code(files):
        # A declaration such as `func connect(_:)` is not a call to POSIX connect(2).
        calls = re.sub(r'\bfunc\s+\w+', 'func _', code)
        if any(module in modules for module in re.findall(IMPORT, code)) or re.search(symbols, calls):
            issues.append(f"{path}: network API is forbidden")
    return issues


def app_source_issues(root):
    """Ticket 77: the app links FrisketAdapters and compiles no adapter file itself."""
    project_path = root / "Frisket.xcodeproj" / "project.pbxproj"
    result = subprocess.run(["/usr/bin/plutil", "-convert", "json", "-o", "-", str(project_path)],
                            capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise ValueError(result.stderr.strip() or result.stdout.strip())
    project = json.loads(result.stdout)
    objects = project["objects"]
    paths = set()

    def visit(identifier, parent, ancestors):
        if identifier in ancestors:
            raise ValueError("cyclic project group")
        item = objects[identifier]
        tree = item.get("sourceTree", "<group>")
        if tree not in {"<group>", "SOURCE_ROOT"}:
            return
        base = pathlib.PurePosixPath() if tree == "SOURCE_ROOT" else parent
        path = pathlib.PurePosixPath(os.path.normpath(base / item.get("path", "")))
        if item["isa"] == "PBXFileReference" and path.parts[:1] == ("Frisket",) and path.suffix == ".swift":
            paths.add(path.as_posix())
        for child in item.get("children", []):
            visit(child, path, ancestors | {identifier})

    visit(objects[project["rootObject"]]["mainGroup"], pathlib.PurePosixPath(), set())
    issues = [f"{path}: explicit app-source reference; use the synchronized Frisket folder" for path in sorted(paths)]
    for identifier, item in sorted(objects.items()):
        if item.get("isa") != "PBXFileSystemSynchronizedRootGroup" or item.get("path") != "Frisket":
            continue
        for target_id, target in sorted(objects.items()):
            if target.get("isa") != "PBXNativeTarget" or identifier not in target.get("fileSystemSynchronizedGroups", []):
                continue
            excluded = set()
            for exception in item.get("exceptions", []):
                if objects[exception].get("target") == target_id:
                    excluded.update(objects[exception].get("membershipExceptions", []))
            # Xcode ignores a folder name here, so each adapter file is listed.
            for adapter in sorted(p.relative_to(root / "Frisket").as_posix() for p in (root / "Frisket" / "Adapters").glob("*.swift")):
                if adapter not in excluded:
                    issues.append(f"Frisket/{adapter}: the app target compiles an adapter source; "
                                  "list it in the Frisket folder's membership exceptions")
            products = {objects[d].get("productName") for d in target.get("packageProductDependencies", [])}
            if "FrisketAdapters" not in products:
                issues.append("Frisket/Adapters: the app target does not link the FrisketAdapters product")
    return issues


FILE_CHECKS = {
    "finalization": finalization_issues,
    "app-writes": app_write_issues,
    "storage-pixels": storage_pixel_issues,
    "core-io": core_io_issues,
    "input-monitoring": input_monitoring_issues,
    "network": network_issues,
}
CHECKS = list(FILE_CHECKS) + ["app-sources"]


def product_files(root):
    files = {}
    for directory in ("Sources", "Frisket"):
        for path in sorted((root / directory).rglob("*.swift")):
            files[path.relative_to(root).as_posix()] = path.read_text(encoding="utf-8")
    return files


def repository_issues(root, checks):
    files = product_files(root)
    issues = []
    for check in checks:
        found = app_source_issues(root) if check == "app-sources" else FILE_CHECKS[check](files)
        issues.extend(f"{check}: {issue}" for issue in found)
    return issues


def fixture_issues(path):
    fixture = json.loads(path.read_text())
    if fixture["check"] == "app-sources":
        # The project parser needs real files: plutil reads the pbxproj from disk.
        scratch = path.resolve().parents[2] / ".build" / "check-fixtures"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            root = pathlib.Path(directory)
            for name, text in fixture["files"].items():
                (root / name).parent.mkdir(parents=True, exist_ok=True)
                (root / name).write_text(text)
            actual = app_source_issues(root)
    else:
        actual = FILE_CHECKS[fixture["check"]](fixture["files"])
    return fixture["check"], fixture["expected"], actual


def self_test(folder):
    failures, passing, failing = [], set(), set()
    for path in sorted(folder.glob("*.json")):
        check, expected, actual = fixture_issues(path)
        if actual != expected:
            failures.append(f"{path.name}: expected {expected!r}; got {actual!r}")
        (failing if expected else passing).add(check)
    for check in CHECKS:
        if check not in passing or check not in failing:
            failures.append(f"{check}: needs a passing and a failing fixture")
    return failures


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--root", type=pathlib.Path)
    mode.add_argument("--self-test", action="store_true")
    parser.add_argument("--check", action="append", choices=CHECKS)
    args = parser.parse_args()
    try:
        if args.self_test:
            problems = self_test(pathlib.Path(__file__).resolve().parent / "Fixtures")
        else:
            problems = repository_issues(args.root.resolve(), args.check or CHECKS)
    except (ValueError, KeyError, TypeError, OSError, subprocess.TimeoutExpired) as error:
        problems = [f"{type(error).__name__}: {error}"]
    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(1)
