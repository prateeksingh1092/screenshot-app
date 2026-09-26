# 103: A dead menu item and a dead permission button (D33, D34)

**What Prateek saw (2026-09-25, acceptance test 83, test 11, build `4969168`):**
- **D33:** after the external display was unplugged, its Thumbnail moved to the main display and then left. The menu's **Focus Latest Thumbnail** stayed enabled with no Thumbnail on screen, and clicking it did nothing. Copy Latest and Delete Latest are disabled correctly (decision 79).
- **D34:** after Screen Recording was revoked in System Settings, capture showed the permission message. Its **Request Screen Recording** button did nothing. Once the user has answered, macOS doesn't prompt again, so a second request is silent.

**Status:** ready-for-agent (medium effort)

- [ ] Focus Latest Thumbnail is disabled whenever `thumbnails()` is empty, by the same rule as Copy Latest. Add a test at that seam, and extend the live `menu-latest` row.
- [ ] Remove the "Request Screen Recording" button from the permission message (decision 100). The existing "Open System Settings" button, which already opens the Screen & System Audio Recording page, stays. Add a test on the permission-recovery state (see `docs/permission-recovery.md`).
- [ ] The permission message text matches the button: after a refusal, it tells the user to turn Frisket on in System Settings and relaunch if asked.
