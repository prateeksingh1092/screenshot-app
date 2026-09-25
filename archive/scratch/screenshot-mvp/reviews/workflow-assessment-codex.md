1. **Steps 3–5: restore review-before-commit.** Decision 46 authorizes commits **after review**; local `implement` also orders review before commit. Stop the worker before those stages and delegate review once.

2. **Step 5: document how uncommitted work is reviewed.** Spot-check confirms `code-review` uses `<fixed-point>...HEAD`, excluding pending changes. Explicitly adapt it to review a frozen patch containing staged, unstaged, and untracked files; commit only the reviewed content.

3. **Steps 5–6: require finding validation and post-fix checks.** “One pass” must not permit unresolved correctness failures. Codex validates findings, implements justified fixes, reruns affected checks, and records outstanding issues; avoid repeatedly launching broad reviews merely to obtain zero findings.

4. **Step 6: validate integration before advancing `main`.** Test the combined result against current `main` in an integration worktree, then merge serially; independently passing ticket branches can conflict behaviorally.

5. **Step 1 and ticket completion: define execution status separately from triage.** The tracker reserves `claimed/resolved` for wayfinding, while implementation uses triage labels. Specify coordinator-owned claims, completion evidence, and the tested commit before advancing the frontier.

6. **Periodically: route architecture proposals through selection/grilling and specification before ticketing.** The local architecture skill requires user selection and grilling; automatically sending every proposal through triage skips that process.

7. **Research attribution: distinguish local requirements from upstream commentary.** Spot-check confirms red→green without refactoring, HEAD-only review, and review-before-commit; fresh-session preference and operator-owned ticket closure are not stated in those three local skills.

Verdict: adopt-with-changes