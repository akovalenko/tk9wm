# Raw X client for the size-honesty regression: creates its window at the
# size it wants and just maps it — NO ConfigureRequest ever. This is how
# kitty arrives, and a WM that only remembers sizes from ConfigureRequests
# frames such a client at some default instead of asking the server.
#
#   whale-cli client-size.tcl ?display? ?WxH?

package require cffi

cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XDefaultRootWindow ulong {dpy pointer.unsafe}
X11 function XCreateSimpleWindow ulong {dpy pointer.unsafe parent ulong x int y int
    w uint h uint bw uint border ulong bg ulong}
X11 function XMapWindow int {dpy pointer.unsafe w ulong}
X11 function XSync int {dpy pointer.unsafe discard int}
X11 function XGetGeometry int {dpy pointer.unsafe d ulong root {ulong out}
    x {int out} y {int out} width {uint out} height {uint out}
    bw {uint out} depth {uint out}}

lassign $argv disp size
if {$disp eq ""} { set disp $::env(DISPLAY) }
if {$size eq "" || ![regexp {^(\d+)x(\d+)$} $size -> W H]} { set W 500; set H 400 }
set dpy [XOpenDisplay $disp]
if {[cffi::pointer isnull $dpy]} { puts "CLIENT: no display"; exit 1 }
chan configure stdout -buffering line

set win [XCreateSimpleWindow $dpy [XDefaultRootWindow $dpy] 40 40 $W $H 0 0 0x336644]
XMapWindow $dpy $win
XSync $dpy 0
puts "CLIENT: window 0x[format %x $win] created ${W}x${H} and mapped, no ConfigureRequest"

after 2500
XGetGeometry $dpy $win r x y w h bw d
puts "CLIENT: server-side size now ${w}x${h}"
after 5000
exit
