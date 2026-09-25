<!-- Source: Cursor Claude Opus 5.5 High, data architect, agent 3f6a5555-a98c-47eb-8ad4-466e20029e9d. Final response saved verbatim, 00:11 UTC Sep 23. -->
## DATA: reconciliation
DATA-2: accept: The launch sweep adopts a file that has no row only if the file carries a validated finalization record written by the finalizer (matching UUID and finalization marker, and the image decodes at the recorded dimensions); otherwise it discards the file.
DATA-3: accept: No original pixels are ever written to storage, and nothing is written under the storage root before an authorized finalization request; staging writes made after that request are permitted.
DATA-4: accept: Recovery archives stay app-owned and count toward usage until the user explicitly exports or deletes them, wherever they are stored.
DATA-5: accept: Age eviction is deferred when the clock looks anomalous: it reads earlier than the newest committed capture, or it has jumped past the last recorded sweep by more than the retention window. Future-dated captures are normalized once and recorded.
