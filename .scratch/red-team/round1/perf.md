<!-- Provenance: Cursor Claude Opus 5.5 High subagent ce8bc2c6-43a6-46ca-b0ba-74f6bf394e1b, round 1, 2026-09-22. Final response saved by the facilitator. Arithmetic figures are estimates; nothing was measured. -->

## Performance and reliability engineer (PERF): round 1

Machine: 16-inch Intel MacBook Pro, Intel UHD 630 plus AMD Radeon Pro 5500M (read from `system_profiler`).

### Findings

**PERF-1: Porting the stitcher as-is breaks the 2 GB placeholder, and so does the editor**
- Target: decisions 16, 22 (and the stitcher port in 13)
- Attack: 5K at 2x = 5120×2880×4 B = 59 MB/frame. Twenty screens = 57,600 rows; output alone 1.18 GB. Snapzy retains every accepted frame's full raster, builds a merged array, then copies it to `Data`. With 1,440-row steps: 40×59 MB = 2.36 GB + 2×1.18 GB + 8-frame ring 0.47 GB ≈ **5.2 GB**. Snapzy's 32,768-row cap (~11 screens, 671 MB) still peaks ≈ 3.2 GB. Editor with the capped result: original 671 MB + rendered 671 MB + likely encoder copy (inference) ≈ 2.0 GB, no headroom. 32,768 rows also exceeds Metal's 16,384-pixel texture limit.
- Severity: blocker
- Evidence: `ScrollingCaptureStitcher.swift:280-284,611`; `:655`, `:238`; `ScrollingCaptureTypes.swift:252`; `ScrollingCaptureCoordinator.swift:47`; [Metal feature set tables](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf).
- Amendment: Copy only new rows into 512-row strips (10.5 MB each), keep only the previous frame for alignment, release frames promptly. Hold the memory-only original as LZ4/LZFSE-compressed strips in RAM (decision 16 unchanged). Pixel budget (proposed 150 MP, ~29,000 rows at 5K): on reaching it, stop with a HUD message, or offer 1x output (quarter memory). Tiled/downsampled editor proxy; render and encode per strip after verifying ImageIO reads a sequential `CGDataProvider` without materializing the image. Peak = `phys_footprint` from capture start through finalization; synthetic 5120×57,600 fixture must stay under 2 GB.
- Changes an accepted product decision (1-12): no

**PERF-2: Multiple pending captures multiply memory and crash loss**
- Target: decision 16 + gap
- Attack: Three pending capped scroll captures (2.0 GB) + one in the editor (2.0 GB) ≈ 4 GB; with Cursor and a browser on 16 GB, macOS compresses and swaps (CPU-heavy on Intel). A crash loses every pending item. Quit with pending items means seconds of PNG encoding.
- Severity: major
- Evidence: decision 16 text; otherwise inference.
- Amendment: Global pending-bytes budget (e.g. 2.5 GB, counting compressed strips); beyond it, refuse new scrolling captures with a message. On quit, `applicationShouldTerminate` returns `.terminateLater` with progress until pending commits finish.
- Changes an accepted product decision (1-12): no

**PERF-3: Keep PNG encode/decode off the thumbnail path**
- Target: decisions 20, 22
- Attack: If ImageIO PNG runs ~50-150 MB/s of raw pixels on one Intel core (inference), one 5K frame takes 0.4-1.2 s and a capped scroll 4.5-13 s. Snapzy builds the floating thumbnail from the saved file after encoding, then a check that can sleep up to 3×50 ms; History thumbnails re-decode the full PNG. Scrolling Done also triggers a 671 MB merge (~0.3-0.6 s, inference) before downsampling.
- Severity: major
- Evidence: `QuickAccessManager.swift:259-271`; `ScreenCaptureManager.swift:1380-1405,1445-1462`; `HistoryThumbnailGenerator.swift:390-407`.
- Amendment: Floating thumbnail from the in-memory image via vImage downsample; scrolling reuses the live preview (`ScrollingCaptureCoordinator.swift:1681-1682`). Encode on a utility queue, never main. History JPEG from the in-memory render during finalization. Targets: ≤500 ms from mouse-up (single capture); ≤500 ms from Done (scrolling).
- Changes an accepted product decision (1-12): no

