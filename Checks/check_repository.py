"""Offline repository checks. Invoked by Swift Testing; also usable without its runner."""

import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import unicodedata

TEST_ROOTS = ("Tests/",)
CHECKS = ["dependencies", "imports", "identity", "provenance", "diagnostics", "capture-memory",
          "input-monitoring", "app-sources", "network", "silgen", "modals"]


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



def diagnostic_issues(files):
    issues = []
    allowed_fields = {
        "DiagnosticEvent": {"name": "DiagnosticEventName", "operation": "DiagnosticOperation", "error": "DiagnosticError?"},
        "DiagnosticError": {"domain": "DiagnosticErrorDomain", "code": "DiagnosticErrorCode"},
        "DiagnosticRecord": {"recordedAt": "Date", "event": "DiagnosticEvent"},
    }
    for path, text in sorted(files.items()):
        if not path.endswith(".swift") or not path.startswith(("Sources/", "Frisket/")):
            continue
        code = swift_code(text).replace("`", "")
        if re.search(r'\b(?:print|debugPrint|dump|NSLog|os_log|os_signpost|Logger|OSLog|assert|assertionFailure|precondition|preconditionFailure|fatalError)\b', code):
            issues.append(f"{path}: raw logging or assertion route outside closed diagnostics")
        for name, fields in allowed_fields.items():
            for match in re.finditer(r'\bstruct\s+' + name + r'\b[^\{]*\{([^}]+)', code):
                properties = re.findall(r'\b(?:let|var)\s+(\w+)\s*(?::\s*([^\s;=]+))?', match.group(1))
                if any(fields.get(field) != kind for field, kind in properties):
                    issues.append(f"{path}: diagnostic payload type is not closed")
    return issues



def swift_function_bodies(code, pattern):
    """Bounded lexical bodies, skipping parameter defaults and nested braces."""
    for match in re.finditer(pattern + r'\s*\(', code):
        start = match.end()
        depth = 1
        while start < len(code) and depth:
            depth += (code[start] == '(') - (code[start] == ')')
            start += 1
        start = code.find('{', start)
        if start < 0:
            continue
        end, depth = start + 1, 1
        while end < len(code) and depth:
            depth += (code[end] == '{') - (code[end] == '}')
            end += 1
        yield code[start + 1:end - 1]


