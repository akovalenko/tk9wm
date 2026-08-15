#!/bin/sh
# Regression for the LOG knobs: set-log-stamp dresses every one-arg
# puts line in a wall-clock stamp (and only the one-arg form — channel
# writes pass as written), set-log-mute drops a topic's lines
# entirely, and both sit OFF by default so every other suite's ^WM:
# anchor stands exactly as written.
. "$(dirname "$0")/common.sh"
start_xvfb 640x480x24
CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT

cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
EOF

LOG="$HERE/wm-logknobs.log"
XDG_CONFIG_HOME="$CONF" "$WHALE" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM

q() { printf '%s\n' "$1" > "$CONF/q.tcl"
      "$WHALE" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl"; }

FAIL=0
STAMP_RE='^[01][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9]:[0-6][0-9]\.[0-9][0-9][0-9] '

# ---- off by default: the config announced itself naked ----
BARE=$(grep -c '^WM: config /' "$LOG")

# ---- stamp on: a witness line arrives dressed ----
q 'set-log-stamp on'
q 'puts "WM: logknobs witness-stamped"'

# ---- ...and only the one-arg form: a channel write stays naked ----
q 'puts stdout "WM: logknobs witness-channel"'

# ---- stamp off: back to bare ----
q 'set-log-stamp off'
q 'puts "WM: logknobs witness-bare"'

# ---- mute a topic: the line lands nowhere; unmute: it speaks ----
q 'set-log-mute {logknobs}'
q 'puts "WM: logknobs muted-line"'
q 'set-log-mute {}'
q 'puts "WM: logknobs spoken-line"'

sleep 1
STAMPED=$(grep -cE "${STAMP_RE}WM: logknobs witness-stamped\$" "$LOG")
CHAN=$(grep -c '^WM: logknobs witness-channel$' "$LOG")
BAREBACK=$(grep -c '^WM: logknobs witness-bare$' "$LOG")
MUTED=$(grep -c 'logknobs muted-line' "$LOG")
SPOKEN=$(grep -c '^WM: logknobs spoken-line$' "$LOG")

echo "--- bare $BARE stamped $STAMPED chan $CHAN bareback $BAREBACK muted $MUTED spoken $SPOKEN"
echo "--- verdict"
[ "$BARE" -ge 1 ]     && echo "OK: off by default — the config line is naked" \
                      || { echo "FAIL: default not bare ($BARE)"; FAIL=1; }
[ "$STAMPED" -eq 1 ]  && echo "OK: the stamp dresses a one-arg line" \
                      || { echo "FAIL: stamped=$STAMPED"; FAIL=1; }
[ "$CHAN" -eq 1 ]     && echo "OK: a channel write passes as written" \
                      || { echo "FAIL: chan=$CHAN"; FAIL=1; }
[ "$BAREBACK" -eq 1 ] && echo "OK: off restores the naked line" \
                      || { echo "FAIL: bareback=$BAREBACK"; FAIL=1; }
[ "$MUTED" -eq 0 ]    && echo "OK: a muted topic says nothing" \
                      || { echo "FAIL: muted=$MUTED"; FAIL=1; }
[ "$SPOKEN" -eq 1 ]   && echo "OK: unmuted, the topic speaks" \
                      || { echo "FAIL: spoken=$SPOKEN"; FAIL=1; }

check_invariants "$LOG"
exit $FAIL
