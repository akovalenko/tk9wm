#!/bin/sh
# Regression for the configurator: it renders the live knob-table
# (rows exist), an edit PREVIEWS on the desk at once, Save persists
# through custom-write, Revert is the desk's own reload — and the
# welcome mat's font buttons turn the one font everything derives
# from, persistently. The style bridge is asserted by the host
# wearing the desk's DeskFont.
. "$(dirname "$0")/common.sh"
export DISPLAY=:94
rm -f /tmp/.X94-lock /tmp/.X11-unix/X94
Xvfb :94 -screen 0 1024x768x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/cfg-config"
mkdir -p "$HERE/cfg-config"
cat > "$HERE/cfg-config/tk9wm.tcl" <<'EOF'
set-edge-resist 3
panel-button dummy {launch {exec true &}}
EOF

XDG_CONFIG_HOME="$HERE/cfg-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-cfg.log" 2>&1 &
WM=$!
sleep 1.5

q()  { printf '%s\n' "$1" > "$HERE/cfg-config/q.tcl"
       "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/cfg-config/q.tcl"; }
qu() { printf '%s\n' "$1" > "$HERE/cfg-config/qu.tcl"
       "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm-ui "$HERE/cfg-config/qu.tcl"; }

q 'applet configurator' >/dev/null
sleep 3
ROWS=$(qu 'llength [dict keys $::cfg_item]')
HOSTFONT=$(qu 'font actual DeskFont -size')
WMFONT=$(q 'font actual DeskFont -size')
CFGBADGE=$(qu 'cfg-owner set-edge-resist')

qu 'cfg-set set-fade 0.42' >/dev/null
sleep 0.5
PREVIEW=$(q 'set ::fade')
SAVED0=$(grep -c 'set-fade' "$HERE/cfg-config/tk9wm.custom.tcl" 2>/dev/null)
qu 'cfg-save' >/dev/null
sleep 0.5
SAVED1=$(grep -c 'set-fade 0.42' "$HERE/cfg-config/tk9wm.custom.tcl" 2>/dev/null)

qu 'cfg-set set-drag-slop 9' >/dev/null
sleep 0.3
qu 'cfg-revert' >/dev/null
sleep 1
REVERTED=$(q 'set ::drag_slop')

BAD=$(qu 'cfg-set set-fade 7')

# the list kind: summarized in its cell, edited whole in the sub-editor
LISTCELL=$(qu 'cfg-value-text set-icon-path {/a /b}')
qu 'cfg-set set-icon-path {/tmp/one /tmp/two /tmp/three}' >/dev/null
sleep 0.3
LISTLIVE=$(q 'llength $::icon_path')
# navigation survives a refresh: pick a knob deep in the tree, fold a
# group, then Revert
qu 'cfg-select [dict get $::cfg_item set-tray-icon-size]' >/dev/null
qu 'set g [$::cfg_T item id {root child 0}]; $::cfg_T collapse $g; list folded' >/dev/null
qu 'cfg-revert' >/dev/null
sleep 1
KEPT=$(qu 'cfg-name-of [cfg-selected]')
FOLD=$(qu 'expr {[$::cfg_T item state get [$::cfg_T item id {root child 0}] open] ? 0 : 1}')
THEME=$(qu 'ttk::style theme use')
# a derived font is shown AS CONFIGURED — a delta, not the computed font
qu 'cfg-set set-title-font {-weight bold}' >/dev/null
qu 'cfg-save' >/dev/null
sleep 0.5
# a PENDING multi-word value must offer itself back whole to the next
# edit (it used to come back as its last word)
PENDBACK=$(qu 'cfg-set set-title-font {-weight bold}; cfg-cur set-title-font')
# a PARTIAL font spec — one option, no size — must render and apply
PARTIAL=$(qu 'cfg-set set-desk-font {-family {DejaVu Sans}}')
PARTIALCELL=$(qu 'cfg-value-text set-desk-font {-family {DejaVu Sans}}')
PARTIALLIVE=$(q 'font actual DeskFont -family')
FONTCELL=$(qu 'cfg-value-text set-title-font [dict get $::cfg_table set-title-font value]')
FONTOWNER=$(qu 'cfg-owner set-title-font')
FONTLIVE=$(q 'font actual TitleFont -weight')
FONTFAM=$(q 'expr {[font actual TitleFont -family] eq [font actual DeskFont -family]}')
# ...and the customization can be taken back
qu 'cfg-select [dict get $::cfg_item set-title-font]; cfg-erase' >/dev/null
sleep 1
ERASEDOWNER=$(qu 'cfg-owner set-title-font')
ERASEDLIVE=$(q 'font actual TitleFont -weight')
ERASEDFILE=$(grep -c 'set-title-font' "$HERE/cfg-config/tk9wm.custom.tcl" 2>/dev/null)
THEME=$(qu 'ttk::style theme use')
# a refusal must SAY why — and must not throw: an unmatched quote in a
# list-shaped kind, and a place spec the desk itself rejects
BADLIST=$(qu 'cfg-set set-terminal {kitty "unclosed}')
BADLISTMSG=$(qu 'set l [winfo toplevel $::cfg_T].b.note; $l cget -text')
BADCURSOR=$(qu 'cfg-set set-root-cursor no-such-cursor')
BADCURSORMSG=$(qu 'set l [winfo toplevel $::cfg_T].b.note; $l cget -text')
GOODCURSOR=$(qu 'cfg-set set-root-cursor watch')
CURSORLIVE=$(q 'set ::root_cursor')
BADPLACE=$(qu 'cfg-set set-key-echo-place {bla bla bla}')
BADPLACEMSG=$(qu 'set l [winfo toplevel $::cfg_T].b.note; $l cget -text')
GOODMSG=$(qu 'cfg-set set-drag-slop 5; set l [winfo toplevel $::cfg_T].b.note; $l cget -text')
SBFOCUS=$(qu 'set w [winfo toplevel $::cfg_T].sb; $w cget -takefocus')

q 'welcome-font-bump up' >/dev/null
sleep 0.5
BUMPED=$(q 'font actual DeskFont -size')
BUMPFILE=$(grep -c 'set-desk-font -size' "$HERE/cfg-config/tk9wm.custom.tcl" 2>/dev/null)

# the window must SIT INSIDE the workarea: a tall tree used to be
# born with its bottom edge under the panel
GEO=$(q 'set w [lindex [array names ::frameof] 0]
         set t $::frameof($w)
         regexp {^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fw fh fx fy
         lassign [workarea] wax way ww wh
         list [wm geometry $t] wa [workarea] fits \
              [expr {$fx >= $wax && $fy >= $way
                     && $fx + $fw <= $wax + $ww && $fy + $fh <= $way + $wh}]')

kill $WM 2>/dev/null
pkill -f 'ui/host[.]tcl' 2>/dev/null

echo "--- rows=$ROWS hostfont=$HOSTFONT wmfont=$WMFONT badge=$CFGBADGE"
echo "--- preview=$PREVIEW save=$SAVED0->$SAVED1 reverted=$REVERTED bad=$BAD"
echo "--- bumped=$BUMPED bumpfile=$BUMPFILE"
echo "--- verdict"
if [ "${ROWS:-0}" -ge 25 ]; then
    echo "OK: the configurator renders the live registry ($ROWS rows)"
else
    echo "FAIL: rows=$ROWS"
fi
if [ -n "$HOSTFONT" ] && [ "$HOSTFONT" = "$WMFONT" ]; then
    echo "OK: the style bridge carried the desk font to the host"
else
    echo "FAIL: host font $HOSTFONT vs wm font $WMFONT"
fi
if [ "$CFGBADGE" = config ]; then
    echo "OK: the owner column knows set-edge-resist came from the config"
else
    echo "FAIL: owner of set-edge-resist = $CFGBADGE"
fi
if [ "$PREVIEW" = 0.42 ]; then
    echo "OK: an edit previews on the live desk at once"
else
    echo "FAIL: fade after preview = $PREVIEW"
fi
if [ "${SAVED0:-0}" = 0 ] && [ "$SAVED1" = 1 ]; then
    echo "OK: preview did not persist, Save did — through custom-write"
else
    echo "FAIL: custom file set-fade lines: before=$SAVED0 after=$SAVED1"
fi
if [ "$REVERTED" = 4 ]; then
    echo "OK: Revert reloaded the desk's own layers (slop back to default 4)"
else
    echo "FAIL: drag_slop after revert = $REVERTED"
fi
if [ "$BAD" = 0 ]; then
    echo "OK: a value the kind refuses is refused (fade 7)"
else
    echo "FAIL: cfg-set accepted fade 7"
fi
if [ "$BUMPED" = "$((WMFONT + 1))" ] && [ "$BUMPFILE" = 1 ]; then
    echo "OK: the mat's font button turned the desk font and persisted"
else
    echo "FAIL: bumped=$BUMPED (want $((WMFONT + 1))), file lines=$BUMPFILE"
fi
if [ "$LISTCELL" = "[2 directories]" ] && [ "$LISTLIVE" = 3 ]; then
    echo "OK: a list summarizes in its cell and edits whole"
else
    echo "FAIL: list cell «$LISTCELL», live length $LISTLIVE"
fi
if [ "$KEPT" = "set-tray-icon-size" ] && [ "$FOLD" = 1 ]; then
    echo "OK: a refresh kept the selection and the folded group"
else
    echo "FAIL: after refresh selection=$KEPT folded=$FOLD"
fi
case $THEME in
    awdark|awlight) echo "OK: ttk wears the matching aw theme ($THEME)" ;;
    clam) echo "OK: ttk fell back to clam (awthemes absent)" ;;
    *) echo "FAIL: ttk theme is $THEME" ;;
