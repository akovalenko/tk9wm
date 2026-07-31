#!/bin/sh
# Regression for the ACTION registry (the actions-first turn): a
# named deed binds its chord by name, panel or no panel; the name is
# the primary key and a second declaration refines; `run` is raw argv
# through the one door (Run), and a terminal word answers that Run;
# an unmet needs leaves the action waiting — visible, unbound — and
# it comes alive by itself on the reload after the command appears;
# the custom layer refines actions and an erase falls back honestly.
. "$(dirname "$0")/common.sh"
export DISPLAY=:67
rm -f /tmp/.X67-lock /tmp/.X11-unix/X67
Xvfb :67 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/action-config" "$HERE/action-mark"
mkdir -p "$HERE/action-config" "$HERE/action-config/bin"
cat > "$HERE/action-config/tk9wm.tcl" <<EOF
set env(PATH) "$HERE/action-config/bin:\$env(PATH)"
action ed {run {true} key {<Super>F5} icon E}
action w8 {run {true} needs mycmd key {<Super>F6}}
action term1 {terminal {name T1} run {sh -c {sleep 9}}}
action probe {run {touch $HERE/action-mark}}
EOF

XDG_CONFIG_HOME="$HERE/action-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-action.log" 2>&1 &
WM=$!
sleep 1.5

q() { printf '%s\n' "$1" > "$HERE/action-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/action-config/q.tcl"; }

BOUND=$(q 'chord-of {action-fire ed}')
WAITING=$(q 'list state [dict get $::action_spec w8 state] \
                  bound [expr {[chord-of {action-fire w8}] ne ""}]')
# the vocabulary: `run` is sugar for a launch that says Run, the
# terminal word answers that Run by opening a terminal around it, and
# a bare run goes through the same door with nobody to answer it
DERIVED=$(q 'list match [dict get $::action_spec term1 match] \
    launch [dict get $::action_spec term1 launch] \
    via [lindex [dict get $::action_spec term1 runvia] 0] \
    door [lindex [dict get $::action_spec probe launch] 0]')
# ...and the two spellings of the one slot cannot both be said, nor
# can a command hide inside the terminal word any more
BOTH=$(q 'action clash {run {true} launch {Run true}}')
TERMRUN=$(q 'action clash2 {terminal {name X run {true}}}')
# refine by name: a later word merges, the unsaid stand
q 'action ed {icon X}' >/dev/null
MERGED=$(q 'list icon [dict get $::action_raw ed icon] \
                 run [dict get $::action_raw ed run] \
                 key [dict get $::action_raw ed key]')
# fire the launch path — the mark lands through Run
q 'action-fire probe' >/dev/null
sleep 1
FIRED=$(test -f "$HERE/action-mark" && echo mark || echo none)
# an empty value un-says: the chord goes
q 'action ed {key {}}' >/dev/null
UNSAID=$(q 'chord-of {action-fire ed}')
# the custom layer refines an action, and the word survives a reload
q 'custom-write {action ed {key {<Super>F7}}}' >/dev/null
sleep 0.5
q reload-config >/dev/null
sleep 1
CUSTOMKEY=$(q 'list chord [chord-of {action-fire ed}] \
                    owner [knob-owner {action ed}]')
# ...and the erase falls back to the config's word, honestly
q 'custom-erase {action ed}' >/dev/null
sleep 1
ERASED=$(q 'list chord [chord-of {action-fire ed}] \
                 owner [knob-owner {action ed}]')
# the software arrives; the reload notices — auto_execok's cached
# miss must not hide it
printf '#!/bin/sh\nexit 0\n' > "$HERE/action-config/bin/mycmd"
chmod +x "$HERE/action-config/bin/mycmd"
q reload-config >/dev/null
sleep 1
ALIVE=$(q 'list state [dict get $::action_spec w8 state] \
                chord [chord-of {action-fire w8}]')
# the collection view: family, waiting flag, said values
COLL=$(q 'set t [collection-table]
    set w {}
    foreach e [dict get $t actions elements] {
        if {[dict get $e key] eq "w8"} {
            set w [expr {[dict exists $e waiting] ? "waiting" : "alive"}]
        }
    }
    list n [llength [dict get $t actions elements]] w8 $w')

kill $WM 2>/dev/null

echo "--- bound=$BOUND waiting={$WAITING} derived={$DERIVED}"
echo "--- merged={$MERGED} fired=$FIRED custom={$CUSTOMKEY} erased={$ERASED}"
echo "--- alive={$ALIVE} coll={$COLL}"
echo "--- verdict"
if [ "$BOUND" = "Super+F5" ]; then
    echo "OK: an action binds its chord by name, no button anywhere"
else
    echo "FAIL: bound=$BOUND"
fi
if [ "$WAITING" = "state waiting bound 0" ]; then
    echo "OK: an unmet needs leaves the action waiting and unbound"
else
    echo "FAIL: waiting: $WAITING"
fi
case $DERIVED in
    "match {filter -class T1} launch {Run sh -c {sleep 9}} via spawn-terminal-run door Run")
        echo "OK: run desugars to a Run, and the terminal word answers it" ;;
    *) echo "FAIL: derived: $DERIVED" ;;
esac
case $BOTH in
    *"run and launch both said"*)
        echo "OK: run and launch together are refused, not silently ranked" ;;
    *) echo "FAIL: run+launch said «$BOTH»" ;;
esac
case $TERMRUN in
    *"unknown terminal key"*)
        echo "OK: the terminal word carries no command of its own" ;;
    *) echo "FAIL: terminal {run …} said «$TERMRUN»" ;;
esac
if [ "$MERGED" = "icon X run true key <Super>F5" ]; then
    echo "OK: the name is the key — a later word refines, the unsaid stand"
else
    echo "FAIL: merged: $MERGED"
fi
if [ "$FIRED" = mark ]; then
    echo "OK: action-fire launched through Run"
else
    echo "FAIL: no mark after action-fire"
fi
if [ "$UNSAID" = "" ]; then
    echo "OK: an empty value un-says the chord"
else
    echo "FAIL: after un-say the chord reads «$UNSAID»"
fi
if [ "$CUSTOMKEY" = "chord Super+F7 owner custom" ]; then
    echo "OK: the custom refinement survives the replay"
else
    echo "FAIL: custom: $CUSTOMKEY"
fi
if [ "$ERASED" = "chord Super+F5 owner config" ]; then
    echo "OK: the erase falls back to the config's word"
else
    echo "FAIL: erased: $ERASED"
fi
if [ "$ALIVE" = "state active chord Super+F6" ]; then
    echo "OK: the software arrived and the action came alive by itself"
else
    echo "FAIL: alive: $ALIVE"
fi
if [ "$COLL" = "n 4 w8 alive" ]; then
    echo "OK: the actions family serves its elements, waiting told apart"
else
    echo "FAIL: coll: $COLL"
fi
check_invariants "$HERE/wm-action.log"
