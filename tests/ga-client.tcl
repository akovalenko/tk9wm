# The globally-active control client (ICCCM: WM_HINTS input=False +
# WM_TAKE_FOCUS) — the model Wine 10+ lives in. The WM must not set
# the input focus on such a window; it sends a WM_TAKE_FOCUS
# invitation and THIS client answers with XSetInputFocus carrying the
# invitation's timestamp, then reports whether the server honored the
# answer (a request older than the last focus change is silently
# dropped — the exact wedge fought in fvwm3, see
# notes/fvwm3-wine-focus.md in thoughts).
#
# It models Wine's two defining behaviours, both always on:
#
#  - the FOCUS-STEALING GUARD. An invitation whose timestamp is not
#    newer than the time this client last took the focus is refused,
#    exactly as Wine's window_should_take_focus refuses one older than
#    its foreground's focus time. A WM that stamps invitations from a
#    clock of its own — one that goes stale while the user types INTO a
#    window — loses to this guard, which is what wedged smsrc at
#    startup on the live display (step 31).
#  - the RE-ASK. A refused invitation is not the end: Wine asks for
#    activation itself, with an EWMH _NET_ACTIVE_WINDOW client message
#    to the root. That is the recovery path a correct WM leans on
#    instead of resending invitations on a timer — but it only works
#    if the WM has not already published this window as the active one
#    (a client that believes it IS the foreground has nothing to ask
#    for).
#
# After every honored answer it bumps its own focus time once with
# CurrentTime — the menu-like own-focus traffic real Wine generates,
# which is what makes a careless WM's next invitation stale. Reports
# every KeyPress, so a driver can prove keys actually flow.
# An optional REJECT count refuses the first N invitations outright
# whatever their stamp (a stubborn guard), to exercise the recovery.
# Usage: DISPLAY=:N whale ga-client.tcl ?title? ?rejectN?
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
X11 function XSendEvent int {dpy pointer.unsafe w ulong propagate int \
    mask long ev pointer.unsafe}
X11 function XSetInputFocus int {dpy pointer.unsafe w ulong revert int time ulong}
X11 function XGetInputFocus int {dpy pointer.unsafe focus {ulong out} revert {int out}}
X11 function XSync int {dpy pointer.unsafe discard int}
X11 function XDefaultRootWindow ulong {dpy pointer.unsafe}
X11 function XBlackPixel ulong {dpy pointer.unsafe screen int}
X11 function XWhitePixel ulong {dpy pointer.unsafe screen int}

chan configure stdout -buffering line
set title [expr {[llength $argv] ? [lindex $argv 0] : "га-клиент"}]
set rejects [expr {[llength $argv] > 1 ? [lindex $argv 1] : 0}]
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
set NET_ACTIVE    [XInternAtom $dpy _NET_ACTIVE_WINDOW 0]
put-longs $win $WM_PROTOCOLS 4 [list $WM_TAKE_FOCUS $WM_DELETE]

# Wine's own recovery: ask the WM for activation (EWMH source 1 =
# application, plus a timestamp of our own).
proc re-ask {t} {
    # XClientMessageEvent LP64: type@0 serial@8 send_event@16 display@24
    # window@32 message_type@40 format@48 data.l[0]@56 l[1]@64 l[2]@72
    set b [binary format iux4wuiux4wuwuwuiux4wuwuwu \
        33 0 1 0 $::win $::NET_ACTIVE 32 1 $t 0]
    set ev [cffi::memory frombinary [binary format a192 $b] unsafe]
    # SubstructureRedirect|SubstructureNotify, as the EWMH spec requires
    XSendEvent $::dpy $::root 0 [expr {(1 << 20) | (1 << 19)}] $ev
    cffi::memory free $ev
    XSync $::dpy 0
    puts "GACLIENT: asked for activation myself (t=$t)"
}

XSelectInput $dpy $win [expr {(1 << 0) | (1 << 17)}]  ;# KeyPress|StructureNotify
XMapWindow $dpy $win
XSync $dpy 0
puts "GACLIENT: up, window [format 0x%x $win] (input=False, WM_TAKE_FOCUS)"

set focus_time 0     ;# when this client last took the focus — the guard's bar
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
        if {$rejects > 0} {
            incr rejects -1
            puts "GACLIENT: invitation REJECTED t=$l1 (stubborn guard)"
            XStoreName $dpy $win "$title (отверг $l1)"
            XSync $dpy 0
            re-ask $l1
            continue
        }
        if {$l1 <= $focus_time} {
            # Wine's guard: a stale invitation is a focus-stealing
            # attempt as far as the client can tell.
            puts "GACLIENT: invitation REJECTED t=$l1 (stale, my focus time $focus_time)"
            re-ask $l1
            continue
        }
        puts "GACLIENT: invited t=$l1"
        XSetInputFocus $dpy $win 2 $l1   ;# the answer, invitation's stamp
        XSync $dpy 0
        XGetInputFocus $dpy f r
        if {$f == $win} {
            puts "GACLIENT: answer honored"
            set focus_time $l1
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