**PERF-4: One ordered, idempotent finalization protocol**
- Target: gap (touches 18, 20, 23)
- Attack: Snapzy encodes directly to the final file (kill mid-write leaves a partial PNG); its retention deletes rows before files (orphans never counted). macOS `fsync` doesn't flush the drive cache.
- Severity: major
- Evidence: `ScreenCaptureManager.swift:1383`; `CaptureHistoryRetentionService.swift:74-97`; `man 2 fsync` (`F_FULLFSYNC`).
- Amendment: Commit: (1) one transaction inserts the row as `committing` with planned paths; (2) encode to `.<id>.png.tmp` in the same directory, `F_FULLFSYNC`, `rename`, fsync the directory; (3) thumbnail the same way; (4) second transaction marks `finalized` with sizes; then enforce quota, then publish. Eviction: mark `evicting`, unlink, delete row. SQLite WAL, `synchronous=FULL`, `fullfsync=ON` (few writes per minute). Launch sweep takes an exclusive `flock` first (debug and release may share a directory), then: delete `*.tmp`; promote a `committing` row only if both files decode at its dimensions, else remove row and files; finish `evicting`; delete row-less app files; drop rows with missing files and log an error code. Debug fault points `kill -9` at each step; recovery run twice yields identical state and database size totals matching disk.
- Changes an accepted product decision (1-12): no

**PERF-5: Enforce quota from database-tracked sizes; scan only to reconcile**
- Target: decision 18
- Attack: Scans are cheap (~1,000 stats in tens of ms, inference); the risk is drift (in-flight temp files, WAL growth, logical vs allocated, database growing during the enforcing commit). Snapzy bug not to port: the orphan-thumbnail sweep compares `<UUID>` against `<UUID>-preview-v2-…` names, deleting every current thumbnail per sweep (launch and daily) and forcing full PNG decodes.
- Severity: major
- Evidence: `CaptureHistoryRetentionService.swift:228-236` vs `HistoryThumbnailGenerator.swift:22,331`.
- Amendment: Sizes stored in rows (logical `st_size`, image + thumbnail); enforce after commit with an indexed `SUM`; database counted as main file + WAL after `wal_checkpoint(TRUNCATE)`; launch reconciliation corrects drift. Tests for a single >1 GB item and equal timestamps.
- Changes an accepted product decision (1-12): no

**PERF-6: Decision 22 targets can't be measured as written**
- Target: decision 22
- Attack: `/usr/bin/xctrace` is installed but refuses to run with CLT only. This Intel generation throttles thermally. "1%" doesn't say one core or all.
- Severity: major
- Evidence: observed `xctrace` error; `footprint`, `vmmap`, `sample`, `powermetrics`, `pmset` present.
- Amendment: Scripted Xcode-free measurement. Idle = menu bar only, 10 min; CPU% = Δ`ps -o time` / wall time, one core. Idle wakeups from `top -stats idlew`. Memory from `footprint`. Latency from app-logged monotonic event timestamps (fits decision 25). Preconditions: AC power, `pmset -g therm` CPU limit 100, 5-min cool-down; 20 runs, median and p95. Check Activity Monitor "Requires High Perf GPU": `MTLCreateSystemDefaultDevice` can switch to the 5500M (Snapzy does this in `AnnotateBlurEffectRenderer.swift:50`), so select the low-power GPU.
- Changes an accepted product decision (1-12): no

**PERF-7: Carbon hotkeys only; no persistent main-thread event taps**
- Target: decisions 4, 22 + gap
- Attack: `RegisterEventHotKey` has no idle cost. Snapzy installs a key-down event tap on the main run loop, first for every keystroke; a main-thread stall (stitching, encoding) lags typing system-wide until macOS disables the tap. Its global `mouseMoved` monitor starts a Task per mouse move while thumbnails show.
- Severity: major
- Evidence: `KeyboardShortcutManager.swift:1641`; `QuickAccessHoverShortcutRegistry.swift:159-186`; `QuickAccessPanel.swift:110-134`.
- Amendment: Global shortcuts via Carbon only. Taps only during overlay sessions, listen-only, on a dedicated thread, handling `tapDisabledByTimeout`. Tracking areas instead of global mouse monitors. Test: no taps or monitors exist while idle.
- Changes an accepted product decision (1-12): no

### Keep
- Decision 16: memory-only originals simplify crash recovery and keep unredacted pixels off disk.
- Decision 19: one command layer enables a repeatable measurement harness.
- Decision 22: baselines before targets is the right order.

### Questions only Prateek can answer
1. Do you capture on an external 5K display, or mostly the built-in screen (typically 3584×2240 at default scaling, ~32 MB/frame, inference)?
2. Should unedited pending thumbnails survive a crash (requires writing them to disk before any editing)?
3. Is stopping scrolling capture at ~10 screens at 5K acceptable, or auto-switch to 1x output beyond that?
