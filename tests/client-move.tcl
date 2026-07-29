# Raw X client that checks one ICCCM 4.1.5 obligation of the WM:
#
#   "If a client's ConfigureWindow request is denied in whole or in part,
#    the window manager must send the client a synthetic ConfigureNotify"
#
# A window manager that silently ignores a MOVE request leaves the client
# believing the move happened — which is exactly how an app ends up with a
# false idea of where it is (clicks miss, menus and tooltips land offset).
#
# No Tk on purpose: a toolkit would paper over the answer by querying the
# server itself. This asks the protocol question and prints PASS/FAIL.
#
#   whale-cli client-move.tcl ?display?

package require cffi

cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XDefaultRootWindow ulong {dpy pointer.unsafe}
X11 function XCreateSimpleWindow ulong {dpy pointer.unsafe parent ulong x int y int
    w uint h uint bw uint border ulong bg ulong}
X11 function XSelectInput int {dpy pointer.unsafe w ulong mask long}
X11 function XMapWindow int {dpy pointer.unsafe w ulong}
X11 function XMoveWindow int {dpy pointer.unsafe w ulong x int y int}
X11 function XNextEvent int {dpy pointer.unsafe ev pointer.unsafe}
X11 function XPending int {dpy pointer.unsafe}
X11 function XSync int {dpy pointer.unsafe discard int}
X11 function XFlush int {dpy pointer.unsafe}
X11 function XTranslateCoordinates int {dpy pointer.unsafe src ulong dst ulong
    sx int sy int dx {int out} dy {int out} child {ulong out}}

set disp [lindex $argv 0]
if {$disp eq ""} { set disp $::env(DISPLAY) }
set dpy [XOpenDisplay $disp]
if {[cffi::pointer isnull $dpy]} { puts "CLIENT: no display"; exit 1 }
set root [XDefaultRootWindow $dpy]
chan configure stdout -buffering line

set win [XCreateSimpleWindow $dpy $root 40 40 300 200 0 0 0x445566]
XSelectInput $dpy $win 131072      ;# StructureNotifyMask
XMapWindow $dpy $win
XSync $dpy 0
puts "CLIENT: window 0x[format %x $win] mapped, waiting to be framed"

set buf [cffi::memory allocate 256 unsafe]
proc drain-events {label} {
    set out {}
    while {[XPending $::dpy] > 0} {
        XNextEvent $::dpy $::buf
        binary scan [cffi::memory tobinary! $::buf 96] iux4wuiux4wuwuwuiiii \
            type serial sendev disp ev win x y w h
        if {$type == 22} {
            lappend out "$label ConfigureNotify synthetic=$sendev +$x+$y ${w}x${h}"
        }
    }
    return $out
}

# let the WM frame us
after 2500
foreach l [drain-events "  (framing)"] { puts $l }

XTranslateCoordinates $dpy $win $root 0 0 tx ty child
puts "CLIENT: true root origin before the move request: +$tx+$ty"

# Ask to MOVE (position bits only). A reparenting WM normally denies this
# — but denial or not, it owes us an answer.
puts "CLIENT: requesting a move to +500+400"
XMoveWindow $dpy $win 500 400
XFlush $dpy
after 1500

set replies [drain-events "  (after move request)"]
foreach l $replies { puts $l }
XTranslateCoordinates $dpy $win $root 0 0 nx ny child2
puts "CLIENT: true root origin after the request: +$nx+$ny"

set answered 0
foreach l $replies { if {[string match "*synthetic=1*" $l]} { set answered 1 } }
if {$answered} {
    puts "CLIENT: PASS — the WM answered the move request (ICCCM 4.1.5)"
} else {
    puts "CLIENT: FAIL — no synthetic ConfigureNotify: the client is left\
 believing its move took effect"
}
