#!/bin/sh
# Regression for EWMH fullscreen: the whole SCREEN, no decoration, and
# nothing of ours left standing on top of it — for every client that CAN
# be that size, which is the one thing the hints still decide here.
#
# Three clients, because three different things are being proved. Our
# own client.tcl is the one with a KNOWN COLOR, so a screenshot can say
# whether it really covers the panel and the tray rather than merely
# claiming their geometry. Then xterm and kitty, unmodified and real:
# both look for _NET_WM_STATE_FULLSCREEN in _NET_SUPPORTED and, before
# this existed, went fullscreen by NOT ASKING — measured, they sent
# nothing at all and stayed their old size. They are here so the answer
# to "does it work" is not a mock of what they do. And emacs, the
# client whose OFF depends on how it reads our _NET_WM_STATE property
# back (pass 5) — the round trip nobody else on this list drives.
#
# The desk carries a panel AND a tray, which is what makes the stacking
# question real: both are our own override-redirect top-levels that
# lift themselves whenever they rebuild or an icon docks.
. "$(dirname "$0")/common.sh"
# kitty wants both, and refuses to start when it cannot write them.
# Under /tmp and not next to the test: they hold nothing worth reading
# afterwards, unlike every other artifact a run leaves here.
export XDG_CACHE_HOME=/tmp/tk9wm-fs-cache
export XDG_RUNTIME_DIR=/tmp/tk9wm-fs-run
rm -rf "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
mkdir -p "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
start_xvfb 1024x768x24 +extension RENDER

CONF="$HERE/fullscreen-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
action терм {}
panel-button терм
set-tray on
wm-style {filter -title стилевой} {start fullscreen}
EOF
# A client that declares a size WINDOW and lives by it — argv is
# title, min, max, and an optional delay for saying so LATE (after it
# is already in the state).
cat > "$CONF/client-pin.tcl" <<'EOF'
package require Tk
lassign $argv title minw minh maxw maxh late
chan configure stdout -buffering line
wm title . $title
wm geometry . 240x120
label .l -text $title -background #729fcf -font {Sans 12}
pack .l -expand 1 -fill both
proc pin {} {
    wm minsize . $::minw $::minh
    wm maxsize . $::maxw $::maxh
    puts "PIN: min ${::minw}x${::minh} max ${::maxw}x${::maxh}"
}
if {$late eq ""} { pin } else { after $late pin }
after 45000 exit
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-fullscreen.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-fullscreen.log" $WM

SUPPORTED=$(xprop -root _NET_SUPPORTED | tr ',' '\n' | grep -c _NET_WM_STATE_FULLSCREEN)

"$LINUX/whale" "$HERE/client.tcl" "полноэкранный" 240x120 "#8ae234" "" "" 45 \
    > "$HERE/fullscreen-client.log" 2>&1 &
CA=$!
wait_client "$HERE/wm-fullscreen.log" 'полноэкранный'
CID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-fullscreen.log" | head -1)

