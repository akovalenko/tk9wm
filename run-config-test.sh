#!/bin/sh
# Regression for the customization layer: config resolution (XDG →
# project default-config), the increments knob on style predicates, and
# the dev-preset knobs (bold font, centered title).
#
# Phase A, no user config: the project default-config is sourced (a
# deliberate no-op), so increments are respected — the gridded client
# (inc 10x10, base 0, natural 300x200) dragged +37 on the right edge
# lands SNAPPED at 330. Phase B, XDG_CONFIG_HOME points at the dev
# preset (ignore increments, bold centered titles): the same drag lands
# RAW at 337; the screenshot shows the restyled titlebar.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:76
rm -f /tmp/.X76-lock /tmp/.X11-unix/X76
Xvfb :76 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
CONF=$(mktemp -d)
trap 'kill $XVFB 2>/dev/null; rm -rf "$CONF"' EXIT
mkdir -p "$CONF/empty" "$CONF/dev"
cat > "$CONF/dev/tk9wm.tcl" <<'EOF'
set-title-font -weight bold
set-title-justify center
wm-style always {increments ignore}
EOF
sleep 1

drag() { xdotool mousemove "$1" "$2" mousedown 1 mousemove "$3" "$4" mouseup 1; sleep 0.4; }

# run one phase: $1 = XDG subdir, $2 = phase tag; leaves GEOM set and
# the WM log at wm-config-$2.log
phase() {
    XDG_CONFIG_HOME="$CONF/$1" "$LINUX/whale" "$HERE/wm.tcl" \
        > "$HERE/wm-config-$2.log" 2>&1 &
    WM=$!
    sleep 1.5
    "$LINUX/whale" "$HERE/client-grid.tcl" "ячейки-$2" \
        > "$HERE/config-client-$2.log" 2>&1 &
    CL=$!
    sleep 1.5
    AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-config-$2.log")
    eval "$(awk '/frame \.f[0-9]+ for/ {
        if (match($0, /\+(-?[0-9]+)\+(-?[0-9]+)$/)) {
            split(substr($0, RSTART + 1), a, "+")
            print "FX=" a[1] "; FY=" a[2]
        }
    }' "$HERE/wm-config-$2.log")"
    echo "--- $2: client $AID frame at +$FX+$FY, dragging right edge +37"
    drag $((FX + 309)) $((FY + 120)) $((FX + 346)) $((FY + 120))
    GEOM=$(xwininfo -id "$AID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')
}

phase empty A
kill $WM $CL 2>/dev/null
sleep 0.5
GEOM_A=$GEOM

phase dev B
import -display :76 -window root "$HERE/config-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/config-test.png"
kill $WM $CL 2>/dev/null
GEOM_B=$GEOM

echo "--- verdict"
if grep -q 'WM: config .*default-config\.tcl$' "$HERE/wm-config-A.log"; then
    echo "OK: phase A fell back to the project default-config"
else
    echo "FAIL: phase A config line: $(grep '^WM: config' "$HERE/wm-config-A.log")"
fi
if [ "$GEOM_A" = "330x200" ]; then
    echo "OK: default respects increments — 337 requested, $GEOM_A snapped"
else
    echo "FAIL: phase A client is $GEOM_A, want 330x200"
fi
if grep -q "WM: config $CONF/dev/tk9wm\.tcl\$" "$HERE/wm-config-B.log"; then
    echo "OK: phase B loaded the user config from XDG_CONFIG_HOME"
else
    echo "FAIL: phase B config line: $(grep '^WM: config' "$HERE/wm-config-B.log")"
fi
if [ "$GEOM_B" = "337x200" ]; then
    echo "OK: styled ignore — the same drag lands raw at $GEOM_B"
else
    echo "FAIL: phase B client is $GEOM_B, want 337x200"
fi
