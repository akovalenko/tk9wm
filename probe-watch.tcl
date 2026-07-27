# Watch a display's input focus and print every change (read-only).
# Usage: DISPLAY=:7 whale-cli probe-watch.tcl ?interval-ms?
package require cffi
cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XGetInputFocus int {dpy pointer.unsafe focus {ulong out} revert {int out}}
set dpy [XOpenDisplay $::env(DISPLAY)]
if {[cffi::pointer isnull $dpy]} { puts "WATCH: no display"; exit 1 }
set interval [expr {[llength $argv] ? [lindex $argv 0] : 200}]
chan configure stdout -buffering line
set prev ""
while 1 {
    XGetInputFocus $dpy f r
    if {"$f/$r" ne $prev} {
        set prev "$f/$r"
        puts "WATCH: focus=[format 0x%x $f] revert=$r"
    }
    after $interval
}
