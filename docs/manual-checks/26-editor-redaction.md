# Ticket 26: editor and Solid redaction (Prateek)

**Pending; not executed by the implementer.** Use only the synthetic test
pattern (decisions 50 and 51). Never capture or keep real content, and keep
every exported image under ignored `.build/`. Follow the signing, install and
launch path in [app-build.md](../app-build.md); never launch the unsigned
verification build. Screen Recording must already be granted
([ticket 08's checklist](08-first-launch.md)).

1. Record the date, OS and build, architecture, tested commit, code signature
   and designated requirement, display scale, and Screen Recording state. On
   this Mac record **arm64 not executed**.

2. Build the synthetic helper and show the pattern:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
     -parse-as-library -target x86_64-apple-macos26.0 \
     -module-cache-path "$PWD/.build/module-cache" \
     Tools/FrisketTestPattern.swift -o .build/FrisketTestPattern
   .build/FrisketTestPattern --show
   ```

   Confirm only synthetic content is visible on the target display.

3. Press **⌃⌥⌘4**, then **Return** without moving the default selection. Its
   320×180-point rectangle matches the pattern exactly.

4. On the thumbnail, choose **Edit** (or press **E** with the thumbnail
   focused through **Focus Latest Thumbnail**). Expected: an "Edit Capture"
   window at the capture's natural size, the **Solid Redaction** tool selected,
   and the thumbnail's buttons disabled while the editor is open.

5. Drag on the canvas from outside the capture's top-left corner to a point
   just past the red quadrant's bottom-right corner, staying clear of the
   centres of the green, blue and white quadrants and the black marker. The
   covered area must turn solid black immediately, with hard edges.

6. Keyboard and VoiceOver, controls only (canvas contents are exempt):
   - Tab and Shift-Tab reach Solid Redaction, Undo, Close Without Changes and
     Done with a visible focus ring. With VoiceOver, confirm "Solid redaction
     tool", "Undo last redaction", "Close editor without changes" and "Done"
     (its help reads "Done: finish editing and add the redacted capture to History"); the canvas is announced as one labelled image.
   - ⌘Z removes the redaction and redraws the red quadrant; drag again.
   - With a redaction present, **Close Without Changes** is disabled and the
     window's close button shows "Press Done to keep the redacted capture"
     without closing. Esc does nothing.
   - Quit Frisket from the menu while the editor is open: expect "Finish
     editing first"; Frisket keeps running.

7. Press **Return** (Done). Expected: the editor closes, and the thumbnail
   switches to the redacted image without Edit or Delete Capture. With
   VoiceOver, the card's controls remain labelled.

8. Verify the History image. Take the newest file under
   `~/Library/Application Support/io.github.prateeksingh1092.frisket.debug/History.noindex/images/`
   (exclude `*.finalization.json`) and run, with `1` on a 1× display:

   ```sh
   .build/FrisketTestPattern --verify-redacted "<that image path>" 2
   ```

   Expected: PASS. Its `.finalization.json` record must contain `"revision":2`.

9. **Copy** from the refreshed thumbnail. In Preview choose File → New from
   Clipboard and save as `$PWD/.build/redacted-copy.png`, then run
   `--verify-redacted` on it. Expected: PASS.

10. Look at the refreshed thumbnail before Copy in step 9: it must show the
    black box, never red. A screenshot of the thumbnail is not required and
    must not be kept.

11. Close-without-changes path: take a new capture, choose Edit, then close
    the editor without drawing. The thumbnail returns with all buttons
    enabled; Dismiss keeps it in History as usual.

12. Record PASS, FAIL or not-executed for each step, with verifier output.
    Delete the exported PNGs under `.build/` after recording. Ticket status and
    checkboxes belong to the coordinator.

13. With History unavailable before image writes in an authorized synthetic
    test setup, Copy the pattern. The thumbnail remains with Copied, Edit,
    Delete and Dismiss. Edit, redact and Done without copying anything else:
    paste the result into Preview under `.build/` and run `--verify-redacted`.
    While History remains unavailable, Edit again, cover another synthetic
    region, and Done. The unchanged clipboard must now contain both redactions.
    Repeat, copying an unrelated synthetic text marker between Copy and Done;
    that marker must remain on the clipboard. A capture whose History write
    was interrupted cannot be edited. Automated fault-injection tests cover
    this state; this checklist does not require altering the real History root.

14. If conditional clipboard replacement fails, expect “Could not replace the
    earlier copy” and a refreshed redacted thumbnail. Explicit Copy must deliver
    the redacted result. Encoding failure or memory-budget rejection must keep
    the editor open with its redactions and undo history intact, leave thumbnail
    actions disabled, and offer Retry Done without suggesting saving the original.
    While Done is pending, repeated Done, Undo, canvas edits and closing must not
    change the submitted document. After a successful retry, the editor closes
    and every output contains the redacted result. Automated fault-injection
    tests cover rejection and retry; this checklist does not require changing
    the production memory budget or encoder.

The editor tracer doesn't yet implement ticket 30's Finalize / Delete capture
/ Cancel prompt or quit choices, ticket 27's crop, or ticket 31's editor Copy,
Save and drag.
