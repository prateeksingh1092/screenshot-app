#!/bin/bash
# The unattended live beta matrix (plan §4; ticket 48). It drives the real screen, keyboard,
# mouse and clipboard, so run it only when Prateek has said he is away.
#
#   Tools/LiveHarness/beta-matrix.sh --dry-run [--display builtin|external|all] [--row ID]
#   Tools/LiveHarness/beta-matrix.sh --live    [--display builtin|external|all] [--row ID]
#
# Rows live in matrix.tsv. Each row runs once per chosen display and ends as PASS, XFAIL
# (failed while its defect is open), XPASS (passed although its defect is marked open: flip
# the row), FAIL or ERROR. Any FAIL, XPASS or ERROR makes the exit status 1.
# The clipboard is saved first and restored on every exit path. Evidence and the report go
# to .build/live-harness/runs/<time>/, which git ignores. Screenshots are cropped to the
# test windows. Only synthetic pattern content is ever captured.
#
# Time cap (CLAUDE.md): a live run lasts at most --minutes (default and maximum 9, per display). No row starts in
# the last minute, and a watchdog ends the run at the cap. Rows left over are SKIP. Run one display at a time.
# Every FAIL, XPASS, ERROR and SKIP is written to failures.md with its log tail and evidence path,
# so one file shows all the failures before any row is rerun.
set -u

here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../.." && pwd)
H="$root/.build/live-harness"
bundle=${FRISKET_BUNDLE_ID:-io.github.prateeksingh1092.frisket.debug}
history_root="$HOME/Library/Application Support/$bundle/History.noindex"
exports="$HOME/Pictures/Frisket"

mode="" display_choice=all only_row="" minutes=9
usage="usage: $0 --dry-run|--live [--display builtin|external|all] [--row ID] [--minutes 1-9]"
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) mode=dry ;;
    --live) mode=live ;;
    --display) display_choice=$2; shift ;;
    --row) only_row=$2; shift ;;
    --minutes) minutes=$2; shift ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$mode" ] || { echo "$usage" >&2; exit 2; }
case $minutes in ''|*[!0-9]*) echo "$usage" >&2; exit 2 ;; esac
[ "$minutes" -ge 1 ] && [ "$minutes" -le 9 ] || { echo "--minutes must be 1-9 (the 9-minute cap)" >&2; exit 2; }

rows() { awk -F'\t' '!/^#/ && NF == 4' "$here/matrix.tsv"; }
if [ -n "$only_row" ] && ! rows | cut -f1 | grep -qx "$only_row"; then
  echo "no row '$only_row' in matrix.tsv" >&2; exit 2
fi

# ---------------------------------------------------------------- dry run: no side effects at all
if [ "$mode" = dry ]; then
  echo "Live beta matrix plan (dry run: nothing is launched, typed, clicked or copied)"
  echo "Displays: $display_choice (resolved at run time from 'drive displays')"
  echo "Clipboard: saved before the first row, restored on exit"
  echo "Evidence and report: .build/live-harness/runs/<time>/"
  printf '%-22s %-7s %-6s %s\n' ROW DEFECTS EXPECT CHECK
  rows | while IFS=$'\t' read -r id defects expect check; do
    [ -z "$only_row" ] || [ "$id" = "$only_row" ] || continue
    printf '%-22s %-7s %-6s %s\n' "$id" "$defects" "$expect" "$check"
  done
  for tool in pattern drive meter sckwins sheet; do
    [ -x "$H/$tool" ] || echo "note: $H/$tool is missing; run Tools/LiveHarness/build.sh before --live"
  done
  exit 0
fi

# ---------------------------------------------------------------- live preconditions
for tool in pattern drive meter; do
  [ -x "$H/$tool" ] || { echo "missing $H/$tool: run Tools/LiveHarness/build.sh" >&2; exit 2; }
done
"$H/drive" frisket >/dev/null 2>&1 || { echo "Frisket ($bundle) is not running; launch the installed app first" >&2; exit 2; }
# Another screenshot app holding the ⌘⇧ shortcuts takes every capture key (2026-09-25: CleanShot X ran the whole matrix).
if pgrep -f '/CleanShot X.app/Contents/MacOS/' >/dev/null; then
  echo "CleanShot X is running and takes the ⌘⇧ shortcuts; quit it, relaunch Frisket, then run again" >&2; exit 2
fi

run="$H/runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run"
report="$run/report.tsv"
printf 'row\tdisplay\tdefects\texpect\tresult\tverdict\n' >"$report"
private=$(mktemp -d -t frisket-harness)   # holds the user's saved clipboard: owner-only, deleted on exit
chmod 700 "$private"
"$H/drive" clip-save "$private/clipboard.plist" >>"$run/harness.log" 2>&1 || { echo "could not save the clipboard" >&2; exit 2; }

