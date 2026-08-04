#!/bin/sh
# Regression for the collection registry: collection-table serves the
# configurator every family — buttons, bindings, widgets, key
# bundles — with the values the layers SAID and an owner badge per
# element; a binding buried by a later word is served flagged
# ineffectual (last wins, custom over config); and the whole view
# replays the same after a reload.
. "$(dirname "$0")/common.sh"
export DISPLAY=:66
rm -f /tmp/.X66-lock /tmp/.X11-unix/X66
Xvfb :66 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

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
sleep 1.5

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
if [ "$META" = "cards {} types {clock welcome} bundle windows" ]; then
    echo "OK: cards, the type catalogue and bundle membership are served"
else
    echo "FAIL: meta is {$META}"
fi
check_invariants "$HERE/wm-coll.log"
