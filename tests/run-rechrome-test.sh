#!/bin/sh
# Regression for what a LIVE metrics knob leaves behind on standing
# frames (retitle-frames). set-title-air re-derives the strip height
# and rebuilds every titlebar, and two promises used to break there.
# COLOUR: titlebar-build paints the strip it makes in the maker's
# focus blue and nothing repainted it after the rebuild, so every
# unfocused window came out of a live knob turn dressed as the active
# one (the owner, 2026-08-25). EDGES: the frame's height moves with
# the strip, so a window flush at the panel came off it when the strip
# shrank (growth was already clamped back), and a maximized window
# stopped filling its workarea. Now the retitle re-says each frame's
# colour (frame-recolor) and re-judges its edges the way the workarea
# reflow does (rechrome-axis): flush re-sticks, spanning re-fits — in
# both directions of the knob.
. "$(dirname "$0")/common.sh"
start_xvfb

CONF="$HERE/rechrome-config"
rm -rf "$CONF"; mkdir -p "$CONF"
: > "$CONF/tk9wm.tcl"

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-rechrome.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-rechrome.log" $WM

"$LINUX/whale" "$HERE/client.tcl" "lower" 300x140 "#8ae234" "" "" 90 \
    > "$HERE/rechrome-lower.log" 2>&1 &
CA=$!
wait_client "$HERE/wm-rechrome.log" 'lower'
"$LINUX/whale" "$HERE/client.tcl" "maxi" 260x120 "#fcaf3e" "" "" 90 \
    > "$HERE/rechrome-maxi.log" 2>&1 &
CB=$!
wait_client "$HERE/wm-rechrome.log" 'maxi'
"$LINUX/whale" "$HERE/client.tcl" "upper" 260x120 "#729fcf" "" "" 90 \
    > "$HERE/rechrome-upper.log" 2>&1 &
CC=$!
wait_client "$HERE/wm-rechrome.log" 'upper'

q() { printf '%s\n' "$1" > "$CONF/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl" 2>&1; }

# window ids by title, answered from inside the WM from here on
q 'proc ttlw {ttl} { foreach w [array names ::frameof] {
    if {[visible-title $w] eq $ttl} { return $w } } }' >/dev/null

