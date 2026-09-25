# 100: Remember the editor's last-used styles (decision 93)

**What to build:** The redaction colour, ink colour, arrow style, line width, label size and label style persist through `PreferenceKey` and UserDefaults, across editors and relaunches.

**Blocked by:** 99. **Status:** ready-for-agent (medium effort).

- [ ] A core test: a style model loads its defaults when nothing is stored, round-trips every value, and ignores a stored value that is invalid (for example a redaction colour outside the palette).
- [ ] A new editor opens with the last choices.
