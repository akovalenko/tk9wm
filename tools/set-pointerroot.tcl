# Simulate the external (Xephyr-style) focus nuke: set input focus to
# PointerRoot with RevertToPointerRoot, exactly what breaks click-to-focus.
package require cffi
cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XSetInputFocus int {dpy pointer.unsafe focus ulong revert int time ulong}
X11 function XSync int {dpy pointer.unsafe discard int}
set dpy [XOpenDisplay $::env(DISPLAY)]
if {[cffi::pointer isnull $dpy]} { puts "EXTERNAL: no display"; exit 1 }
XSetInputFocus $dpy 1 1 0
XSync $dpy 0
puts "EXTERNAL: forced focus to PointerRoot"
