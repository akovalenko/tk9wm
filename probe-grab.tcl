# probe-grab.tcl — read-only-ish: does somebody already hold a passive
# button grab on a window?
#
# Only one client can hold a given (button, modifiers, window) passive
# grab: a second XGrabButton(AnyButton, AnyModifier) on the same window
# fails with BadAccess. So we try to take the grab ourselves and report:
#
#   BadAccess  → somebody (our WM, or the app) already grabs there
#   taken      → NOBODY grabs there — a WM relying on that grab is deaf
#                to clicks on this window
#
# The grab is released immediately (and dies with the connection anyway).
#
# With an explicit narrow combination (e.g. button 3 + Mod5, which no
# toolkit grabs) the answer disambiguates WHOSE grab it is: a failure on
# such a combination can only come from somebody holding
# AnyButton/AnyModifier — the WM's signature.
#
#   whale-cli probe-grab.tcl <display> <win> [<win> ...]     (AnyButton/AnyMod)
#   whale-cli probe-grab.tcl <display> -b <btn> -m <mods> <win> ...

package require cffi

cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XGrabButton int {dpy pointer.unsafe button uint modifiers uint
    w ulong owner_events int event_mask uint pointer_mode int
    keyboard_mode int confine ulong cursor ulong}
X11 function XUngrabButton int {dpy pointer.unsafe button uint modifiers uint w ulong}
X11 function XSync int {dpy pointer.unsafe discard int}
X11 function XFetchName int {dpy pointer.unsafe w ulong name {pointer unsafe out}}
X11 function XFree int {ptr pointer.unsafe}

set ::lastcode 0
proc xerror {edpy ev} {
    binary scan [cffi::memory tobinary! $ev 40] iux4wuwuwucucucu \
        type disp rid serial code req minor
    set ::lastcode $code
    return 0
}
cffi::prototype function XErrHandler int {edpy {pointer unsafe} ev {pointer unsafe}}
X11 function XSetErrorHandler pointer.unsafe {handler pointer.XErrHandler}
XSetErrorHandler [cffi::callback new ::XErrHandler ::xerror 0]

set disp [lindex $argv 0]
set args [lrange $argv 1 end]
set btn 0          ;# AnyButton
set mods 0x8000    ;# AnyModifier
while {[lindex $args 0] in {-b -m}} {
    lassign $args flag val
    if {$flag eq "-b"} { set btn $val } else { set mods $val }
    set args [lrange $args 2 end]
}
set dpy [XOpenDisplay $disp]
if {[cffi::pointer isnull $dpy]} { puts "cannot open $disp"; exit 1 }
puts "probing button=$btn modifiers=[format 0x%x $mods]"

foreach w $args {
    set ::lastcode 0
    XGrabButton $dpy $btn $mods $w 0 4 0 1 0 0
    XSync $dpy 0
    set name "(no name)"
    if {![catch {XFetchName $dpy $w np}] && ![cffi::pointer isnull $np]} {
        set name [cffi::memory tostring! $np]; catch {XFree $np}
    }
    if {$::lastcode == 10} {
        puts "$w: BadAccess — a passive grab is ALREADY held here — $name"
    } elseif {$::lastcode != 0} {
        puts "$w: X error code $::lastcode — $name"
    } else {
        puts "$w: grab TAKEN by us — nobody was grabbing here — $name"
        XUngrabButton $dpy $btn $mods $w
        XSync $dpy 0
    }
}
