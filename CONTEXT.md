# Screenshot capture

Capturing visible content on a Mac, preparing it for use, and delivering the resulting image or extracted text.

## Language

### Capturing

**Capture**:
A still image obtained from a selected area, window, or entire screen.
_Avoid_: Recording (which implies moving images)

**Selection**:
The rectangle chosen on screen for an area capture.
_Avoid_: Region, crop (crop happens in the editor)

**Origin display**:
The display on which a selection begins; the selection cannot leave it.

**Capture exclusion list**:
Apps whose windows are always left out of captures.

### Editing

**Annotation**:
A visual addition to a capture, such as an arrow, label, or shape.

**Solid redaction**:
An opaque replacement of a selected image region to conceal its contents in the delivered image. Its fill is one colour from a small neutral palette, black by default, always at full opacity.
_Avoid_: Blur, pixelate, black box (none of these is guaranteed to conceal)

**Blur**:
An editor effect that softens part of a capture. It never conceals content.
_Avoid_: Redaction

**Magnify**:
An editor effect that enlarges part of a capture in place. It never conceals content.
_Avoid_: zoom

**Mark**:
Anything drawn on a capture in the editor that stays an object after drawing: an annotation, a Solid redaction, a Blur or a Magnify box. A mark can be selected, moved, resized, deleted and restyled. A crop is not a mark.

**OCR**:
Extraction of text from a capture so that the text can be copied or otherwise used.

### Lifecycle

**Thumbnail**:
The small floating preview of one capture, shown right after capturing or editing, from which the capture is copied, saved, dragged, edited, or dismissed.
_Avoid_: Card, Quick Access Overlay, popup

**Notice**:
Something Frisket tells the user without blocking: shown on the notice line (or, for a failure a Thumbnail can retry, on its status line) and announced to VoiceOver. Only a destructive or irreversible choice (a **Confirmation**) is modal (DA-5).
_Avoid_: Alert, dialog, popup

**Pending capture**:
A capture that exists only in memory, shown as a thumbnail or open in the editor, and not yet finalized or deleted. Nothing about it reaches storage before an authorized finalization request.
_Avoid_: Draft, unsaved capture

**Finalized capture**:
A capture committed to history, either by dismissing its unedited thumbnail or by finishing an edit with Done, Copy, Save, or a drag. An edited finalized capture contains the flattened result rather than reversible annotation layers or its original image.

**History**:
The app-managed collection of finalized captures, subject to the user's retention limits.
_Avoid_: Export folder (explicitly saved files are separate from history retention)

**App-owned file**:
A file Frisket created under its history storage root and tracks by capture identifier. Retention and the size limit apply only to these.
_Avoid_: Deciding ownership from a file's path

**Export**:
A copy of a finalized capture's rendered image placed outside the app-owned root by Save, drag, or Export. Frisket never moves, tracks, or deletes an export.