geo() { xwininfo -id "$1" | sed -n 's/^  -geometry \([0-9x+-]*\).*/\1/p'; }
size() { xwininfo -id "$1" | awk '/Width:/{w=$2} /Height:/{h=$2}
    /Absolute upper-left X:/{x=$4} /Absolute upper-left Y:/{y=$4}
    END{printf "%dx%d+%d+%d", w, h, x, y}'; }
state() { xprop -id "$1" _NET_WM_STATE 2>/dev/null | sed 's/.*= //'; }
px() { import -window root "$HERE/fs-shot.png" 2>/dev/null
       convert "$HERE/fs-shot.png" -format "%[pixel:p{$1,$2}]" info:; }

# The panel is at the bottom edge, the tray strip in its right corner.
# A pixel in each is what a fullscreen window has to have taken over.
BEFORE_SIZE=$(size "$CID")
BEFORE_PANEL=$(px 300 750)

# --- pass 1: the state, asked for from outside (wmctrl speaks plain EWMH)
wmctrl -i -r "$CID" -b add,fullscreen
sleep 1.5
FS_SIZE=$(size "$CID")
FS_STATE=$(state "$CID")
FS_PANEL=$(px 300 750)
FS_TRAY=$(px 1000 750)

# --- an icon docks while a window is fullscreen: the tray lifts itself
# for its own reasons, and must not come up over the window
"$LINUX/whale" "$HERE/tray-client.tcl" "#729fcf" > "$HERE/fullscreen-tray.log" 2>&1 &
CT=$!
sleep 2
DOCKED=$(grep -c '^WM: tray: docked' "$HERE/wm-fullscreen.log")
AFTERDOCK_PANEL=$(px 1000 750)

# --- pass 2: and back out again
wmctrl -i -r "$CID" -b remove,fullscreen
sleep 1.5
BACK_SIZE=$(size "$CID")
BACK_STATE=$(state "$CID")
BACK_PANEL=$(px 300 750)

# --- pass 3: the OTHER road in, the property already on the window at
# manage time. Tk's `wm attributes -fullscreen` on an unmapped toplevel
# writes it there; the terminals below were measured NOT doing this
# (they map first and send the message), so without this client the
# manage-time path would go untested.
"$LINUX/whale" "$HERE/fs-client.tcl" "премап" "#ad7fa8" 25 \
    > "$HERE/fullscreen-premap.log" 2>&1 &
CP=$!
sleep 2.5
PREMAP=$(grep -c 'asked to start fullscreen' "$HERE/wm-fullscreen.log")
PMWIN=$(sed -n 's/^WM: \(0x[0-9a-f]*\) asked to start fullscreen/\1/p' \
    "$HERE/wm-fullscreen.log" | tail -1)
PM_SIZE=""
[ -n "$PMWIN" ] && PM_SIZE=$(size "$PMWIN")
kill $CP 2>/dev/null
sleep 1

# --- pass 3b: the same birth, said by the CONFIG. `start fullscreen`
# is the style's word for the clients that have no flag of their own;
# this client asks for nothing at all and is framed fullscreen anyway.
"$LINUX/whale" "$HERE/client.tcl" "стилевой" 240x120 "#fcaf3e" "" "" 25 \
    > "$HERE/fullscreen-styled.log" 2>&1 &
CS=$!
wait_client "$HERE/wm-fullscreen.log" 'стилевой'
STWIN=$(sed -n 's/^WM: \(0x[0-9a-f]*\) styled to start fullscreen/\1/p' \
    "$HERE/wm-fullscreen.log" | tail -1)
ST_SIZE=""
if [ -n "$STWIN" ]; then sleep 1; ST_SIZE=$(size "$STWIN"); fi
kill $CS 2>/dev/null
sleep 0.5

# --- pass 4: the real terminals, unmodified, each asking as it does
timeout 30 xterm -fullscreen -geometry 40x10 -e sh -c 'sleep 25' \
    >/dev/null 2>&1 &
sleep 3
XTWIN=$(xdotool search --class xterm 2>/dev/null | tail -1)
XT_SIZE=""; XT_STATE=""
[ -n "$XTWIN" ] && XT_SIZE=$(size "$XTWIN") && XT_STATE=$(state "$XTWIN")

timeout 30 kitty --start-as fullscreen -o confirm_os_window_close=0 \
    sh -c 'sleep 25' > "$HERE/fullscreen-kitty.log" 2>&1 &
sleep 6
KTWIN=$(xdotool search --class kitty 2>/dev/null | tail -1)
KT_SIZE=""; KT_STATE=""
[ -n "$KTWIN" ] && KT_SIZE=$(size "$KTWIN") && KT_STATE=$(state "$KTWIN")

# --- pass 5: emacs, the live client that could enter but never leave.
# Born maximized (-mm), it toggles fullscreen ON at t+4 and OFF at
# t+12 BY ITSELF — the round trip rides on ITS OWN idea of its state,
# which it folds out of our _NET_WM_STATE property left to right into
# one slot (xterm.c, x_get_current_wm_state). Published
# FULLSCREEN-first, the fold ended «maximized», the frame never
# believed it was fullscreen, and the second toggle asked for
# fullscreen AGAIN (the owner's desk, 2026-08-08). The property now
# lists maximized before fullscreen; the fold ends on the stronger
# word and the way back exists — and leads to MAXIMIZED, the state
# emacs held underneath all along.
EMWIN=""; EM0=""; EM1=""; EM2=""; EMST2=""
if command -v emacs >/dev/null 2>&1; then
    PRE=$(grep -c '^WM: managed' "$HERE/wm-fullscreen.log")
    emacs -Q -mm --eval '(progn
      (run-at-time 4 nil #'\''toggle-frame-fullscreen)
      (run-at-time 12 nil #'\''toggle-frame-fullscreen)
      (run-at-time 22 nil #'\''kill-emacs))' \
        > "$HERE/fullscreen-emacs.log" 2>&1 &
    EMPID=$!
    _one_more_managed() { [ "$(grep -c '^WM: managed' "$1")" -gt "$2" ]; }
    wait_for 15 _one_more_managed "$HERE/wm-fullscreen.log" "$PRE"
    EMWIN=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' \
        "$HERE/wm-fullscreen.log" | tail -1)
    EM0=$(size "$EMWIN")
    sleep 8                      # past the ON toggle (t+4)
    EM1=$(size "$EMWIN")
    sleep 8                      # past the OFF toggle (t+12)
    EM2=$(size "$EMWIN"); EMST2=$(state "$EMWIN")
    kill $EMPID 2>/dev/null
fi

# --- what the hints still get a say in: whether the state may be
# entered at all. "Fills the screen" is a promise about a window that
# CAN fill it; one that declared otherwise would be held at a size it
# had already refused, and the two would restate themselves at each
# other forever (lazarus-ide put fullscreen, the owner 2026-08-19).
# Three readings of the one predicate — can it be exactly this big:
# a bar that cannot, a window pinned at EXACTLY the screen (which can,
# and must not be refused for merely being non-resizable), and a client
# that says it cannot only once it is already in the state.
"$LINUX/whale" "$CONF/client-pin.tcl" тесный 1 64 32767 64 \
    > "$CONF/tight.log" 2>&1 &
CN1=$!
wait_client "$HERE/wm-fullscreen.log" 'тесный'
N1=$(wmctrl -l | awk '/тесный/{print $1; exit}')
wmctrl -i -r "$N1" -b add,fullscreen; sleep 1
ST_TIGHT=$(state "$N1")

"$LINUX/whale" "$CONF/client-pin.tcl" влитой 1024 768 1024 768 \
    > "$CONF/snug.log" 2>&1 &
CN2=$!
wait_client "$HERE/wm-fullscreen.log" 'влитой'
N2=$(wmctrl -l | awk '/влитой/{print $1; exit}')
wmctrl -i -r "$N2" -b add,fullscreen; sleep 1
ST_SNUG=$(state "$N2"); SZ_SNUG=$(size "$N2")

"$LINUX/whale" "$CONF/client-pin.tcl" запоздалый 1 64 32767 64 5000 \
    > "$CONF/latefs.log" 2>&1 &
CN3=$!
wait_client "$HERE/wm-fullscreen.log" 'запоздалый'
N3=$(wmctrl -l | awk '/запоздалый/{print $1; exit}')
wmctrl -i -r "$N3" -b add,fullscreen; sleep 1
ST_LATE0=$(state "$N3")
sleep 6                      # past the client's late pin
ST_LATE=$(state "$N3")
kill $CN1 $CN2 $CN3 2>/dev/null

import -window root "$HERE/fullscreen-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/fullscreen-test.png"

pkill -f 'sleep 25' 2>/dev/null
kill $CA $CT 2>/dev/null
sleep 0.5
kill $WM 2>/dev/null
sleep 0.5

echo "--- client $CID: $BEFORE_SIZE -> $FS_SIZE -> $BACK_SIZE"
echo "--- state while fullscreen: «$FS_STATE», after: «$BACK_STATE»"
echo "--- panel pixel: before=$BEFORE_PANEL fullscreen=$FS_PANEL back=$BACK_PANEL"
echo "--- tray pixel: fullscreen=$FS_TRAY, after an icon docked=$AFTERDOCK_PANEL"
echo "--- pre-map client $PMWIN: $PM_SIZE (manage-time property, $PREMAP seen)"
echo "--- xterm $XTWIN: $XT_SIZE «$XT_STATE»"
echo "--- kitty $KTWIN: $KT_SIZE «$KT_STATE»"
grep -E 'WM: (fullscreen|_NET_WM_STATE)' "$HERE/wm-fullscreen.log"

echo "--- verdict"
if [ "$SUPPORTED" = 1 ]; then
    echo "OK: _NET_WM_STATE_FULLSCREEN is advertised in _NET_SUPPORTED"
else
    echo "FAIL: the atom is not in _NET_SUPPORTED — no client will ever ask"
fi
if [ "$FS_SIZE" = "1024x768+0+0" ]; then
    echo "OK: the fullscreen client got the whole SCREEN, panel and all"
else
    echo "FAIL: fullscreen geometry «$FS_SIZE», want 1024x768+0+0"
fi
case "$FS_STATE" in
    *_NET_WM_STATE_FULLSCREEN*) echo "OK: ...and the state is published on the window" ;;
    *) echo "FAIL: _NET_WM_STATE is «$FS_STATE» while fullscreen" ;;
esac
case "$FS_PANEL" in
    *"138,226,52"*) echo "OK: ...and it really covers the panel (the pixel is the client)" ;;
    *) echo "FAIL: the panel pixel is $FS_PANEL, not the client — the strip is on top" ;;
