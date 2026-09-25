#!/usr/bin/env python3
"""Fail when a term that a decision retired reappears in a live file.

Retired terms live in Checks/retired-terms.tsv. Live files are the code, the
instructions agents read and the current docs. History is not live: archive/,
decisions.md, ticket files, plans other than the implementer brief, and ADRs
keep their old words. A line that names why a term is gone (Retired,
Superseded, "decision 6x") is allowed. Paths listed as pending for a ticket
only warn until that ticket updates them.

    python3 Checks/check_drift.py [--root DIR]
    python3 Checks/check_drift.py --self-test
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

LIVE = re.compile(
    r"^(CLAUDE\.md|AGENTS\.md|CONTEXT\.md|\.scratch/screenshot-mvp/spec\.md"
    r"|Plans/implementer-brief\.md|docs/(?!adr/).*\.md"
    r"|(Sources|Frisket|Tests|Tools|scripts)/.*\.(swift|sh|py|md|tsv))$"
)
EXEMPT = {"Checks/check_drift.py", "Checks/retired-terms.tsv"}
EXPLAINED = re.compile(r"retired|supersed|decision 6[0-9]", re.IGNORECASE)


def load_terms(text):
    terms = []
    for line in text.splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        cols = (line.split("\t") + ["", "", "", ""])[:4]
        pattern, decision, instead, pending = cols
        prefixes = [p.split("=", 1) for p in pending.split(",") if "=" in p]
        terms.append((re.compile(pattern, re.IGNORECASE), decision, instead, prefixes))
    return terms


def scan(files, terms, show=False):
    """files: iterable of (path, text). Returns (failures, warnings) as message lists."""
    failures, warnings = [], []
    for path, text in files:
        if path in EXEMPT or not LIVE.match(path):
            continue
        lines = text.splitlines()
        for number, line in enumerate(lines, 1):
            # The explanation may wrap onto the next line of a paragraph.
            context = line + " " + (lines[number] if number < len(lines) else "")
            for pattern, decision, instead, prefixes in terms:
                if not pattern.search(line) or EXPLAINED.search(context):
                    continue
                message = f"{path}:{number}: retired by decision {decision}; use: {instead}"
                if show:
                    message += f"\n    {line.strip()[:160]}"
                ticket = next((t for prefix, t in prefixes if path.startswith(prefix)), None)
                if ticket:
                    warnings.append(f"{message} (pending ticket {ticket})")
                else:
                    failures.append(message)
    return failures, warnings


def tracked_files(root):
    names = subprocess.run(["git", "-C", str(root), "ls-files"], check=True,
                           capture_output=True, text=True).stdout.splitlines()
    for name in names:
        path = root / name
        if path.is_file():
            try:
                yield name, path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue


def self_test():
    terms = load_terms("\\bLoupe\\b\t60\tnothing\t\nopaque black\t61\tcolour\tdocs/=88\n")
    failures, warnings = scan([
        ("CLAUDE.md", "Show the Loupe.\nOther text.\nThe Loupe is\nretired (decision 60).\n"),
        ("docs/x.md", "It is opaque black.\n"),
        ("archive/old.md", "Loupe everywhere.\n"),
        ("Frisket/A.swift", "// the loupe\n"),
    ], terms)
    assert failures == [
        "CLAUDE.md:1: retired by decision 60; use: nothing",
        "Frisket/A.swift:1: retired by decision 60; use: nothing",
    ], failures
    assert warnings == ["docs/x.md:1: retired by decision 61; use: colour (pending ticket 88)"], warnings
    print("check_drift self-test: ok")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=Path(__file__).resolve().parent.parent, type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    terms = load_terms((args.root / "Checks/retired-terms.tsv").read_text(encoding="utf-8"))
    failures, warnings = scan(tracked_files(args.root), terms, show=True)
    for w in warnings:
        print(f"drift (pending): {w}")
    for f in failures:
        print(f"drift: {f}", file=sys.stderr)
    print(f"check_drift: {len(failures)} failures, {len(warnings)} pending")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
