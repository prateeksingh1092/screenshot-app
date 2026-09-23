# 11: Save to the export folder, with the Settings window shell

**What to build:** Save on a thumbnail writes a PNG to `~/Pictures/Frisket` by default, and a Settings window lets Prateek change the export folder safely.

**Blocked by:** 09

**Status:** ready-for-agent

- [ ] Save goes through the shared finalization policy (the capture is finalized to History as well) and reports commit and delivery outcomes separately.
- [ ] Export copies the rendered revision and never moves an app-owned file; exported files are untouched by retention and deletion.
- [ ] Settings (SwiftUI) holds the export folder; it refuses a folder inside the app-owned root and warns when the folder is iCloud-synced.
- [ ] Settings controls have VoiceOver labels and keyboard operation.
- [ ] Seam 1 tests cover save success, save failure with History commit intact, and retry on the same revision.

## Comments
