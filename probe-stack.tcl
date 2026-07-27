# probe-stack.tcl — read-only: root's viewable children BOTTOM to TOP
# (X stacking order exactly as XQueryTree reports it), each annotated
# with every window found in its subtree. That maps WM frames to the
# clients they hold, so "who is above whom" is answered by line order.
#
#   whale-cli probe-stack.tcl <display>

package require cffi

cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XDefaultRootWindow ulong {dpy pointer.unsafe}
X11 function XQueryTree int {dpy pointer.unsafe w ulong rootw {ulong out} parentw {ulong out} children {pointer unsafe out} nkids {uint out}}
X11 function XFree int {ptr pointer.unsafe}
X11 function XGetWindowAttributes int {dpy pointer.unsafe w ulong attrs pointer.unsafe}

lassign $argv disp
if {$disp eq ""} { set disp $::env(DISPLAY) }
set dpy [XOpenDisplay $disp]
if {[cffi::pointer isnull $dpy]} { puts "cannot open $disp"; exit 1 }
set root [XDefaultRootWindow $dpy]

proc kids {w} {
    if {[catch {XQueryTree $::dpy $w r p children n} status] || !$status || $n == 0} {
        return {}
    }
    if {[cffi::pointer isnull $children]} { return {} }
    binary scan [cffi::memory tobinary! $children [expr {8 * $n}]] wu$n ids
    catch {XFree $children}
    return $ids
}
proc descendants {w} {
    set out {}
    foreach c [kids $w] { lappend out $c {*}[descendants $c] }
    return $out
}
proc viewable {w} {
    # XWindowAttributes (LP64): map_state@92; IsViewable = 2
    set a [cffi::memory allocate 136 unsafe]
    set v 0
    if {![catch {XGetWindowAttributes $::dpy $w $a} ok] && $ok} {
        binary scan [cffi::memory tobinary! $a 136] x92iu ms
        set v [expr {$ms == 2}]
    }
    cffi::memory free $a
    return $v
}

puts "root children bottom -> top on $disp:"
foreach c [kids $root] {
    if {![viewable $c]} continue
    puts "stack: 0x[format %x $c] contains [lmap d [descendants $c] {format 0x%x $d}]"
}