def capture_memory_issues(files):
    issues = []
    coordinator = "Sources/FrisketCore/CaptureLifecycleCoordinator.swift"
    write_routes = r'\b(?:createDirectory|createFile|removeItem|FileHandle|OutputStream|fopen|open|openat|mkdir|unlink|rename)\b|\.\s*write\s*\(\s*to\s*:'
    for path, text in sorted(files.items()):
        if not path.startswith(("Sources/FrisketCore/", "Frisket/")) or not path.endswith(".swift"):
            continue
        code = swift_code(text).replace("`", "")
        if path != coordinator and re.search(r'\bAuthorizedFinalization\s*\(', code):
            issues.append(f"{path}: finalization capability constructed outside coordinator")
        if path == coordinator:
            capture = re.search(r'case\s+(?:let\s+)?\.capture\b(.*?)(?=case\s+(?:let\s+)?\.(?:copy|retryCopy|dismiss|discard)\b|\Z)', code, re.S)
            if capture and re.search(r'AuthorizedFinalization|\.\s*finalize\s*\(', capture.group(1)):
                issues.append(f"{path}: capture cannot authorize persistence")
        if path.startswith("Frisket/"):
            # Recovery opens Settings and directs relaunch helper I/O to /dev/null.
            # Mask only these exact non-storage forms; other writes in the same
            # file (including POSIX open and writable FileHandle) stay forbidden.
            storage_code = re.sub(r'\bNSWorkspace\s*\.\s*shared\s*\.\s*open\b', 'workspaceLaunch', code)
            storage_code = re.sub(r'\bFileHandle\s*\.\s*nullDevice\b', 'nullDeviceHandle', storage_code)
            # Ticket 38's opt-in adapter emits only the closed numeric latency
            # row to inherited stdout. It cannot open a file or accept pixels.
            if path == "Frisket/Adapters/CaptureLatencyLog.swift":
                storage_code = re.sub(r'\bFileHandle\s*\.\s*standardOutput\b', 'latencyOutput', storage_code)
            if re.search(write_routes, storage_code):
                issues.append(f"{path}: app filesystem write bypasses authorized finalization")
            continue
        if path.startswith("Sources/FrisketCore/StorageAdapter/"):
            if re.search(r'\b(?:CapturePixelSource|CaptureImage|original\w*|unredacted\w*)\b', code, re.I):
                issues.append(f"{path}: storage accepts source or original pixels")
            bodies = swift_function_bodies(code, r'\b(?:init|func\s+(?:entries|rows|thumbnailPNG|finalizedImage|readExisting))')
            eager = write_routes + r'|\b(?:DatabaseQueue|writableDatabase|durableWrite|cacheThumbnail|renameExclusively)\s*\('
            if any(re.search(eager, body) for body in bodies):
                issues.append(f"{path}: storage initialization or query may write before finalization")
            outside_functions = code
            for body in swift_function_bodies(code, r'\b(?:init|func\s+\w+)'):
                outside_functions = outside_functions.replace(body, "")
            if any(re.search(eager, value) for value in re.findall(r'\b(?:let|var)\s+\w+(?:\s*:\s*[^=;\n]+)?\s*=([^;\n}]+)', outside_functions)):
                issues.append(f"{path}: eager storage property may write before finalization")
            continue
        imports = re.findall(r'\bimport\s+(?:(?:struct|class|enum|protocol|typealias|func|var|let)\s+)?(\w+)', code)
        disk_symbols = r'\b(?:URL|NSURL|FileManager|FileHandle|OutputStream|InputStream|UserDefaults|Process|Bundle|NSFileCoordinator|StorageAdapter|GRDB|Darwin|Glibc|POSIX|fopen|freopen|open|openat|creat|fwrite|pwrite|writev|unlink|rename|mkdir|mmap)\b'
        # DA-1 (decision 57): rendering may use these frameworks, but only in memory.
        allowed_imports = {"Foundation", "Synchronization", "CoreGraphics", "CoreText", "ImageIO", "Accelerate"}
        file_routes = r'\b(?:CG|CT|CF)\w*(?:URL|Filename)\w*|\burl\s*:'
        if (any(module not in allowed_imports for module in imports)
                or re.search(disk_symbols, code)
                or re.search(file_routes, code)
                or re.search(r'\.\s*write\s*\(\s*to\s*:', code)):
            issues.append(f"{path}: platform or filesystem capability in memory-only core")
        invalid_clipboard = False
        for match in re.finditer(r'\bprotocol\s+ImageClipboard\b[^\{]*\{([^}]+)', code):
            body = match.group(1)
            functions = re.findall(r'\bfunc\s+\w+', body)
            writes = re.findall(r'\bfunc\s+write\s*\(\s*_\s+\w+\s*:\s*ClipboardImage\s*\)', body)
            invalid_clipboard |= len(functions) != 1 or len(writes) != 1 or bool(re.search(r'\b(?:var|associatedtype)\b', body))
        for match in re.finditer(r'\bstruct\s+ClipboardImage\b[^\{]*\{([^}]+)', code):
            fields = re.findall(r'\b(?:let|var)\s+(\w+)\s*(?::\s*([\w?]+))?', match.group(1))
            allowed = {"pngData": "Data", "currentHostOnly": "", "concealed": "", "replacing": "ClipboardReceipt?"}
            invalid_clipboard |= any(allowed.get(name) != kind for name, kind in fields)
        if invalid_clipboard:
            issues.append(f"{path}: clipboard contract must be image-only and write-only")
    return issues


def input_monitoring_issues(files):
    issues = []
    registrations = 0
    for path, text in sorted(files.items()):
        if not path.endswith((".swift", ".m", ".mm", ".h", ".c", ".cc", ".cpp")):
            continue
        if not path.startswith(("Sources/", "Frisket/")):
            continue
        code = swift_code(text).replace("`", "")
        registrations += len(re.findall(r'\bRegisterEventHotKey\s*\(', code))
        if re.search(r'\b(?:CGEventTap\w*|CGEvent\s*\.\s*tap\w*|tapCreate\w*|tapEnable|tapIsEnabled|addGlobalMonitorForEvents\w*)\b', code):
            issues.append(f"{path}: event tap or global event monitor is forbidden")
    if registrations > 1:
        issues.append(f"product: more than one Carbon hot-key registration (found {registrations})")
    return issues



def product_swift(files):
    for path, text in sorted(files.items()):
        if path.startswith(("Sources/", "Frisket/")) and path.endswith(".swift"):
            yield path, text


def network_issues(files):
    """Spec story 74: Frisket makes no network connections. Lexical, like the other checks."""
    issues = []
    modules = {"Network", "CFNetwork", "NetworkExtension", "WebKit", "MultipeerConnectivity", "CloudKit"}
    symbols = (r'\b(?:URLSession\w*|NSURLSession\w*|NSURLConnection|NSURLDownload|NW(?:Connection|Listener|Browser|PathMonitor|Endpoint)\w*'
               r'|CFSocket\w*|CFStreamCreatePairWithSocket\w*|CFHTTPMessage\w*|SCNetworkReachability\w*|WKWebView'
               r'|getStreamsToHost\w*)\b'
               r'|(?<![\w.])(?:socket|connect|sendto|recvfrom|getaddrinfo|gethostbyname)\s*\(')
    for path, text in product_swift(files):
        code = swift_code(text).replace("`", "")
        imports = re.findall(r'\bimport\s+(?:(?:struct|class|enum|protocol|typealias|func|var|let)\s+)?(\w+)', code)
        # A declaration such as `func connect(_:)` is not a call to POSIX connect(2).
        calls = re.sub(r'\bfunc\s+\w+', 'func _', code)
        if any(module in modules for module in imports) or re.search(symbols, calls):
            issues.append(f"{path}: network API is forbidden")
    return issues


