#!/bin/sh
# Regression for the customization layer: it loads after the config
# and wins, the loader names each overlapping knob (and only those),
# custom-write persists canonically and applies live, the layering
# survives a reload — and a FRESH desk (no config) shows the welcome
# note whose "hide forever" writes the first customization.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/custom-config"
mkdir -p "$HERE/custom-config"
cat > "$HERE/custom-config/tk9wm.tcl" <<'EOF'
set-title-font -weight bold
set-edge-resist 3
action dummy {launch {exec true &}}
# `terminal {}` is a WORD (just a terminal), not an erasure: if the
# merge sweep ever eats it again, this action loses its derived match,
# its style errors, and nothing below this line loads — every tail
# assertion then fails loudly (the owner's desk, 2026-08-01)
action anyterm {terminal {} style {place center}}
action second {launch {exec true &} key {<Super>2}}
panel-button dummy
panel-button anyterm
panel-button second
EOF
# ---- THE CUSTOM LAYER IN PIECES (the owner, 2026-08-02) ----
# «эту панель буду хранить у себя в гите»: the main file pulls another
# one in, and what lives there is written back there
cat > "$HERE/custom-config/mine.tcl" <<'EOT'
set-drag-slop 7
EOT
cat > "$HERE/custom-config/tk9wm.custom.tcl" <<EOF
custom-include $HERE/custom-config/mine.tcl
set-title-font -weight normal
EOF

XDG_CONFIG_HOME="$HERE/custom-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-custom.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-custom.log" $WM

q() { printf '%s\n' "$1" > "$HERE/custom-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/custom-config/q.tcl"; }

S0=$(q 'list [font actual TitleFont -weight] $::drag_slop $::edge_resist')
q reload-config >/dev/null
sleep 0.5
S1=$(q 'list [font actual TitleFont -weight] $::drag_slop $::edge_resist')
q 'custom-write {set-fade 0.33}' >/dev/null
sleep 0.5
FADE=$(q 'set ::fade')
KT=$(q 'set t [knob-table]; list [dict get $t set-fade value] [dict get $t set-minimize kind] [dict get $t set-panel-side value] [dict get $t set-title-font group]')

