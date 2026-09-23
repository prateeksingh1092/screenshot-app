# 40: Final acceptance

**What to build:** Frisket v1 is verified end to end on this Mac against the spec.

**Blocked by:** 10, 14, 15, 16, 17, 22, 25, 27, 28, 29, 30, 31, 33, 36, 38, 39

**Status:** ready-for-agent

- [ ] The complete manual checklist passes, including cases added after ticket 39 (display unplug and lock outcomes, exclusion list, editor flows).
- [ ] Performance is re-measured after scrolling capture and meets the ratified targets.
- [ ] A universal release build is produced and labelled "arm64 built and signed, never executed"; nothing is distributed (decision C3).
- [ ] All static checks pass: dependency allowlist, dependency direction, identity scrub, licence headers and provenance, no writes before finalization, no free-text logging, no event taps or idle monitors, no network entitlement.
- [ ] Codex assesses the verification report before v1 is declared done.

## Comments
