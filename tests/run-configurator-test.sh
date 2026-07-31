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
CFGBADGE=$(qu 'expr {"set-edge-resist" in $::cfg_cfgkeys}')

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

q 'welcome-font-bump up' >/dev/null
sleep 0.5
BUMPED=$(q 'font actual DeskFont -size')
BUMPFILE=$(grep -c 'set-desk-font -size' "$HERE/cfg-config/tk9wm.custom.tcl" 2>/dev/null)

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
if [ "$CFGBADGE" = 1 ]; then
    echo "OK: the config-touched badge knows set-edge-resist"
else
    echo "FAIL: cfg badge = $CFGBADGE"
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
check_invariants "$HERE/wm-cfg.log"
