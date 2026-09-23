# 01: Repository hygiene before the first commit

**What to build:** the repository is safe to commit for the first time: third-party material is credited, generated and personal files are ignored, and nothing secret is staged.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Third-party notices credit GRDB and the copied Matt Pocock skills (Snapzy is added only if ticket 34 ports the stitcher).
- [x] No project licence file is added while the repository stays private (decision 43).
- [x] Ignore rules cover build outputs, Xcode user data, local test artefacts, and any captured images or recordings.
- [x] A staged-diff review for secrets and personal content is run and its result recorded (no secret values written into markdown).
- [x] The first commit is made only after Prateek approves the staged set (approved under decision 46; coordinator reviewed the manifest and committed it without ticket 02's in-progress package files).

## Comments

### 2026-09-22 — implementation and proposed-set secret review

- Implemented by Codex under the ticket-specific ownership boundary. Changed
  `.gitignore`, `THIRD-PARTY-NOTICES.md`, this ticket, and the exact proposed
  [first-commit file manifest](../first-commit-paths.txt). No package, source,
  test, or static-check script was created or edited by this worker.
- Review basis: the branch is unborn and the index is empty. The user's explicit
  no-staging instruction replaces a literal staged diff with review of all
  proposed additions against the empty tree. Enumerated the union using
  `git ls-files --cached --others --exclude-standard -z`; scanned every listed
  file's complete contents and recorded the exact set in the manifest. No
  `git add`, commit, Git configuration change, or network request was performed.
- Method: local Python standard-library scan for private-key blocks, provider
  token formats (GitHub, OpenAI/Anthropic, Slack, AWS, Google), credential
  assignments, JWTs, credential-bearing URLs, email addresses, phone/SSN-like
  identifiers, personal-data keywords, home-directory/absolute paths, and
  high-entropy strings. Inspected file types and symlinks and reviewed all
  flagged paths/contexts. Scanner output reported categories and locations,
  never suspected secret values. Follow-up checks covered the final manifest
  and the ticket-02 files present at handoff.
- Final snapshot: 177 files; 0 credential/contact-pattern matches, 24 reviewed
  path-context matches, 0 binary files or symlinks, and 0 index entries. The
  manifest's SHA-256 is
  `cfd4ba6da337c078a330667e585e4afc3dd7359448df1c0057719182733a8c8c`.
- Result: no secrets, access tokens, private keys, personal contact/identity
  data, binary captures, or symlinks found in the proposed set. Entropy matches
  were public source URLs, documented identifiers, and relative code paths;
  the personal-data keyword hit was technical prose. Existing owner name,
  public bundle/GitHub identity, local tooling paths, and the specified export
  folder were retained. No path disclosed an unrelated personal location
  beyond the repository's existing context. This is a pattern-based local
  review, not a guarantee that arbitrary secrets can be detected.
- Exclusions: raw `.scratch/research/` downloads, `.scratch/evaluation/`
  checkouts/probes/runner records, task prompts, JSONL session output, generated
  build/test/runtime data, captured media, credentials, and signing material.
  Authored project docs, decisions, tickets, review ballots, copied skills with
  provenance, and the minimal checked-in IDE/model configuration remain eligible.
- Validation: 24 ignored-path and 16 visible-path cases passed through
  `git check-ignore --no-index`, including nested SwiftPM and Xcode output;
  package manifests, source, tests, and scripts remain visible. All 77 copied
  skill files match their SHA-256 provenance entries, and the reproduced Matt
  Pocock licence matches the retained licence text. No root project licence.
  GRDB's complete MIT text is included as an advance notice; compare against
  the pinned upstream licence when first linked. Snapzy remains conditional.
- Required code review: separate Codex Standards and Spec reviewers assessed
  the empty-tree additions. Standards: 0 findings. Spec: 0 findings. No
  application code changed, so this ticket required no Swift build/typecheck
  or test-suite run; ticket 02 owns those. Local verification ran on x86_64,
  macOS 26.7 (25G229); arm64 was not executed.
- During final verification the system Git launcher encountered an Xcode
  licence gate. Using the existing Command Line Tools Git with a process-local
  `DEVELOPER_DIR` completed the checks; no system selection, licence acceptance,
  install, or Git configuration was changed.
- Handoff boundary: the manifest is a snapshot, not permission to stage a
  directory recursively. Ticket 02 is running concurrently; its final changes
  and any other files added or modified after this review must be reviewed by
  the coordinator before staging. The index remains empty. The commit criterion
  is intentionally unchecked: the coordinator handles final staged-set approval
  and the first commit under the user's instruction.

## Answer

Repository hygiene is ready for coordinator review. Every non-commit criterion
is complete; the first commit is deliberately deferred.
