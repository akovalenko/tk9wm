#!/bin/sh
# Regression for the menu rows' SECOND reading: shift-do /
# shift-action on a wm-menu row, shift-value on a Choose row, and the
# degradations that keep the modifier honest.
#
# Every way of picking carries the modifier: Shift+Return on the
# selection, Shift+letter on a mnemonic (a shifted letter arrives as
# its own uppercase keysym — the -nocase match takes it), and a
# Shift+click (the %s the popup shell now hands every pick). A row
# without a shift half must read PLAIN under Shift — the modifier
# never invents a difference the row did not declare — and a shift
# half whose reference nobody declared is a PROBLEM once per
# declaration cycle while the row itself stays alive.
. "$(dirname "$0")/common.sh"
start_xvfb

key() { xdotool key "$@"; sleep 1; }

# The desk: one menu of three rows — plain-only, both-readings with a
# mnemonic, and a shift half pointing at nobody — pinned to the top
# left corner so the mouse leg can aim at a row by arithmetic; plus a
# Choose with one two-reading row inside an ordinary binding.
CONF="$HERE/menushift-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
wm-menu sh1 {
    key   {<Super>m}
    place {left top}
    items {
        {label одинокий do {puts "TEST: plain only"}}
        {label двоякий key b
         do       {puts "TEST: both plain"}
         shift-do {puts "TEST: both shift"}}
        {label призрачный do {puts "TEST: ghosty plain"}
         shift-action nosuch-deed}
    }
}
wm-bind {<Super>c} {puts "TEST: chose <[Choose {
    {label раз value R shift-value SR key r}
    {label два value D key d}}]>"}
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-menushift.log" 2>&1 &
WM=$!
sleep 2

# ---- Shift+Return takes the shift half; bare Return the plain one
key super+m
key Down              # onto «двоякий»
key shift+Return
key super+m
key Down
key Return
# ---- Shift+letter is the same second reading as Shift+Return
key super+m
key shift+b
key super+m
key b
# ---- a row with no shift half reads plain under Shift
key super+m
key shift+Return      # selection starts on «одинокий»
# ---- the unknown shift half: the row lives, Shift reads plain
key super+m
key Down
key Down              # onto «призрачный»
key shift+Return
# ---- Choose: shift-value answered shifted, value bare, and a row
# without a shift-value ignores the modifier
key super+c
key shift+r
key super+c
key r
key super+c
key shift+d
# ---- the mouse: a Shift+click reads the same second reading. The
# menu is pinned to the top left, so the second row's center is one
# row-height and a half below the top edge, read off the geometry the
# open line prints.
key super+m
GEO=$(grep 'WM: menu sh1 open' "$HERE/wm-menushift.log" | tail -1 \
      | sed -n 's/.* \([0-9]*x[0-9]*+[0-9]*+[0-9]*\)$/\1/p')
W=${GEO%%x*}; rest=${GEO#*x}; H=${rest%%+*}; xy=${rest#*+}
X=${xy%%+*}; Y=${xy#*+}
ROWH=$(( (H - 2) / 3 ))
xdotool mousemove $((X + W / 2)) $((Y + 1 + ROWH + ROWH / 2))
sleep 0.3
xdotool keydown shift click 1 keyup shift
sleep 1

kill $WM 2>/dev/null
sleep 0.3

echo "--- WM saw:"
grep -E 'WM: menu|WM: PROBLEM|TEST:' "$HERE/wm-menushift.log"

echo "--- verdict"
BAD=0
if grep -q 'BadAccess request=2' "$HERE/wm-menushift.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"; BAD=1
fi
if grep -q 'soft failure\|handler error' "$HERE/wm-menushift.log"; then
    echo "FAIL: soft failures or handler errors:"
    grep 'soft failure\|handler error' "$HERE/wm-menushift.log"; BAD=1
fi

SHIFTS=$(grep -c 'TEST: both shift' "$HERE/wm-menushift.log")
if [ "$SHIFTS" = "3" ]; then
    echo "OK: the shift half fired by Shift+Return, Shift+letter and Shift+click"
else
    echo "FAIL: the shift half fired $SHIFTS times, want 3 (Return, letter, click)"; BAD=1
fi
PLAINS=$(grep -c 'TEST: both plain' "$HERE/wm-menushift.log")
if [ "$PLAINS" = "2" ]; then
    echo "OK: the plain half still answers bare Return and the bare letter"
else
    echo "FAIL: the plain half fired $PLAINS times, want 2"; BAD=1
fi
MARKED=$(grep -c 'pick «двоякий» (shift)' "$HERE/wm-menushift.log")
if [ "$MARKED" = "3" ]; then
    echo "OK: a shifted pick says so in the log — (shift) on the pick line"
else
    echo "FAIL: the (shift) mark showed $MARKED times, want 3"; BAD=1
fi
if grep -q 'TEST: plain only' "$HERE/wm-menushift.log"; then
    echo "OK: Shift on a row with no shift half read plain"
else
    echo "FAIL: the plain-only row did not fire under Shift"; BAD=1
fi
if grep -q 'TEST: ghosty plain' "$HERE/wm-menushift.log" \
        && grep -q 'WM: PROBLEM menu sh1: shift half «nosuch-deed»' \
               "$HERE/wm-menushift.log"; then
    echo "OK: the unknown shift half griped and the row read plain"
else
    echo "FAIL: the unknown shift half did not gripe, or the row died"; BAD=1
fi
if grep -q 'TEST: chose <SR>' "$HERE/wm-menushift.log"; then
    echo "OK: Choose answered the shift-value to a shifted pick"
else
    echo "FAIL: Choose did not answer SR"; BAD=1
fi
if grep -q 'TEST: chose <R>' "$HERE/wm-menushift.log"; then
    echo "OK: Choose answered the plain value to a bare pick"
else
    echo "FAIL: Choose did not answer R"; BAD=1
fi
if grep -q 'TEST: chose <D>' "$HERE/wm-menushift.log"; then
    echo "OK: a Choose row without a shift-value ignored the modifier"
else
    echo "FAIL: Choose did not answer D under Shift"; BAD=1
fi
check_invariants "$HERE/wm-menushift.log"
if grep -q 'WM: INVARIANT' "$HERE/wm-menushift.log"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: every way of picking carries the modifier, and no row is surprised by it"
exit $BAD
