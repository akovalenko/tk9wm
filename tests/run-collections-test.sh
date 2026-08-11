#!/bin/sh
# Regression for the collection registry: collection-table serves the
# configurator every family — buttons, bindings, widgets, key
# bundles — with the values the layers SAID and an owner badge per
# element; a binding buried by a later word is served flagged
# ineffectual (last wins, custom over config); and the whole view
# replays the same after a reload.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/coll-config"
mkdir -p "$HERE/coll-config"
cat > "$HERE/coll-config/tk9wm.tcl" <<'EOF'
action дом {launch {exec true &}}
panel-button дом
wm-bind {<Super>5} {list config-five}
wm-widget часы -type clock
wm-keys chords -prefix {<Super>x}
EOF

XDG_CONFIG_HOME="$HERE/coll-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-coll.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-coll.log" $WM

q() { printf '%s\n' "$1" > "$HERE/coll-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/coll-config/q.tcl"; }

# the custom layer refines the config's action (merge by name), the
# panel reference (label override), and buries the config's Super+5
# under its own word
q 'custom-write {action дом {key {<Super>4}}}' >/dev/null
q 'custom-write {panel-button дом {label Дом}}' >/dev/null
q 'custom-write {wm-bind {<Super>5} {list custom-five}}' >/dev/null
sleep 0.5

tblq() { q 'set t [collection-table]
    set b [lindex [dict get $t panel elements] 0]
    set a {}
    foreach e [dict get $t actions elements] {
        if {[dict get $e key] eq "дом"} {
            set a [list [dict get $e owner] \
                       launch [dict exists [dict get $e values] launch] \
                       key [dict exists [dict get $e values] key]]
        }
    }
    set five {}
    foreach e [dict get $t bindings elements] {
        if {[dict get $e key] eq "Super+5"} {
            lappend five [dict get $e values script] [dict get $e owner] \
                [expr {[dict exists $e ineffectual] ? "dead" : "live"}]
        }
    }
    set w {}
    foreach e [dict get $t widgets elements] {
        if {[dict get $e key] eq "часы"} {
            set w [list [dict get $e values] [dict get $e owner]]
        }
    }
    set kb {}
    foreach e [dict get $t keys elements] {
        if {[dict get $e key] eq "chords"} {
            set kb [list [dict get $e values state] [dict get $e owner] \
                        [dict get [dict get $e values params] prefix]]
        }
    }
    list btn [dict get $b key] [dict get $b owner] \
         label [dict exists [dict get $b values] label] \
         act $a \
         five $five widget $w chords $kb'; }

T1=$(tblq)
q reload-config >/dev/null
sleep 0.5
T2=$(tblq)

# the step-C meta: cards (empty here — the one declared action is on
# the panel), the widget type catalogue, and a bundle member knowing
# its family
META=$(q 'set t [collection-table]
    set ab {}
    foreach e [dict get $t bindings elements] {
        if {[dict get $e key] eq "Alt+Tab"} { set ab [dict get $e bundle] }
    }
    list cards [dict get $t panel cards] \
         types [lsort [dict get $t widgets types]] bundle $ab')

# ---- a type's params ride the element (widget-params plan, step A) --
# The clock's -time-format arrives as the element's OWN field — kind,
# default, and the default as a derived value, never a said one; -every
# stands beside it carrying the type's pace.
PARAMS=$(q 'set t [collection-table]
    set out {}
    foreach e [dict get $t widgets elements] {
        if {[dict get $e key] ne "часы"} continue
        set f [dict get $e fields]
        set out [list kind [dict get $f -time-format kind] \
            def [dict get $f -time-format default] \
            said [dict exists [dict get $e values] -time-format] \
            derived [dict get $e derived -time-format] \
            every [dict get $f -every default]]
    }
    set out')

# ...and the GATE: a word the type does not take is refused by name, a
# value its kind refuses is refused, -every on a type with no heartbeat
# is nobody's word, -band is told and never declared — and none of the
# refused declarations stand.
GATE=$(q 'set r1 [catch {wm-widget типо -type clock -time-fromat %H} e1]
    set r2 [catch {wm-widget типо -type desks -gap мимо} e2]
    set r3 [catch {wm-widget типо -type welcome -every 500} e3]
    set r4 [catch {wm-widget типо -type clock -band vertical} e4]
    list $r1 [string match {*not a word of type*} $e1] \
         $r2 [string match {*whole number*} $e2] \
         $r3 [string match {*not a word of type*} $e3] \
         $r4 [string match {*told by the desk*} $e4] \
         ghost [dict exists $::widgets типо]')

# ...and a param SAID lands in values, wins over the default on the
# read path, and -every paces a declaration of its own
q 'custom-write {wm-widget часы -type clock -time-format %H:%M:%S -every 250}' >/dev/null
sleep 0.5
SAIDP=$(q 'set t [collection-table]
    set out {}
    foreach e [dict get $t widgets elements] {
        if {[dict get $e key] ne "часы"} continue
        set out [list owner [dict get $e owner] \
            said [dict get $e values -time-format] \
            merged [dict get [widget-opts часы] -time-format] \
            pace [dict get [widget-opts часы] -every]]
    }
    set out')

kill $WM 2>/dev/null

echo "--- table: $T1"
echo "--- after reload: $T2"
echo "--- verdict"
WANT='btn дом custom label 1 act {custom launch 1 key 1} five {{list custom-five} custom live} widget {{-type clock} config} chords {on config <Super>x}'
if [ "$T1" = "$WANT" ]; then
    echo "OK: every family serves said values, owners and the buried bind"
else
    echo "FAIL: table is {$T1}"
    echo "      want  {$WANT}"
fi
if [ "$T2" = "$T1" ]; then
    echo "OK: the table replays the same after a reload"
else
    echo "FAIL: after reload {$T2}"
fi
if [ "$META" = "cards {} types {battery clock desks weather welcome} bundle windows" ]; then
    echo "OK: cards, the type catalogue and bundle membership are served"
else
    echo "FAIL: meta is {$META}"
fi
echo "--- params: $PARAMS"
echo "--- gate: $GATE"
echo "--- said: $SAIDP"
if [ "$PARAMS" = "kind text def %H:%M said 0 derived %H:%M every 1000" ]; then
    echo "OK: the type's params ride the element — default derived, not said"
else
    echo "FAIL: params served as {$PARAMS}"
fi
if [ "$GATE" = "1 1 1 1 1 1 1 1 ghost 0" ]; then
    echo "OK: the vocabulary gate refuses by name, kind, beat and band"
else
    echo "FAIL: gate answered {$GATE}"
fi
if [ "$SAIDP" = "owner custom said %H:%M:%S merged %H:%M:%S pace 250" ]; then
    echo "OK: a said param lands in values and wins on the read path"
else
    echo "FAIL: said param served as {$SAIDP}"
fi
check_invariants "$HERE/wm-coll.log"
