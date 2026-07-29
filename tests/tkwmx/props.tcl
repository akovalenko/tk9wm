# The shim under test is the one built in THIS tree: ./configure &&
# make leaves libtkwmx.so and its pkgIndex.tcl at the root, three
# directories up. Any Tcl/Tk 9 interpreter can host the battery —
# it needs no window manager and no tk9wm.
lappend ::auto_path [file dirname [file dirname [file dirname \
    [file normalize [info script]]]]]
package require Tk
package require tkwmx

proc A {name} { tkwmx::atom intern $name }
set fail 0
proc ok {what got want} {
    if {$got eq $want} { puts "PASS: $what" } else {
        puts "FAIL: $what — got «$got», want «$want»"; set ::fail 1
    }
}

toplevel .t
wm title .t "проба-свойств"
wm geometry .t 240x140+20+20
update
# Tk keeps the WM properties on a WRAPPER window — the PARENT of
# `winfo id` (and `wm frame` does not point at it either: with no WM
# reparenting anything, it answers the widget's own id). A WM sees
# wrappers, so that is what the typed getters are asked about.
proc wrapper {w} { lindex [tkwmx::window tree [winfo id $w]] 1 }
set id [wrapper .t]

# --- the round trip a WM lives on: write, read back, delete
tkwmx::prop set $id [A TKWMX_TEST] [A CARDINAL] 32 {1 2 3}
lassign [tkwmx::prop get $id [A TKWMX_TEST]] type format value
ok "format-32 round trip" [list $format $value] [list 32 {1 2 3}]
ok "type comes back"      $type [A CARDINAL]
tkwmx::prop delete $id [A TKWMX_TEST]
ok "delete leaves nothing" [tkwmx::prop get $id [A TKWMX_TEST]] {}

tkwmx::prop set $id [A TKWMX_BYTES] [A STRING] 8 [binary format H* 00ff41]
lassign [tkwmx::prop get $id [A TKWMX_BYTES]] type format value
ok "format-8 keeps bytes" [binary encode hex $value] 00ff41

# --- typed getters against a real Tk toplevel
ok "prop text reads the title" [tkwmx::prop text $id [A WM_NAME]] проба-свойств
ok "prop class" [lindex [tkwmx::prop class $id] 1] Toplevel
set nh [tkwmx::prop normal-hints $id]
ok "normal-hints has flags" [expr {[dict exists $nh flags]}] 1
ok "hints has input"        [expr {[dict exists [tkwmx::prop hints $id] input]}] 1
wm protocol .t WM_DELETE_WINDOW {}
ok "protocols lists WM_DELETE_WINDOW" \
    [expr {[A WM_DELETE_WINDOW] in [tkwmx::prop protocols $id]}] 1
toplevel .d
wm transient .d .t
update
ok "transient points at the leader" [tkwmx::prop transient [wrapper .d]] $id
ok "transient of a plain window is 0" [tkwmx::prop transient $id] 0

# --- a dead window is ordinary life, not an error
set doomed [wrapper .d]
destroy .d
update
ok "prop get on a dead window returns {}" [tkwmx::prop get $doomed [A WM_NAME]] {}
ok "prop text on a dead window returns {}" [tkwmx::prop text $doomed [A WM_NAME]] {}
ok "geometry on a dead window returns {}" [tkwmx::window geometry $doomed] {}

puts [expr {$fail ? "SOME FAILED" : "ALL PASS"}]
exit $fail
