# 26: The editor by keyboard and VoiceOver, and leaving it

Set up as in [README.md](README.md). The harness checks the editor's pixels:
arrow and label placement, typed label text, a grey Solid redaction under Blur
and Magnify, crop size, and that Done, Copy and Save are on screen. The
package tests check that every output matches the preview. This file checks
what a person must see, hear or press.

Over `.build/FrisketTestPattern --show`, press ⌘⇧4, Return, then E on the
Thumbnail (⌘⇧2 focuses it).

1. **Tools.** Each key picks its tool, with no modifier: V Select, R Solid
   Redaction, C Crop, S Shape, A Arrow, L Line, T Text, B Blur, M Magnify. The
   editor opens on Solid Redaction. VoiceOver reads each tool's name, the
   redaction colour swatches ("Redaction colour: Grey"), the Arrow style,
   line width, Label Size and Label Style menus, and Done.
2. **Looks.** Draw each Arrow style (Standard, Curved, Double) and a Line, and
   type a label in each Label style. They look right at each width and size.
   A shape is an outline only. This is a judgement the harness can't make.
3. **Marks by keyboard.** Tab and Shift-Tab step through the marks; VoiceOver
   reads each one ("Arrow from 2, 38 to 38, 38"). The arrow keys move the
   selected mark by 1 point, 10 with Shift. Delete removes it.
4. **Undo.** After a crop, the Edit menu reads "Undo Crop". ⌘Z and ⌘⇧Z work.
   Undoing every edit lets Esc close the editor without asking.
5. **Close with edits.** Draw a redaction and close the window. A confirmation
   asks "Keep this edited capture?" with Finalize (Return), Delete Capture and
   Cancel (Esc). Cancel keeps the editor; Finalize keeps the edit in History;
   Delete Capture writes nothing.
6. **Quit with the editor open.** Choose Quit. The same confirmation shows.
   Quit waits for the answer.
7. **Drag from the editor.** Drag "Drag the edited capture" into Finder. The
   dropped file matches the canvas.
