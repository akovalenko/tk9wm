# A RESIDENT client that hides itself rather than exiting: withdrawn,
# waiting to be called back. The owner's runner and his configurator are
# both this shape, and it is a shape the desk must not undo behind the
# client's back — a window the user put away has to stay away.
#
# argv = ?title? ?secs?
package require Tk
lassign $argv title secs
if {$title eq ""} { set title затворник }
if {$secs eq ""} { set secs 60 }
chan configure stdout -buffering line
wm title . $title
wm geometry . 300x160+300+300
label .l -text $title -background #fcaf3e -font {Sans 14}
pack .l -expand 1 -fill both
after 2000 {
    wm withdraw .
    puts "HIDE: withdrawn, mapped=[winfo ismapped .]"
}
# Read AFTER whatever the driver does in between: `winfo ismapped` is
# the client's own answer to "did anybody map me while I was not
# looking", which is the whole question here.
after 12000 { puts "HIDE: mapped=[winfo ismapped .]" }
after [expr {$secs * 1000}] exit
vwait ::forever