failures="$run/failures.md"
echo "# Failures in $(basename "$run") (read all of these before rerunning any row)" >"$failures"
# The watchdog ends the run at the cap; the EXIT trap still restores the clipboard.
( sleep $(( minutes * 60 )); kill -TERM $$ 2>/dev/null ) &
watchdog=$!
cleanup() {
  pkill -P "$watchdog" 2>/dev/null; kill "$watchdog" 2>/dev/null   # its sleep too, so no late kill hits a reused PID
  # A run stopped mid-row can leave a selection overlay or an alert up, which blocks Quit and the
  # next install. Cancel them while the pattern is still frontmost (drive types only to it or Frisket).
  if "$H/drive" cgwin 2>/dev/null | grep -q 'layer=1000'; then "$H/drive" key 53 >/dev/null 2>&1; sleep 0.5; fi
  "$H/drive" axpress frisket "OK" >/dev/null 2>&1
  pkill -x pattern 2>/dev/null
  if "$H/drive" clip-restore "$private/clipboard.plist" >>"$run/harness.log" 2>&1; then
    rm -rf "$private"
  else
    echo "WARNING: clipboard restore failed; the saved copy is in $private" >&2
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'echo "STOPPED at the ${minutes}-minute cap; rows after the last one listed did not run" | tee -a "$failures"; exit 124' TERM

# ---------------------------------------------------------------- helpers
log=/dev/null
drv() { "$H/drive" "$@" >>"$log" 2>&1; }
note() { echo "  $*" >>"$log"; }
nap() { sleep "$1"; }
calc() { awk "BEGIN { printf \"%d\", $1 }"; }   # integer result of a float expression
wait_for() {  # wait_for SECONDS COMMAND…: poll every 0.25 s
  local limit=$1; shift
  local tries=$(( limit * 4 ))
  while [ $tries -gt 0 ]; do "$@" && return 0; nap 0.25; tries=$(( tries - 1 )); done
  return 1
}

# Display geometry in CG global points (top-left origin): DID DX DY DW DH DS, CX CY.
use_display() {
  local line
  line=$("$H/drive" displays | awk -F'\t' -v k="$1" '$2 == k { print; exit }')
  [ -n "$line" ] || return 1
  IFS=$'\t' read -r DID _ DX DY DW DH DS <<<"$line"
  CX=$(( DX + DW / 2 )); CY=$(( DY + DH / 2 ))
}

hotkey() {  # hotkey 1–6: ⌘⇧ and the number (key codes 18–21, 23, 22)
  local code
  case $1 in 1) code=18 ;; 2) code=19 ;; 3) code=20 ;; 4) code=21 ;; 5) code=23 ;; 6) code=22 ;; esac
  drv key "$code" cmd,shift
}
key() { drv key "$@"; }   # Return 36, keypad Enter 76, Esc 53, Tab 48, Page Down 121

pattern_running() { pgrep -x pattern >/dev/null; }
pattern_bounds() { "$H/drive" cgwin | awk -F'\t' '$1 == "pattern" { print $4; exit }'; }   # "x y w h" of the front pattern window
pattern_visible() { [ -n "$(pattern_bounds)" ]; }
pattern_up() {  # pattern_up MODE: the synthetic pattern on the current display
  pkill -x pattern 2>/dev/null; nap 0.4
  "$H/pattern" "$1" --display "$DID" >>"$log" 2>&1 &
  wait_for 6 pattern_visible || { note "pattern did not appear"; return 1; }
  nap 0.6
}
overlay_up() { "$H/drive" cgwin | awk -F'\t' '$1 != "pattern" { split($3, l, "="); if (l[2] + 0 >= 1000) found = 1 } END { exit !found }'; }
card_present() { "$H/drive" axfind frisket "Copy capture" >/dev/null 2>&1; }
# The newest Thumbnail's controls start disabled for a moment after it appears; press only once enabled.
card_ready() { "$H/drive" axfind frisket "Copy capture" 2>/dev/null | grep -q 'enabled="1"'; }
editor_up() { "$H/drive" axfind frisket "Capture canvas" >/dev/null 2>&1; }
editor_gone() { ! editor_up; }
no_cards() { ! card_present; }
count_files() { local n; n=$(ls -1 "$1" 2>/dev/null | grep -c "${2:-.}"); echo "${n:-0}"; }   # names only; never opens a file
history_images() { count_files "$history_root/images" '\.png$'; }
drag_staging() { count_files "$history_root/staging/drag"; }

shot_pattern() {  # evidence cropped to the front pattern window (or its central 800×600 when full-display)
  local x y w h
  read -r x y w h <<<"$(pattern_bounds)"
  [ -n "${x:-}" ] || return 0
  if [ "$w" -gt 1000 ]; then x=$(( x + w / 2 - 400 )); y=$(( y + h / 2 - 300 )); w=800; h=600; fi
  drv seq "shot $x $y $w $h $ev/$1.png"
}

# Drag a new Selection with one drag. Callers start it outside the previous Selection, because a
# press inside a hole goes through to the app underneath (D4).
select_rect() {
  local x0=$1 y0=$2 x1=$3 y1=$4
  # One drag only. A second drag in the same activation doesn't replace the first Selection
  # (candidate D28, seen 2026-09-24), so the old decoy drag captured the decoy.
  drv seq "down $x0 $y0" "drag $(( (x0 + x1) / 2 )) $(( (y0 + y1) / 2 ))" "drag $x1 $y1" "wait 120" "up $x1 $y1"
  nap 0.3
}
capture_area() {  # capture_area X0 Y0 X1 Y1: ⌘⇧4, select, Return, wait for the Thumbnail
  drv move $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
  hotkey 4; nap 1
  select_rect "$@"
  key 36
  wait_for 6 card_present && wait_for 4 card_ready
}
capture_pattern() { capture_area $(( CX - 160 )) $(( CY - 90 )) $(( CX + 160 )) $(( CY + 90 )); }
card_copy() { wait_for 4 card_ready; drv axpress frisket "Copy capture" && nap 1; }
clip_to() { drv clip-png "$ev/$1.png"; }

