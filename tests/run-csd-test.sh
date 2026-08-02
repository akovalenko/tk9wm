#!/bin/sh
# Regression for the client-decorated window — the shape every GTK
# window has had since headerbars, and the one this desk used to frame
# twice. Three questions, all of them the client's to answer:
#
#   1. _MOTIF_WM_HINTS, the Motif hint of 1989 that nothing replaced:
#      the decorations word decides how much frame the window wears,
#      and its three interesting values land on our own three steps —
#      nothing, a border without a title, the lot.
#   2. _NET_WM_WINDOW_TYPE, the semantic half: a splash screen carries
#      no frame without having to spell the Motif mask out.
#   3. _NET_WM_MOVERESIZE: a window with no titlebar of OURS has
#      nothing to grab, so it asks us to run the drag. Under a
#      reparenting manager this is not a nicety — the fallback gdk
#      takes when the atom is missing moves the client INSIDE our
#      frame, which is not a move at all.
#
# And the rule that outranks all three: a `decor` named in the config
# beats what the window asked for (the owner's call, 2026-08-02).
#
# What this file does NOT prove, and where to look instead: the drag is
# driven by a client of ours that follows the spec to the letter. A
# REAL GTK4 app (gnome-text-editor) was measured on the side, and the
# decoration half is exactly right — it comes up bare, no double
# titlebar. Its drag, though, cannot be driven headlessly: the app
# sends the request, we take the pointer grab, and the motion that
# xdotool fakes afterwards never reaches the grab. Not ours — fvwm3
# and icewm were put under the identical script and neither moved the
# window either (icewm honors the Motif hint as we now do; fvwm3
# ignores it and frames GTK4 twice). A live X server is where that
# half gets its last check.
. "$(dirname "$0")/common.sh"
export DISPLAY=:103
rm -f /tmp/.X103-lock /tmp/.X11-unix/X103
Xvfb :103 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

# The config speaks about ONE window, by title: «рулевой» asks for no
# decoration exactly as the others do, and is given the full frame
# anyway. That is the override, and it is the whole reason the hint
# seeds the style instead of replacing it.
rm -rf "$HERE/csd-config"
mkdir -p "$HERE/csd-config"
cat > "$HERE/csd-config/tk9wm.tcl" <<'EOF'
wm-style {filter -title рулевой} {decor full}
# The dragged one is pinned to the workarea's own corner, and for a
# reason the first run of this test found the hard way: an asked-for
# drag is a drag like any other, edge resistance included, and a window
# left where the cascade happened to put it landed 10px from the right
# edge and STUCK to it — correctly, and 10px away from what the
# arithmetic below expected. Started flush in the corner, it is nowhere
# near an edge after the drag.
wm-style {filter -title таскаемый} {place {left top}}
EOF

XDG_CONFIG_HOME="$HERE/csd-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-csd.log" 2>&1 &
WM=$!
sleep 1.5