# COLLECTIONS: the name is the primary key — a custom word REFINES
# the config's action instead of adding a second one; owning the set
# (panel-buttons-own) sweeps the panel, the references after it ARE
# the set, and a swept button is simply absent — no remove verb. The
# description lives on the ACTION, so the re-admitted dummy comes
# back whole by its bare name — and the swept second keeps its
# CHORD: the bind rides the action, not the button, and outlives the
# strip. It must all REPLAY the same from the file, with the sweep
# written above the references.
q 'custom-write {action dummy {key {<Super>9}}}' >/dev/null
q 'custom-write {panel-buttons-own default}' >/dev/null
q 'custom-write {panel-button dummy {}}' >/dev/null
q 'custom-write {wm-bind {<Super>7} {list seven}}' >/dev/null
sleep 0.5
collq() { q 'set names {}
          foreach b [panel-cfg default shown] { lappend names [lindex $b 0] }
          list buttons $names                dummylaunch [dict exists [lindex [lindex [panel-cfg default shown] 0] 2] launch]                secondchord [dict exists $::keymap [join [parse-chord {<Super>2}] ,]]                newchord [dict exists $::keymap [join [parse-chord {<Super>9}] ,]]'; }
COLL=$(collq)
q reload-config >/dev/null
sleep 0.5
COLL2=$(collq)
FILEORDER=$(grep -n 'panel-button\|wm-bind\|set-fade\|action ' "$HERE/custom-config/tk9wm.custom.tcl" | tr '
' ' ')

# ---- a word the desk refuses is not written down ----
# It used to be recorded and saved BEFORE it ran, so a refused word
# stayed in the file and stopped the whole layer loading on the next
# start — the owner lost a panel section to one mistyped chord.
# The refused word must stay refused: this one was `super+t r w` until
# modifier names became case-insensitive and both spellings legal —
# which made the bad word GOOD and the assertion a false alarm rather
# than a measurement. A modifier nobody has is the same test with a
# token the parser cannot ever come to like.
BADWRITE=$(q 'catch {custom-write {wm-bind {shmuper+t r w} whatever}} err
    list rc [catch {custom-write {wm-bind {shmuper+t r w} whatever}}] \
         filed [dict exists $::layer_knobs custom {wm-bind shmuper+t r w}] \
         said [string match {*unknown modifier*} $err]')
BADFILE=$(grep -c 'shmuper' "$HERE/custom-config/tk9wm.custom.tcl" 2>/dev/null; true)

# ---- one table says where a word lands ----
# The layers file a word under a key, the save puts the ordered kinds
# out in sections, and both used to be hand-written switches. They
# read the verb registry now, and every verb the layers can record
# has to be in it — a word nobody described would be filed under
# itself and quietly stop overriding anything.
VERBS=$(q 'set bad {}
    foreach v $::knob_vocab {
        if {![dict exists $::verb_registry $v]} { lappend bad $v }
    }
    list missing $bad')
KEYS=$(q 'join [list [knob-key {wm-bind {<Super>9} x}] \
    [knob-key {wm-unbind {<Super>9}}] [knob-key {action Foo {}}] \
    [knob-key {action-remove Foo}] [knob-key {set-fade 0.5}] \
    [knob-key {panel-buttons-own default}]] " | "')
SECTIONS=$(q 'config-ordered-verbs')

# ---- a knob's state is a variable the reset knows ----
# «Reset to saved» on a knob is reload-config, and a reload restores
# only what config_vars names: a knob reading a bare ::variable that
# the list does not carry keeps its previewed value through every
# reload — the owner watched set-emacs-edit-daemon shrug off Reset to
# saved (2026-08-02), three emacs knobs having been born after the
# list was written. The walk finds the NEXT forgotten one.
RESETTABLE=$(q 'set bad {}
    dict for {name meta} [knob-registry] {
        if {[regexp {^\s*set ::(\w+)\s*$} [dict get $meta get] -> v]
                && $v ni $::config_vars} { lappend bad $name }
    }
    list missing $bad')
q 'say-as custom {set-emacs-edit-daemon telega}
   say-as custom {set-emacs-edit create}
   say-as custom {set-emacs-keep-frame-name on}' >/dev/null
q reload-config >/dev/null
sleep 0.5
RESETBACK=$(q 'list daemon $::emacs_edit_daemon \
    edit $::emacs_edit keep $::emacs_keep_frame_name')

# the word that came out of the included file goes BACK to it, and
# the main file keeps the include line and its own words only
INCLUDED=$(q 'list slop $::drag_slop home [dict get $::custom_home set-drag-slop]')
q 'custom-write {set-drag-slop 9}' >/dev/null
sleep 0.5
MINE=$(grep -c 'set-drag-slop 9' "$HERE/custom-config/mine.tcl")
MAINHAS=$(grep -c 'set-drag-slop' "$HERE/custom-config/tk9wm.custom.tcl")
MAININC=$(grep -c 'custom-include' "$HERE/custom-config/tk9wm.custom.tcl")

kill $WM 2>/dev/null
sleep 0.5

echo "--- phase 2: a fresh desk, no config at all"
rm -rf "$HERE/custom-fresh"
mkdir -p "$HERE/custom-fresh"
XDG_CONFIG_HOME="$HERE/custom-fresh" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-fresh.log" 2>&1 &
WM2=$!
wait_wm "$HERE/wm-fresh.log" $WM2
qf() { printf '%s\n' "$1" > "$HERE/custom-fresh/q.tcl"
       "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/custom-fresh/q.tcl"; }
WELCOME=$(qf 'dict exists $::widgets __welcome')
# ...AND THE SET IT OFFERS TO WRITE — «set up the basics», furnishing
# a bare desk in one click. Every word of it goes through the ordinary
# layer, so a key nobody registered would die at apply time and leave
# the desk half furnished. It is also the EXAMPLE a first-time user
# reads afterwards, which is why two of its words are the way they are
# (the owner, 2026-08-06): the terminal button carries a NAME, so its
# match is its own windows and not the any-emulator catch-all (a tmux
# in a plain xterm is not «my shell»), and the tmux button carries a
# title of its own — a terminal left to name its window takes the
# command's first word, and that word is `sh`.
qf 'welcome-preset minimal' >/dev/null
sleep 0.5
PRESET=$(qf 'list type [action-type [dict get $::action_raw terminal]] \
    name [expr {[dict exists $::action_raw terminal terminal name]
                ? [dict get $::action_raw terminal terminal name] : "none"}] \
    title [expr {[dict exists $::action_raw tmux terminal title]
                 ? [dict get $::action_raw tmux terminal title] : "none"}] \
    actions [expr {[dict exists $::action_raw terminal]
                   && [dict exists $::action_raw emacs]
                   && [dict exists $::action_raw tmux]}]')
PRESETFILE=$(grep -c '^action ' "$HERE/custom-fresh/tk9wm.custom.tcl")
# A PANEL WITH ITS FURNITURE IN IT: the offer is a strip, and a strip
# with nothing on it is not what was offered — so the tray is on and
# the clock rides THAT panel, not the workarea a widget defaults to.
FURNITURE=$(qf 'list tray $::tray_on clock [expr {
    [dict exists $::widgets clock] ? [dict get $::widgets clock -on] : "none"}]')
qf welcome-hide >/dev/null
sleep 0.5
AFTERHIDE=$(qf 'list $::welcome [dict exists $::widgets __welcome]')
kill $WM2 2>/dev/null

echo "--- states: start={$S0} reload={$S1} fade=$FADE welcome=$WELCOME afterhide={$AFTERHIDE}"
echo "--- layer lines:"
grep -aE 'custom|welcome' "$HERE/wm-custom.log" "$HERE/wm-fresh.log" | grep -v widget
echo "--- badwrite={$BADWRITE} in-file=$BADFILE"
echo "--- verbs={$VERBS} sections={$SECTIONS}"
echo "--- resettable={$RESETTABLE} resetback={$RESETBACK}"
echo "--- keys={$KEYS}"
echo "--- included={$INCLUDED} mine=$MINE main=$MAINHAS/$MAININC"
echo "--- verdict"
if [ "$S0" = "normal 7 3" ]; then
    echo "OK: the click wins, the untouched knobs hold (normal 7 3)"
else
    echo "FAIL: start state is {$S0}, want {normal 7 3}"
fi
if [ "$S1" = "normal 7 3" ]; then
    echo "OK: the layering survives a reload"
else
    echo "FAIL: after reload {$S1}"
fi
N=$(grep -c 'custom overrides the config: set-title-font' "$HERE/wm-custom.log")
if [ "$N" -ge 2 ]; then
    echo "OK: the overlap is named, on load and on reload"
else
    echo "FAIL: $N overlap lines for set-title-font"
fi
if grep -q 'overrides the config: set-drag-slop' "$HERE/wm-custom.log"; then
    echo "FAIL: a knob only custom touched was reported as an overlap"
else
    echo "OK: no false overlap for set-drag-slop"
fi
if [ "$FADE" = 0.33 ] && grep -q 'set-fade 0.33' "$HERE/custom-config/tk9wm.custom.tcl"; then
    echo "OK: custom-write applied live and persisted canonically"
else
    echo "FAIL: fade=$FADE, file: $(grep set-fade "$HERE/custom-config/tk9wm.custom.tcl")"
fi
if grep -q 'MACHINE-WRITTEN' "$HERE/custom-config/tk9wm.custom.tcl" \
        && grep -q 'set-title-font -weight normal' "$HERE/custom-config/tk9wm.custom.tcl"; then
    echo "OK: the rewrite kept the header and the standing entries"
else
    echo "FAIL: the rewritten custom file lost its shape"
fi
if [ "$KT" = "0.33 {choice iconify refuse} bottom fonts" ]; then
    echo "OK: knob-table serves kinds, groups and live values"
else
    echo "FAIL: knob-table sample is {$KT}"
fi
if [ "$WELCOME" = 1 ]; then
    echo "OK: a fresh desk lays out the welcome mat"
else
    echo "FAIL: no welcome widget on the fresh desk"
fi
# ...and the first run put the annotated sample where the editing
# will happen — a real file, all comment, changing nothing
if grep -q 'first run — .*tk9wm.tcl written from the sample' "$HERE/wm-fresh.log" \
        && [ -s "$HERE/custom-fresh/tk9wm.tcl" ] \
        && ! grep -qv '^#\|^$' "$HERE/custom-fresh/tk9wm.tcl"; then
    echo "OK: the first run materialized the sample config, and it is a no-op"
else
    echo "FAIL: no materialized sample on the fresh desk"
fi
if [ "$PRESET" = "type terminal name terminal title tmux actions 1" ] \
        && [ "$PRESETFILE" = 3 ]; then
    echo "OK: the starter set applied whole — a named terminal, a titled tmux"
else
    echo "FAIL: the starter set: {$PRESET}, action lines written: $PRESETFILE"
fi
if [ "$FURNITURE" = "tray 1 clock {panel default}" ]; then
    echo "OK: the offered panel comes furnished — tray and clock, in the strip"
else
    echo "FAIL: the starter set's furniture is {$FURNITURE}"
fi
if [ "$AFTERHIDE" = "off 0" ] \
        && grep -q 'set-welcome off' "$HERE/custom-fresh/tk9wm.custom.tcl"; then
    echo "OK: hide-forever wrote the first customization and took the mat away"
else
    echo "FAIL: after hide {$AFTERHIDE}, file: $(cat "$HERE/custom-fresh/tk9wm.custom.tcl" 2>/dev/null | tail -1)"
fi
echo "--- collections: $COLL"
echo "--- after reload: $COLL2"
echo "--- file: $FILEORDER"
WANTCOLL="buttons dummy dummylaunch 1 secondchord 1 newchord 1"
case $COLL in
    "$WANTCOLL")
        echo "OK: the owned set holds one button; the swept second keeps its chord — binds ride actions" ;;
    *) echo "FAIL: collections: $COLL" ;;
esac
case $COLL2 in
    "$WANTCOLL")
        echo "OK: the owned set replays the same from the file" ;;
    *) echo "FAIL: collections after reload: $COLL2" ;;