open_editor() {  # a real click on the Thumbnail's Edit (an AX press doesn't activate Frisket)
  if ! drv axclick frisket "Edit capture"; then
    # If the click guard refuses the point, fall back to an AX press and activate Frisket.
    drv axpress frisket "Edit capture" || return 1
    wait_for 6 editor_up && drv activate frisket
  fi
  wait_for 6 editor_up && drv axfocus frisket "Capture canvas" && nap 0.5
}
# The image's on-screen rectangle inside the canvas, for an image of aspect W:H: IX IY IW IH.
image_rect() {
  local fx fy fw fh
  read -r fx fy fw fh <<<"$("$H/drive" axframe frisket "Capture canvas")"
  [ -n "${fh:-}" ] || return 1
  if awk "BEGIN { exit !($fw / $fh > $1 / $2) }"; then
    IH=$fh; IW=$(calc "$fh * $1 / $2"); IX=$(calc "$fx + ($fw - $IW) / 2"); IY=$fy
  else
    IW=$fw; IH=$(calc "$fw * $2 / $1"); IX=$fx; IY=$(calc "$fy + ($fh - $IH) / 2")
  fi
}
at() { calc "$1 + $2 * $3"; }   # at ORIGIN FRACTION SIZE
tool() {  # select an editor tool; pressing the selected tool again deselects it
  "$H/drive" axfind frisket "$1" 2>/dev/null | grep -q 'value="1"' && return 0
  drv axpress frisket "$1" && nap 0.3
}
canvas_click() {  # canvas_click FX FY as a fraction of the image rectangle
  drv click "$(at $IX "$1" $IW)" "$(at $IY "$2" $IH)"
  nap 0.4
}
canvas_drag() {  # canvas_drag FX0 FY0 FX1 FY1 as fractions of the image rectangle
  drv drag "$(at $IX "$1" $IW)" "$(at $IY "$2" $IH)" "$(at $IX "$3" $IW)" "$(at $IY "$4" $IH)" 20
  nap 0.4
}
# Finish an edit through the close sheet: ⌘W, then Return (Finalize, the sheet's default). This path
# works whatever has focus, including a label being typed, where Return ends the label and is not Done (D5).
editor_done() {
  drv key 13 cmd; nap 0.8
  editor_up && key 36
  wait_for 6 editor_gone; nap 0.8
}
# The edited result, copied from its Thumbnail after Finalize, so the row reads the finalized revision.
editor_copy() { editor_done && wait_for 6 card_present && card_copy; }   # card_copy waits for card_ready
close_editor() {  # every open editor; edits are finalized (test captures stay in History)
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    editor_up || return 0
    drv axfocus frisket "Capture canvas"; editor_done
  done
}
close_cards() {  # every Thumbnail, through its "Close thumbnail and keep capture in History" action
  local y
  for y in $("$H/drive" cgwin | awk -F'\t' '$1 == "Frisket" && $3 == "layer=3" { split($4, b, " "); print b[2] }'); do
    drv cardact "$y" "Close thumbnail"
  done
  nap 0.5
}
dismiss_alert() { drv axpress frisket "OK"; }

reset_state() {  # best effort between rows: no overlay, no editor, no alert, no Thumbnails
  if overlay_up; then
    pattern_running || pattern_up --show
    drv click $(( DX + 12 )) $(( DY + DH - 12 )); key 53; nap 0.5
  fi
  dismiss_alert
  close_editor
  close_cards
  wait_for 5 no_cards || note "Thumbnails still open after closing them"
  pkill -x pattern 2>/dev/null
  nap 0.5
}

# ---------------------------------------------------------------- rows (return 0 = the check passed)
row_area() { pattern_up --show && capture_pattern && card_copy && clip_to area && "$H/pattern" --verify "$ev/area.png" "$DS" >>"$log" 2>&1; }

row_area_click_inside() {
  pattern_up --show-window || return 1
  local x y w h before after
  read -r x y w h <<<"$(pattern_bounds)"
  # Mouse-up accepts a Selection, so the hole to press into is the preselected last Selection
  # of the next activation. The first capture sets it over the window, title bar included.
  drv move $(( x + w / 2 )) $(( y + h / 2 )); hotkey 4; nap 1
  select_rect $(( x + 10 )) $(( y + 2 )) $(( x + w - 10 )) $(( y + h - 10 ))
  wait_for 6 card_present || { note "first capture gave no Thumbnail"; return 1; }
  hotkey 4; nap 1
  overlay_up || { note "no overlay on the second activation"; return 1; }
  before=$(pattern_bounds)
  # A press-drag on the title bar inside the hole: it must start a Selection, not move the window.
  drv seq "down $(( x + w / 2 )) $(( y + 12 ))" "drag $(( x + w / 2 + 50 )) $(( y + 62 ))" "drag $(( x + w / 2 + 100 )) $(( y + 112 ))" "up $(( x + w / 2 + 100 )) $(( y + 112 ))"
  nap 0.6; after=$(pattern_bounds); shot_pattern area-click-inside
  note "pattern window before=$before after=$after"
  [ "$before" = "$after" ] || return 1
  # Esc cancels an open overlay; the pattern (which quits on Esc) must not receive it.
  hotkey 4; nap 1; key 53; nap 0.6
  ! overlay_up && pattern_running
}

row_top_row() {
  pattern_up --show || return 1
  drv move "$CX" "$DY"; hotkey 4; nap 1
  key 53; nap 0.6   # without an Origin display the overlay isn't key, Esc reaches the pattern and quits it
  ! overlay_up && pattern_running
}

row_window() {
  pattern_up --show-window || return 1
  local x y w h
  read -r x y w h <<<"$(pattern_bounds)"
  drv move $(( x + w / 2 )) $(( y + h / 2 )); hotkey 5; nap 1.5
  shot_pattern window-picker
  key 36
  if ! wait_for 6 card_present; then
    "$H/drive" axfind frisket "Capture unavailable" >>"$log" 2>&1 && note "alert: Capture unavailable"
    return 1
  fi
  card_copy && clip_to window || return 1
  local px ws
  px=$(sips -g pixelWidth "$ev/window.png" | awk '/pixelWidth/ {print $2}'); ws=$(( px / w ))
  [ "$ws" -eq "$DS" ] || note "window capture is at scale $ws (the pattern window's display), row display is $DS"
  "$H/pattern" --verify-full "$ev/window.png" $(( w * ws )) $(( h * ws )) "$ws" >>"$log" 2>&1
}

