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
set -u

here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../.." && pwd)
H="$root/.build/live-harness"
bundle=${FRISKET_BUNDLE_ID:-io.github.prateeksingh1092.frisket.debug}
history_root="$HOME/Library/Application Support/$bundle/History.noindex"
exports="$HOME/Pictures/Frisket"

mode="" display_choice=all only_row=""
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) mode=dry ;;
    --live) mode=live ;;
    --display) display_choice=$2; shift ;;
    --row) only_row=$2; shift ;;
    *) echo "usage: $0 --dry-run|--live [--display builtin|external|all] [--row ID]" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$mode" ] || { echo "usage: $0 --dry-run|--live [--display builtin|external|all] [--row ID]" >&2; exit 2; }

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

run="$H/runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run"
report="$run/report.tsv"
printf 'row\tdisplay\tdefects\texpect\tresult\tverdict\n' >"$report"
private=$(mktemp -d -t frisket-harness)   # holds the user's saved clipboard: owner-only, deleted on exit
chmod 700 "$private"
"$H/drive" clip-save "$private/clipboard.plist" >>"$run/harness.log" 2>&1 || { echo "could not save the clipboard" >&2; exit 2; }

cleanup() {
  pkill -x pattern 2>/dev/null
  if "$H/drive" clip-restore "$private/clipboard.plist" >>"$run/harness.log" 2>&1; then
    rm -rf "$private"
  else
    echo "WARNING: clipboard restore failed; the saved copy is in $private" >&2
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

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
  wait_for 6 card_present
}
capture_pattern() { capture_area $(( CX - 160 )) $(( CY - 90 )) $(( CX + 160 )) $(( CY + 90 )); }
card_copy() { drv axpress frisket "Copy capture" && nap 1; }
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
canvas_drag() {  # canvas_drag FX0 FY0 FX1 FY1 as fractions of the image rectangle
  drv drag "$(at $IX "$1" $IW)" "$(at $IY "$2" $IH)" "$(at $IX "$3" $IW)" "$(at $IY "$4" $IH)" 20
  nap 0.4
}
# Finish an edit through the close sheet: ⌘W, then Return (Finalize, the sheet's default). This path
# works while the toolbar overflows (D5), when Done, Copy, Save and their key equivalents don't.
editor_done() {
  drv key 13 cmd; nap 0.8
  editor_up && key 36
  wait_for 6 editor_gone; nap 0.8
}
# The edited result, copied from its Thumbnail after Finalize (the editor's own ⌘C dies under D5).
editor_copy() { editor_done && wait_for 6 card_present && card_copy; }
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
  drv axpress frisket "Cancel scrolling capture"
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
  drv move $(( x + w / 2 )) $(( y + h / 2 )); hotkey 4; nap 1
  select_rect $(( x + 10 )) $(( y + 2 )) $(( x + w - 10 )) $(( y + h - 10 ))   # the hole covers the title bar
  before=$(pattern_bounds)
  drv seq "down $(( x + w / 2 )) $(( y + 12 ))" "drag $(( x + w / 2 + 50 )) $(( y + 62 ))" "drag $(( x + w / 2 + 100 )) $(( y + 112 ))" "up $(( x + w / 2 + 100 )) $(( y + 112 ))"
  nap 0.4; after=$(pattern_bounds); shot_pattern area-click-inside
  pattern_running && key 53; nap 0.6
  note "pattern window before=$before after=$after"
  [ "$before" = "$after" ] && ! overlay_up && pattern_running
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
  card_copy && clip_to window && "$H/pattern" --verify-full "$ev/window.png" $(( w * DS )) $(( h * DS )) "$DS" >>"$log" 2>&1
}

row_full() {
  pattern_up --show || return 1
  drv move "$CX" "$CY"; hotkey 3
  wait_for 6 card_present && card_copy && clip_to full \
    && "$H/pattern" --verify-full "$ev/full.png" $(( DW * DS )) $(( DH * DS )) "$DS" >>"$log" 2>&1
}

