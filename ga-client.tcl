# The globally-active control client (ICCCM: WM_HINTS input=False +
# WM_TAKE_FOCUS) — the model Wine 10+ lives in. The WM must not set
# the input focus on such a window; it sends a WM_TAKE_FOCUS
# invitation and THIS client answers with XSetInputFocus carrying the
# invitation's timestamp, then reports whether the server honored the
# answer (a request older than the last focus change is silently
# dropped — the exact wedge fought in fvwm3, see
# notes/fvwm3-wine-focus.md in thoughts). After every honored answer
# it bumps the focus time once with CurrentTime — the menu-like
# own-focus traffic real Wine generates, which is what makes a
# careless WM's next invitation stale. Reports every KeyPress, so a
# driver can prove keys actually flow.
# Usage: DISPLAY=:N whale ga-client.tcl ?title?
package require cffi
cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XCreateSimpleWindow ulong {dpy pointer.unsafe parent ulong \
    x int y int w uint h uint bw uint border ulong bg ulong}
X11 function XChangeProperty int {dpy pointer.unsafe w ulong prop ulong \
    type ulong fmt int mode int data pointer.unsafe n int}
X11 function XInternAtom ulong {dpy pointer.unsafe name string only int}
X11 function XStoreName int {dpy pointer.unsafe w ulong name string}
X11 function XSelectInput int {dpy pointer.unsafe w ulong mask long}
X11 function XMapWindow int {dpy pointer.unsafe w ulong}
X11 function XNextEvent int {dpy pointer.unsafe ev pointer.unsafe}
X11 function XSetInputFocus int {dpy pointer.unsafe w ulong revert int time ulong}
X11 function XGetInputFocus int {dpy pointer.unsafe focus {ulong out} revert {int out}}
X11 function XSync int {dpy pointer.unsafe discard int}
X11 function XDefaultRootWindow ulong {dpy pointer.unsafe}
X11 function XBlackPixel ulong {dpy pointer.unsafe screen int}
X11 function XWhitePixel ulong {dpy pointer.unsafe screen int}

chan configure stdout -buffering line
set title [expr {[llength $argv] ? [lindex $argv 0] : "га-клиент"}]
set dpy [XOpenDisplay $::env(DISPLAY)]
if {[cffi::pointer isnull $dpy]} { puts "GACLIENT: no display"; exit 1 }
set root [XDefaultRootWindow $dpy]
set win [XCreateSimpleWindow $dpy $root 60 60 220 110 0 \
    [XBlackPixel $dpy 0] [XWhitePixel $dpy 0]]
XStoreName $dpy $win $title

proc put-longs {w prop type values} {
    set b ""
    foreach v $values { append b [binary format wu $v] }
    set p [cffi::memory frombinary $b unsafe]
    XChangeProperty $::dpy $w $prop $type 32 0 $p [llength $values]
    cffi::memory free $p
}
# WM_HINTS (atom 35, 9 longs): flags=InputHint only, input=False
put-longs $win 35 35 {1 0 0 0 0 0 0 0 0}
set WM_PROTOCOLS  [XInternAtom $dpy WM_PROTOCOLS 0]
set WM_TAKE_FOCUS [XInternAtom $dpy WM_TAKE_FOCUS 0]
set WM_DELETE     [XInternAtom $dpy WM_DELETE_WINDOW 0]
put-longs $win $WM_PROTOCOLS 4 [list $WM_TAKE_FOCUS $WM_DELETE]

XSelectInput $dpy $win [expr {(1 << 0) | (1 << 17)}]  ;# KeyPress|StructureNotify
XMapWindow $dpy $win
XSync $dpy 0
puts "GACLIENT: up, window [format 0x%x $win] (input=False, WM_TAKE_FOCUS)"

set ev [cffi::memory allocate 256 unsafe]
while 1 {
    XNextEvent $dpy $ev
    binary scan [cffi::memory tobinary! $ev 96] iux28wuwuiux4wuwu \
        type ewin mtype fmt l0 l1
    if {$type == 33 && $mtype == $WM_PROTOCOLS && $l0 == $WM_DELETE} {
        puts "GACLIENT: delete, bye"
        exit 0
    }
    if {$type == 33 && $mtype == $WM_PROTOCOLS && $l0 == $WM_TAKE_FOCUS} {
        puts "GACLIENT: invited t=$l1"
        XSetInputFocus $dpy $win 2 $l1   ;# the answer, invitation's stamp
        XSync $dpy 0
        XGetInputFocus $dpy f r
        if {$f == $win} {
            puts "GACLIENT: answer honored"
            # menu-like own focus traffic: bump the last-focus-change
            # time past any timestamp the WM has seen so far
            XSetInputFocus $dpy $win 2 0
            XSync $dpy 0
        } else {
            puts "GACLIENT: answer DROPPED (focus=[format 0x%x $f])"
        }
        continue
    }
    if {$type == 2} { puts "GACLIENT: key" }
}