esac
if [ "$SBFOCUS" = 0 ]; then
    echo "OK: the scrollbar is out of the focus cycle"
else
    echo "FAIL: scrollbar takefocus = $SBFOCUS"
fi
case "$BADLIST|$BADLISTMSG" in
    "0|"*unmatched*) echo "OK: an unmatched quote is refused with a sentence, not a stack" ;;
    *) echo "FAIL: bad list gave rc=$BADLIST msg «$BADLISTMSG»" ;;
esac
case "$BADPLACE|$BADPLACEMSG" in
    "0|"*bla*|"0|"*place*|"0|"*keyecho*) echo "OK: the desk's own refusal reaches the status line" ;;
    *) echo "FAIL: bad place gave rc=$BADPLACE msg «$BADPLACEMSG»" ;;
esac
case "$FONTCELL|$FONTOWNER|$FONTLIVE|$FONTFAM" in
    "-weight bold|custom|bold|1")
        echo "OK: a derived font shows its delta, and inherits the family" ;;
    *) echo "FAIL: font cell «$FONTCELL» owner=$FONTOWNER live=$FONTLIVE family-inherited=$FONTFAM" ;;
esac
case "$PARTIAL|$PARTIALCELL|$PARTIALLIVE" in
    "1|-family {DejaVu Sans}|DejaVu Sans")
        echo "OK: a partial font spec renders as itself and applies" ;;
    *) echo "FAIL: partial font: rc=$PARTIAL cell «$PARTIALCELL» live «$PARTIALLIVE»" ;;
