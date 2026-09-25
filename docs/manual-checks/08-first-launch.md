# 08: First launch and signed rebuilds

Set up as in [README.md](README.md). Ask Prateek before the signed build, the
install and the launch. The harness checks the captured pixels (`area`); this
file checks the grant and the first-launch path.

1. Install the signed build as in [app-build.md](../app-build.md). Keep the
   designated requirement and entitlements output for step 4.
2. Launch the installed app and run `.build/FrisketTestPattern --show`.
3. Press ⌘⇧4. On a first run, Frisket shows its permission recovery panel, not
   a Selection. Choose **Request Screen Recording** and allow it in System
   Settings › Privacy & Security › Screen & System Audio Recording. If macOS
   asks, use **Quit & Reopen**; it must reopen the installed path. Press ⌘⇧4
   again and Return: a Thumbnail appears. A blank first attempt is not a pass.
4. **Rebuild twice.** Quit Frisket. Rebuild with the same signed command,
   replace the bundle at the same path, and compare the designated
   requirement. Launch it and capture again. No new grant may be asked for.
   Do it a second time. Record both requirements and both outcomes. A new
   prompt is a failure to investigate, not a reason to reset TCC.
5. Press Esc during a Selection with the pattern helper frontmost. The overlay
   closes and Frisket does not become the active app.

Record PASS, FAIL or not run for: first grant, rebuild 1, rebuild 2, Esc
without activation.
