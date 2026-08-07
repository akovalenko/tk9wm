#!/bin/sh
# Regression for THE THEME — «I want a light theme» in one word (the
# owner, 2026-08-02), and the shape it borrowed from the fonts: the
# theme is the source, a colour knob is an override, and a row says
# which of the two it is looking at.
#
# What is measured, all of it off the SCREEN except the last:
#
#  - one word repaints the desk: the strip and the desktop behind it
#    both change, and change BACK, with nothing else edited;
#  - the band's inner face wears the 1px `curb` hairline in BOTH
#    themes — the line that keeps the strip from fusing with a client
#    of its own lightness — and exactly one pixel of it: the row
#    below is ground again;
#  - an OVERRIDE outranks the theme and only where it was spoken — a
#    desk colour of one's own stands while the strip beside it still
#    follows the theme, which is the whole claim of "overridden whole
#    or inherited, no third thing";
#  - and the configurator's half: an unsaid colour answers what it is
#    WORKED OUT to be (the `derived` field the terminal knob already
#    had), a said one answers the word that was said.
. "$(dirname "$0")/common.sh"
start_xvfb 900x500x24
CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT

LOG="$HERE/wm-theme.log"
conf() { cat > "$CONF/tk9wm.tcl"; }
reload() {
    "$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY" >/dev/null 2>&1
    sleep 1.5
}
pix() {
    import -window root png:- 2>/dev/null | convert png:- -format \
        "%[pixel:p{$1,$2}]" info:-
}
# The bare right end of the strip — past the one button, and no tray to
# share it with — and the middle of the desktop, where nothing sits.
strip() { pix 800 480; }
desk()  { pix 450 200; }
ask() {
    printf '%s\n' "$1" > "$CONF/ask.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/ask.tcl" 2>&1
}

conf <<'EOF'
set-welcome off
set-theme light
action терминал { launch {exec xterm &} }
panel-button терминал
EOF
sleep 1
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 2.5
LSTRIP=$(strip); LDESK=$(desk)
# The inner face of the bottom band: its topmost pixel row, found from
# the strip's own thickness — and the row below it, which must be the
# strip's ground again (a hairline, not a flood).
THICK=$(ask 'panel-thickness default')
LFACE=$(pix 800 $((500 - THICK))); LUNDER=$(pix 800 $((500 - THICK + 1)))
LSAID=$(ask 'dict get [knob-table] set-desk-background')
import -display "$DISPLAY" -window root "$HERE/theme-light.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/theme-light.png"

conf <<'EOF'
set-welcome off
set-theme dark
action терминал { launch {exec xterm &} }
panel-button терминал
EOF
reload
DSTRIP=$(strip); DDESK=$(desk)
DFACE=$(pix 800 $((500 - THICK))); DUNDER=$(pix 800 $((500 - THICK + 1)))
import -display "$DISPLAY" -window root "$HERE/theme-dark.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/theme-dark.png"

# The override: a desk colour of one's own under the light theme.
conf <<'EOF'
set-welcome off
set-theme light
set-desk-background #4e9a06
action терминал { launch {exec xterm &} }
panel-button терминал
EOF
reload
OSTRIP=$(strip); ODESK=$(desk)
OSAID=$(ask 'dict get [knob-table] set-desk-background')

# --- THE SWITCH ON THE WELCOME MAT (the owner, 2026-08-02). One click
#     turns the whole desk, and it STICKS: the mat writes a
#     customization like every other link on it, so the choice
#     survives a restart instead of merely happening. Driven through
#     the proc the link is bound to — the click itself is the mat
#     widget's business and run-widget-test's.
MATWAS=$(ask 'set ::theme')
ask 'welcome-theme-flip' >/dev/null
sleep 1
MATNOW=$(ask 'set ::theme')
MATSAID=$(ask 'expr {[dict exists $::layer_knobs custom set-theme]
                     ? [dict get $::layer_knobs custom set-theme] : "nothing"}')