esac
if [ "$PENDBACK" = "-weight bold" ]; then
    echo "OK: a pending multi-word value comes back whole"
else
    echo "FAIL: pending value came back as «$PENDBACK»"
fi
case "$ERASEDOWNER|$ERASEDLIVE|$ERASEDFILE" in
    "code|normal|0") echo "OK: Erase took the click back — knob, file and desk" ;;
    *) echo "FAIL: after erase owner=$ERASEDOWNER live=$ERASEDLIVE file lines=$ERASEDFILE" ;;
esac
case "$BADCURSOR|$BADCURSORMSG|$GOODCURSOR|$CURSORLIVE" in
    "0|"*"no cursor named"*"|1|watch")
        echo "OK: a bad cursor name is refused by name, a good one applies" ;;
    *) echo "FAIL: cursor: bad=$BADCURSOR msg «$BADCURSORMSG» good=$GOODCURSOR live=$CURSORLIVE" ;;
esac
case $GOODMSG in
    *"Save makes it stick"*) echo "OK: a good value clears the error line" ;;
    *) echo "FAIL: after a good value the line says «$GOODMSG»" ;;
esac
echo "--- geometry: $GEO"
case $GEO in
    *"fits 1") echo "OK: the applet window sits inside the workarea" ;;
    *) echo "FAIL: window vs workarea: $GEO" ;;
esac
check_invariants "$HERE/wm-cfg.log"
