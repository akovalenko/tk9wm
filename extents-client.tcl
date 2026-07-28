# A client that asks how thick its decoration WILL be, before it has
# any — EWMH's _NET_REQUEST_FRAME_EXTENTS, which is what a toolkit
# sends while working out where to put a window it has not mapped yet.
#
# The message names the asking window and is SENT TO THE ROOT, where
# the manager listens; that split is why the shim's `event client`
# takes a destination of its own.
package require Tk
package require tkwmx
wm withdraw .
chan configure stdout -buffering line

set me [winfo id .]
set root [lindex [tkwmx::window tree $me] 0]
set REQ  [tkwmx::atom intern _NET_REQUEST_FRAME_EXTENTS]
set PROP [tkwmx::atom intern _NET_FRAME_EXTENTS]

tkwmx::event client $me $REQ {0 0 0 0 0} 32 \
    {substructure-notify substructure-redirect} $root
puts "EXTENTS-CLIENT: asked about [format 0x%x $me]"

after 800 {
    set v [tkwmx::prop get $me $PROP]
    puts "EXTENTS-CLIENT: answer «[lindex $v 2]»"
    exit 0
}
vwait ::forever
