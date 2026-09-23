# 22: Capture exclusion list

**What to build:** in Settings, Prateek lists apps (such as a password manager) whose windows are always left out of every capture.

**Blocked by:** 08, 11

**Status:** ready-for-agent

- [ ] The list is empty by default (decision 37).
- [ ] Every capture mode applies the list through the capture content filter alongside Frisket's self-exclusion.
- [ ] App names never reach logs.
- [ ] Seam 1 test asserts the filter passed to the capture source; manual check with a listed app on screen.

## Comments
