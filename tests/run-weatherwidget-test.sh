#!/bin/sh
# Regression for the WEATHER widget: a command source speaking
# Open-Meteo's JSON drives the strip (temperature, the sky's glyph,
# the place's word), the forecast sheet opens and closes like the
# calendar and holds seven days, a dead source leaves the OLD reading
# standing in a dimmer ink, and the transport ladder's low rungs —
# bare core-http and curl — are walked for real against a localhost
# httpd, geocoding included. No sky is consulted: every answer is
# canned here.
. "$(dirname "$0")/common.sh"
start_xvfb 900x500x24
CONF=$(mktemp -d)
HTTPD=""
trap 'stop_xservers; [ -n "$HTTPD" ] && kill $HTTPD 2>/dev/null; rm -rf "$CONF"' EXIT

# ---- the sky, canned: Open-Meteo's own shape ----
WX="$CONF/wx.json"
cat > "$WX" <<'EOF'
{"latitude":41.69,"longitude":44.8,"utc_offset_seconds":14400,
 "current":{"time":"2026-08-11T12:00","temperature_2m":20.6,
            "weather_code":2,"is_day":1},
 "daily":{"time":["2026-08-11","2026-08-12","2026-08-13","2026-08-14",
                  "2026-08-15","2026-08-16","2026-08-17"],
          "weather_code":[80,80,3,2,61,0,95],
          "temperature_2m_max":[24.8,17.4,15.7,18.4,17.9,21.0,19.2],
          "temperature_2m_min":[15.5,13.5,11.0,8.6,11.6,12.2,13.0],
          "precipitation_probability_max":[73,65,64,3,20,0,88]}}
EOF
# ...spoken by a script, so it can die and recover on cue
WXCMD="$CONF/wx.sh"
printf '#!/bin/sh\ncat %s\n' "$WX" > "$WXCMD"
chmod +x "$WXCMD"

cat > "$CONF/tk9wm.tcl" <<EOF
set-welcome off
action терминал { launch {exec xterm &} }
panel-button терминал
wm-widget wx -type weather -on {panel default} \
    -source [list command [list sh $WXCMD]] -label T -every 400
EOF

LOG="$HERE/wm-weatherwidget.log"
export NO_PROXY=127.0.0.1 no_proxy=127.0.0.1
XDG_CONFIG_HOME="$CONF" "$WHALE" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM
sleep 2