# HALF-APPLIED, NEVER: the derived variables (the live face, the
# outline, the modal amber) move in the same breath as the word —
# asked INSIDE one script, with no idle tick in between, so a rebuild
# already queued can never read the new theme's raised behind the old
# theme's live (the owner's report, 2026-08-04). Both flips checked,
# both inside the one callback.
MIX=$(ask 'set-theme dark
    set a [expr {$::panel_live_face eq [themed live]
                 && $::OUTLINE eq [themed edge]}]
    set-theme light
    set b [expr {$::panel_live_face eq [themed live]
                 && $::KBMR_BG eq [themed modal]}]
    list $a $b')
kill $WM 2>/dev/null

echo "--- light: strip $LSTRIP desk $LDESK"
echo "--- dark:  strip $DSTRIP desk $DDESK"
echo "--- light + an override: strip $OSTRIP desk $ODESK"
echo "--- the knob, unsaid: $LSAID"
echo "--- ...and said:      $OSAID"

echo "--- verdict"
FAIL=0
want() {
    if [ "$2" = "$3" ]; then
        echo "OK: $1 ($2)"
    else
        echo "FAIL: $1 — got $2, wanted $3"; FAIL=1
    fi
}
want "one word and the strip is light"        "$LSTRIP" "srgb(242,241,239)"
want "...and the desktop behind it too"       "$LDESK"  "srgb(211,215,207)"
want "the light band's inner face wears the curb hairline" \
    "$LFACE"  "srgb(46,52,54)"
want "...exactly one pixel of it — below is ground again" \
    "$LUNDER" "srgb(242,241,239)"
want "...and the dark band steps AWAY from its own ground too" \
    "$DFACE"  "srgb(136,138,133)"
want "...one pixel likewise — below is the dark ground" \
    "$DUNDER" "srgb(46,52,54)"
want "the other word takes the strip back"    "$DSTRIP" "srgb(46,52,54)"
want "...and the desktop with it"             "$DDESK"  "srgb(20,24,27)"
want "an override stands where it was spoken" "$ODESK"  "srgb(78,154,6)"
want "...and NOWHERE else — the strip beside it still follows the theme" \
    "$OSTRIP" "srgb(242,241,239)"
# The configurator's half, asked of the live desk rather than drawn.
case "$LSAID" in
    *"value {}"*) echo "OK: nobody said a desk colour, so the knob says nothing" ;;
    *) echo "FAIL: the unsaid knob claims a value: $LSAID"; FAIL=1 ;;
esac
case "$LSAID" in
    *"derived #d3d7cf"*)
        echo "OK: ...and answers what it is WORKED OUT to be, from the theme" ;;
    *) echo "FAIL: the unsaid knob offers no derived answer: $LSAID"; FAIL=1 ;;
esac
case "$OSAID" in
    *"value #4e9a06"*)
        echo "OK: a said colour answers the word that was said" ;;
    *) echo "FAIL: the said knob does not report it: $OSAID"; FAIL=1 ;;
esac
case "$MIX" in
    "1 1") echo "OK: the derived colours move in the same breath as the word" ;;
    *) echo "FAIL: the word and its derived colours came apart: $MIX"; FAIL=1 ;;
esac
echo "--- the mat's switch: $MATWAS -> $MATNOW, custom says: $MATSAID"
if [ "$MATWAS" = light ] && [ "$MATNOW" = dark ]; then
    echo "OK: the mat's switch turns the desk to the other theme"
else
    echo "FAIL: the mat's switch went $MATWAS -> $MATNOW"; FAIL=1
fi
case "$MATSAID" in
    "set-theme dark")
        echo "OK: ...and writes it down, so the choice survives a restart" ;;
    *) echo "FAIL: the custom layer says «$MATSAID»"; FAIL=1 ;;
esac
if grep -qE 'build failed|handler error|no such colour role' "$LOG"; then
    echo "FAIL: errors in the log:"
    grep -E 'build failed|handler error|no such colour role' "$LOG"
    FAIL=1
fi
check_invariants "$LOG"
exit $FAIL
