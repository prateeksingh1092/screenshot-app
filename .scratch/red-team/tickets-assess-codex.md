1. **#1:** Remove choosing a project licence; decision 43 defers that until publication. Keep dependency notices, ignore rules, and staged-diff review.

2. **#2–4:** Remove #1’s commit as a blocker for #2; merge #4’s initial logging into #6. A standalone logging layer is horizontal work, not justified prefactoring.

3. **#3:** Separate Xcode installation from identity creation; schedule Personal Team setup when the first signed app build needs it, matching decision 42.

4. **#6:** Split into a fixture-backed capture→Copy command slice and a real area-capture→thumbnail→Copy slice. Assign typed identities, duplicate/stale-command handling, and separate commit/delivery outcomes explicitly.

5. **#5, #28–29:** Split the trial into standalone extraction/testing and strip-storage/full-size memory validation; explicitly assign the fresh-stitcher fallback. Each current ticket hides substantial algorithmic work beyond one context.

6. **#7–10:** Put finalization-record creation in #7, before #8 consumes it. Connect Save/drag to the shared finalization policy; their current #6-only blockers omit History integration.

7. **#8, #10, #13–14:** Extend recovery tests whenever handoff, deletion, or eviction adds interruption points. #8 cannot finish all crash coverage before those operations exist.

8. **#11–12:** Split stack behavior from termination/display-event handling. Remove #9 as a blocker for basic stack behavior; assign drag and editor accessibility checks after #10 and #22 exist.

9. **#16–17:** Split overlay geometry, modifiers, and display/Space transitions. Full-screen capture need not wait for every area-selection modifier; give window and full-screen capture separate slices with genuine prerequisites.

10. **#22–26:** Keep #22’s tests to available outputs; add export-path canaries in #26, transformed-redaction cases in #23, and sampling-effect cases in #24. Otherwise #22 promises tests against nonexistent features.

11. **#23:** Separate annotations from crop; each needs its own complete editor→render→delivery behavior and pixel tests.

12. **#6, #7, #15, #28:** Assign pending-byte ownership, dependency-direction checks, migration fixtures, and delivery retries explicitly. Make #15 depend on delivery paths it claims to keep working.

13. **#30:** Separate external baselines from Frisket measurement; baselines need not wait for #6. Repeat acceptance measurements after #28–29.

14. **#6, #12–31:** Allocate VoiceOver labels and keyboard checks to every UI slice. Add explicit homes for network exclusion, idle-monitor checks, restore reconciliation, signing stability, and universal-release verification; retain #31 as an initial run, followed by complete acceptance.

Verdict: rework