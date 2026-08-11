#!/bin/sh
# Regression for the BATTERY widget — the params showcase: a fake
# sysfs supply read synchronously, a command source polled through
# pipe-run, the stale «no link» face, AC online as bolt or plug, the
# letter that tells two batteries apart, and the -low threshold
# turning the fill red. State is keyed by the source and read off the
# live widget's own labels and photo, no screen pixels needed.
. "$(dirname "$0")/common.sh"
start_xvfb 900x500x24
CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT

# ---- a fake supply tree: a battery and a Mains sibling ----
PS="$CONF/ps"
mkdir -p "$PS/BAT0" "$PS/AC"
echo Battery     > "$PS/BAT0/type"
echo 42          > "$PS/BAT0/capacity"
echo Discharging > "$PS/BAT0/status"
echo Mains       > "$PS/AC/type"
echo 0           > "$PS/AC/online"

# ...and a command source: the phone, played by a shell script
# answering termux-battery-status JSON
BATCMD="$CONF/batstat.sh"
cat > "$BATCMD" <<'EOF'
#!/bin/sh
cat <<'JSON'
{"present": true, "plugged": "UNPLUGGED", "status": "DISCHARGING",
 "percentage": 38, "level": 38, "scale": 100}
JSON
EOF
chmod +x "$BATCMD"

cat > "$CONF/tk9wm.tcl" <<EOF
set-welcome off
action терминал { launch {exec xterm &} }
panel-button терминал
wm-widget бат -type battery -on {panel default} \
    -source [list sys $PS/BAT0] -letter L
wm-widget тел -type battery -on {panel default} \
    -source [list command [list sh $BATCMD]] -letter P -every 400
EOF

LOG="$HERE/wm-batwidget.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM
sleep 2

q() { printf '%s\n' "$1" > "$CONF/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl"; }

# any pixel of the photo wearing exactly this colour?
PROBE='proc has-color {img rgb} {
    set want [lmap v [winfo rgb . $rgb] {expr {$v / 257}}]
    for {set x 0} {$x < [image width $img]} {incr x} {
        for {set y 0} {$y < [image height $img]} {incr y} {
            if {[$img get $x $y] eq $want} { return 1 }
        }
    }
    return 0
}'

