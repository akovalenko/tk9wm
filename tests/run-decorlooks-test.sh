#!/bin/sh
# Regression for the named decoration schemes: wm-look declares a
# scheme (border, grips, a font delta on TitleFont, everything
# derived precomputed), the style key `look` dresses windows in it by
# rule. Two actors side by side on one desk:
#
#   - the extents differ per window — the scheme's border and strip
#     height answer for ITS windows, default's for the rest;
#   - a smaller italic title font gives a SHORTER strip (titleh
#     derives from the scheme's own font), and the strip's text is
#     set in the scheme's font, not TitleFont;
#   - narrow corner grips hit-test narrow: a point inside default's
#     arm reach but past the scheme's answers the plain edge;
#   - re-application is LIVE: a reload that re-declares the scheme
#     re-frames its windows (new numbers, extents republished), and a
#     reload that drops the rule hands the window back to default —
#     the full re-frame sweep, not just a titlebar rebuild.
. "$(dirname "$0")/common.sh"
start_xvfb

CONF="$HERE/decorlooks-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
wm-look compact {border 3 grips 10 air 0 button-gap 1 font {-size 8 -slant italic}}
wm-style {filter -title узкий*} {look compact}
titlebar-button ask -glyph ✳
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-decorlooks.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-decorlooks.log" $WM

# two actors: обычный wears default, узкий wears compact by the rule
"$LINUX/whale" "$HERE/client.tcl" "обычный" 240x120 "#8ae234" "" "" 60 \
    > "$HERE/decorlooks-a.log" 2>&1 &
CA=$!
wait_client "$HERE/wm-decorlooks.log" 'обычный'
"$LINUX/whale" "$HERE/client.tcl" "узкий актёр" 240x120 "#fcaf3e" "" "" 60 \
    > "$HERE/decorlooks-b.log" 2>&1 &
CB=$!
wait_client "$HERE/wm-decorlooks.log" 'узкий актёр'

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-decorlooks.log")
WA=$1; WB=$2
WAD=$(printf %d "$WA")
WBD=$(printf %d "$WB")

q() { printf '%s\n' "$1" > "$CONF/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl" 2>&1; }
ext() { xprop -id "$1" _NET_FRAME_EXTENTS 2>/dev/null | sed 's/.*= //'; }
extB_is() { [ "$(ext $WB)" = "$1" ]; }

# the desk's numbers from the boot log; the scheme's from its own line
DH=$(sed -n 's/^WM: titlebar h=\([0-9]*\).*/\1/p' "$HERE/wm-decorlooks.log" | tail -1)
DTOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-decorlooks.log" | tail -1)
DBTN=$(sed -n 's/^WM: titlebar h=[0-9]* top=[0-9]* btn=\([0-9]*\).*/\1/p' "$HERE/wm-decorlooks.log" | tail -1)
looknums() { sed -n 's/^WM: look compact h=\([0-9]*\) top=\([0-9]*\) btn=\([0-9]*\) border=\([0-9]*\) grips=\([0-9]*\).*/\1 \2 \3 \4 \5/p' \
    "$HERE/wm-decorlooks.log" | tail -1; }
set -- $(looknums); CH=$1; CTOP=$2; CBTN=$3; CBORD=$4; CGRIPS=$5

