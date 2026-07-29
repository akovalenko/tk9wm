# tkwmx events: the redirect on TK'S OWN connection, dispatched by TK'S
# OWN event loop. No second X connection, no worker thread watching an
# fd, no XEvent picked apart by hand at LP64 offsets.
#
# The subject has to be ANOTHER client — a map request from the client
# that holds the redirect is not redirected — so the test drives an
# xterm and watches what arrives.
# The shim under test is the one built in THIS tree: ./configure &&
# make leaves libtkwmx.so and its pkgIndex.tcl at the root, three
# directories up. Any Tcl/Tk 9 interpreter can host the battery —
# it needs no window manager and no tk9wm.
# Front of auto_path, not the back: `package require` stops at the
# first directory that supplies the package, so appending would let a
# compiled-in shim answer instead of the one just built here.
set ::auto_path [linsert $::auto_path 0 \
    [file dirname [file dirname [file dirname \
        [file normalize [info script]]]]]]
package require Tk
package require tkwmx

set fail 0
proc ok {what got want} {
    if {$got eq $want} { puts "PASS: $what" } else {
        puts "FAIL: $what — got «$got», want «$want»"; set ::fail 1
    }
}

wm withdraw .
set root [lindex [tkwmx::window tree [winfo id .]] 0]
puts "root = $root"

set seen {}
proc note {ev} {
    lappend ::seen $ev
    # A window manager's minimum duty: a MapRequest is a request, and
    # somebody has to answer it — otherwise the client hangs unmapped.
    if {[dict get $ev type] eq "map-request"} {
        tkwmx::window map [dict get $ev window]
        set ::mapped [dict get $ev window]
    }
}
tkwmx::event on note
if {[catch {tkwmx::event select $root {substructure-redirect substructure-notify}} e]} {
    puts "FAIL: could not take the redirect — $e"
    exit 1
}
puts "PASS: redirect taken on the root"
ok "mask vocabulary is published" \
    [expr {"substructure-redirect" in [tkwmx::event masks]}] 1

exec xterm -T подопытный -e sleep 20 &
set ::mapped 0
after 8000 {set ::mapped -1}
vwait ::mapped
ok "a MapRequest arrived and was honored" [expr {$::mapped > 0}] 1

set types {}
foreach ev $seen { lappend types [dict get $ev type] }
ok "CreateNotify seen too"  [expr {"create-notify" in $types}] 1
set mr [lindex [lsearch -inline -index 1 $seen map-request] 0]
foreach ev $seen {
    if {[dict get $ev type] eq "map-request"} { set mr $ev; break }
}
ok "the dict names its fields" \
    [expr {[dict exists $mr window] && [dict exists $mr parent]
           && [dict exists $mr serial] && [dict exists $mr send-event]}] 1
puts "    map-request dict: $mr"

# and the events keep coming: the client's own properties land here
# because substructure-notify covers its life under the root
after 2000 {set ::done 1}
vwait ::done
ok "more than one event type arrived" [expr {[llength [lsort -unique $types]] > 1}] 1

tkwmx::event on {}
puts [expr {$fail ? "SOME FAILED" : "ALL PASS"}]
exit $fail