# motif "" type ""      — says nothing, the ordinary framed window
# motif 0               — GTK's own request: no decoration at all
# motif 8               — MWM_DECOR_TITLE: a titlebar, i.e. the lot
# motif 6               — BORDER|RESIZEH: a border, no title strip
# type splash           — no Motif word at all, the type decides
# motif 0 + config rule — the hint loses to the config
for spec in "молчун:::" "гтк::0:" "заголовок::8:" "бордюр::6:" \
            "заставка:splash::" "рулевой::0:"; do
    title=${spec%%:*}; rest=${spec#*:}
    wtype=${rest%%:*};  rest=${rest#*:}
    motif=${rest%%:*}
    "$LINUX/whale" "$HERE/csd-client.tcl" "$title" 200x140 "#8ae234" \
        "$motif" "$wtype" "" 25 > "$HERE/csd-$title.log" 2>&1 &
    sleep 1.2
done
sleep 1
# Read while the WM is alive: the list goes off the root with it.
SUPPORTED=$(xprop -root _NET_SUPPORTED 2>/dev/null)

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-csd.log")
PLAIN=$1; BARE=$2; TITLED=$3; BORDERED=$4; SPLASH=$5; RULED=$6
ext() { xprop -id "$1" _NET_FRAME_EXTENTS 2>/dev/null | sed 's/.*= //'; }

# The decoration's own numbers, from the WM's own metric line — the
# same source the extents regression trusts.
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-csd.log" | head -1)
B=6                       # the border, all four sides (policy.tcl)
FULL="$B, $B, $TOP, $B"
BORDER="$B, $B, $B, $B"
NONE="0, 0, 0, 0"

echo "--- what each window was framed with"
printf 'молчун    %s\nгтк       %s\nзаголовок %s\nбордюр    %s\nзаставка  %s\nрулевой   %s\n' \
    "$(ext $PLAIN)" "$(ext $BARE)" "$(ext $TITLED)" "$(ext $BORDERED)" \
    "$(ext $SPLASH)" "$(ext $RULED)"
echo "--- full «$FULL», border «$BORDER», none «$NONE»"

verdict() {
    if [ "$2" = "$3" ]; then
        echo "OK: $1"
    else
        echo "FAIL: $1 — got «$2», want «$3»"
    fi
}
echo "--- verdict: the hints"
verdict "a window that said nothing wears the whole frame" "$(ext $PLAIN)" "$FULL"
verdict "decorations=0 takes the frame off (GTK's own request)" "$(ext $BARE)" "$NONE"
verdict "MWM_DECOR_TITLE keeps the titlebar" "$(ext $TITLED)" "$FULL"
verdict "BORDER|RESIZEH is a border and no title" "$(ext $BORDERED)" "$BORDER"
verdict "a splash screen needs no Motif word to go bare" "$(ext $SPLASH)" "$NONE"
verdict "the config's decor outranks the client's hint" "$(ext $RULED)" "$FULL"

# ---- the drag the client asks for ----
# Alone on the desk, so nothing else is under the pointer: the others
# go, and a fresh window asks to be carried three seconds in.
pkill -f csd-client.tcl 2>/dev/null
sleep 1
"$LINUX/whale" "$HERE/csd-client.tcl" "таскаемый" 200x140 "#729fcf" 0 "" 8 20 \
    > "$HERE/csd-drag.log" 2>&1 &
sleep 1.5
DRAGGED=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-csd.log" | tail -1)
pos() { xwininfo -id "$1" | sed -n 's/^  Absolute upper-left \([XY]\): *\([0-9-]*\)/\2/p' | tr '\n' ' '; }
BEFORE=$(pos "$DRAGGED")
set -- $BEFORE
PX=$(( $1 + 100 )); PY=$(( $2 + 70 ))

# A press for real, where a GTK headerbar drag begins: our
# click-to-focus grab sees it, replays it to the client, and the client
# ungrabs the pointer before asking — which is what makes the grab
# below ours to take.
xdotool mousemove $PX $PY mousedown 1
sleep 2                    # the client asks at t=3s, pointer already parked
xdotool mousemove_relative -- 60 40
sleep 0.5
xdotool mouseup 1
sleep 0.5
AFTER=$(pos "$DRAGGED")

kill $WM 2>/dev/null
pkill -f csd-client.tcl 2>/dev/null
sleep 0.5

set -- $BEFORE; BX=$1; BY=$2
set -- $AFTER;  AX=$1; AY=$2
echo "--- the asked-for drag: +$BX+$BY -> +$AX+$AY (want +$((BX+60))+$((BY+40)))"
grep -E 'moveresize request|asked for' "$HERE/wm-csd.log"
echo "--- verdict: the drag"
if grep -q 'moveresize request dir=8' "$HERE/wm-csd.log"; then
    echo "OK: the request reached the WM"
else
    echo "FAIL: no _NET_WM_MOVERESIZE line in the log"
fi
if [ "$AX" = "$((BX+60))" ] && [ "$AY" = "$((BY+40))" ]; then
    echo "OK: the window followed the pointer, frame and all"
else
    echo "FAIL: moved to +$AX+$AY, want +$((BX+60))+$((BY+40))"
fi
if echo "$SUPPORTED" | grep -q _NET_WM_MOVERESIZE; then
    echo "OK: _NET_WM_MOVERESIZE is advertised (gdk looks before it asks)"
else
    echo "FAIL: _NET_WM_MOVERESIZE is not in _NET_SUPPORTED"
fi
check_invariants "$HERE/wm-csd.log"
