# Ticket 40: final acceptance

Not a v1 declaration. Codex must assess the verification report. On this Intel
Mac record **arm64 not executed**. Nothing is distributed (decision C3).

## Automatable

1. Static checks: `swift test --filter RepositoryChecksTests` (includes
   first-run and Release project tests).
2. Universal Release, signed, never launched or installed:

   ```sh
   sh scripts/release-universal.sh
   ```

   Expect `.build/release/ARM64-BUILT-AND-SIGNED-NEVER-EXECUTED.json` with
   `architectures: ["arm64","x86_64"]`, identifier
   `io.github.prateeksingh1092.frisket`, `distributed: false`,
   `arm64_executed: false`. Do not `open` or `ditto` that bundle to
   `~/Applications`.

## Still operator / Codex

3. First-run hardware cases: [39-first-run.md](39-first-run.md).
4. Remaining decision-49 manuals (08, 14–18, 21–26, 28–36, 38).
5. Live performance vs ratified targets ([37](37-performance-baselines.md),
   [38](38-frisket-performance.md)). Placeholders stand until those numbers exist.
6. Codex assessment of
   [40-verification-draft.md](../../.scratch/screenshot-mvp/reports/40-verification-draft.md)
   after included Codex usage returns (2026-09-29 11:57).
