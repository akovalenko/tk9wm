# The focus spy: a Tk client that reads its own X events RAW — mode and
# detail included — through the tkwmx shim, and prints them in arrival
# order. It is the witness for the focus-loss discipline: a window the
# WM takes off the screen must lose the focus by an explicit
# SetInputFocus while still mapped (FocusOut before UnmapNotify, detail
# never Ancestor), not by a server revert — the dirty pair that wedged
# chromium's activation (2026-08-12). argv = title.
package require Tk
set here [file dirname [file normalize [info script]]]
lappend auto_path [file dirname $here]   ;# the checkout: pkgIndex + libtkwmx
package require tkwmx

lassign $argv title
wm title . $title
. configure -background #ad7fa8
label .l -text $title -background #ad7fa8 -font {Sans 14}
pack .l -padx 30 -pady 24
wm geometry . 300x140+60+60
update
chan configure stdout -buffering line

# The window the WM manages is the WRAPPER — Tk keeps the WM properties
# on the parent of `winfo id`, not on that id itself (the shim's own
# note at `window tree`). The wrapper never changes across the WM's
# reparent, so it is read once, before the WM has even seen us.
set wrapper [lindex [tkwmx::window tree [winfo id .]] 1]
tkwmx::event select $wrapper {focus-change structure-notify}

array set modename {0 Normal 1 Grab 2 Ungrab 3 WhileGrabbed}
array set detailname {0 Ancestor 1 Virtual 2 Inferior 3 Nonlinear
                      4 NonlinearVirtual 5 Pointer 6 PointerRoot 7 None}
proc spy-event {ev} {
    if {![dict exists $ev window] || [dict get $ev window] != $::wrapper} return
    switch -- [dict get $ev type] {
        focus-in - focus-out {
            set m [dict get $ev mode]
            set d [dict get $ev detail]
            puts "SPY: [dict get $ev type]\
 mode=[expr {[info exists ::modename($m)] ? $::modename($m) : $m}]\
 detail=[expr {[info exists ::detailname($d)] ? $::detailname($d) : $d}]"
        }
        unmap-notify { puts "SPY: unmap" }
        map-notify   { puts "SPY: map" }
    }
}
tkwmx::event on spy-event
puts "SPY: watching wrapper [format 0x%x $wrapper]"
vwait ::forever