# A 700×530 Selection inside the scroll page's document area. Wheel steps are in lines;
# the first live run calibrates them (README).
scroll_start() {
  pattern_up --show-scroll || return 1
  read -r SX SY SW SH <<<"$(pattern_bounds)"
  drv move $(( SX + 400 )) $(( SY + 300 )); hotkey 6; nap 1
  select_rect $(( SX + 20 )) $(( SY + 40 )) $(( SX + 720 )) $(( SY + 570 ))
  # The scrolling session starts when the mouse button comes up. Return would mean Done at once.
  wait_for 4 scroll_panel_up || { note "no scrolling panel"; return 1; }
  nap 1
}
scroll_panel_up() { "$H/drive" axfind frisket "Done with scrolling capture" >/dev/null 2>&1; }
scroll_finish() {
  drv axpress frisket "Done with scrolling capture" || return 1
  wait_for 8 card_present && card_copy && clip_to "$1"
}
row_scroll_steady() {
  scroll_start || return 1
  local step
  for step in 1 2 3 4; do drv wheel $(( SX + 400 )) $(( SY + 300 )) -4; nap 1.2; done   # a step well under the 530-row viewport
  scroll_finish scroll-steady && "$H/meter" blocks "$ev/scroll-steady.png" "$DS" $(( 530 * DS )) >>"$log" 2>&1
}
row_scroll_flick() {
  scroll_start || return 1
  drv wheel $(( SX + 400 )) $(( SY + 300 )) -40; nap 1.5
  if "$H/drive" axfind frisket "Slow down" >>"$log" 2>&1; then
    note "Slow down shown"; drv axpress frisket "Cancel scrolling capture"; return 0
  fi
  scroll_finish scroll-flick && "$H/meter" blocks "$ev/scroll-flick.png" "$DS" $(( 530 * DS )) >>"$log" 2>&1
}
row_scroll_keys() {
  scroll_start || return 1
  local before after
  before=$("$H/drive" scrollpos pattern)
  key 121; nap 0.8
  after=$("$H/drive" scrollpos pattern)
  note "scroller before=$before after=$after"
  drv axpress frisket "Cancel scrolling capture"
  awk "BEGIN { exit !($after > $before) }"
}

row_editor_arrow_label() {
  pattern_up --show && capture_area $(( CX - 200 )) $(( CY - 250 )) $(( CX + 200 )) $(( CY + 250 )) && open_editor || return 1
  image_rect 400 500 || return 1
  tool "Arrow" && canvas_drag 0.3 0.9 0.7 0.9                       # arrow at row 450 of 500
  tool "Text" && drv axfocus frisket "Annotation label text" && drv type "Label" \
    && canvas_drag 0.2 0.08 0.5 0.1                                          # label at row 40
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
  tool "Text" && drv axfocus frisket "Annotation label text" && drv type 'v2.1 $4.99 -10%' \
    && canvas_drag 0.05 0.35 0.9 0.55
  editor_done
  wait_for 6 card_present && drv axpress frisket "Copy recognized text" && nap 2 && drv clip-text "$ev/editor-label-text.txt" || return 1
  grep -q 'v2\.1' "$ev/editor-label-text.txt" && grep -qF '$4.99' "$ev/editor-label-text.txt" && grep -q -- '-10%' "$ev/editor-label-text.txt"
}