row_full() {
  pattern_up --show || return 1
  drv move "$CX" "$CY"; hotkey 3
  wait_for 6 card_present && card_copy && clip_to full \
    && "$H/pattern" --verify-full "$ev/full.png" $(( DW * DS )) $(( DH * DS )) "$DS" >>"$log" 2>&1
}

row_editor_arrow_label() {
  pattern_up --show && capture_area $(( CX - 200 )) $(( CY - 250 )) $(( CX + 200 )) $(( CY + 250 )) && open_editor || return 1
  image_rect 400 500 || return 1
  tool "Arrow" && canvas_drag 0.3 0.9 0.7 0.9                       # arrow at row 450 of 500
  tool "Text" && canvas_click 0.2 0.08 && drv type "Label" && key 36 && nap 0.4   # label at row 40, typed on the image
  editor_copy && clip_to editor-arrow-label || return 1
  local band=$(( 100 * DS )) top arrow between
  top=$("$H/meter" band "$ev/editor-arrow-label.png" 0 "$band")
  arrow=$("$H/meter" band "$ev/editor-arrow-label.png" $(( 4 * band )) $(( 5 * band )))
  between=$("$H/meter" band "$ev/editor-arrow-label.png" "$band" $(( 4 * band )))
  note "annotation ink: label band=$top arrow band=$arrow between=$between"
  [ "$top" -gt 0 ] && [ "$arrow" -gt 0 ] && [ "$between" -eq 0 ]
}

row_editor_label_text() {
  pattern_up --show && capture_pattern && open_editor || return 1
  image_rect 320 180 || return 1
  tool "Text" && canvas_click 0.05 0.35 && drv type 'v2.1 $4.99 -10%' && key 36 && nap 0.4
  editor_done
  wait_for 6 card_present && wait_for 6 card_ready && drv axpress frisket "Copy recognized text" && nap 2 && drv clip-text "$ev/editor-label-text.txt" || return 1
  if [ "$DS" -ge 2 ]; then
    grep -qi 'v2\.1' "$ev/editor-label-text.txt" && grep -qF '$4.99' "$ev/editor-label-text.txt" && grep -q -- '-10%' "$ev/editor-label-text.txt"
  else
    # At 1× an 18 pt label is small for text recognition, which reads "$" as "8" and "v" as "V".
    # The exact glyphs are covered by the package D6 test; here the digits must survive.
    grep -qF '2.1' "$ev/editor-label-text.txt" && grep -qF '4.99' "$ev/editor-label-text.txt" && grep -qF -- '-10%' "$ev/editor-label-text.txt"
  fi
}

row_editor_redaction() {
  pattern_up --show && capture_pattern && open_editor || return 1
  image_rect 320 180 || return 1
  # A non-black palette colour (ticket 88, decision 61), so the check proves the chosen colour reaches the output.
  tool "Solid Redaction"
  "$H/drive" axfind frisket "Redaction colour" >>"$log" 2>&1 || "$H/drive" axdump frisket 2>/dev/null | grep -i -E 'toolbar|overflow|colour|AXMenuButton' | head -20 >>"$log"
  drv axpress frisket "Redaction colour: Grey"
  canvas_drag 0 0 0.505 0.51   # the red quadrant from the image corner (a drag that starts outside the image is ignored)
  tool "Blur" && canvas_drag 0.4 0.1 0.7 0.4
  tool "Magnify" && canvas_drag 0.1 0.1 0.3 0.35
  editor_done
  wait_for 6 card_present && card_copy && clip_to editor-redaction \
    && "$H/pattern" --verify-redacted "$ev/editor-redaction.png" "$DS" grey >>"$log" 2>&1
}

row_editor_crop() {
  pattern_up --show && capture_pattern && open_editor || return 1
  image_rect 320 180 || return 1
  tool "Crop" && canvas_drag 0.25 0.25 0.75 0.75
  editor_copy && clip_to editor-crop || return 1
  local w h
  read -r w h <<<"$("$H/drive" size "$ev/editor-crop.png")"
  note "crop output ${w}x${h}"
  [ $(( w - 160 * DS )) -ge -2 ] && [ $(( w - 160 * DS )) -le 2 ] && [ $(( h - 90 * DS )) -ge -2 ] && [ $(( h - 90 * DS )) -le 2 ]
}

row_editor_finish_visible() {
  pattern_up --show && capture_pattern && open_editor || return 1
  local ok=0
  local label
  # The action bar (D5): each control must exist in the window, not only in a toolbar overflow menu.
  for label in "Drag the edited capture" "Copy edited capture" "Save edited capture" "Done"; do
    "$H/drive" axframe frisket "$label" >>"$log" 2>&1 || ok=1
  done
  return $ok
}

row_copytext_text() {
  pattern_up --show && capture_area $(( DX + 20 )) $(( DY + 40 )) $(( DX + 900 )) $(( DY + 80 )) || return 1   # the caption line
  drv axpress frisket "Copy recognized text" && nap 2 && drv clip-text "$ev/copytext-text.txt" \
    && grep -qi 'synthetic' "$ev/copytext-text.txt"
}

row_copytext_none() {
  pattern_up --show && capture_area $(( CX - 160 )) $(( CY + 120 )) $(( CX + 160 )) $(( CY + 200 )) || return 1   # background only
  local before after alert=0
  before=$("$H/drive" clip-count)
  drv axpress frisket "Copy recognized text"; nap 2
  after=$("$H/drive" clip-count)
  "$H/drive" axfind frisket "Copied 0" >>"$log" 2>&1 && alert=1 && dismiss_alert
  local shown=0   # the notice is a static text's value, which axfind doesn't search
  "$H/drive" axdump frisket 2>/dev/null | grep -q 'value="No text found"' && shown=1
  note "clipboard changeCount before=$before after=$after alert=$alert status=$shown"
  [ "$before" = "$after" ] && [ $alert -eq 0 ] && [ $shown -eq 1 ]
}