# ---- the sysfs battery, read at build ----
SYS=$(q "$PROBE
    set c \$::widget_win(бат)
    list pct [\$c.pct cget -text] letter [\$c.letter cget -text] \
        fill [has-color battery-icon:\$c.icon [themed found]] \
        low [has-color battery-icon:\$c.icon [themed alert]] \
        state \$::battery_state([list sys $PS/BAT0])")

# ---- the phone answers over its own poll ----
PHONE=$(q 'set c $::widget_win(тел)
    list pct [$c.pct cget -text] letter [$c.letter cget -text]')
AREA=$(sed -n 's/^WM: widget area .*(\([0-9]*\): \(.*\))$/\1: \2/p' "$LOG" | tail -1)

# ---- charging: the bolt, and ac online without charge: the plug ----
echo 38       > "$PS/BAT0/capacity"
echo Charging > "$PS/BAT0/status"
echo 1        > "$PS/AC/online"
BOLT=$(q "$PROBE
    widgets-tick-all
    set c \$::widget_win(бат)
    list pct [\$c.pct cget -text] \
        glyph [has-color battery-icon:\$c.icon [themed modal]] \
        state \$::battery_state([list sys $PS/BAT0])")
echo Full > "$PS/BAT0/status"
PLUG=$(q "$PROBE
    widgets-tick-all
    set c \$::widget_win(бат)
    list glyph [has-color battery-icon:\$c.icon [themed modal]] \
        status [dict get \$::battery_state([list sys $PS/BAT0]) status] \
        ac [dict get \$::battery_state([list sys $PS/BAT0]) ac]")

# ---- the -low threshold turns the fill red ----
echo 9           > "$PS/BAT0/capacity"
echo Discharging > "$PS/BAT0/status"
echo 0           > "$PS/AC/online"
LOW=$(q "$PROBE
    widgets-tick-all
    set c \$::widget_win(бат)
    list pct [\$c.pct cget -text] \
        low [has-color battery-icon:\$c.icon [themed alert]] \
        fill [has-color battery-icon:\$c.icon [themed found]]")

# ---- the phone plugs in: JSON says so ----
cat > "$BATCMD" <<'EOF'
#!/bin/sh
cat <<'JSON'
{"present": true, "plugged": "PLUGGED_AC", "status": "CHARGING",
 "percentage": 39, "level": 39, "scale": 100}
JSON
EOF
sleep 1.5
CHARGE=$(q 'set c $::widget_win(тел)
    set src [dict get [widget-opts тел] -source]
    list pct [$c.pct cget -text] state $::battery_state($src)')

# ---- no link: the command dies, the face goes grey and dashed ----
printf '#!/bin/sh\nexit 1\n' > "$BATCMD"
sleep 1.5
DEAD=$(q "$PROBE
    set c \$::widget_win(тел)
    list pct [\$c.pct cget -text] \
        grey [has-color battery-icon:\$c.icon [themed dim]]")

# ---- ...and the first good answer takes it back, a bare percent ----
printf '#!/bin/sh\necho 55\n' > "$BATCMD"
sleep 1.5
BACK=$(q 'set c $::widget_win(тел)
    list pct [$c.pct cget -text]')

kill $WM 2>/dev/null

echo "--- sys: $SYS"
echo "--- phone: $PHONE  area: $AREA"
echo "--- bolt: $BOLT"
echo "--- plug: $PLUG"
echo "--- low: $LOW"
echo "--- charge: $CHARGE  dead: $DEAD  back: $BACK"
echo "--- verdict"
FAIL=0
case "$SYS" in
    "pct 42% letter L fill 1 low 0 state {stale 0 pct 42 status discharging ac 0}")
        echo "OK: the sysfs battery is read at build — percent, letter, green fill" ;;
    *) echo "FAIL: sys battery: $SYS"; FAIL=1 ;;
esac
case "$PHONE" in
    "pct 38% letter P")
        echo "OK: the phone's JSON landed over its own poll" ;;
    *) echo "FAIL: phone: $PHONE"; FAIL=1 ;;
esac
case "$AREA" in
    "2: бат тел")
        echo "OK: two batteries queue in one area, told apart by letter" ;;
    *) echo "FAIL: area holds «$AREA»"; FAIL=1 ;;
esac
case "$BOLT" in
    "pct 38% glyph 1 state {stale 0 pct 38 status charging ac 1}")
        echo "OK: charging wears the bolt" ;;
    *) echo "FAIL: charging: $BOLT"; FAIL=1 ;;
esac
case "$PLUG" in
    "glyph 1 status full ac 1")
        echo "OK: plugged without charge wears the plug" ;;
    *) echo "FAIL: plugged-not-charging: $PLUG"; FAIL=1 ;;
esac
case "$LOW" in
    "pct 9% low 1 fill 0")
        echo "OK: at 9% the fill is the alert red, not the green" ;;
    *) echo "FAIL: low threshold: $LOW"; FAIL=1 ;;
esac
case "$CHARGE" in
    "pct 39% state {stale 0 pct 39 status charging ac 1}")
        echo "OK: the phone's PLUGGED_AC/CHARGING reads as ac+charging" ;;
    *) echo "FAIL: phone charging: $CHARGE"; FAIL=1 ;;
esac
case "$DEAD" in
    "pct — grey 1")
        echo "OK: a dead command is «no link» — grey icon, a dash" ;;
    *) echo "FAIL: no-link face: $DEAD"; FAIL=1 ;;
esac
case "$BACK" in
    "pct 55%")
        echo "OK: the first good answer takes the stale face back — a bare percent counts" ;;
    *) echo "FAIL: recovery: $BACK"; FAIL=1 ;;
esac
if grep -qE 'build failed|tick failed|handler error' "$LOG"; then
    echo "FAIL: errors in the log:"; grep -E 'build failed|tick failed|handler error' "$LOG"
    FAIL=1
fi
check_invariants "$LOG"
exit $FAIL
