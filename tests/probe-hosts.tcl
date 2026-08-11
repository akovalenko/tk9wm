# The ui hosts THIS DISPLAY carries — asked of the X server itself,
# which is the only counter that does not see a parallel battery's
# neighbours (pgrep counts the machine; see run-applet-test.sh).
#
#   (no arg)   print «N PID»: how many tk9wm-ui* interps stand, and
#              the pid of the one answering to the well-known name
#              (- when nobody does)
#   kill       ask every tk9wm-ui* interp to leave, async
package require Tk
wm withdraw .
set names [lsearch -all -inline [winfo interps] tk9wm-ui*]
if {[lindex $argv 0] eq "kill"} {
    foreach n $names { catch {send -async -- $n {after idle exit}} }
    exit 0
}
set pid -
catch {set pid [send -- tk9wm-ui pid]}
puts "[llength $names] $pid"
exit 0