row_stack() {
  pattern_up --show && capture_pattern && capture_area $(( CX - 100 )) $(( CY - 60 )) $(( CX + 100 )) $(( CY + 60 )) || return 1
  nap 0.8
  "$H/drive" axwin frisket | grep 'Pending capture' | sed -E 's/.*frame=([0-9-]+),([0-9-]+) ([0-9]+)x([0-9]+).*/\1 \2 \3 \4/' >"$ev/stack-frames.txt"
  cat "$ev/stack-frames.txt" >>"$log"
  [ "$(wc -l <"$ev/stack-frames.txt")" -ge 2 ] || return 1
  awk 'NR == 1 { x = $1; y = $2; w = $3; h = $4 } NR == 2 { overlap = ($1 < x + w && x < $1 + $3 && $2 < y + h && y < $2 + $4) } END { exit overlap }' "$ev/stack-frames.txt"
}

row_focus_latest() {
  pattern_up --show && capture_pattern || return 1
  local before after
  before=$("$H/drive" clip-count)
  hotkey 2; nap 0.6
  key 8; nap 1   # C: the Thumbnail's Copy, if keys reach it
  after=$("$H/drive" clip-count)
  note "clipboard changeCount before=$before after=$after, frontmost $("$H/drive" frontmost)"
  [ "$after" != "$before" ]
}

history_newest() {  # open History (⌘⇧1); it selects its newest row itself (D30), so no click
  hotkey 1; nap 1.2
  local x y w h
  read -r x y w h <<<"$("$H/drive" axframe frisket "History captures, newest first")"
  [ -n "${h:-}" ] || return 1
  nap 0.4
}
keep_card() { drv axpress frisket "Pending capture" "Close thumbnail and keep capture in History"; nap 1; }
row_history_copy() {
  # A size no other row captures, varied per run, so an older identical pattern can't pass (D30):
  # the pattern plus a margin of 2–80 points on each side, and the copy must have exactly that size.
  local m w h cw ch
  m=$(( 2 * (1 + $(date +%s) % 40) )); w=$(( 320 + 2 * m )); h=$(( 180 + 2 * m ))
  pattern_up --show && capture_area $(( CX - w / 2 )) $(( CY - h / 2 )) $(( CX + w / 2 )) $(( CY + h / 2 )) \
    && keep_card && history_newest || return 1
  drv axpress frisket "Copy selected History capture" && nap 1 && clip_to history-copy || return 1
  read -r cw ch <<<"$("$H/drive" size "$ev/history-copy.png")"
  note "captured ${w}x${h} points at scale $DS; History copied ${cw}x${ch}"
  [ "${cw:-0}" -eq $(( w * DS )) ] && [ "${ch:-0}" -eq $(( h * DS )) ] \
    && "$H/pattern" --verify-full "$ev/history-copy.png" $(( w * DS )) $(( h * DS )) "$DS" >>"$log" 2>&1
}
row_history_save() {
  pattern_up --show && capture_pattern && keep_card && history_newest || return 1
  local before new
  before=$(ls -1 "$exports" 2>/dev/null)
  drv axpress frisket "Save selected History capture"; nap 1.5
  new=$(comm -13 <(echo "$before") <(ls -1 "$exports" 2>/dev/null))
  note "new exports: $new"
  # Remove only the test export this row just created.
  printf '%s\n' "$new" | while read -r name; do [ -n "$name" ] && rm -f "$exports/$name"; done
  [ "$(printf '%s\n' "$new" | grep -c .)" -eq 1 ] && printf '%s\n' "$new" | grep -Eq '20[0-9]{2}-[01][0-9]-[0-3][0-9]'
}
# Ticket 81 (D15–D17). Uncalibrated: adjust from the first --live logs.
window_on_display() {  # window_on_display LABEL: the window's centre lies on the current display (D15)
  local x y w h
  read -r x y w h <<<"$("$H/drive" axframe frisket "$1" 2>/dev/null)"
  [ -n "${h:-}" ] || { note "no window $1"; return 1; }
  note "$1 at $x $y ${w}x$h"
  local mx=$(( x + w / 2 )) my=$(( y + h / 2 ))
  [ $mx -ge $DX ] && [ $mx -lt $(( DX + DW )) ] && [ $my -ge $DY ] && [ $my -lt $(( DY + DH )) ]
}
row_history_display() {
  pattern_up --show && drv move $CX $CY && hotkey 1 && nap 1 || return 1
  local ok=1
  window_on_display "Frisket History" && ok=0
  drv key 13 cmd; nap 0.4
  return $ok
}
row_settings_focus() {
  pattern_up --show && drv move $CX $CY && drv activate frisket && key 43 cmd && nap 1 || return 1
  local ok=0 field
  window_on_display "Frisket Settings" || ok=1
  field=$("$H/drive" axfind frisket "Thumbnail auto-dismiss delay in seconds" 2>/dev/null)
  note "auto-dismiss field: $field"
  printf '%s' "$field" | grep -q 'focused="1"' && { note "the auto-dismiss field has first focus"; ok=1; }
  "$H/drive" axfind frisket "⇧⌘" >>"$log" 2>&1 && { note "a shortcut reads ⇧⌘, not ⌘⇧"; ok=1; }
  drv key 13 cmd; nap 0.4
  return $ok
}
row_thumbnail_picture() {
  pattern_up --show && capture_pattern && wait_for 4 card_present || return 1
  local ok=1
  "$H/drive" axfind frisket "Pending capture preview" >>"$log" 2>&1 && ok=0
  keep_card
  return $ok
}
row_save_confirms() {
  pattern_up --show && capture_pattern && wait_for 4 card_ready || return 1
  local before new ok=1
  before=$(ls -1 "$exports" 2>/dev/null)
  drv axpress frisket "Save capture"
  saved_notice() { "$H/drive" axdump frisket 2>/dev/null | grep 'AXStaticText' | grep 'is in the export folder' >>"$log"; }
  wait_for 3 saved_notice && ok=0
  "$H/drive" axdump frisket 2>/dev/null | grep -q 'AXSheet\|AXDialog' && { note "Save showed a modal"; ok=1; }
  nap 0.5
  new=$(comm -13 <(echo "$before") <(ls -1 "$exports" 2>/dev/null))
  note "new exports: $new"
  printf '%s\n' "$new" | while read -r name; do [ -n "$name" ] && rm -f "$exports/$name"; done
  return $ok
}
row_menu_latest() {
  # With no Thumbnail, Copy Latest and Delete Latest are disabled (D17).
  pattern_up --show || return 1
  wait_for 12 no_cards || { note "a Thumbnail is still up"; return 1; }
  drv axpress frisket "Frisket capture menu"; nap 0.6
  local copy delete
  copy=$("$H/drive" axfind frisket "Copy Latest Capture" 2>/dev/null)
  delete=$("$H/drive" axfind frisket "Delete Latest Capture" 2>/dev/null)
  note "copy: $copy"; note "delete: $delete"
  key 53; nap 0.3
  printf '%s' "$copy" | grep -q 'enabled="0"' && printf '%s' "$delete" | grep -q 'enabled="0"'
}
row_history_delete() {
  # Copy finalizes and keeps the Thumbnail open (editor Done closes it). Stay inside its 10 s timeout.
  pattern_up --show && capture_pattern && card_copy && card_present && history_newest || return 1
  local before after asked=0
  before=$(history_images)
  drv axpress frisket "Delete selected History capture"; nap 1
  if "$H/drive" axdump frisket 2>/dev/null | grep -q 'value="Delete this capture from History?"'; then
    # Return doesn't reach the modal alert when another app is frontmost; press its Delete button.
    asked=1; drv axpress frisket "Delete"; nap 1.2
  fi
  after=$(history_images)
  "$H/drive" axfind frisket "Delete failed" >>"$log" 2>&1 && note "saw: Delete failed"
  note "asked=$asked History images before=$before after=$after"
  [ $asked -eq 1 ] && [ "$after" -eq $(( before - 1 )) ]
}

