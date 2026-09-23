# Ticket 39 code review

Fixed point: `9575f6f` (merge-base with main). Review snapshot: `9d250dd`.
Model: Cursor coordinator chat (Claude Opus 5.5 High). In-chat review; Other Models and Codex are past included-usage limits.

## Standards

- Closed enums for permission, case ids, and results. No free-text notes.
- Display serials and image magic bytes are refused before write.
- **Fix:** `command()` discarded `codesign -dv` stderr, which is where
  Identifier/Team/CDHash are printed.
- **Fix:** `lipo -archs` was pointed at the `.app` bundle, not the Mach-O.
- **Fix:** live `SPDisplaysDataType` stores points in `_spdisplays_resolution`;
  the first parse only read the unprefixed key.

## Spec

- Ticket 39: bundled 320×180 centred pattern plus `--verify`; each run records
  date, OS build, commit, architectures, signature, display layout, permission.
- Required hardware cases are indexed to existing 08/18/23/24/32 runbooks.
- First recorded hardware run remains for Prateek. Not a merge blocker for the
  automatable harness.

## Summary

Standards: 2 justified host-command fixes. Spec: 0 blocking gaps for the
harness. Worst per axis: live `header` would fail on a real app until the
stderr/lipo fixes.