q() { printf '%s\n' "$1" > "$CONF/q.tcl"
      "$WHALE" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl"; }

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

# ---- the canned sky lands over the first poll ----
FIRST=$(q "$PROBE"'
    set c $::widget_win(wx)
    set src [dict get [widget-opts wx] -source]
    list temp [$c.temp cget -text] label [$c.label cget -text] \
        ink [has-color weather-icon:$c.icon [themed ink]] \
        days [llength [dict get $::weather_state($src) days]] \
        stale [dict get $::weather_state($src) stale]')

# ---- the sheet: open by the widget, seven days, close by the sheet ----
area()   { sed -n 's/^WM: widget area \([0-9x+]*\) .*/\1/p' "$LOG" | tail -1; }
sheet()  { sed -n 's/^WM: weather sheet open \([0-9x+]*\) .*/\1/p' "$LOG" | tail -1; }
opens()  { grep -c '^WM: weather sheet open '  "$LOG"; }
closes() { grep -c '^WM: weather sheet closed' "$LOG"; }
click() {   # click WxH+X+Y — one press on the middle of that rectangle
    set -- $(echo "$1" | sed 's/[x+]/ /g')
    xdotool mousemove $(($3 + $1 / 2)) $(($4 + $2 / 2)) click 1
    sleep 1
}
click "$(area)"
DAYS=$(sed -n 's/^WM: weather sheet open [0-9x+]* (\(.*\) days)$/\1/p' "$LOG" | tail -1)
import -display "$DISPLAY" -window root "$HERE/weather-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/weather-test.png"
click "$(area)"
TOGGLED="$(opens) $(closes)"
click "$(area)"
click "$(sheet)"
DISMISSED="$(opens) $(closes)"

# ---- a colder sky, by night, snowing ----
cat > "$WX" <<'EOF'
{"current":{"temperature_2m":-3.4,"weather_code":71,"is_day":0},
 "daily":{"time":["2026-08-11","2026-08-12"],"weather_code":[71,3],
          "temperature_2m_max":[-1.0,0.5],"temperature_2m_min":[-6.2,-2.0],
          "precipitation_probability_max":[40,10]}}
EOF
sleep 1.5
COLD=$(q 'set c $::widget_win(wx)
    set src [dict get [widget-opts wx] -source]
    list temp [$c.temp cget -text] \
        code [dict get $::weather_state($src) code] \
        days [llength [dict get $::weather_state($src) days]]')

# ---- the source dies: the OLD reading stands, in the dim ink ----
printf '#!/bin/sh\nexit 1\n' > "$WXCMD"
sleep 1.5
DEAD=$(q "$PROBE"'
    set c $::widget_win(wx)
    set src [dict get [widget-opts wx] -source]
    list temp [$c.temp cget -text] \
        dim [has-color weather-icon:$c.icon [themed dim]] \
        stale [dict get $::weather_state($src) stale]')

# ---- ...and the first good answer takes it back ----
printf '#!/bin/sh\nprintf %%s '\''{"current":{"temperature_2m":25.0,"weather_code":0,"is_day":1},"daily":{"time":["2026-08-11"],"weather_code":[0],"temperature_2m_max":[26],"temperature_2m_min":[14],"precipitation_probability_max":[0]}}'\''\n' > "$WXCMD"
sleep 1.5
BACK=$(q 'set c $::widget_win(wx)
    list temp [$c.temp cget -text]')

# ---- the low rungs of the ladder, against a localhost sky ----
PORT=18973
cat > "$CONF/geo.json" <<'EOF'
{"results":[{"name":"Тбилиси","latitude":41.69,"longitude":44.83}]}
EOF
cat > "$CONF/wx2.json" <<'EOF'
{"current":{"temperature_2m":30.1,"weather_code":1,"is_day":1},
 "daily":{"time":["2026-08-11","2026-08-12"],"weather_code":[1,2],
          "temperature_2m_max":[32.0,31.0],"temperature_2m_min":[21.0,20.5],
          "precipitation_probability_max":[0,5]}}
EOF
cat > "$CONF/wx-httpd.tcl" <<'EOF'
lassign $argv port dir
proc serve {ch args} { fileevent $ch readable [list answer $ch] }
proc answer {ch} {
    if {[catch {gets $ch req}] || $req eq ""} { catch {close $ch}; return }
    while {[gets $ch h] > 0} {}
    set f [expr {[string match *search* $req] ? "geo.json" : "wx2.json"}]
    set b [open [file join $::dir $f] rb]
    set body [read $b]
    close $b
    fconfigure $ch -translation binary
    puts -nonewline $ch "HTTP/1.0 200 OK\r\nContent-Type: application/json;\
 charset=utf-8\r\nContent-Length: [string length $body]\r\n\r\n$body"
    close $ch
}
socket -server serve $port
vwait forever
EOF
"$WHALE_CLI" "$CONF/wx-httpd.tcl" $PORT "$CONF" &
HTTPD=$!
sleep 1

# bare core-http, geocoding a Cyrillic name on the way
q "set ::weather_via http
   set ::weather_sky http://127.0.0.1:$PORT
   wm-widget sky -type weather -on {panel default} \
       -source {name Тбилиси} -every 400" >/dev/null
sleep 2
HTTPRUNG=$(q 'set c $::widget_win(sky)
    list temp [$c.temp cget -text] \
        geo [expr {[info exists ::weather_geo(Тбилиси)]
                   ? $::weather_geo(Тбилиси) : "unresolved"}]')
GEOSAID=$(grep -c 'WM: weather: «Тбилиси» is Тбилиси' "$LOG")

# ...and curl, coordinates as they stand
q "set ::weather_via curl
   wm-widget curled -type weather -on {panel default} \
       -source {latlon 41.69 44.8} -every 400" >/dev/null
sleep 2
CURLRUNG=$(q 'set c $::widget_win(curled)
    list temp [$c.temp cget -text]')

kill $WM 2>/dev/null

echo "--- first: $FIRST"
echo "--- sheet days: $DAYS  toggled: $TOGGLED  dismissed: $DISMISSED"
echo "--- cold: $COLD"
echo "--- dead: $DEAD  back: $BACK"
echo "--- http rung: $HTTPRUNG  geocoded: $GEOSAID"
echo "--- curl rung: $CURLRUNG"
echo "--- verdict"
FAIL=0
case "$FIRST" in
    "temp +21° label T ink 1 days 7 stale 0")
        echo "OK: the canned sky lands — +21°, the word, the glyph, seven days" ;;
    *) echo "FAIL: first reading: $FIRST"; FAIL=1 ;;
esac
case "$DAYS" in
    7) echo "OK: the sheet holds seven days" ;;
    *) echo "FAIL: the sheet says «$DAYS» days"; FAIL=1 ;;
esac
case "$TOGGLED" in
    "1 1") echo "OK: the widget's click is a toggle" ;;
    *) echo "FAIL: toggle counts open/close = $TOGGLED"; FAIL=1 ;;
esac
case "$DISMISSED" in
    "2 2") echo "OK: a click on the sheet dismisses it" ;;
    *) echo "FAIL: dismissal counts open/close = $DISMISSED"; FAIL=1 ;;
esac
case "$COLD" in
    "temp -3° code 71 days 2")
        echo "OK: the next poll turns the sky — -3°, snow, two days" ;;
    *) echo "FAIL: cold reading: $COLD"; FAIL=1 ;;
esac
case "$DEAD" in
    "temp -3° dim 1 stale 1")
        echo "OK: a dead source leaves the old reading standing, dimmed" ;;
    *) echo "FAIL: stale face: $DEAD"; FAIL=1 ;;
esac
case "$BACK" in
    "temp +25°")
        echo "OK: the first good answer takes the stale face back" ;;
    *) echo "FAIL: recovery: $BACK"; FAIL=1 ;;
esac
case "$HTTPRUNG" in
    "temp +30° geo {41.69 44.83}")
        echo "OK: bare core-http walks — Cyrillic name geocoded, sky read" ;;
    *) echo "FAIL: http rung: $HTTPRUNG"; FAIL=1 ;;
esac
case "$GEOSAID" in
    0) echo "FAIL: the gazetteer's answer was never said"; FAIL=1 ;;
    *) echo "OK: the gazetteer's answer is said in the log" ;;
esac
case "$CURLRUNG" in
    "temp +30°")
        echo "OK: the curl rung walks the same road" ;;
    *) echo "FAIL: curl rung: $CURLRUNG"; FAIL=1 ;;
esac
if grep -qE 'build failed|tick failed|handler error|errand .* FAILED' "$LOG"; then
    echo "FAIL: errors in the log:"
    grep -E 'build failed|tick failed|handler error|errand .* FAILED' "$LOG"
    FAIL=1
fi
check_invariants "$LOG"
exit $FAIL
