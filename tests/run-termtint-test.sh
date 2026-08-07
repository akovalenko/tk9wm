#!/bin/sh
# Regression for the terminal's colours and the name-tint word.
#
# A terminal deed says bg/fg in any Tk colour; the adapter normalizes
# to hex ONCE (alacritty knows no X names) and speaks the beast's own
# dialect — xterm through -xrm aimed at the VT100 widget, so the menus
# stay unpainted. Measured by pixel: the spawned xterm's body must BE
# the colour the spec said. The dialect table is asked directly for
# the beasts this box does not carry, and vanilla st must have no
# colour entry at all — its colours are compiled in.
#
# name-tint is the badge hash published as a word: stable per name,
# different across names, format honest, -amount 0 is the bare ground,
# the unsaid -from follows the theme's side.
. "$(dirname "$0")/common.sh"
start_xvfb
CONF="$HERE/termtint-config"

key() { xdotool key "$@"; sleep 1; }
ask() {
    printf '%s\n' "$1" > "$CONF/ask.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/ask.tcl" 2>&1
}
px() {
    import -window root png:- 2>/dev/null | convert png:- -format \
        "%[pixel:p{$1,$2}]" info:-
}

rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
action tinted {terminal {name tinted bg #200040 fg #e0e0ff}
               run {sleep 60} key {<Super>1}}
action named  {terminal {name namedcol bg DarkSlateGray4}
               run {sleep 60} key {<Super>2}}
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$HERE/wm-termtint.log" 2>&1 &
WM=$!
sleep 1.5

key super+1
sleep 2.5
TID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-termtint.log" | sed -n 1p)
GEOM=$(xwininfo -id "$TID" | awk '/Absolute upper-left X/ {x=$NF}
    /Absolute upper-left Y/ {y=$NF} /Width:/ {w=$NF} /Height:/ {h=$NF}
    END {print x+w/2, y+h/2}')
BODY=$(px $GEOM)
key super+2
sleep 2.5

NT=$(ask 'list fmt [regexp {^#[0-9a-f]{6}$} [name-tint пример]] \
    stable [expr {[name-tint пример] eq [name-tint пример]}] \
    differs [expr {[name-tint пример] ne [name-tint другой]}] \
    w0 [name-tint x -from white -amount 0] \
    b0 [name-tint x -from black -amount 0] \
    sides [expr {[name-tint x -from white] ne [name-tint x -from black]}] \
    theme [expr {[name-tint x] eq [name-tint x -from black]}]')
AD=$(ask 'list kitty [dict get $::terminal_adapters kitty bg] \
    alacritty [dict get $::terminal_adapters alacritty bg] \
    st [dict exists $::terminal_adapters st bg]')

import -window root "$HERE/termtint-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/termtint-test.png"
kill $WM 2>/dev/null

echo "--- terminal window $TID, body pixel at ($GEOM): $BODY"
echo "--- name-tint: $NT"
echo "--- adapters:  $AD"
echo "--- WM saw:"
grep -E 'terminal: spawn|no way to say' "$HERE/wm-termtint.log"

echo "--- verdict"
BAD=0
if grep -q 'soft failure\|handler error' "$HERE/wm-termtint.log"; then
    echo "FAIL: soft failures or handler errors:"
    grep 'soft failure\|handler error' "$HERE/wm-termtint.log"; BAD=1
fi
if grep -q 'VT100\.background: #200040' "$HERE/wm-termtint.log" \
        && grep -q 'VT100\.foreground: #e0e0ff' "$HERE/wm-termtint.log"; then
    echo "OK: xterm is told through -xrm at the VT100 widget, dot-bound, bg and fg"
else
    echo "FAIL: the xterm spelling is missing from the spawn"; BAD=1
fi
if [ "$BODY" = "srgb(32,0,64)" ]; then
    echo "OK: the terminal's body IS the colour the spec said ($BODY)"
else
    echo "FAIL: the body pixel is $BODY, want srgb(32,0,64)"; BAD=1
fi
if grep -q 'VT100\.background: #528b8b' "$HERE/wm-termtint.log"; then
    echo "OK: an X colour name is normalized to hex before the dialect"
else
    echo "FAIL: DarkSlateGray4 did not come out as #528b8b"; BAD=1
fi
if [ "$NT" = "fmt 1 stable 1 differs 1 w0 #ffffff b0 #000000 sides 1 theme 1" ]; then
    echo "OK: name-tint is stable, distinct, honest at both grounds and follows the theme"
else
    echo "FAIL: name-tint answered: $NT"; BAD=1
fi
if [ "$AD" = 'kitty {-o background=%s} alacritty {-o {colors.primary.background = "%s"}} st 0' ]; then
    echo "OK: the dialect table spells kitty and alacritty, and st has no word"
else
    echo "FAIL: the dialect table says: $AD"; BAD=1
fi

check_invariants "$HERE/wm-termtint.log"
if grep -q 'WM: INVARIANT' "$HERE/wm-termtint.log"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: the colours reach the glass, the names normalize, the word answers"
exit $BAD
