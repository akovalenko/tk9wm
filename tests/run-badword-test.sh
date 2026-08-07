#!/bin/sh
# Regression for the guard every config word wears: ONE WORD THAT
# THROWS MUST NOT COST THE REST OF THE FILE.
#
# It used to: the layer was read by `source`, so a word that threw
# ended the file there and everything below it never ran. The owner
# mistyped one chord in the configurator (`super+t r w`, and the desk
# spells its modifiers Super), and his whole panel section — three
# sections further down — silently stopped loading: the strip would
# not reorder and flickered, and nothing in that pointed at the typo
# (2026-08-01).
#
# Now the word is recorded as a problem and the file goes on. What
# must NOT change: a word said through the applet's door still
# throws, because whoever asked for it is standing right there.
#
# The owner's own typo is no longer one — modifier names read
# case-insensitively now (the Alt+f4 rule), so `super+t` simply
# works. The bad word here misspells the modifier itself (`Supr`),
# which no case rule can save; what is being measured is the guard,
# not the spelling.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/badword-config"
mkdir -p "$HERE/badword-config"
cat > "$HERE/badword-config/tk9wm.tcl" <<'EOF'
set-desk-background #001100
action Ok {run {true} icon O}
wm-bind {Supr+t r w} restart-wm
set-fade 0.42
panel-button Ok
EOF

XDG_CONFIG_HOME="$HERE/badword-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-badword.log" 2>&1 &
WM=$!
sleep 2

q() { printf '%s\n' "$1" > "$HERE/badword-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/badword-config/q.tcl"; }

# everything BELOW the bad word is standing
AFTER=$(q 'list fade $::fade buttons [llength [panel-cfg default shown]] \
    bg $::desk_background')
# ...and the word itself is a problem, named and placed
PROB=$(q 'set p ""
    foreach e [problems] {
        if {[string match "config word*" [dict get $e what]]} { set p $e }
    }
    if {$p eq ""} { list none } else {
        list what [dict get $p what] \
             said [string match {*unknown modifier*} [dict get $p text]] \
             where [lmap w [dict get $p where] {file tail $w}]
    }')
GUARDED=$(grep -c 'config vocabulary: [0-9]* words guarded' "$HERE/wm-badword.log")
# the applet's door is NOT the file: a refused word still throws there
DOOR=$(q 'catch {custom-write {wm-bind {Supr+t r w} restart-wm}} e
    list rc [catch {custom-write {wm-bind {Supr+t r w} restart-wm}}] \
         said [string match {*unknown modifier*} $e]')

kill $WM 2>/dev/null
sleep 0.5

echo "--- after={$AFTER}"
echo "--- problem={$PROB} guarded=$GUARDED door={$DOOR}"
echo "--- verdict"
if [ "$AFTER" = "fade 0.42 buttons 1 bg #001100" ]; then
    echo "OK: every word below the bad one took effect"
else
    echo "FAIL: after the bad word: $AFTER"
fi
case $PROB in
    "what {config word wm-bind} said 1 where tk9wm.tcl:3")
        echo "OK: the word that threw is a problem, named and placed at its line" ;;
    *) echo "FAIL: problem: $PROB" ;;
esac
if [ "$GUARDED" -ge 1 ]; then
    echo "OK: the vocabulary said how many words it guarded"
else
    echo "FAIL: no guard line in the log"
fi
if [ "$DOOR" = "rc 1 said 1" ]; then
    echo "OK: the same word through the applet's door still throws"
else
    echo "FAIL: through the door: $DOOR"
fi
check_invariants "$HERE/wm-badword.log"
