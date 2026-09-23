#!/usr/bin/env python3
"""C3 release label. Inspects a built app; never installs, launches, or distributes."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

RELEASE_ID = "io.github.prateeksingh1092.frisket"
IDENTIFIER = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
TEAM = re.compile(r"^[A-Z0-9]{10}$")
HASH = re.compile(r"^[0-9a-f]{40}$")


def command(args):
    return subprocess.check_output([str(a) for a in args], text=True, stderr=subprocess.STDOUT,
                                   timeout=30)


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


def sign(app):
    app = Path(app)
    entitlements = Path(__file__).resolve().parents[2] / "Frisket" / "Frisket.entitlements"
    command(["/usr/bin/codesign", "--force", "--sign", "Apple Development",
             "--options", "runtime", "--timestamp=none",
             "--entitlements", entitlements, app])


def write(app, output, install=False, launch=False):
    if install:
        raise ValueError("install is forbidden; nothing is distributed")
    if launch:
        raise ValueError("launch is forbidden; arm64 is never executed")
    app = Path(app)
    binary = app / "Contents/MacOS/Frisket"
    architectures = sorted(command(["/usr/bin/lipo", "-archs", binary]).split())
    if architectures != ["arm64", "x86_64"]:
        raise ValueError("binary is not a universal x86_64+arm64 release")
    signature = parse_signature(command(["/usr/bin/codesign", "-dv", "--verbose=4", app]))
    if signature["identifier"] != RELEASE_ID:
        raise ValueError("identity is not the production release bundle")
    document = {
        "label": "arm64 built and signed, never executed",
        "architectures": architectures,
        "identifier": signature["identifier"],
        "team": signature["team"],
        "cdhash": signature["cdhash"],
        "distributed": False,
        "arm64_executed": False,
    }
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    temporary.write_text(json.dumps(document, indent=2, allow_nan=False) + "\n")
    temporary.replace(output)
    return document


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sign", action="store_true")
    args = parser.parse_args()
    if args.sign:
        sign(args.app)
    write(args.app, args.output)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError, json.JSONDecodeError, KeyError) as error:
        print(f"Release label stopped: {type(error).__name__}: {error}", file=sys.stderr)
        sys.exit(1)
