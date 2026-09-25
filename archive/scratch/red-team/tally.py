"""Tally red-team round 2 ballots in round2/*.md.

Rule: an item is adopted when at least two roles other than its author vote
agree and no role votes object.
"""
import pathlib
import re
import sys
from collections import defaultdict

ROOT = pathlib.Path(__file__).parent / "round2"
LINE = re.compile(r"^(?P<item>(ARCH|UX|QA|DATA|REL|PERF|SEC|PLAT)-\d+|C[123]):\s*(?P<vote>[a-z|]+)\s*:?\s*(?P<note>.*)$")

votes = defaultdict(dict)
notes = defaultdict(dict)
blockers = {}
for path in sorted(ROOT.glob("*.md")):
    role = path.stem.upper()
    for raw in path.read_text().splitlines():
        line = raw.strip().strip("`")
        if line.startswith("New blocker"):
            text = line.split(":", 1)[1].strip()
            if text.lower() not in ("", "none"):
                blockers[role] = text
            continue
        m = LINE.match(line)
        if m:
            votes[m["item"]][role] = m["vote"]
            if m["note"]:
                notes[m["item"]][role] = m["note"]

roles = sorted({r for v in votes.values() for r in v})
print(f"Ballots: {', '.join(roles)} ({len(roles)})\n")

adopted, objected, short, superseded = [], [], [], []
for item in sorted((i for i in votes if not i.startswith("C")), key=lambda s: (s.split("-")[0], int(s.split("-")[1]))):
    author = item.split("-")[0]
    v = votes[item]
    agrees = [r for r, x in v.items() if x == "agree" and r != author]
    objs = [r for r, x in v.items() if x == "object"]
    sups = [r for r, x in v.items() if x == "superseded"]
    if objs:
        objected.append((item, objs))
    elif len(sups) >= 2 and len(agrees) < 2:
        superseded.append((item, sups))
    elif len(agrees) >= 2:
        adopted.append(item)
    else:
        short.append((item, agrees))

print(f"ADOPTED ({len(adopted)}): {', '.join(adopted)}\n")
print(f"SUPERSEDED ({len(superseded)}): " + ", ".join(f"{i} [{'/'.join(s)}]" for i, s in superseded) + "\n")
print(f"NOT ENOUGH AGREEMENT ({len(short)}): " + ", ".join(f"{i} [{'/'.join(a) or '-'}]" for i, a in short) + "\n")
print(f"OBJECTED ({len(objected)}):")
for item, objs in objected:
    for r in objs:
        print(f"  {item} by {r}: {notes[item].get(r, '')}")
print("\nCONFLICTS:")
for c in ("C1", "C2", "C3"):
    tally = defaultdict(list)
    for r, x in votes[c].items():
        tally[x].append(r)
    print(f"  {c}: " + "; ".join(f"{k}={'/'.join(v)}" for k, v in sorted(tally.items())))
print("\nNEW BLOCKERS:")
for r, t in blockers.items():
    print(f"  {r}: {t}")
sys.exit(0)
