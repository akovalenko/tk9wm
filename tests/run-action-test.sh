#!/bin/sh
# Regression for the ACTION registry (the actions-first turn): a
# named deed binds its chord by name, panel or no panel; the name is
# the primary key and a second declaration refines; `run` is raw argv
# through the one door (Run), and a terminal word answers that Run;
# an unmet needs leaves the action waiting — visible, unbound — and
# it comes alive by itself on the reload after the command appears;
# the custom layer refines actions and an erase falls back honestly.
. "$(dirname "$0")/common.sh"
start_xvfb

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
wait_wm "$HERE/wm-action.log" $WM

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
TYPO=$(q 'action clash3 {ruN {true}}')
# the family the configurator draws is the SPEC TABLE, mapped onto
# this tree's editors — one source, and the mapping is the only seam
FIELDS=$(q 'set f [collection-fields actions]
    list run [dict get $f run kind] launch [dict get $f launch kind] \
         key [dict get $f key kind] terminal [dict get $f terminal kind]')
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

# ---- the linter: the same table, softer verdicts (slice 4) ----
# what it remarks on, and what it calls each remark
LINT=$(q 'set out {}
    foreach v [spec-lint action {key {<Nope>q} needs {/no/such/cmd} \
                                 launch {exec true &}}] {
        lappend out [dict get $v key]/[dict get $v level]
    }
    set out')
LINTSYNC=$(q 'set v [lindex [spec-lint action {launch {exec true}}] 0]
    list [dict get $v level] [string match {*holds the desk still*} \
                                  [dict get $v text]]')
# ...and a leading ~ in command words is a literal ~ (dir expands its
# own now): flagged wherever the words are extractable, quiet where
# there is nothing to expand — and quiet on dir itself
TILDE=$(q 'set r {}
    foreach s {{run {vi ~/todo}} {launch {Run tail -f ~/log}} \
               {launch {exec ~/bin/x &}} {run {vi todo}} {dir ~/notes}} {
        set hit 0
        foreach v [spec-lint action $s] {
            if {[string match {*literal ~*} [dict get $v text]]} { set hit 1 }
        }
        lappend r $hit
    }
    set r')
# ...and it says so when the deed is DECLARED — once, not on every
# replay of the same words
q 'action loud {launch {exec true &}}' >/dev/null
sleep 0.3
LOGNOTE=$(grep -c 'action loud: note — this is «Run true» said the long way' \
    "$HERE/wm-action.log")
q 'action loud {icon L}' >/dev/null
sleep 0.3
LOGNOTE2=$(grep -c 'action loud: note — this is «Run true» said the long way' \
    "$HERE/wm-action.log")

# ---- the deed's TYPE is a word, and presence is its sugar ----
# (the owner, 2026-08-02: «у action есть тип, который можно вычислить
# по присутствующим полям, но можно и промоутнуть до отдельного поля»)
TYPEOF=$(q 'list plain [action-type {}] \
    sugar [action-type {terminal {}}] \
    said [action-type {type terminal}] \
    wins [action-type {type emacs terminal {name X}}] \
    both [action-type {emacs {frame F} terminal {}}]')
q 'action typed {type terminal run {htop}}' >/dev/null
sleep 0.3
TYPEDEED=$(q 'list via [lindex [dict get $::action_spec typed runvia] 0] \
    launch [expr {[dict exists $::action_spec typed launch]}] \
    match [expr {[dict exists $::action_spec typed match]}]')
# ...and the old spelling still works and is told the plain one
q 'action longway {terminal {} run {htop}}' >/dev/null
sleep 0.3
LONGWAY=$(q 'set out {}
    foreach v [dict get $::action_lint longway] {
        if {[dict get $v key] eq "terminal"} { lappend out [dict get $v level] }
    }
    list note $out type [action-type [dict get $::action_raw longway]]')

# ---- what an empty value MEANS, and how to say «not there» ----
# (config-tree step 2, the owner's fork answered 2026-08-02: a custom
# word stays a delta, so un-say is permanent and empty-as-a-value has
# to be declared)
EMPTYMEANS=$(q 'list run [node-empty-means {@spec action run}] \
    terminal [node-empty-means {@spec action terminal}] \
    label [node-empty-means {panel @ label}] \
    unknown [node-empty-means {@spec action nosuch}]')
# an empty terminal is a WORD and survives the merge; an empty run is
# the word taken back
q 'action bothways {run {true} terminal {}}
   action bothways {run {}}' >/dev/null
sleep 0.3
EMPTYKEEP=$(q 'list terminal [dict exists $::action_raw bothways terminal] \
    run [dict exists $::action_raw bothways run]')
# ...and the one node where the two meanings collide is KNOWN, so a
# second one cannot be added without the suite noticing
EMPTYCLASH=$(q 'config-empty-clashes')
# «absent, not empty» reaches the child both ways: around a script,
# and in the argv of a launch
ENVUNSET=$(q 'set ::env(TK9WM_PROBE) yes
    with-env {A 1} {set ::probe_seen [info exists ::env(TK9WM_PROBE)]} {TK9WM_PROBE}
    list during $::probe_seen after [info exists ::env(TK9WM_PROBE)]')
ENVARGV=$(q 'env-argv {env {A 1} env-unset {B C}}')

kill $WM 2>/dev/null

echo "--- empty={$EMPTYMEANS} keep={$EMPTYKEEP} clash={$EMPTYCLASH}"
echo "--- envunset={$ENVUNSET} envargv={$ENVARGV}"
echo "--- bound=$BOUND waiting={$WAITING} derived={$DERIVED}"
echo "--- merged={$MERGED} fired=$FIRED custom={$CUSTOMKEY} erased={$ERASED}"
echo "--- alive={$ALIVE} coll={$COLL}"
echo "--- lint={$LINT} sync={$LINTSYNC} logged=$LOGNOTE/$LOGNOTE2"
echo "--- verdict"
if [ "$TYPEOF" = "plain generic sugar terminal said terminal wins emacs both emacs" ]; then
    echo "OK: a deed's type is a word, and the settings below are its sugar"
else
    echo "FAIL: action-type: $TYPEOF"
fi
if [ "$TYPEDEED" = "via spawn-terminal-run launch 1 match 1" ]; then
    echo "OK: the type alone makes a terminal deed, with no settings to say"
else
    echo "FAIL: a typed deed: $TYPEDEED"
fi
if [ "$LONGWAY" = "note note type terminal" ]; then
    echo "OK: the old spelling still works and hears the plain one"
else
    echo "FAIL: the long way round: $LONGWAY"
fi
if [ "$EMPTYMEANS" = "run unsay terminal value label unsay unknown unsay" ]; then
    echo "OK: what an empty value means is the node's own word, not a name in a loop"
else
    echo "FAIL: empty means: $EMPTYMEANS"
fi
if [ "$EMPTYKEEP" = "terminal 1 run 0" ]; then
    echo "OK: an empty terminal is a word and an empty run takes the word back"
else
    echo "FAIL: empty on the merge: $EMPTYKEEP"
fi
if [ "$EMPTYCLASH" = "{@spec action terminal}" ]; then
    echo "OK: the one node whose empty cannot mean both is the known one"
else
    echo "FAIL: empty/absent clashes: $EMPTYCLASH"
fi
if [ "$ENVUNSET" = "during 0 after 1" ] && [ "$ENVARGV" = "-u B -u C A=1" ]; then
    echo "OK: a launch can be told a variable is not there, not merely empty"
else
    echo "FAIL: env-unset: $ENVUNSET argv=$ENVARGV"
fi
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
    *"cannot both be said"*)
        echo "OK: run and launch together are refused, not silently ranked" ;;
    *) echo "FAIL: run+launch said «$BOTH»" ;;
esac
case $TYPO in
    *"unknown action key"*)
        echo "OK: a key nobody registered is a typo, said so at once" ;;
    *) echo "FAIL: the typo said «$TYPO»" ;;
esac
if [ "$FIELDS" = "run list launch text key chord terminal dict" ]; then
    echo "OK: the actions family is the spec table, mapped to editors"
else
    echo "FAIL: fields: $FIELDS"
fi
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
if [ "$TILDE" = "1 1 1 0 0" ]; then
    echo "OK: a ~ in command words is flagged with its repair — dir's own expands"
else
    echo "FAIL: tilde lint: $TILDE"
fi
case "$LINT|$LINTSYNC" in
    "key/warn needs/note launch/note|warn 1")
        echo "OK: the linter remarks on the chord, the command and the long way" ;;
    *) echo "FAIL: lint: «$LINT» sync «$LINTSYNC»" ;;
esac
case "$LOGNOTE|$LOGNOTE2" in
    "1|1") echo "OK: a remark reaches the log at the declaration, and once" ;;
    *) echo "FAIL: log notes: first=$LOGNOTE after a refine=$LOGNOTE2 (want 1|1)" ;;
esac
check_invariants "$HERE/wm-action.log"