esac
case $FILEORDER in
    *"action dummy"*set-fade*wm-bind*"panel-buttons-own default"*"panel-button dummy"*)
        echo "OK: knobs, actions and binds sorted; the owned set one section, sweep first" ;;
    *) echo "FAIL: file layout: $FILEORDER" ;;
esac
check_invariants "$HERE/wm-custom.log"
check_invariants "$HERE/wm-fresh.log"

if [ "$VERBS" = "missing {}" ]; then
    echo "OK: every verb the layers record is described in one table"
else
    echo "FAIL: verbs: $VERBS"
fi
if [ "$KEYS" = "wm-bind <Super>9 | wm-bind <Super>9 | action Foo | action Foo\
 | set-fade | panel-buttons-own default" ]; then
    echo "OK: a word and its denial file under the same key, from that table"
else
    echo "FAIL: keys: $KEYS"
fi
if [ "$SECTIONS" = "wm-font wm-widget panel-buttons-own panel-button" ]; then
    echo "OK: the ordered sections come from the table, in its own order"
else
    echo "FAIL: sections: $SECTIONS"
fi
if [ "$RESETTABLE" = "missing {}" ]; then
    echo "OK: every bare-variable knob is a variable the reset knows"
else
    echo "FAIL: knobs a reload cannot restore: $RESETTABLE"
fi
if [ "$RESETBACK" = "daemon {} edit reuse keep off" ]; then
    echo "OK: previewed emacs knobs go back to their defaults on reload"
else
    echo "FAIL: after reload: $RESETBACK"
fi

if [ "$BADWRITE" = "rc 1 filed 0 said 1" ] && [ "$BADFILE" = 0 ]; then
    echo "OK: a refused word is neither filed nor written to the layer"
else
    echo "FAIL: bad write: {$BADWRITE}, lines in file: $BADFILE"
fi

case "$INCLUDED" in
    "slop 7 home "*"/mine.tcl")
        echo "OK: an included file's word is in force and knows which file it is in" ;;
    *) echo "FAIL: the include: $INCLUDED" ;;
esac
if [ "$MINE" = 1 ] && [ "$MAINHAS" = 0 ] && [ "$MAININC" = 1 ]; then
    echo "OK: a setting lands back in the file that defines it, include line kept"
else
    echo "FAIL: write-back: mine=$MINE main-has=$MAINHAS include=$MAININC"
fi
