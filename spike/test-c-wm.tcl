# Test C: select SubstructureRedirect on the ROOT window via cffi over a
# second X connection and act as a minimal WM: log events, honor MapRequest.
package require cffi
cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XDefaultRootWindow ulong {dpy pointer.unsafe}
X11 function XSelectInput int {dpy pointer.unsafe w ulong mask long}
X11 function XPending int {dpy pointer.unsafe}
X11 function XNextEvent int {dpy pointer.unsafe ev pointer.unsafe}
X11 function XMapWindow int {dpy pointer.unsafe w ulong}
X11 function XSync int {dpy pointer.unsafe discard int}

set dpy [XOpenDisplay $::env(DISPLAY)]
if {[cffi::pointer isnull $dpy]} {puts "WM: cannot open display"; exit 1}
set root [XDefaultRootWindow $dpy]
# SubstructureRedirectMask | SubstructureNotifyMask; only ONE client per
# screen may hold redirect — errors here would mean a WM is already running.
XSelectInput $dpy $root [expr {(1 << 20) | (1 << 19)}]
XSync $dpy 0
puts "WM: redirect armed on root [format 0x%x $root]"

# tag "unsafe" so the pointer matches the pointer.unsafe parameter type
set evbuf [cffi::memory allocate 256 unsafe]
array set evname {16 CreateNotify 17 DestroyNotify 18 UnmapNotify 19 MapNotify
                  20 MapRequest 21 ReparentNotify 22 ConfigureNotify 23 ConfigureRequest}

proc evbytes {} {
    # XEvent prefix: type@0, serial@8, send_event@16, display@24,
    # parent@32, window@40 (LP64) — 48 bytes is enough for our fields.
    global evbuf
    if {[catch {cffi::memory tobinary $evbuf 48} b]} {
        set b [cffi::memory tobinary! $evbuf 48]
    }
    return $b
}

proc poll {} {
    global dpy evbuf evname
    while {[XPending $dpy] > 0} {
        XNextEvent $dpy $evbuf
        binary scan [evbytes] iux4wuiux4wuwuwu type serial sendev disp parent window
        set name [expr {[info exists evname($type)] ? $evname($type) : $type}]
        puts "WM: $name parent=[format 0x%x $parent] window=[format 0x%x $window]"
        if {$type == 20} {
            puts "WM: -> XMapWindow [format 0x%x $window]"
            XMapWindow $dpy $window
            XSync $dpy 0
        }
    }
    after 25 poll
}
poll
after 6000 {puts "WM: done"; exit 0}
vwait ::forever
