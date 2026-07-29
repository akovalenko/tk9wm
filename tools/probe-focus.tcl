# One-shot server focus probe: prints the real input focus as X sees it.
# focus=0x1 means PointerRoot (input follows the pointer — WM lost focus).
package require cffi
cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XGetInputFocus int {dpy pointer.unsafe focus {ulong out} revert {int out}}
set dpy [XOpenDisplay $::env(DISPLAY)]
if {[cffi::pointer isnull $dpy]} { puts "PROBE: no display"; exit 1 }
XGetInputFocus $dpy f r
puts "PROBE: server focus=[format 0x%x $f] revert=$r"
