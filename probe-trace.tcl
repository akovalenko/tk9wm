# probe-trace.tcl — read-only live trace: where the pointer is, WHAT WINDOW
# it is really over (deepest child, not the pixels you see), and where the
# input focus sits. Prints a line only when something changes.
#
# Made for "I click the dialog and the wrong window gets focus" reports:
# the pixels on screen can lie (stale content, a window on top), the
# containment chain cannot.
#
#   whale-cli probe-trace.tcl <display> ?interval-ms?

package require cffi

cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XDefaultRootWindow ulong {dpy pointer.unsafe}
X11 function XQueryPointer int {dpy pointer.unsafe w ulong root {ulong out}
    child {ulong out} rx {int out} ry {int out} wx {int out} wy {int out}
    mask {uint out}}
X11 function XTranslateCoordinates int {dpy pointer.unsafe src ulong dst ulong
    sx int sy int dx {int out} dy {int out} child {ulong out}}
X11 function XGetInputFocus int {dpy pointer.unsafe focus {ulong out} revert {int out}}
X11 function XFetchName int {dpy pointer.unsafe w ulong name {pointer unsafe out}}
X11 function XFree int {ptr pointer.unsafe}

lassign $argv disp interval
if {$disp eq ""} { set disp $::env(DISPLAY) }
if {$interval eq ""} { set interval 100 }
set dpy [XOpenDisplay $disp]
if {[cffi::pointer isnull $dpy]} { puts "TRACE: cannot open $disp"; exit 1 }
set root [XDefaultRootWindow $dpy]
chan configure stdout -buffering line

proc wname {w} {
    if {![catch {XFetchName $::dpy $w np} ok] && $ok && ![cffi::pointer isnull $np]} {
        set s [cffi::memory tostring! $np]; catch {XFree $np}
        return [string range $s 0 45]
    }
    return "-"
}
proc deepest {X Y} {
    set w $::root
    while {1} {
        if {[catch {XTranslateCoordinates $::dpy $::root $w $X $Y dx dy child}]} break
        if {$child == 0} break
        set w $child
    }
    return $w
}

set prev ""
while 1 {
    if {![catch {XQueryPointer $dpy $root r c rx ry wx wy m} ok] && $ok} {
        set d [deepest $rx $ry]
        XGetInputFocus $dpy f fr
        set btn [expr {($m & 0x1f00) ? " BUTTON-DOWN(mask=[format 0x%x $m])" : ""}]
        set key "$d/$f$btn"
        if {$key ne $prev} {
            set prev $key
            puts "TRACE: pointer +$rx+$ry over 0x[format %x $d] ([wname $d])\
 focus=0x[format %x $f] revert=$fr$btn"
        }
    }
    after $interval
}