EA0=$(ext $WA)
EB0=$(ext $WB)
# the strip's text element wears the scheme's font
BFONT=$(q "set t \$::frameof($WBD); \$t.title element cget eTxt -font")
BSLANT=$(q "font actual LookFont-compact -slant")
BPIN=$(q "set t \$::frameof($WBD); list \$::btnwof(\$t) \$::lookof(\$t)")
# the TEXT-glyph button's box, both schemes: the glyph font is walked
# down to fit and may stop short of the square — the pad must make up
# the difference, or the box rides visibly shorter than its svg
# neighbours (the ✳ under `look compact`, 2026-08-14)
boxh() { q "set t \$::frameof($1); update idletasks
lassign [\$t.title item bbox 1 Cask eBox] x1 y1 x2 y2
expr {\$y2 - \$y1}"; }
ABOX=$(boxh $WAD)
BBOX=$(boxh $WBD)
# ...and the pad arithmetic itself, with contents the fonts at hand
# may never produce (the walked font lands ON g in this environment,
# so the bbox check alone cannot catch a pad that quietly loses a
# pixel): the odd split, the even split, the sub-floor split a midget
# cell needs, and the floor fallback for content that fits not at all
PADS=$(q "list [btn-pad 18 25 3] [btn-pad 19 25 3] [btn-pad 24 25 3] [btn-pad 30 25 3]")
# (1,20) is inside default's 24px corner arm but past compact's 10px
D_EDGE=$(q "set t \$::frameof($WBD); rz-edge \$t 1 20")
D_CORNER=$(q "set t \$::frameof($WBD); rz-edge \$t 1 5")

# --- reload 1: the scheme re-declared thicker — its windows re-frame
cat > "$CONF/tk9wm.tcl" <<'EOF'
wm-look compact {border 5 grips 10 air 0 button-gap 1 font {-size 8 -slant italic}}
wm-style {filter -title узкий*} {look compact}
titlebar-button ask -glyph ✳
EOF
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY"
wait_for 10 extB_is "5, 5, $((CH + 7)), 5"
EB1=$(ext $WB)
EA1=$(ext $WA)

# --- reload 2: the rule is gone — the window falls back to default
cat > "$CONF/tk9wm.tcl" <<'EOF'
wm-look compact {border 5 grips 10 air 0 button-gap 1 font {-size 8 -slant italic}}
titlebar-button ask -glyph ✳
EOF
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY"
wait_for 10 extB_is "6, 6, $DTOP, 6"
EB2=$(ext $WB)
BFONT2=$(q "set t \$::frameof($WBD); \$t.title element cget eTxt -font")
D_EDGE2=$(q "set t \$::frameof($WBD); rz-edge \$t 1 20")

kill $CA $CB 2>/dev/null
sleep 0.5
kill $WM 2>/dev/null
sleep 0.5

echo "--- desk h=$DH top=$DTOP; compact h=$CH top=$CTOP btn=$CBTN border=$CBORD grips=$CGRIPS"
echo "--- boot: обычный «$EA0», узкий «$EB0», eTxt font $BFONT ($BSLANT), pin {$BPIN}"
echo "--- ✳ box height: обычный $ABOX (btn $DBTN), узкий $BBOX (btn $CBTN)"
echo "--- edges on узкий: (1,20)=$D_EDGE (1,5)=$D_CORNER"
echo "--- reload thicker: узкий «$EB1», обычный «$EA1»"
echo "--- reload rule gone: узкий «$EB2», eTxt font $BFONT2, (1,20)=$D_EDGE2"

echo "--- verdict"
if [ "$EA0" = "6, 6, $DTOP, 6" ] && [ "$EB0" = "3, 3, $((CH + 5)), 3" ]; then
    echo "OK: two schemes answer side by side in the extents"
else
    echo "FAIL: extents обычный «$EA0» (want «6, 6, $DTOP, 6»),\
 узкий «$EB0» (want «3, 3, $((CH + 5)), 3»)"
fi
if [ -n "$CH" ] && [ -n "$DH" ] && [ "$CH" -lt "$DH" ]; then
    echo "OK: the smaller italic title makes a shorter strip ($CH < $DH)"
else
    echo "FAIL: compact titleh $CH not below default's $DH"
fi
if [ "$CBTN" = "$((CH - 1))" ]; then
    echo "OK: the button square derives from the scheme's own numbers"
else
    echo "FAIL: compact btn=$CBTN, want $((CH - 1)) (titleh $CH - button-gap 1)"
fi
if [ "$BFONT" = "LookFont-compact" ] && [ "$BSLANT" = "italic" ]; then
    echo "OK: the strip's text is set in the scheme's italic font"
else
    echo "FAIL: eTxt font «$BFONT» (want LookFont-compact), slant «$BSLANT» (want italic)"
fi
if [ "$BPIN" = "$CBTN compact" ]; then
    echo "OK: the frame is pinned to its scheme at its button size"
else
    echo "FAIL: pin «$BPIN», want «$CBTN compact»"
fi
if [ "$ABOX" = "$DBTN" ] && [ "$BBOX" = "$CBTN" ]; then
    echo "OK: the text-glyph button is the same square as its svg neighbours"
else
    echo "FAIL: ✳ box height обычный $ABOX (want $DBTN), узкий $BBOX (want $CBTN)"
fi
if [ "$PADS" = "{3 4} {3 3} {0 1} 3" ]; then
    echo "OK: the pad makes up exactly what the walked font left short"
else
    echo "FAIL: btn-pad said «$PADS», want «{3 4} {3 3} {0 1} 3»"
fi
if [ "$D_EDGE" = "w" ] && [ "$D_CORNER" = "nw" ]; then
    echo "OK: narrow grips hit-test narrow — the arm ends where the scheme says"
else
    echo "FAIL: edges on узкий: (1,20)=$D_EDGE (want w), (1,5)=$D_CORNER (want nw)"
fi
if [ "$EB1" = "5, 5, $((CH + 7)), 5" ] && [ "$EA1" = "$EA0" ]; then
    echo "OK: a re-declared scheme re-frames its windows live, and only its"
else
    echo "FAIL: after thicker reload: узкий «$EB1» (want «5, 5, $((CH + 7)), 5»),\
 обычный «$EA1» (want «$EA0»)"
fi
if [ "$EB2" = "6, 6, $DTOP, 6" ] && [ "$BFONT2" = "TitleFont" ] \
        && [ "$D_EDGE2" = "nw" ]; then
    echo "OK: dropping the rule hands the window back to default whole"
else
    echo "FAIL: after rule-gone reload: узкий «$EB2» (want «6, 6, $DTOP, 6»),\
 eTxt font «$BFONT2» (want TitleFont), (1,20)=$D_EDGE2 (want nw)"
fi
if grep -q 'handler error\|soft failure — settle' "$HERE/wm-decorlooks.log"; then
    echo "FAIL: errors in the WM log:"
    grep 'handler error\|soft failure — settle' "$HERE/wm-decorlooks.log"
else
    echo "OK: no handler or settler errors"
fi
check_invariants "$HERE/wm-decorlooks.log"
