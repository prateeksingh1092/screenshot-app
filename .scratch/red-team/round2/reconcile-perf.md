<!-- Source: Cursor Claude Opus 5.5 High, performance and reliability engineer, agent ce8bc2c6-43a6-46ca-b0ba-74f6bf394e1b. Final response saved verbatim, 00:21 UTC Sep 23. -->
## PERF: reconciliation
PERF-1: accept: The trial must produce the complete 5120×57,600 output, with no truncation or downscaling, under 2 GB. Any v1 pixel cap is set only after the trial measures memory.
PERF-2: accept: Keep a global budget for pending bytes. On quit, wait only for commits the user has authorized, and apply the agreed editor-close choices; unapproved edits are never committed.
PERF-3: accept: Build thumbnails from the in-memory image and keep PNG encoding off the main thread. The 500 ms targets stay placeholders until baselines are measured and ratified.
PERF-4: accept: Follow C1(b), file-first with only `finalized` and `deleting` states. Keep `flock`, `synchronous=FULL`, `F_FULLFSYNC`, kill-at-each-step tests with recovery run twice, and separate storage roots for debug and release.
PERF-5: accept: Enforce the quota from sizes stored in the database, using DATA-4's full accounting definition. A launch-time scan reconciles drift.
PERF-7: accept: v1 has no event taps. Global shortcuts use Carbon only, overlay key panels handle keys, and there are no global mouse monitors while idle.
