#!/bin/sh
# Regression for FADE — a frame made translucent by command — and for
# the claim underneath it: that it happens ON THE FLY.
#
# The owner's question (2026-07-30) was exactly that: can we do it
# live, or only across a withdraw/deiconify — and if only the latter,
# whose limitation is it. The answer is measured here rather than
# argued: the frame's opacity is one property a COMPOSITOR reads
# (_NET_WM_WINDOW_OPACITY, which Tk spells `wm attributes -alpha`), so
#
#  - the PIXELS change while the window stays mapped, and to the value
#    the arithmetic says: half the titlebar's blue plus half of
#    whatever the desk behind it is — sampled, not assumed, since the
#    root under Xvfb is a gray and not the black the screenshots of
#    the other tests suggest;
#  - the SERVER's own event stream carries no map, unmap or reparent
#    for that frame across the change — xev is the witness, since a
#    "no remap" claim cannot be made by the process doing the remapping;
#  - Unfade puts it back, and a style rule can make a client rest
#    translucent from the moment it is mapped.
#
# xcompmgr is what makes any of it visible; with no compositor the
# property is ignored by everybody and nothing here would move, which
# is the compositor's half of the bargain and not the WM's.
. "$(dirname "$0")/common.sh"
start_xvfb
CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-fade 0.5
wm-bind {<Super>f} Fade
wm-bind {<Super>g} Unfade
# a client that is translucent from birth, by rule and not by command
wm-style {filter -title призрак} {opacity 0.25}
EOF
sleep 1

command -v xcompmgr >/dev/null || { echo "SKIP: no xcompmgr on this host"; exit 0; }
xcompmgr -n >/dev/null 2>&1 &
COMP=$!
sleep 0.7

LOG="$HERE/wm-fade.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM
"$LINUX/whale" "$HERE/client.tcl" "плотное" 300x200 "#fce94f" "" "" 60 &
CA=$!
sleep 1.5

AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | head -1)
eval "$(awk '/frame \.f[0-9]+ for/ {
    if (match($0, /\+(-?[0-9]+)\+(-?[0-9]+)$/)) {
        split(substr($0, RSTART + 1), a, "+")
        print "FX=" a[1] "; FY=" a[2]
    }
}' "$LOG")"
# a pixel in the middle of the titlebar, clear of the buttons and text
pixel_at() {
    import -window root png:- 2>/dev/null \
        | convert png:- -format "%[pixel:p{$1,$2}]" info:-
}
# the middle of the titlebar, clear of the buttons and the text...
bar() { pixel_at $((FX + 150)) $((FY + 12)); }
# ...and a patch of bare desk well away from the frame, which is what
# a translucent frame will be blended WITH.
desk() { pixel_at 700 500; }

SOLID=$(bar)
DESK=$(desk)

# --- the fade itself, with the server watched across it
XEVLOG="$HERE/fade-xev.log"
stdbuf -oL xev -root -event substructure > "$XEVLOG" 2>&1 &
XEV=$!
sleep 0.5
xdotool key super+f
sleep 0.8
FADED=$(bar)
kill $XEV 2>/dev/null
import -display "$DISPLAY" -window root "$HERE/fade-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/fade-test.png"

xdotool key super+g
sleep 0.8
BACK=$(bar)

# --- and a client that is born translucent, by style
"$LINUX/whale" "$HERE/client.tcl" "призрак" 300x200+380+300 "#8ae234" "" "" 20 &
CB=$!
sleep 2
GHOST=$(sed -n 's/^WM: opacity 0x[0-9a-f]* -> //p' "$LOG" | tail -1)

kill $WM $CA $CB $COMP 2>/dev/null

# The frame's own X window is the WRAPPER — Tk's toplevel is its child,
# and the wrapper is what the root has and the compositor composites.
# Map events for it are what a withdraw/deiconify would show.
FRAMEW=$(awk '/^(Map|Unmap|Reparent)Notify event/ {t=$1}
    t != "" && /window 0x/ {print t; t=""}' "$XEVLOG" | sort | uniq -c \
    | tr "\n" " ")

echo "--- opacity lines:"
grep -E 'WM: opacity' "$LOG"
echo "--- titlebar pixel: solid=$SOLID faded=$FADED back=$BACK; desk=$DESK"
echo "--- structure events seen anywhere while fading: ${FRAMEW:-none}"

echo "--- verdict"
FAIL=0
if [ "$SOLID" = "srgb(52,101,164)" ]; then
    echo "OK: the titlebar starts solid ($SOLID)"
else
    echo "FAIL: the titlebar reads $SOLID before the fade, want srgb(52,101,164)"
    FAIL=1
fi
# Half the titlebar plus half the desk behind it, computed from the two
# pixels actually sampled — a hard-coded expectation would only be
# testing what colour Xvfb paints its root.
BLEND=$(echo "$SOLID $DESK $FADED" | awk '
    { split($0, p, /[^0-9]+/) }
    END {
        # p[1] is the empty field before the first "srgb(" — and there
        # is no empty one BETWEEN the triples, ")" and " srgb(" being
        # one separator. Nine numbers, in order.
        fr = p[2]; fg = p[3]; fb = p[4]
        dr = p[5]; dg = p[6]; db = p[7]
        gr = p[8]; gg = p[9]; gb = p[10]
        er = (fr + dr) / 2; eg = (fg + dg) / 2; eb = (fb + db) / 2
        off = 0
        if ((gr - er) ^ 2 > 9 || (gg - eg) ^ 2 > 9 || (gb - eb) ^ 2 > 9) off = 1
        printf "%d want=srgb(%d,%d,%d)", off, er, eg, eb
    }')
case "$BLEND" in
    0*) echo "OK: at 0.5 the titlebar blends with the desk to $FADED\
 (${BLEND#0 })" ;;
    *)  echo "FAIL: faded pixel is $FADED over desk $DESK — ${BLEND#1 }"
        FAIL=1 ;;
esac
if [ "$BACK" = "$SOLID" ]; then
    echo "OK: Unfade put it back exactly ($BACK)"
else
    echo "FAIL: after Unfade the pixel is $BACK, want $SOLID"; FAIL=1
fi
case "$FRAMEW" in
    *Map*|*Unmap*|*Reparent*)
        echo "FAIL: the server saw $FRAMEW while fading — that is a remap,\
 not a live change"; FAIL=1 ;;
    *)  echo "OK: not one map, unmap or reparent crossed the wire — the\
 change is live" ;;
esac
if [ "$GHOST" = "0.25" ]; then
    echo "OK: a style rule made a client rest translucent from birth ($GHOST)"
else
    echo "FAIL: the styled client's opacity is «$GHOST», want 0.25"; FAIL=1
fi
if grep -q 'handler error' "$LOG"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$LOG"; FAIL=1
fi
check_invariants "$LOG"
exit $FAIL