# D22: C functions bound with the Swift calling convention. Ticket 63 removed notify_post and
# ticket 67 removed the zlib and libcompression bindings, so every use in product code is rejected.
def silgen_issues(files):
    issues = []
    for path, text in product_swift(files):
        if not re.search(r'@_silgen_name\b', swift_code(text)):
            continue
        names = re.findall(r'@_silgen_name\s*\(\s*"([^"]*)"', text) or ["?"]
        for name in names:
            issues.append(f"{path}: @_silgen_name(\"{name}\") binds a C function with the Swift calling convention")
    return issues

# DA-5 (ticket 76): notices are non-modal. An alert may appear only for a destructive or
# irreversible choice (FrisketCore's `Confirmation`): History Delete, closing an edited capture,
# and an export folder that syncs copies off this Mac.
CONFIRMATION_FILES = {"Frisket/HistoryWindow.swift", "Frisket/EditorWindow.swift", "Frisket/ExportSettings.swift"}


def modal_issues(files):
    issues = []
    for path, text in product_swift(files):
        if path not in CONFIRMATION_FILES and re.search(r'\bNSAlert\b', swift_code(text)):
            issues.append(f"{path}: NSAlert is only for the destructive or irreversible choices (DA-5); show a Notice instead")
    return issues


def app_source_issues(root):
    # Parse the project rather than depending on Xcode's formatting or comments.
    project_path = root / "Frisket.xcodeproj" / "project.pbxproj"
    result = subprocess.run(
        ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(project_path)],
        capture_output=True, text=True, timeout=30
    )
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
        if (item["isa"] == "PBXFileReference" and path.parts[:1] == ("Frisket",)
                and path.suffix == ".swift"):
            paths.add(path.as_posix())
        for child in item.get("children", []):
            visit(child, path, ancestors | {identifier})

    visit(objects[project["rootObject"]]["mainGroup"], pathlib.PurePosixPath(), set())
    return [f"{path}: explicit app-source reference; use the synchronized Frisket folder"
            for path in sorted(paths)]


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
        if "adaptedSHA256" in entry and (
                not re.fullmatch(r'[0-9a-f]{64}', entry["adaptedSHA256"])
                or hashlib.sha256(files[path].encode("utf-8")).hexdigest() != entry["adaptedSHA256"]):
            issues.append(f"{path}: adapted source hash missing or changed")
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
    if "repositoryFiles" in fixture:
        # Exercise the real on-disk inventory, not just the individual scanners.
        scratch = path.resolve().parents[2] / ".build" / "check-fixtures"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            root = pathlib.Path(directory)
            for name, text in fixture["repositoryFiles"].items():
                destination = root / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text(text)
            actual = repository_issues(root, fixture["check"])
    elif fixture["check"] == "dependencies":
        actual = dependency_issues(fixture["manifest"], fixture.get("resolved"))
    elif fixture["check"] == "imports":
        actual = import_issues(fixture["files"])
    elif fixture["check"] == "diagnostics":
        actual = diagnostic_issues(fixture["files"])
    elif fixture["check"] == "capture-memory":
        actual = capture_memory_issues(fixture["files"])
    elif fixture["check"] == "identity":
        actual = identity_issues(fixture["files"])
    elif fixture["check"] == "provenance":
        actual = provenance_issues(fixture["files"], fixture["entries"])
    elif fixture["check"] == "network":
        actual = network_issues(fixture["files"])
    elif fixture["check"] == "modals":
        actual = modal_issues(fixture["files"])
    elif fixture["check"] == "silgen":
        actual = silgen_issues(fixture["files"])
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
    environment = dict(os.environ)
    environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    environment["CLANG_MODULE_CACHE_PATH"] = str(root / ".build" / "clang-cache")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(root / ".build" / "module-cache")
    command = [
        "/usr/bin/xcrun", "swift", "package", "--package-path", str(root),
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
    if check == "app-sources":
        return app_source_issues(root)
    if check == "dependencies":
        lockfile = root / "Package.resolved"
        resolved = json.loads(lockfile.read_text()) if lockfile.exists() else None
        return dependency_issues(dumped_manifest(root), resolved)
    files = product_files(root)
    if check == "input-monitoring":
        return input_monitoring_issues(files)
    if check == "network":
        return network_issues(files)
    if check == "silgen":
        return silgen_issues(files)
    if check == "modals":
        return modal_issues(files)
    if check == "imports":
        return import_issues(files)
    if check == "diagnostics":
        return diagnostic_issues(files)
    if check == "capture-memory":
        return capture_memory_issues(files)
    if check == "identity":
        return identity_issues({path: text for path, text in files.items() if not path.startswith(TEST_ROOTS)})
    entries = json.loads((root / "docs" / "ported-files.json").read_text())
    return provenance_issues(files, entries)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--fixture", type=pathlib.Path)
    mode.add_argument("--root", type=pathlib.Path)
    parser.add_argument("--check", choices=CHECKS)
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
