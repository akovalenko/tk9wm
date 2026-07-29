# Can the window manager put up a REAL decorated toplevel of its own?
#
# The question matters because every menu this WM draws is an
# override-redirect window it decorates by hand, and a dialog would
# rather be a dialog. The answer is in the redirect's own rules:
# SubstructureRedirect on the root turns a child's MapWindow into a
# MapRequest for whoever selected it — UNLESS the window is
# override-redirect, or the client asking IS the one that selected the
# redirect. We are that client, always.
#
# So this probe takes the redirect exactly as the substrate does, puts
# up a plain Tk toplevel, and reports what actually happened: did a
# MapRequest arrive for our own window, and did the window map anyway.
#
#   whale tools/probe-selftoplevel.tcl
lappend ::auto_path [file dirname [file dirname [file normalize [info script]]]]
package require Tk
package require tkwmx
wm withdraw .
chan configure stdout -buffering line

set root [lindex [tkwmx::window tree [winfo id .]] 0]
puts "root: [format 0x%x $root]"

set ::sawrequest 0
set ::ours 0
proc on-event {e} {
    set type [dict get $e type]
    if {$type eq "map-request"} {
        incr ::sawrequest
        puts "  MapRequest for [format 0x%x [dict get $e window]]"
        if {[dict get $e window] == $::ours} {
            puts "  ...which is OUR OWN toplevel — the redirect caught us"
        }
    }
}
tkwmx::event on on-event
tkwmx::event select $root {substructure-redirect substructure-notify}

# A plain Tk toplevel: no -overrideredirect, the ordinary kind an
# application would create.
toplevel .t
wm title .t "confirm?"
wm geometry .t 240x100+80+80
label .t.l -text "a real toplevel" -padx 20 -pady 20
pack .t.l
update
# Tk keeps a toplevel's WM properties on a WRAPPER window, the PARENT
# of `winfo id` — that is the window a WM would see and reparent.
set ::ours [lindex [tkwmx::window tree [winfo id .t]] 1]
puts "our toplevel: [format 0x%x [winfo id .t]] wrapper [format 0x%x $::ours]"
tkwmx::server sync 0
after 800 {
    set g [tkwmx::window geometry $::ours]
    set parent [lindex [tkwmx::window tree $::ours] 1]
    puts "after mapping:"
    puts "  MapRequests seen: $::sawrequest"
    puts "  our wrapper's parent: [format 0x%x $parent]\
          ([expr {$parent == $::root ? {THE ROOT — unmanaged, undecorated}
                                     : {reparented into something}}])"
    puts "  geometry: $g"
    puts "  viewable: [winfo viewable .t]"
    puts ""
    if {$::sawrequest == 0} {
        puts "VERDICT: our own toplevel was NOT redirected — it mapped"
        puts "         straight to the root, bare. A window manager cannot"
        puts "         decorate itself by its own redirect."
    } else {
        puts "VERDICT: the redirect DID catch our own window."
    }
    exit 0
}
vwait ::forever