row_editor_redaction() {
  pattern_up --show && capture_pattern && open_editor || return 1
  image_rect 320 180 || return 1
  tool "Solid Redaction" && canvas_drag 0 0 0.505 0.51   # the red quadrant from the image corner (a drag that starts outside the image is ignored)
  tool "Blur" && canvas_drag 0.4 0.1 0.7 0.4
  tool "Magnify" && canvas_drag 0.1 0.1 0.3 0.35
  editor_done
  wait_for 6 card_present && card_copy && clip_to editor-redaction \
    && "$H/pattern" --verify-redacted "$ev/editor-redaction.png" "$DS" >>"$log" 2>&1
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
  "$H/drive" axframe frisket "Copy the edited capture" >>"$log" 2>&1 || ok=1
  "$H/drive" axframe frisket "Save the edited capture" >>"$log" 2>&1 || ok=1
  { "$H/drive" axframe frisket "Done" || "$H/drive" axframe frisket "Keep this capture in History"; } >>"$log" 2>&1 || ok=1
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
  note "clipboard changeCount before=$before after=$after alert=$alert"
  [ "$before" = "$after" ] && [ $alert -eq 0 ]
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

history_newest() {  # open History (⌘⇧1) and click its newest row
  hotkey 1; nap 1.2
  local x y w h
  read -r x y w h <<<"$("$H/drive" axframe frisket "History captures, newest first")"
  [ -n "${h:-}" ] || return 1
  drv click $(( x + w / 2 )) $(( y + 24 )); nap 0.4
}
keep_card() { drv axpress frisket "Pending capture" "Close thumbnail and keep capture in History"; nap 1; }
row_history_copy() {
  pattern_up --show && capture_pattern && keep_card && history_newest || return 1
  drv axpress frisket "Copy" && nap 1 && clip_to history-copy && "$H/pattern" --verify "$ev/history-copy.png" "$DS" >>"$log" 2>&1
}
row_history_save() {
  pattern_up --show && capture_pattern && keep_card && history_newest || return 1
  local before new
  before=$(ls -1 "$exports" 2>/dev/null)
  drv axpress frisket "Save"; nap 1.5
  new=$(comm -13 <(echo "$before") <(ls -1 "$exports" 2>/dev/null))
  note "new exports: $new"
  # Remove only the test export this row just created.
  printf '%s\n' "$new" | while read -r name; do [ -n "$name" ] && rm -f "$exports/$name"; done
  [ "$(printf '%s\n' "$new" | grep -c .)" -eq 1 ] && printf '%s\n' "$new" | grep -Eq '20[0-9]{2}-[01][0-9]-[0-3][0-9]'
}
row_history_delete() {
  pattern_up --show && capture_pattern && open_editor || return 1
  editor_done   # a finalized capture whose Thumbnail stays open
  wait_for 6 card_present && history_newest || return 1
  local before after asked=0
  before=$(history_images)
  drv axpress frisket "Delete"; nap 1
  if "$H/drive" axfind frisket "Cancel" >>"$log" 2>&1; then
    asked=1; drv axpress frisket "Delete Capture" || drv axpress frisket "Delete"; nap 1.2
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
  for p in "$(( DX + 60 )) $(( DY + DH / 2 ))" "$(( DX + DW - 60 )) $(( DY + DH / 2 ))" "$(( CX )) $(( DY + 80 ))" "$(( CX )) $(( DY + DH - 80 ))"; do
    if "$H/drive" whatat $p | head -1 | grep -q 'owner=pattern'; then target=$p; break; fi
  done
  [ -n "$target" ] || { note "no visible pattern point to drop on"; return 1; }
  drv drag $(( wx + ww / 2 )) $(( wy + wh / 2 )) $target 30; nap 2   # the pattern window accepts no drops
  note "History images $images -> $(history_images); drag staging $staged -> $(drag_staging)"
  [ "$(history_images)" = "$images" ] && [ "$(drag_staging)" = "$staged" ]
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
    if ! "$H/drive" frisket >/dev/null 2>&1; then
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
      *) verdict=ERROR; status=1 ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$display" "$defects" "$expect" "$result" "$verdict" >>"$report"
    printf '%-6s %-22s %-9s %s\n' "$verdict" "$id" "$display" "$defects"
    reset_state </dev/null
  done < <(rows)
done
echo "report: $report"
exit $status
