# Red team round 2: ballot

You are one of eight panel roles. Round 1 is complete. Vote on every amendment the panel proposed, so the facilitator can adopt the ones with consensus and send the rest to Prateek.

Stay read-only: no builds, installs, app launches, screen capture, pasteboard access, signing, keychain, or file writes. Read the round-1 files for the amendment text:
`/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.scratch/red-team/round1/{arch,ux,qa,data,rel,perf,sec,plat}.md`

## What changed since round 1 (accepted by Prateek)

- **Decision 13 amended:** build the app fresh with Snapzy as a read-only reference. Do not port its renderer, capture overlay, capture engine, or database layer. The scrolling stitcher is the only port candidate, decided by a trial (compiles alone, passes its tests on this Intel Mac, under 2 GB on a synthetic 5120×57,600 capture after moving to strip storage, cheaper than fresh). See `docs/adr/0001-build-fresh-snapzy-as-reference.md`.
- **Decision 26:** the app is named Frisket; bundle identifier `io.github.prateeksingh1092.frisket`, development builds `.debug`.

Amendments made moot or narrowed by these (for example ones about porting the renderer, overlay, or database, or about choosing the bundle identifier) should be voted `superseded`, or `agree` if they still apply to the stitcher alone.

## Rules

- Votes: `agree`, `object`, `abstain`, or `superseded`.
- An amendment is adopted when at least two roles other than its author vote `agree` and no role votes `object`.
- An `object` must give a reason and the smallest change that would lift the objection, in 25 words or fewer.
- Vote `abstain` when an item is outside your expertise; that is expected, not a weakness.
- Where the amendment defers to "Prateek's call", vote on the rest of it; his choice is collected separately.

## Items

ARCH-1 … ARCH-7, UX-1 … UX-8, QA-1 … QA-8, DATA-1 … DATA-8, REL-1 … REL-8, PERF-1 … PERF-7, SEC-1 … SEC-8, PLAT-1 … PLAT-8 (64 items).

## Conflicts: pick one option each

- **C1 commit protocol.** (a) PERF-4: insert a `committing` row before writing the file, then mark it `finalized`. (b) DATA-2/DATA-3: write, flush (`F_FULLFSYNC`), and atomically rename the file first, then insert one row; only `finalized` and `deleting` states. Both use an idempotent launch sweep.
- **C2 oversized single capture versus the 1 GB limit.** (a) Refuse it from history, and tell the user. (b) Keep it, and let eviction stop once only the just-committed item remains, with a visible overage (DATA-4, PERF-5). (c) Another option, stated in 25 words or fewer.
- **C3 the untestable Apple-silicon (arm64) half.** (a) Build universal and label arm64 unverified (QA-5, REL-6). (b) Development builds native architecture only, universal builds only for release, arm64 labelled unverified, and any distribution needs an Apple-silicon test run (PLAT-6). (c) Intel-only for v1.

## Output format (return only this)

```
## <ROLE>: round 2 votes
ARCH-1: agree
ARCH-2: superseded
UX-3: object: <reason>; lift if <change>
...one line for each of the 64 items...
C1: a|b: <reason, 15 words or fewer>
C2: a|b|c: <reason>
C3: a|b|c: <reason>
New blocker (optional, at most one): <one sentence, only if voting revealed something none of the 64 items covers>
```
