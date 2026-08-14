#!/bin/sh
# The clock and the tray share the far corner of the panel's band, and
# the corner is contested from two sides:
#
#  - the STRIP grows when an icon docks, and the widget area is told
#    to back off (tray-tell-panel -> a panel rebuild);
#  - the AREA grows when a slow widget finally answers — a weather
#    fetch, a phone battery over ssh — and nobody is told anything:
#    the frame just grows in place, because a frame's width is its
#    content's. Placed by its NEAR corner it grew straight under the
#    strip and stayed there until some widget's own tick happened to
#    change a size and re-lay the area — the owner watched his clock's
#    tail sit under the tray until the minute flipped (2026-08-14).
#    The cure under test: the area is anchored by the edge the strip
#    is on, so late growth eats the panel's free middle.
#
# The desk is shaped like the owner's: ARGB strip and big cells under
# a compositor, several widgets (one answering SLOWLY, with NO tick
# for minutes — the heal must not be the tick), buttons on the panel,
# two clients docking at their own pace, a restart in the middle.
# The verdicts ask the GLASS (winfo via send-eval), not the log.
. "$(dirname "$0")/common.sh"
start_xvfb 1600x900x24 +extension Composite +extension RENDER
trap 'kill $COMP 2>/dev/null; stop_xservers' EXIT
hsetroot -solid '#ff00ff' 2>/dev/null
compton --backend xrender --config /dev/null \
    >"$HERE/traywidget-comp.log" 2>&1 &
COMP=$!
sleep 1

rm -rf "$HERE/traywidget-config"
mkdir -p "$HERE/traywidget-config"
cat > "$HERE/traywidget-config/tk9wm.tcl" <<'EOF'
set-welcome off
set-panel-preset icons
set-panel-side bottom
set-tray-icon-size 42
set-tray on
action терм {}
action диск {}
action окно {}
panel-button терм
panel-button диск
panel-button окно
# A widget whose answer comes LATE and WIDE — the model of a weather
# fetch or a phone battery over ssh: at build it shows a placeholder,
# ~2s later the real content lands and the area grows with NO layout
# event. -every is HALF AN HOUR, so no heartbeat re-lays the area
# after the answer — if the tail stays out from under the strip, the
# anchoring did it.
wm-widget-type lazy {
    build lazy-build
    every 1800000
    prefers panel
}
proc lazy-build {w opts} {
    label $w.l -text "…" -background [dict get $opts -background] \
        -foreground [dict get $opts -foreground]
    pack $w.l
    after 2000 [list lazy-answer $w.l]
}
proc lazy-answer {l} {
    if {[winfo exists $l]} { $l configure -text "the late and wide answer" }
}
wm-widget P -type battery -source {command {sh -c {sleep 2; echo 100}}} \
    -every 1800000 -letter Phone
wm-widget слоу -type lazy
wm-widget desks -type desks -style dots
wm-widget туда -type clock -timezone Pacific/Auckland -label AKL
wm-widget clock -type clock
EOF

XDG_CONFIG_HOME="$HERE/traywidget-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-traywidget.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-traywidget.log" $WM

python3 "$HERE/tray-client-gtk.py" "#729fcf" > "$HERE/traywidget-gtk.log" 2>&1 &
GTK=$!
wait_for 15 grep -q '^WM: tray: docked' "$HERE/wm-traywidget.log" \
    || echo "note: the GTK icon never docked"
"$LINUX/whale" "$HERE/tray-client.tcl" "#8ae234" > "$HERE/traywidget-tk.log" 2>&1 &
CA=$!
sleep 4

# what the GLASS holds: the area's right edge and the strip's left
glass() {
    printf '%s\n' '
        set out {}
        foreach k [array names ::widget_area] {
            set A $::widget_area($k)
            if {[winfo exists $A] && [winfo ismapped $A]} {
                lappend out [expr {[winfo rootx $A] + [winfo width $A]}]
            }
        }
        list area-end $out strip [expr {[winfo exists .tray]
            && [winfo ismapped .tray] ? [winfo rootx .tray] : -1}]
    ' > "$HERE/traywidget-config/q.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/traywidget-config/q.tcl"
}
G1=$(glass)

"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" "$DISPLAY"
sleep 4          # the desk is up again, the slow answer lands at ~2s...
sleep 4          # ...and has had time to grow the area
kill -0 $GTK 2>/dev/null && ALIVE=1 || ALIVE=0
G2=$(glass)
import -display "$DISPLAY" -window root "$HERE/traywidget-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/traywidget-test.png"

kill $GTK $CA 2>/dev/null
kill $WM 2>/dev/null
sleep 0.5

judge() {  # "area-end E strip X" -> ok / overlap / unmeasured
    set -- $1
    [ "$1" = "area-end" ] && [ "$3" = "strip" ] || { echo unmeasured; return; }
    [ -n "$2" ] && [ "$4" -gt 0 ] 2>/dev/null || { echo unmeasured; return; }
    [ "$2" -le "$4" ] && echo ok || echo overlap
}
V1=$(judge "$G1")
V2=$(judge "$G2")

echo "--- glass before restart: $G1 -> $V1"
echo "--- glass after restart:  $G2 -> $V2"
echo "--- widget/strip lines:"
grep -E 'WM: widget area|WM: tray strip|restart requested|WM: tray: docked' \
    "$HERE/wm-traywidget.log" | sed 's/^/    /'

echo "--- verdict"
[ "$ALIVE" = 1 ] && echo "OK: the GTK client survived the restart" \
    || echo "FAIL: the GTK client died on the restart"
[ "$V1" = ok ] && echo "OK: before the restart the area ends before the strip" \
    || echo "FAIL: before the restart: $V1 ($G1)"
[ "$V2" = ok ] \
    && echo "OK: after the restart AND the late answer the area still ends before the strip" \
    || echo "FAIL: after the restart: $V2 ($G2)"
if grep -q 'handler error' "$HERE/wm-traywidget.log"; then
    echo "FAIL: handler errors present:"
    grep 'handler error' "$HERE/wm-traywidget.log" | sed 's/^/    /'
fi
