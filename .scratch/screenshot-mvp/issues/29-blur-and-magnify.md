# 29: Blur and magnify over the redacted composite

**What to build:** Prateek can place blur or magnify effects, and an effect placed over a redaction can never reveal what's under it.

**Blocked by:** 26

**Status:** ready-for-agent

- [ ] Solid redactions are applied to the base layer before any pixel-sampling effect; effects read only the redacted composite.
- [ ] Blur is an annotation effect, never offered as a redaction method.
- [ ] Canary cases with overlapping blur and magnifier across every available output.

## Comments
