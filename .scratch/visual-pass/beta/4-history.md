# Beta person 4: History person

Run: 2026-09-24, about 20:00 local, driven directly from the main Claude session, with Frisket 73be4ce (PID 47669). History held four captures from 18:29–18:32 that predate every test run; they were not opened, copied or deleted. Only this session's test captures were touched.

| Surface | What I did | What I saw | What VoiceOver would hear (AX) | What failed or felt unfinished | Evidence |
| --- | --- | --- | --- | --- | --- |
| ⌘⇧1 | Hotkey with the pointer and the frontmost app on the ASUS | The History window opened on the **built-in** display (576,109 560×552), a remembered position. **Frisket's focused window stayed a thumbnail card, not History** | Window "Frisket History"; list "History captures, newest first" | Opens away from where the user is working, without keyboard focus | `evidence/p4-history-window.png` |
| Rows | Read | Picture, "W × H", "Sep 24 at HH:MM". Copy, Save and Delete buttons at the bottom. No repeated in-content title | **Each row's image and both text lines all carry the same label** ("History capture, 240 by 140 pixels, Sep 24, 2026 at 19:58"), so VoiceOver would read it three times | Low (a11y) | — |
| **H. Bare Delete key** | Selected a row and pressed Delete | **No confirmation.** It went straight to deleting. On this row it **failed with "Delete failed. Try again."** The capture's thumbnail card was still on screen | Error is a static text line | **Medium:** no confirmation or undo. The failure message is misleading: retrying cannot work while the card is open. The message stayed after the selection changed | `evidence/p4-history-delete-failed.png` |
| Delete button | Selected the 400×500 test row (card closed) and clicked Delete | Deleted immediately with no confirmation (History 11 → 10) | Button "Delete" | Same as H | — |
| Delete after closing the card | Closed the card, then deleted the 240×140 row | Deleted (10 → 9). **Its staged drag PNG stayed in `staging/drag/`** (finding E) | — | See `3-editor.md` | — |
| Copy | Row Copy | Clipboard has `public.png` (320×180) plus `ConcealedType`; silent | — | — | — |
| Save | Row Save | Wrote `~/Pictures/Frisket/Frisket-29E0BDAC-…-r2.png`; silent | — | UUID file name, no confirmation | — |
| Menu icon states | Not reached. The missing-permission state needs revoking the grant, which was out of bounds | — | — | Not tested | — |