# the stage: lower flush at the workarea's bottom edge by hand (an
# edge is where a drag most often leaves a window), maxi maximized
# (the STATE, not just the look), upper holding the focus
q 'set t $::frameof([ttlw lower])
lassign [workarea] wx wy ww wh
regexp {^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fw fh fx fy
wm geometry $t +$fx+[expr {$wy + $wh - $fh}]' >/dev/null
q 'maximize-client [ttlw maxi]' >/dev/null
q 'focus-to [ttlw upper]' >/dev/null

# how far lower's bottom edge sits from the workarea's (0 = flush)
lower_off() { q 'set t $::frameof([ttlw lower])
lassign [workarea] wx wy ww wh
regexp {^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fw fh fx fy
expr {$fy + $fh - ($wy + $wh)}'; }
lower_flush() { [ "$(lower_off)" = "0" ]; }
# a maximized Tk client owes the increments nothing: frame == workarea
maxi_fills() { q 'set t $::frameof([ttlw maxi])
lassign [workarea] wx wy ww wh
expr {[wm geometry $t] eq "${ww}x${wh}+${wx}+${wy}"}'; }
maxi_spans() { [ "$(maxi_fills)" = "1" ]; }
bg_lower() { q '[set ::frameof([ttlw lower])].title cget -background'; }
bg_upper() { q '[set ::frameof([ttlw upper])].title cget -background'; }
titleh() { q 'look default titleh'; }
titleh_is() { [ "$(titleh)" = "$1" ]; }

FOCUSBG=$(q 'themed focus')
UNFOCBG=$(q 'themed unfocus')
H0=$(titleh)

wait_for 10 lower_flush || echo "note: lower never reached the edge"
wait_for 10 maxi_spans  || echo "note: maxi never filled the workarea"
B0L=$(bg_lower); B0U=$(bg_upper)

# --- grow: a taller strip, every frame taller with it
q 'set-title-air 9' >/dev/null
wait_for 10 titleh_is $((H0 + 12))
wait_for 10 lower_flush; F1=$?
wait_for 10 maxi_spans;  M1=$?
B1L=$(bg_lower); B1U=$(bg_upper)
O1=$(lower_off)

# --- shrink: the reported break — the strip tightens, the frame used
# to let go of the panel and keep the gap
q 'set-title-air 0' >/dev/null
wait_for 10 titleh_is $((H0 - 6))
wait_for 10 lower_flush; F2=$?
wait_for 10 maxi_spans;  M2=$?
B2L=$(bg_lower); B2U=$(bg_upper)
O2=$(lower_off)

reload() { "$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY" >/dev/null 2>&1; }

# --- reload, chrome only: the config says the air, the ground stands.
# The titles settle under the hold, so this exercises the DEFERRED
# judgment (rechrome-settle at the reload's end) — before it, the
# release had no reflow to run (the workarea never moved) and the gap
# simply stayed.
printf 'set-title-air 9\n' > "$CONF/tk9wm.tcl"
reload
wait_for 10 titleh_is $((H0 + 12))
wait_for 10 lower_flush; F3=$?
wait_for 10 maxi_spans;  M3=$?
B3L=$(bg_lower); B3U=$(bg_upper)
O3=$(lower_off)

# --- reload, chrome AND ground in one breath: the air shrinks back
# and a panel takes the bottom edge. The deferred judgment re-glues
# the edges to the OLD ground, the release's reflow carries them to
# the new one — the two transitions compose.
printf 'set-title-air 0\nset-panel-side bottom\naction one {}\npanel-button one\n' \
    > "$CONF/tk9wm.tcl"
reload
wait_for 10 titleh_is $((H0 - 6))
wait_for 10 lower_flush; F4=$?
wait_for 10 maxi_spans;  M4=$?
B4L=$(bg_lower); B4U=$(bg_upper)
O4=$(lower_off)
WA4=$(q 'workarea')

kill $CA $CB $CC 2>/dev/null
sleep 0.5
kill $WM 2>/dev/null
sleep 0.5

echo "--- stage: titleh $H0 focus «$FOCUSBG» unfocus «$UNFOCBG»\
 lower «$B0L» upper «$B0U»"
echo "--- air 9: lower off=$O1 «$B1L» upper «$B1U»"
echo "--- air 0: lower off=$O2 «$B2L» upper «$B2U»"
echo "--- reload air 9: lower off=$O3 «$B3L» upper «$B3U»"
echo "--- reload air 0 + panel (wa $WA4): lower off=$O4 «$B4L» upper «$B4U»"
grep '^WM: rechrome' "$HERE/wm-rechrome.log" | sed 's/^/    /'
grep '^WM: reflow'   "$HERE/wm-rechrome.log" | sed 's/^/    /'

echo "--- verdict"
if [ "$F1" = 0 ] && [ "$F2" = 0 ]; then
    echo "OK: the flush window re-sticks to the edge in both directions"
else
    echo "FAIL: lower came off the bottom edge (grow off=$O1, shrink off=$O2)"
fi
if [ "$M1" = 0 ] && [ "$M2" = 0 ]; then
    echo "OK: the maximized window re-fits and keeps filling the workarea"
else
    echo "FAIL: maxi stopped filling the workarea (grow=$M1 shrink=$M2)"
fi
if [ "$B1L" = "$UNFOCBG" ] && [ "$B2L" = "$UNFOCBG" ]; then
    echo "OK: an unfocused strip comes out of the rebuild in unfocus grey"
else
    echo "FAIL: lower's strip wears «$B1L»/«$B2L», want unfocus «$UNFOCBG»"
fi
if [ "$B1U" = "$FOCUSBG" ] && [ "$B2U" = "$FOCUSBG" ]; then
    echo "OK: the focused strip still wears the focus colour"
else
    echo "FAIL: upper's strip wears «$B1U»/«$B2U», want focus «$FOCUSBG»"
fi
if [ "$F3" = 0 ] && [ "$M3" = 0 ]; then
    echo "OK: a reload's air change keeps the edges too (the deferred judgment)"
else
    echo "FAIL: after the air-only reload: lower off=$O3 (want 0), maxi spans (0=ok): $M3"
fi
if [ "$F4" = 0 ] && [ "$M4" = 0 ]; then
    echo "OK: air and panel in one reload compose — flush and span land on the new ground"
else
    echo "FAIL: after the air+panel reload: lower off=$O4 (want 0), maxi spans (0=ok): $M4"
fi
if [ "$B3L" = "$UNFOCBG" ] && [ "$B4L" = "$UNFOCBG" ] \
        && [ "$B3U" = "$FOCUSBG" ] && [ "$B4U" = "$FOCUSBG" ]; then
    echo "OK: the reloads keep the colours straight as well"
else
    echo "FAIL: reload colours: lower «$B3L»/«$B4L» upper «$B3U»/«$B4U»"
fi