row_drag_cancel() {
  pattern_up --show && capture_pattern && open_editor || return 1
  image_rect 320 180 || return 1
  tool "Shape" && canvas_drag 0.6 0.6 0.9 0.9
  local images staged wx wy ww wh target=""
  images=$(history_images); staged=$(drag_staging)
  read -r wx wy ww wh <<<"$("$H/drive" axframe frisket "Drag the edited capture")"
  [ -n "${wh:-}" ] || return 1
  local fx fy p   # the first point of a 5×5 grid where the pattern is the front window
  for fy in 2 5 8 3 7; do
    for fx in 1 9 5 3 7; do
      p="$(( DX + DW * fx / 10 )) $(( DY + DH * fy / 10 ))"
      if "$H/drive" whatat $p | grep -v owner=Dock | head -1 | grep -q 'owner=pattern'; then target=$p; break 2; fi
    done
  done
  [ -n "$target" ] || { note "no visible pattern point to drop on"; return 1; }
  drv drag $(( wx + ww / 2 )) $(( wy + wh / 2 )) $target 30; nap 2   # the pattern window accepts no drops
  note "History images $images -> $(history_images); drag staging $staged -> $(drag_staging)"
  [ "$(history_images)" = "$images" ] && [ "$(drag_staging)" = "$staged" ]
}

# ---------------------------------------------------------------- ticket 94: Restore and the editor features of 69, 84, 85, 86, 92
# Uncalibrated: the first --live run confirms the labels and geometry; adjust from its logs.
row_history_restore() {  # ticket 79
  local m w h cw ch images ok=0
  m=$(( 2 * (1 + $(date +%s) % 40) )); w=$(( 320 + 2 * m )); h=$(( 180 + 2 * m ))   # run-unique, as history-copy
  pattern_up --show && capture_area $(( CX - w / 2 )) $(( CY - h / 2 )) $(( CX + w / 2 )) $(( CY + h / 2 )) \
    && keep_card && wait_for 5 no_cards && history_newest || return 1
  images=$(history_images)
  drv axpress frisket "Restore selected History capture to a Thumbnail"
  wait_for 6 card_present && wait_for 4 card_ready || { note "no Thumbnail after Restore"; return 1; }
  "$H/drive" axwin frisket | tee -a "$log" | grep -q 'Capture kept in History' || { note "the Thumbnail is not named as finalized"; ok=1; }
  "$H/drive" axfind frisket "Edit capture" >>"$log" 2>&1 && { note "the restored Thumbnail offers Edit"; ok=1; }
  card_copy && clip_to history-restore || return 1
  read -r cw ch <<<"$("$H/drive" size "$ev/history-restore.png")"
  note "captured ${w}x${h} points at scale $DS; the restored Thumbnail copied ${cw}x${ch}"
  [ "${cw:-0}" -eq $(( w * DS )) ] && [ "${ch:-0}" -eq $(( h * DS )) ] \
    && "$H/pattern" --verify-full "$ev/history-restore.png" $(( w * DS )) $(( h * DS )) "$DS" >>"$log" 2>&1 || ok=1
  close_cards
  wait_for 5 no_cards || { note "the restored Thumbnail did not close"; ok=1; }
  nap 0.5
  note "History images before Restore=$images after Close=$(history_images)"
  [ "$(history_images)" = "$images" ] || ok=1
  return $ok
}