esac
case "$FS_TRAY" in
    *"138,226,52"*) echo "OK: ...and the tray strip too" ;;
    *) echo "FAIL: the tray pixel is $FS_TRAY, not the client" ;;
esac
if [ "$DOCKED" -ge 1 ] 2>/dev/null; then
    case "$AFTERDOCK_PANEL" in
        *"138,226,52"*) echo "OK: an icon docking did not lift the tray back over it" ;;
        *) echo "FAIL: after a dock the tray pixel is $AFTERDOCK_PANEL — the strip climbed back" ;;
    esac
else
    echo "FAIL: no icon docked, the stacking-after-dock case went untested"
fi
if [ "$BACK_SIZE" = "$BEFORE_SIZE" ]; then
    echo "OK: leaving fullscreen restored the exact geometry ($BACK_SIZE)"
else
    echo "FAIL: came back as «$BACK_SIZE», was «$BEFORE_SIZE»"
fi
case "$BACK_STATE" in
    *_NET_WM_STATE_FULLSCREEN*) echo "FAIL: the state is still published after leaving" ;;
    *) echo "OK: ...and the state is gone from the property" ;;
esac
if [ "$BACK_PANEL" = "$BEFORE_PANEL" ]; then
    echo "OK: ...and the panel is back on top of the desk"
