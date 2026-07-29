# set-focus.tcl — hand the input focus to a window from OUTSIDE the WM
# (diagnostic counterpart of set-pointerroot.tcl: that one simulates an
# external PointerRoot reset, this one an external honest focus grab).
#
#   whale-cli set-focus.tcl <display> <window>

package require cffi
cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XSetInputFocus int {dpy pointer.unsafe focus ulong revert int time ulong}
X11 function XGetInputFocus int {dpy pointer.unsafe focus {ulong out} revert {int out}}
X11 function XSync int {dpy pointer.unsafe discard int}

lassign $argv disp win
if {$disp eq ""} { set disp $::env(DISPLAY) }
set dpy [XOpenDisplay $disp]
if {[cffi::pointer isnull $dpy]} { puts "no display $disp"; exit 1 }
XSetInputFocus $dpy $win 2 0
XSync $dpy 0
XGetInputFocus $dpy f r
puts "EXTERNAL: asked focus=$win, server now focus=[format 0x%x $f] revert=$r"