undo_title() { "$H/drive" menu frisket Edit 2>/dev/null | grep 'id="undo:"' | grep -o 'title="[^"]*' | sed 's/^title="//'; }   # Edit › Undo; the toolbar button's tooltip isn't exposed to AX
row_editor_undo_names() {  # ticket 69
  pattern_up --show && capture_pattern && open_editor || return 1
  image_rect 320 180 || return 1
  tool "Crop" && canvas_drag 0.25 0.25 0.75 0.75
  image_rect 160 90 || return 1   # the canvas now shows the crop
  tool "Arrow" && canvas_drag 0.15 0.5 0.85 0.5
  local ok=0 first menu undone redone
  first=$(undo_title)
  menu=$("$H/drive" menu frisket Edit 2>&1); printf '%s\n' "$menu" >>"$log"
  printf '%s' "$menu" | grep -q 'title="Undo Arrow"' || { note "Edit menu has no \"Undo Arrow\" item"; ok=1; }
  key 6 cmd; nap 0.6; undone=$(undo_title)          # ⌘Z
  key 6 cmd,shift; nap 0.6; redone=$(undo_title)    # ⌘⇧Z
  note "Undo button: after Arrow \"$first\", after ⌘Z \"$undone\", after ⌘⇧Z \"$redone\""
  [ "$first" = "Undo Arrow" ] && [ "$undone" = "Undo Crop" ] && [ "$redone" = "Undo Arrow" ] || ok=1
  editor_copy && clip_to editor-undo-names || return 1
  local cw ch ink
  read -r cw ch <<<"$("$H/drive" size "$ev/editor-undo-names.png")"
  ink=$("$H/meter" band "$ev/editor-undo-names.png" 0 "${ch:-0}")
  note "copy ${cw}x${ch}, arrow ink $ink"
  [ $(( cw - 160 * DS )) -ge -2 ] && [ $(( cw - 160 * DS )) -le 2 ] && [ $(( ch - 90 * DS )) -ge -2 ] && [ $(( ch - 90 * DS )) -le 2 ] \
    && [ "${ink:-0}" -gt 0 ] || ok=1
  return $ok
}

row_editor_mark_keyboard() {  # ticket 84; rows below are document points of the 320×180 capture
  pattern_up --show && capture_pattern && open_editor || return 1
  image_rect 320 180 || return 1
  tool "Shape" || return 1
  canvas_drag 0.1 0.2 0.3 0.4      # first Shape: rows 36–72
  canvas_drag 0.6 0.65 0.9 0.9     # second Shape: rows 117–162
  drv axfocus frisket "Capture canvas"
  key 48; nap 0.3                  # Tab: the first mark in paint order
  key 125 shift; nap 0.3; key 125 shift; nap 0.3   # ⇧↓ twice: 20 pt down, rows 56–92
  key 48; nap 0.3; key 51; nap 0.5 # Tab to the second, Delete
  editor_copy && clip_to editor-mark-keyboard || return 1
  local f="$ev/editor-mark-keyboard.png" old new second
  old=$("$H/meter" band "$f" $(( 26 * DS )) $(( 50 * DS )))       # the first Shape's old top edge
  new=$("$H/meter" band "$f" $(( 86 * DS )) $(( 100 * DS )))      # its moved bottom edge
  second=$("$H/meter" band "$f" $(( 108 * DS )) $(( 180 * DS )))  # the deleted second Shape
  note "shape ink: old top=$old moved bottom=$new second=$second"
  [ "$old" -eq 0 ] && [ "$new" -gt 0 ] && [ "$second" -eq 0 ]
}

pick() {  # pick POPUP ITEM TITLE: choose ITEM (its accessibility label) in a style-bar pop-up, which then reads TITLE
  drv axpress frisket "$1"; nap 0.6
  drv axpress frisket "$2"; nap 0.5
  if "$H/drive" axfind frisket "$1" 2>/dev/null | tee -a "$log" | grep -q "value=\"$2\""; then return 0; fi   # the pop-up's value is the item's label
  note "pop-up $1 does not read $3"
  "$H/drive" axdump frisket 2>/dev/null | grep -q 'role="AXMenu"' && key 53   # close a menu left open
  return 1
}
row_editor_curved_arrow() {  # ticket 85; rows are document points of the 320×180 capture
  pattern_up --show && capture_pattern && open_editor || return 1
  image_rect 320 180 || return 1
  tool "Arrow" && pick "Arrow style" "Curved arrow" Curved || return 1
  canvas_drag 0.15 0.45 0.85 0.45   # ends on row 81; a new Curved arrow bows up to row 36 (ArrowBend.newCurve)
  canvas_click 0.5 0.2              # select it at its middle handle
  canvas_drag 0.5 0.2 0.5 0.9       # drag the handle to row 162, below the ends
  local marks
  marks=$("$H/drive" axdump frisket 12 2>/dev/null | grep -c 'desc="Curved arrow')
  editor_copy && clip_to editor-curved-arrow || return 1
  local f="$ev/editor-curved-arrow.png" bow handle
  bow=$("$H/meter" band "$f" $(( 26 * DS )) $(( 46 * DS )))       # the new arrow's bow, gone once bent down
  handle=$("$H/meter" band "$f" $(( 145 * DS )) $(( 175 * DS )))  # the curve through the dragged handle
  note "curved arrows on the canvas=$marks; ink at the old bow=$bow, at the handle=$handle"
  [ "$marks" -eq 1 ] && [ "$bow" -eq 0 ] && [ "$handle" -gt 0 ]
}

