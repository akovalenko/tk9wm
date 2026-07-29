# send-configure.tcl — send a client the ICCCM 4.1.5 synthetic
# ConfigureNotify from OUTSIDE the WM, with the window's true root
# coordinates (queried via XTranslateCoordinates).
#
# Diagnostic for "the app has a false idea of where it is": clicks miss,
# tooltips and combo dropdowns land in the wrong place. If sending this
# by hand repairs the app, the WM's event CONTENT is right and only its
# timing was wrong — the app dropped the one sent at manage time.
#
#   whale-cli send-configure.tcl <display> <window>

package require cffi

cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XDefaultRootWindow ulong {dpy pointer.unsafe}
X11 function XTranslateCoordinates int {dpy pointer.unsafe src ulong dst ulong
    sx int sy int dx {int out} dy {int out} child {ulong out}}
X11 function XGetGeometry int {dpy pointer.unsafe d ulong root {ulong out}
    x {int out} y {int out} width {uint out} height {uint out}
    bw {uint out} depth {uint out}}
X11 function XSendEvent int {dpy pointer.unsafe w ulong propagate int mask long ev pointer.unsafe}
X11 function XSync int {dpy pointer.unsafe discard int}

lassign $argv disp win
if {$disp eq ""} { set disp $::env(DISPLAY) }
set dpy [XOpenDisplay $disp]
if {[cffi::pointer isnull $dpy]} { puts "no display $disp"; exit 1 }
set root [XDefaultRootWindow $dpy]

XGetGeometry $dpy $win rr gx gy gw gh gbw gd
XTranslateCoordinates $dpy $win $root 0 0 rx ry child
puts "window 0x[format %x $win]: ${gw}x${gh}, true root origin +$rx+$ry"

# XConfigureEvent LP64: type@0 serial@8 send_event@16 display@24 event@32
# window@40 x@48 y@52 width@56 height@60 border_width@64 above@72
# override_redirect@80
set b [binary format iux4wuiux4wuwuwuiiiiix4wuiu \
    22 0 1 0 $win $win $rx $ry $gw $gh 0 0 0]
set ev [cffi::memory frombinary [binary format a192 $b] unsafe]
XSendEvent $dpy $win 0 131072 $ev      ;# StructureNotifyMask
XSync $dpy 0
cffi::memory free $ev
puts "sent synthetic ConfigureNotify: +$rx+$ry ${gw}x${gh}"