else
    echo "FAIL: the panel pixel is $BACK_PANEL, was $BEFORE_PANEL before"
fi
if [ "$PREMAP" = 1 ] && [ "$PM_SIZE" = "1024x768+0+0" ]; then
    echo "OK: a window that asked BEFORE its map was framed fullscreen at once"
else
    echo "FAIL: pre-map client is «$PM_SIZE» ($PREMAP manage-time requests seen)"
fi
if [ -n "$STWIN" ] && [ "$ST_SIZE" = "1024x768+0+0" ]; then
    echo "OK: a «start fullscreen» style framed its window fullscreen, unasked"
else
    echo "FAIL: the styled client is «$ST_SIZE» (window «$STWIN»)"
fi
if [ "$XT_SIZE" = "1024x768+0+0" ]; then
    echo "OK: xterm -fullscreen came up fullscreen, by itself"
else
    echo "FAIL: xterm is «$XT_SIZE», want 1024x768+0+0"
fi
if [ "$KT_SIZE" = "1024x768+0+0" ]; then
    echo "OK: kitty --start-as fullscreen came up fullscreen, by itself"
else
    echo "FAIL: kitty is «$KT_SIZE», want 1024x768+0+0"
fi
if [ -n "$EMWIN" ]; then
    echo "--- emacs $EMWIN: born=$EM0 on=$EM1 off=$EM2 «$EMST2»"
    if [ "$EM1" = "1024x768+0+0" ]; then
        echo "OK: emacs took itself fullscreen"
    else
        echo "FAIL: after its ON toggle emacs is «$EM1»"
    fi
    if [ "$EM2" = "$EM0" ] && [ "$EM2" != "1024x768+0+0" ]; then
        echo "OK: ...and brought itself BACK — to the maximized frame it was born with"
    else
        echo "FAIL: after its OFF toggle emacs is «$EM2», born «$EM0» — no way back"
    fi
    case "$EMST2" in
        *FULLSCREEN*) echo "FAIL: the property still says fullscreen after the OFF toggle" ;;
        *MAXIMIZED*)  echo "OK: ...and the property agrees — maximized, not fullscreen" ;;
        *) echo "FAIL: after the OFF toggle the property is «$EMST2», want maximized" ;;
    esac