row_editor_label_typed() {  # ticket 86
  pattern_up --show && capture_pattern && open_editor || return 1
  image_rect 320 180 || return 1
  tool "Text" && pick "Label style" "Box label" Box || return 1
  canvas_click 0.05 0.35 && drv type 'Box label 94' && key 36 && nap 1   # Return ends the label, not the edit
  local ok=0
  editor_up || { note "Return finished the editor (Done)"; return 1; }
  "$H/drive" axfind frisket "Label text" >>"$log" 2>&1 && { note "the label is still being typed after Return"; ok=1; }
  editor_done
  wait_for 6 card_present && wait_for 6 card_ready && drv axpress frisket "Copy recognized text" && nap 2 \
    && drv clip-text "$ev/editor-label-typed.txt" || return 1
  if [ "$DS" -ge 2 ]; then
    grep -qi 'box label 94' "$ev/editor-label-typed.txt" || ok=1
  else   # at 1× an 18 pt label is small for text recognition (see editor-label-text)
    grep -qi 'label' "$ev/editor-label-typed.txt" && grep -q '94' "$ev/editor-label-typed.txt" || ok=1
  fi
  return $ok
}

inside_editor() {  # inside_editor LABEL: the control has a frame inside the editor window
  local x y w h
  read -r x y w h <<<"$("$H/drive" axframe frisket "$1" 2>/dev/null)"
  [ -n "${h:-}" ] || { note "not on screen: $1"; return 1; }
  [ "$x" -ge "$EX" ] && [ $(( x + w )) -le $(( EX + EW )) ] && [ "$y" -ge "$EY" ] && [ $(( y + h )) -le $(( EY + EH )) ] \
    || { note "$1 at $x $y ${w}x$h lies outside the editor $EX $EY ${EW}x$EH"; return 1; }
}
row_editor_style_bar() {  # ticket 92
  pattern_up --show && capture_pattern && open_editor || return 1
  local EX EY EW EH ok=0 label
  read -r EX EY EW EH <<<"$("$H/drive" axframe frisket "Edit Capture")"
  [ -n "${EH:-}" ] || { note "no editor window frame"; return 1; }
  # The toolbar: every tool, Undo and Close are laid out in the window, none in the » overflow menu.
  # The tool titles are the labels the other editor rows press (exact matches, found before any substring).
  for label in Select "Solid Redaction" Crop Arrow Line Shape Text Blur Magnify Undo Close; do   # toolbar items expose their item labels, not the buttons' own
    inside_editor "$label" || ok=1
  done
  tool "Solid Redaction"; inside_editor "Redaction colour" || ok=1
  tool "Arrow"; inside_editor "Arrow style" || ok=1
  tool "Text"; inside_editor "Label size" || ok=1; inside_editor "Label style" || ok=1
  "$H/drive" axdump frisket 2>/dev/null | grep -i -E 'overflow|AXMenuButton' >>"$log" && note "possible overflow control (see above)"
  return $ok
}

# ---------------------------------------------------------------- ticket 98: the Thumbnail's hover × (decision 91)
# Uncalibrated: the first --live run confirms the × appears on hover; adjust from its log.
close_x() { "$H/drive" axfind frisket "Close thumbnail and keep capture in History" >>"$log" 2>&1; }   # the × is in the tree only while shown
row_thumbnail_close() {
  pattern_up --show && capture_pattern && wait_for 4 card_ready || return 1
  local x y w h images
  images=$(history_images)
  read -r x y w h <<<"$("$H/drive" axframe frisket "Pending capture")"
  [ -n "${h:-}" ] || { note "no Thumbnail frame"; return 1; }
  drv move $(( x + w / 2 )) $(( y + h / 3 )); drv move $(( x + w / 2 + 4 )) $(( y + h / 3 ))   # over the picture
  wait_for 2 close_x || { note "no × while the pointer is over the card"; return 1; }
  drv axclick frisket "Close thumbnail and keep capture in History" || return 1
  wait_for 5 no_cards || { note "the Thumbnail is still up after ×"; return 1; }
  note "History images $images -> $(history_images)"
  [ "$(history_images)" -eq $(( images + 1 )) ]
}

# ---------------------------------------------------------------- run
case $display_choice in
  all) displays="builtin external" ;;
  builtin|external) displays=$display_choice ;;
  *) echo "bad --display $display_choice" >&2; exit 2 ;;
esac

status=0
for display in $displays; do
  if ! use_display "$display"; then
    echo "skip: no $display display attached"; continue
  fi
  while IFS=$'\t' read -r id defects expect check; do
    [ -z "$only_row" ] || [ "$id" = "$only_row" ] || continue
    ev="$run/$display"; mkdir -p "$ev"; log="$ev/$id.log"
    echo "# $id on $display (${DW}×${DH} pt, scale ${DS}): $check" >"$log"
    fn="row_$(echo "$id" | tr - _)"
    if [ $SECONDS -ge $(( minutes * 60 - 60 )) ]; then
      result=skip   # no row starts in the cap's last minute
    elif ! "$H/drive" frisket >/dev/null 2>&1; then
      result=error
    elif "$fn" </dev/null; then
      result=pass
    else
      result=fail; shot_pattern "$id-failed"
    fi
    case "$result/$expect" in
      pass/pass) verdict=PASS ;;
      fail/xfail) verdict=XFAIL ;;
      pass/xfail) verdict=XPASS; status=1 ;;
      fail/pass) verdict=FAIL; status=1 ;;
      skip/*) verdict=SKIP; status=1 ;;
      *) verdict=ERROR; status=1 ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$display" "$defects" "$expect" "$result" "$verdict" >>"$report"
    printf '%-6s %-22s %-9s %s\n' "$verdict" "$id" "$display" "$defects"
    case $verdict in
      FAIL|XPASS|ERROR|SKIP)
        { echo; echo "## $verdict $id on $display ($defects)"; echo "$check"; echo
          echo '```'; grep -vE '^not found: OK$' "$log" | tail -15 | cut -c1-200; echo '```'
          ls "$ev" | grep -E "^$id(-failed)?\.png$" | sed "s#^#evidence: $ev/#"; } >>"$failures" ;;
    esac
    [ "$verdict" = SKIP ] && continue
    reset_state </dev/null
  done < <(rows)
done
echo "report: $report"
echo "failures: $failures ($(grep -c '^## ' "$failures") rows)"
exit $status
