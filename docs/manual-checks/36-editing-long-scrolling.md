# 36 — Editing a long scrolling capture

**Retired (decision 60).** Scrolling capture was removed in ticket 87, so step 1
cannot be run. The strip render path stays until ticket 67 replaces it.

Automated seams cover strip render, strip PNG encode, a downsampled editor
proxy, and a tall canary through Done. The opt-in peak is
`sh scripts/editor-memory-run.sh` (`FRISKET_EDITOR_MEMORY_RUN=1`).

1. Capture a scrolling page that is taller than the display. Open **Edit**.
   The canvas must stay usable; the machine must not page out.
2. Solid-redact a known marker, add an arrow, **Done**. Confirm the saved
   and copied images keep the redaction at full resolution.
3. Record that the editor preview is a proxy (softer than 1:1) while History
   holds the full-resolution result.
