# Screen Recording permission (ticket 23)

`CapturePermissionState` in FrisketCore has five cases: `notAsked`, `denied`,
`granted`, `revokedWhileRunning`, `needsRelaunch`. The required
`CapturePermissionSource.capturePermission()` interface is injected into
`CaptureCommandLayer`. There is no permissive default. Both capture commands
check it before invoking either pixel source, so a missing grant cannot create
an overlay. Missing access returns `CaptureCommandOutcome.permissionRequired`;
permission failures from a source use the same typed outcome. Reservations are
released on refusal. Copy and Delete of existing Pending captures still work.

## Platform evidence

The adapter uses the installed SDK's `CoreGraphics/CGWindow.h` Boolean functions
`CGPreflightScreenCaptureAccess` and `CGRequestScreenCaptureAccess`, and the
`SCStreamErrorDomain` / `SCStreamError.Code.userDeclined` authorization error
from `ScreenCaptureKit/SCError.h`. No private TCC database or Settings scraping.
No network research was performed under the implementer brief.

| State | Evidence |
| --- | --- |
| Not asked | Negative preflight; this bundle's request-history marker absent. |
| Denied | Negative preflight; request history exists; no grant observed in this process. |
| Granted | Positive preflight, with no latched relaunch requirement. |
| Revoked while running | Preflight becomes negative after this process observed a positive grant. |
| Needs relaunch | Explicit request returns accepted but preflight remains negative, or SCK returns authorization refusal while preflight is positive. Latched for this process. |

The app writes only a Boolean request-history marker to bundle-scoped defaults.
It also records that marker when it sees an existing grant, so a ticket 08 grant
is recognized without another request. It never stores a grant as authorization.
The marker cannot prove virgin TCC state if someone cleared defaults, or denial
if permission was manipulated externally before Frisket recorded its history.
The public Boolean functions cannot distinguish an externally granted but
process-stale permission when both report false. Recovery therefore always
offers Quit & Reopen, including in denied/revoked states. Needs-relaunch is a
conservative recovery interpretation of contradictory API evidence, not a query
of an OS relaunch-status enum. Unrelated SCK errors remain capture-unavailable.

Preflight is rechecked on every capture, before and after shareable-content
loading, and before and after screenshot acquisition. The menu indicator also
refreshes every two seconds, when the menu opens, and on application activation.
No screen pixels are requested by these refreshes. If permission is revoked
during selection, selection finishes/cancels normally; before taking pixels the
adapter rechecks access and returns recovery. No pending image is accepted after
a detected loss of access.

## System alerts and selection ordering

The command gate performs no permission request. Missing access opens an ordinary
recovery panel. Only its explicit Request Screen Recording button invokes
`CGRequestScreenCaptureAccess`, after closing the panel; capture invocation is
blocked while that request executes. Capture never resumes automatically after
the request. While recovery is open, repeated capture commands focus it instead
of opening selection.

After a granted gate, both sources **await** `SCShareableContent` loading before
selection/display capture. The platform creates `SelectionOverlay` lazily, only
when selection actually starts. Thus an authorization prompt raised during
shareable-content loading completes before any overlay is constructed. A refusal
returns typed recovery. SCK screenshot acquisition runs after the selection has
been hidden and the window transaction flushed, so any prompt raised there also
has no overlay above it. All app capture invocations are serialized by the app's
existing capture-in-progress guard. Fixture tests suspend shareable-content
preparation to verify that no selection appears while it is pending. Actual
macOS alert ordering remains a manual acceptance check; Frisket cannot inspect
arbitrary external system alerts through these APIs.

## Recovery actions

The Screen Recording deep link used by **Open Privacy & Security** is:

`x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`

If opening fails, a static notice gives the equivalent System Settings path.
The pane's actual title/routing on the installed OS is in the manual checklist.

**Quit & Reopen** uses the same quit policy as normal Quit, including explicit
pending-capture confirmation. Cancel clears the reopen intent. Only after quit
is accepted does a small `/bin/sh` helper wait for the current PID to exit and
call `/usr/bin/open` with `~/Applications/Frisket.app`. PID/path are quoted
positional arguments, never interpolated shell code. The running bundle must
match that fixed installed path and contain the app executable; otherwise quit
is cancelled with a static notice. It never opens an Xcode build product or
launches a second instance before the original exits. The helper is runtime
code only; it was not executed by the implementer.

See [the complete manual checklist](manual-checks/23-permission-states.md).
The project remains stopped before review, signing, installation or runtime
permission checks; ticket ownership and completion remain with the coordinator.