else
    echo "note: no emacs on this machine — the fold-order pass ran nowhere"
fi
echo "--- the size window: tight=«$ST_TIGHT» snug=«$ST_SNUG» ($SZ_SNUG)\
 late=«$ST_LATE0» -> «$ST_LATE»"
case "$ST_TIGHT" in
    *FULLSCREEN*) echo "FAIL: a bar that declared it cannot be 768 tall was\
 put fullscreen anyway — it will ask its way back out forever" ;;
    *) if grep -q 'fullscreen refused' "$HERE/wm-fullscreen.log"; then
           echo "OK: fullscreen refused to a client that cannot be that size, and said so"
       else
           echo "FAIL: no state, but no refusal line either — something else swallowed it"
       fi ;;
esac
case "$ST_SNUG" in
    *FULLSCREEN*) if [ "$SZ_SNUG" = "1024x768+0+0" ]; then
            echo "OK: a window PINNED at exactly the screen still gets its fullscreen"
        else
            echo "FAIL: the pinned-at-screen client is «$SZ_SNUG», want 1024x768+0+0"
        fi ;;
    *) echo "FAIL: a window that fits the screen exactly was refused — the\
 predicate is reading «non-resizable», not «cannot be this big»" ;;
esac
case "$ST_LATE0" in
    *FULLSCREEN*) echo "OK: the late client entered the state while it still fitted" ;;
    *) echo "FAIL: the late client never got fullscreen at all («$ST_LATE0»)" ;;
esac
case "$ST_LATE" in
    *FULLSCREEN*) echo "FAIL: it declared mid-state that it cannot be that size and\
 the state stayed — the flicker starts here" ;;
    *) echo "OK: ...and the state went when the client withdrew the ground it stood on" ;;
esac
if grep -q 'handler error' "$HERE/wm-fullscreen.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-fullscreen.log"
fi
if grep -q 'soft failure' "$HERE/wm-fullscreen.log"; then
    echo "NOTE: soft failures:"; grep 'soft failure' "$HERE/wm-fullscreen.log"
fi
