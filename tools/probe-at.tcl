# probe-at.tcl — read-only: what X window actually lies under a screen
# pixel, and the whole containment chain down to the deepest child.
# Answers "the pixels show window A but clicks/cursor act like window B"
# questions: the chain is the input truth, the pixels can be stale.
#
#   whale-cli probe-at.tcl <display> <x> <y>

package require cffi

cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XDefaultRootWindow ulong {dpy pointer.unsafe}
X11 function XTranslateCoordinates int {dpy pointer.unsafe src ulong dst ulong
    sx int sy int dx {int out} dy {int out} child {ulong out}}
X11 function XFetchName int {dpy pointer.unsafe w ulong name {pointer unsafe out}}
X11 function XFree int {ptr pointer.unsafe}
X11 function XGetWindowAttributes int {dpy pointer.unsafe w ulong attrs pointer.unsafe}
X11 function XQueryPointer int {dpy pointer.unsafe w ulong root {ulong out}
    child {ulong out} rx {int out} ry {int out} wx {int out} wy {int out}
    mask {uint out}}

lassign $argv disp X Y
if {$disp eq ""} { set disp $::env(DISPLAY) }
set dpy [XOpenDisplay $disp]
if {[cffi::pointer isnull $dpy]} { puts "cannot open $disp"; exit 1 }
set root [XDefaultRootWindow $dpy]

proc wname {w} {
    if {![catch {XFetchName $::dpy $w np} ok] && $ok && ![cffi::pointer isnull $np]} {
        set s [cffi::memory tostring! $np]
        catch {XFree $np}
        return $s
    }
    return "(no name)"
}
proc wattrs {w} {
    # XWindowAttributes (LP64): x@0 y@4 width@8 height@12 map_state@92
    # override_redirect@120
    set a [cffi::memory allocate 136 unsafe]
    set out "?"
    if {![catch {XGetWindowAttributes $::dpy $w $a} ok] && $ok} {
        binary scan [cffi::memory tobinary! $a 136] iuiuiuiux76iux24iu ax ay aw ah ms orr
        set state [lindex {unmapped unviewable VIEWABLE} $ms]
        set out "${aw}x${ah}+$ax+$ay $state[expr {$orr ? " override-redirect" : ""}]"
    }
    cffi::memory free $a
    return $out
}

if {$X ne "" && $Y ne ""} {
    puts "chain under pixel +$X+$Y on $disp:"
    set w $root
    set depth 0
    while {1} {
        puts "[string repeat {  } $depth]0x[format %x $w] [wattrs $w] — [wname $w]"
        if {[catch {XTranslateCoordinates $::dpy $root $w $X $Y dx dy child}]} break
        if {$child == 0} break
        set w $child
        incr depth
    }
    puts "deepest: 0x[format %x $w] — [wname $w]"
}

if {![catch {XQueryPointer $dpy $root r c rx ry wx wy m} ok] && $ok} {
    puts "pointer now at +$rx+$ry, root child 0x[format %x $c] — [wname $c]"
}
