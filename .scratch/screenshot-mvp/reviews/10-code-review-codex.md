Standards: 1 nit; no documented-standard breaches.

- **nit — [HistoryStore.swift:124](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-10/Sources/FrisketCore/StorageAdapter/HistoryStore.swift:124):** Adoption duplicates the finalized-row INSERT at line 341; a shared insertion helper would prevent schema mappings from diverging. Duplicated Code heuristic, not a correctness defect.

Spec: 0 findings. Verified locking, reconciliation, decoded-pixel validation, all nine commit points in both tiers, helper isolation, closed diagnostics, authorized-output storage, and identical second-sweep file bytes.

Validation: focused recovery suite passed **16 tests / 43 cases** on x86_64 macOS 26.7 (25G229); diff whitespace check passed. Working tree remains clean. Arm64, app linking, and manual cross-Mac restoration remain unverified.

Verdict: merge