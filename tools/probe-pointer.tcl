# probe-pointer.tcl — is somebody holding an ACTIVE pointer grab right now?
#
# Diagnoses the classic reparenting-WM freeze: a passive SYNC grab whose
# XAllowEvents never came. Symptoms on screen are misleading — the cursor
# keeps moving but shows the GRAB WINDOW's cursor everywhere, clicks do
# nothing, and the keyboard still reaches the focused window, so it reads
# as "clicks focus the wrong window".
#
# XGrabPointer from a second client tells the truth:
#   AlreadyGrabbed / GrabFrozen → someone holds an active grab (or the
#                                 pointer is frozen by it)
#   GrabSuccess                 → nothing is grabbing; we release at once
#
#   whale-cli probe-pointer.tcl [display]

package require cffi

cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XDefaultRootWindow ulong {dpy pointer.unsafe}
X11 function XGrabPointer int {dpy pointer.unsafe w ulong owner_events int
    event_mask uint pointer_mode int keyboard_mode int confine ulong
    cursor ulong time ulong}
X11 function XUngrabPointer int {dpy pointer.unsafe time ulong}
X11 function XSync int {dpy pointer.unsafe discard int}

set disp [lindex $argv 0]
if {$disp eq ""} { set disp $::env(DISPLAY) }
set dpy [XOpenDisplay $disp]
if {[cffi::pointer isnull $dpy]} { puts "cannot open $disp"; exit 1 }
set root [XDefaultRootWindow $dpy]

set names {0 GrabSuccess 1 AlreadyGrabbed 2 GrabInvalidTime 3 GrabNotViewable 4 GrabFrozen}
set r [XGrabPointer $dpy $root 0 4 1 1 0 0 0]
XSync $dpy 0
set nm [expr {[dict exists $names $r] ? [dict get $names $r] : "code$r"}]
puts "PROBE: XGrabPointer -> $nm ($r)"
switch -- $r {
    0 { puts "PROBE: nobody was grabbing — releasing"; XUngrabPointer $dpy 0; XSync $dpy 0 }
    1 { puts "PROBE: another client holds an ACTIVE pointer grab" }
    4 { puts "PROBE: the pointer is FROZEN by another client's sync grab —\
 an XAllowEvents is missing" }
}
