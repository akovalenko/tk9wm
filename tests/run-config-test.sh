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
. "$(dirname "$0")/common.sh"
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
    XDG_CONFIG_HOME="$CONF/$1" "$LINUX/whale" "$WMTCL" \
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
GEOM_B=$GEOM

# --- does the style SURVIVE? The owner's report (2026-07-30) was that
# his `wm-style always {increments ignore}` had come off his windows,
# and he could not tell whether a config reload had done it or an
# earlier restart of the window manager. So the same drag is repeated
# after each — nothing is changed in between, and the answer is the
# geometry.
#
# The drag is on the RIGHT edge, so each one grows the client by 37 and
# the expectation grows with it: 337, then 374, then 411 if the ignore
# holds; anything snapped to a multiple of 10 is the ignore lost.
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" :76 >/dev/null 2>&1
sleep 1.2
FX=$(xwininfo -id "$AID" | awk '/Absolute upper-left X/ {print $NF - 6}')
FY=$(xwininfo -id "$AID" | awk '/Absolute upper-left Y/ {print $NF - 34}')
drag $((FX + 346)) $((FY + 120)) $((FX + 383)) $((FY + 120))
GEOM_RELOAD=$(xwininfo -id "$AID" \
    | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')

# ...and the restart, which is the one he suspected: the clients are
# released, the process execs itself, and the survivors are ADOPTED by
# a fresh instance. If adoption ran before the config were read, or
# past it, this is where the ignore would go.
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" :76 >/dev/null 2>&1
sleep 2.5
FX=$(xwininfo -id "$AID" | awk '/Absolute upper-left X/ {print $NF - 6}')
FY=$(xwininfo -id "$AID" | awk '/Absolute upper-left Y/ {print $NF - 34}')
drag $((FX + 383)) $((FY + 120)) $((FX + 420)) $((FY + 120))
GEOM_RESTART=$(xwininfo -id "$AID" \
    | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')
kill $WM $CL 2>/dev/null

# --- a bad value is a problem, not a dead config -------------------
# The kind is the check now, on BOTH inputs (lifecycle plan, step 2):
# what the configurator refuses when typed, the desk refuses when
# written — and refusing one word must not cost the rest of the file.
# The last line is the proof: it is applied even though four words
# above it were rejected.
BADCONF=$(mktemp -d)
cat > "$BADCONF/tk9wm.tcl" <<'EOF'
set-edge-resist двенадцать
set-workarea-follow куда-нибудь
set-desk-background "не цвет"
set-fade 7
set-icon-path {/nowhere/at/all /usr/share/icons}
set-title-justify center
EOF
BADLOG="$HERE/wm-config-bad.log"
XDG_CONFIG_HOME="$BADCONF" "$LINUX/whale" "$WMTCL" > "$BADLOG" 2>&1 &
BADWM=$!
sleep 2
BADSTATE=$("$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl /dev/stdin <<'EOF'
list just $::titlejust resist $::edge_resist follow $::workarea_follow \
     fade $::fade path [llength $::icon_path]
EOF
)
kill $BADWM 2>/dev/null
rm -rf "$BADCONF"
REFUSED=$(grep -ac 'PROBLEM config word' "$BADLOG")
KEPTPATH=$(grep -ac 'kept anyway, like PATH' "$BADLOG")
echo "--- bad config: $REFUSED refusals, path note $KEPTPATH, state: $BADSTATE"

echo "--- verdict"
if [ "$REFUSED" = 4 ]; then
    echo "OK: four bad values were refused one by one"
else
    echo "FAIL: $REFUSED refusals in the bad config, want 4"; FAIL=1
fi
case "$BADSTATE" in
    *"just center"*) echo "OK: ...and the line after them still applied" ;;
    *) echo "FAIL: the config died on a bad word: «$BADSTATE»"; FAIL=1 ;;
esac
case "$BADSTATE" in
    *"resist 12"*"follow stick"*"fade 0.8"*)
        echo "OK: ...while the refused values kept their defaults" ;;
    *) echo "FAIL: a refused value got through: «$BADSTATE»"; FAIL=1 ;;
esac
if [ "$KEPTPATH" -ge 1 ]; then
    echo "OK: a missing icon directory is a note, and the path keeps it (PATH semantics)"
else
    echo "FAIL: the missing directory was not reported as kept"; FAIL=1
fi
case "$BADSTATE" in
    *"path 2"*) echo "OK: ...both components are still in the path" ;;
    *) echo "FAIL: the path was shortened behind the config's back"; FAIL=1 ;;
esac
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
if [ "$GEOM_RELOAD" = "374x200" ]; then
    echo "OK: ...and it survives a config RELOAD ($GEOM_RELOAD, still raw)"
else
    echo "FAIL: after a reload the drag landed $GEOM_RELOAD, want 374x200"
fi
if [ "$GEOM_RESTART" = "411x200" ]; then
    echo "OK: ...and a RESTART, adoption and all ($GEOM_RESTART, still raw)"
else
    echo "FAIL: after a restart the drag landed $GEOM_RESTART, want 411x200"
fi
