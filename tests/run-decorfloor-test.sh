#!/bin/sh
# Regression for `decor-floor` — the least frame a window that ASKED
# for no decoration still wears. The desk-wide form is the point:
#
#     wm-style always {decor-floor border}
#
# and every self-decorated window (firefox, any GTK4 window — Motif
# decorations word 0) gets a resize border and a focus ring it cannot
# draw for itself. What the floor must NOT do is as much of the
# contract as what it must:
#
#   - a window that said NOTHING wears the full frame, floor or no
#     floor — the floor is a floor, never a ceiling;
#   - the furniture types (a splash here; dock, tooltip, menus alike)
#     go bare from their TYPE, not from Motif, and stay bare — a
#     desk-wide floor must not dress the panel's neighbours;
#   - an explicit `decor none` rule still pins its window bare UNDER
#     the floor — the config outranks the floor the same way it
#     outranks the hint;
#   - the floor is an ordinary style key: a later rule's
#     `decor-floor full` beats the always-rule's `border` for its
#     windows, per-key, like any other.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/decorfloor-config"
mkdir -p "$HERE/decorfloor-config"
cat > "$HERE/decorfloor-config/tk9wm.tcl" <<'EOF'
wm-style always {decor-floor border}
wm-style {filter -title прибитый} {decor none}
wm-style {filter -title потолще}  {decor-floor full}
EOF

XDG_CONFIG_HOME="$HERE/decorfloor-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-decorfloor.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-decorfloor.log" $WM

# csd-client argv: title geometry color ?motif? ?type? ?dragdir? ?secs?
# молчун    says nothing            — full frame, the floor is no ceiling
# гтк       motif 0                 — promoted: border and grips
# заставка  type splash, no Motif   — furniture, stays bare
# прибитый  motif 0 + `decor none`  — pinned bare under the floor
# потолще   motif 0 + floor full    — the later rule's floor wins
for spec in "молчун::" "гтк:0:" "заставка::splash" "прибитый:0:" \
            "потолще:0:"; do
    title=${spec%%:*}; rest=${spec#*:}
    motif=${rest%%:*}
    wtype=${rest#*:}
    "$LINUX/whale" "$HERE/csd-client.tcl" "$title" 200x140 "#fcaf3e" \
        "$motif" "$wtype" "" 25 > "$HERE/decorfloor-$title.log" 2>&1 &
    sleep 1.2
done
sleep 1

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-decorfloor.log")
PLAIN=$1; BARE=$2; SPLASH=$3; PINNED=$4; RAISED=$5
ext() { xprop -id "$1" _NET_FRAME_EXTENTS 2>/dev/null | sed 's/.*= //'; }

TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-decorfloor.log" | head -1)
B=6                       # the border, all four sides (policy/00-prologue.tcl)
FULL="$B, $B, $TOP, $B"
BORDER="$B, $B, $B, $B"
NONE="0, 0, 0, 0"

echo "--- what each window was framed with"
printf 'молчун   %s\nгтк      %s\nзаставка %s\nприбитый %s\nпотолще  %s\n' \
    "$(ext $PLAIN)" "$(ext $BARE)" "$(ext $SPLASH)" "$(ext $PINNED)" \
    "$(ext $RAISED)"
echo "--- full «$FULL», border «$BORDER», none «$NONE»"

FAIL=0
verdict() {
    if [ "$2" = "$3" ]; then
        echo "OK: $1"
    else
        echo "FAIL: $1 — got «$2», want «$3»"; FAIL=1
    fi
}
echo "--- verdict"
verdict "a window that said nothing keeps the whole frame" \
    "$(ext $PLAIN)" "$FULL"
verdict "the CSD window is floored up to a border" "$(ext $BARE)" "$BORDER"
verdict "the furniture stays bare under a desk-wide floor" \
    "$(ext $SPLASH)" "$NONE"
verdict "an explicit «decor none» still pins its window bare" \
    "$(ext $PINNED)" "$NONE"
verdict "a later rule's floor outbids the desk-wide one" \
    "$(ext $RAISED)" "$FULL"

kill $WM 2>/dev/null
pkill -f csd-client.tcl 2>/dev/null
check_invariants "$HERE/wm-decorfloor.log" || FAIL=1
if grep -q 'handler error' "$HERE/wm-decorfloor.log"; then
    echo "FAIL: handler errors present:"
    grep 'handler error' "$HERE/wm-decorfloor.log"
    FAIL=1
fi
exit $FAIL
