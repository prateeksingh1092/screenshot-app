#!/usr/bin/env python3
"""First-run manual record. Collects host metadata only; never launches or captures."""
import argparse
import datetime
import json
import re
from pathlib import Path
import subprocess
import sys

SCHEMA = 1
KIND = "first-run"
PATTERN = {
    "width_points": 320,
    "height_points": 180,
    "placement": "display-center",
    "verify": "FrisketTestPattern --verify PATH SCALE",
}
PERMISSIONS = ("not-asked", "denied", "granted", "revoked", "needs-relaunch")
RESULTS = ("pass", "fail", "pending", "not-reproducible", "blocked")
CASES = (
    "screen-recording-not-asked",
    "screen-recording-denied",
    "screen-recording-granted",
    "screen-recording-revoked-while-running",
    "screen-recording-after-resign",
    "screen-recording-needs-relaunch",
    "grant-survives-rebuild-1",
    "grant-survives-rebuild-2",
    "display-built-in-retina",
    "display-external-1x",
    "display-negative-coordinates",
    "unplug-mid-selection",
    "overlay-over-fullscreen",
    "overlay-across-space-switch",
    "esc-without-activation",
    "full-keyboard-access-thumbnails",
    "voiceover-thumbnails",
    "default-shortcut-area",
    "default-shortcut-full-screen",
    "default-shortcut-focus-thumbnails",
    "pattern-dimensions-and-markers",
)
COMMIT = re.compile(r"^[0-9a-f]{40}$")
IDENTIFIER = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
TEAM = re.compile(r"^[A-Z0-9]{10}$")
HASH = re.compile(r"^[0-9a-f]{40}$")
PIXELS = re.compile(r"(\d+)\s*x\s*(\d+)")
ORIGIN = re.compile(r"\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)")
FORBIDDEN = (b"\x89PNG\r\n\x1a\n", b"\xff\xd8\xff", b"GIF8")


def command(args):
    return subprocess.check_output([str(a) for a in args], text=True, stderr=subprocess.DEVNULL,
                                   timeout=30)


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def require_commit(value):
    commit = value.strip()
    if not COMMIT.fullmatch(commit):
        raise ValueError("commit is not a 40-character SHA")
    return commit


def parse_signature(text):
    fields = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key.strip()] = value.strip()
    identifier = fields.get("Identifier", "")
    team = fields.get("TeamIdentifier", "")
    cdhash = fields.get("CDHash", "").lower()
    if not IDENTIFIER.fullmatch(identifier) or not TEAM.fullmatch(team) or not HASH.fullmatch(cdhash):
        raise ValueError("signature fields are missing or malformed")
    return {"identifier": identifier, "team": team, "cdhash": cdhash}


def parse_resolution(text):
    match = PIXELS.search(text or "")
    if not match:
        raise ValueError("display resolution is missing")
    return int(match.group(1)), int(match.group(2))


def displays(contents):
    layout = []
    for gpu in json.loads(contents).get("SPDisplaysDataType", []):
        for index, display in enumerate(gpu.get("spdisplays_ndrvs") or []):
            if not isinstance(display, dict):
                continue
            pixel_width, pixel_height = parse_resolution(
                display.get("_spdisplays_pixels") or display.get("spdisplays_pixelresolution") or "")
            point_width, point_height = parse_resolution(display.get("spdisplays_resolution") or "")
            origin = ORIGIN.search(str(display.get("_spdisplays_display-origin") or ""))
            item = {
                "index": index,
                "pixel_width": pixel_width,
                "pixel_height": pixel_height,
                "point_width": point_width,
                "point_height": point_height,
                "retina": (pixel_width, pixel_height) != (point_width, point_height),
            }
            if origin:
                item["origin_x"] = int(origin.group(1))
                item["origin_y"] = int(origin.group(2))
            layout.append(item)
    if not layout:
        raise ValueError("display layout is empty")
    return layout


def refuse_pixels(document):
    encoded = json.dumps(document, indent=2, allow_nan=False).encode("utf-8")
    lowered = encoded.lower()
    if any(marker in encoded for marker in FORBIDDEN) or b"png" in lowered or b"serial" in lowered:
        raise ValueError("pixels, image bytes, or serial numbers are forbidden in a run record")


def save(path, document):
    refuse_pixels(document)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(document, indent=2, allow_nan=False) + "\n")
    temporary.replace(path)
    return document


def load(path):
    document = json.loads(Path(path).read_text())
    refuse_pixels(document)
    if document.get("schema") != SCHEMA or document.get("kind") != KIND:
        raise ValueError("not a schema-1 first-run record")
    return document


def header(app, permission, output, repository):
    if permission not in PERMISSIONS:
        raise ValueError("permission must be a closed Screen Recording state")
    app = Path(app)
    document = {
        "schema": SCHEMA,
        "kind": KIND,
        "date": utc(),
        "os_product": command(["/usr/bin/sw_vers", "-productVersion"]).strip(),
        "os_build": command(["/usr/bin/sw_vers", "-buildVersion"]).strip(),
        "commit": require_commit(command(["/usr/bin/git", "-C", repository, "rev-parse", "HEAD"])),
        "architecture": command(["/usr/bin/uname", "-m"]).strip(),
        "architectures": command(["/usr/bin/lipo", "-archs", app]).split(),
        "arm64_executed": False,
        "signature": parse_signature(command(["/usr/bin/codesign", "-dv", "--verbose=4", app])),
        "display_layout": displays(command(["/usr/sbin/system_profiler", "SPDisplaysDataType", "-json"])),
        "permission_state": permission,
        "pattern": dict(PATTERN),
        "cases": {name: "pending" for name in CASES},
        "status": "partial",
    }
    if document["architecture"] not in {"x86_64", "arm64"}:
        raise ValueError("architecture is unrecognized")
    return save(output, document)


def case(path, name, result, note=None):
    if name not in CASES:
        raise ValueError("case is not in the closed first-run list")
    if result not in RESULTS:
        raise ValueError("result is not in the closed result list")
    if note is not None:
        raise ValueError("note is forbidden; records hold no free text")
    document = load(path)
    document["cases"][name] = result
    document["status"] = "partial"
    return save(path, document)


def finish(path):
    document = load(path)
    pending = [name for name, result in document["cases"].items() if result == "pending"]
    if pending:
        raise ValueError("pending cases remain: " + ",".join(pending))
    document["status"] = "complete"
    return save(path, document)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="mode", required=True)
    header_cmd = commands.add_parser("header")
    header_cmd.add_argument("--app", type=Path, required=True)
    header_cmd.add_argument("--permission", choices=PERMISSIONS, required=True)
    header_cmd.add_argument("--output", type=Path, required=True)
    header_cmd.add_argument("--repository", type=Path, default=Path.cwd())
    case_cmd = commands.add_parser("case")
    case_cmd.add_argument("--record", type=Path, required=True)
    case_cmd.add_argument("--id", choices=CASES, required=True)
    case_cmd.add_argument("--result", choices=RESULTS, required=True)
    commands.add_parser("finish").add_argument("--record", type=Path, required=True)
    args = parser.parse_args()
    if args.mode == "header":
        header(args.app, args.permission, args.output, args.repository)
    elif args.mode == "case":
        case(args.record, args.id, args.result)
    else:
        finish(args.record)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError, json.JSONDecodeError, KeyError) as error:
        print(f"First-run record stopped: {type(error).__name__}: {error}", file=sys.stderr)
        sys.exit(1)
