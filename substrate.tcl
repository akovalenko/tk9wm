# tk9wm substrate — the mechanism layer: everything a WM cannot exist
# without, with zero look-and-feel decisions in it.
#
# One whale process, two X connections:
#  - Tk's own connection draws decorations (the policy layer's job);
#  - a raw Xlib connection (cffi) holds the redirect and does WM surgery
#    (save-set, reparent, map).
# The raw connection's fd is watched by a worker thread blocked in poll();
# it pings the main thread, which drains XPending inside the Tcl event
# loop and then re-arms the worker (ping-pong: exactly one token, so no
# busy loop and no double drains).
#
# Sourcing this file installs the X error handler, loads Tk (order is
# critical — see the error handler section), arms the redirect and the
# pump machinery.  Call substrate-start AFTER the policy layer is loaded:
# it starts draining events and adopts pre-existing windows.
#
# The policy layer must implement these hooks (called by the substrate):
#   policy-attach w cw ch   build a decoration for client w (client area
#                           cw x ch), decide placement, and return the X
#                           window id of the slot to reparent w into; must
#                           return only after the slot exists server-side
#   policy-detach w         destroy w's decoration
#   policy-origin w         root {x y} of w's client area (for synthetic
#                           ConfigureNotify and for parking a withdrawn
#                           client back on root)
#   policy-resize w cw ch   decoration follows w's new client size
#   policy-paint-focus w    repaint the focus highlight (w is focused)
#   policy-client-click w   a click landed inside managed client w
#   policy-managed w        w was just managed (initial-focus decision)
#   policy-pick-refocus     choose a window to refocus after an unmanage
#                           (return 0 for none)
#
# The substrate provides to the policy layer:
#   focus-to w                  set the input focus honestly + repaint
#   close-client w              WM_DELETE_WINDOW when supported, else kill
#   send-synthetic-configure w  ICCCM 4.1.5 notify after a frame move
#   $::focused                  currently focused client (0 = none)

package require cffi
package require Thread
# NB: Tk is required LATER, after our X error handler is installed — see the
# error handler section for why the order matters.

# ---------------- raw Xlib over cffi (second connection) ----------------
cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XDefaultRootWindow ulong {dpy pointer.unsafe}
X11 function XSelectInput int {dpy pointer.unsafe w ulong mask long}
X11 function XPending int {dpy pointer.unsafe}
X11 function XNextEvent int {dpy pointer.unsafe ev pointer.unsafe}
X11 function XMapWindow int {dpy pointer.unsafe w ulong}
X11 function XSync int {dpy pointer.unsafe discard int}
X11 function XConnectionNumber int {dpy pointer.unsafe}
X11 function XAddToSaveSet int {dpy pointer.unsafe w ulong}
X11 function XReparentWindow int {dpy pointer.unsafe w ulong parent ulong x int y int}
X11 function XConfigureWindow int {dpy pointer.unsafe w ulong mask uint changes pointer.unsafe}
X11 function XSetInputFocus int {dpy pointer.unsafe focus ulong revert_to int time ulong}
X11 function XResizeWindow int {dpy pointer.unsafe w ulong width uint height uint}
X11 function XInternAtom ulong {dpy pointer.unsafe name string only_if_exists int}
X11 function XSendEvent int {dpy pointer.unsafe w ulong propagate int mask long ev pointer.unsafe}
X11 function XKillClient int {dpy pointer.unsafe resource ulong}
X11 function XGrabButton int {dpy pointer.unsafe button uint modifiers uint w ulong owner_events int event_mask uint pointer_mode int keyboard_mode int confine ulong cursor ulong}
X11 function XAllowEvents int {dpy pointer.unsafe mode int time ulong}
X11 function XFlush int {dpy pointer.unsafe}
X11 function XChangeProperty int {dpy pointer.unsafe w ulong prop ulong type ulong fmt int mode int data pointer.unsafe n int}
X11 function XCreateSimpleWindow ulong {dpy pointer.unsafe parent ulong x int y int w uint h uint bw uint border ulong bg ulong}
set has_transient [expr {![catch {
    X11 function XGetTransientForHint int {dpy pointer.unsafe w ulong prop {ulong out}}
}]}]
set has_geometry [expr {![catch {
    X11 function XGetGeometry int {dpy pointer.unsafe d ulong root {ulong out}
        x {int out} y {int out} width {uint out} height {uint out}
        bw {uint out} depth {uint out}}
}]}]
set has_getfocus [expr {![catch {
    X11 function XGetInputFocus int {dpy pointer.unsafe focus {ulong out} revert_to {int out}}
}]}]
set has_protocols [expr {![catch {
    X11 function XGetWMProtocols int {dpy pointer.unsafe w ulong protocols {pointer unsafe out} count {int out}}
    X11 function XFree int {ptr pointer.unsafe}
}]}]
set has_querytree [expr {![catch {
    X11 function XQueryTree int {dpy pointer.unsafe w ulong rootw {ulong out} parentw {ulong out} children {pointer unsafe out} nkids {uint out}}
    X11 function XGetWindowAttributes int {dpy pointer.unsafe w ulong attrs pointer.unsafe}
}]}]

# ---------------- X error handler (cffi callback) ----------------
# Xlib's default error handler exits the process; for a WM, BadWindow races
# with dying clients are routine — so: swallow and log.
#
# Install order is the whole trick: our handler goes in BEFORE Tk loads.
# Tk's tkError.c then does XSetErrorHandler(ErrorProc) itself and saves the
# previous handler — us — as its fallback. Result: Tk's own per-request
# error traps (Tk_CreateErrorHandler) keep working and consume the errors
# Tk expects (e.g. colormap walks over dying windows), while anything
# unmatched falls through to us and is logged instead of hitting Xlib's
# exit(). No chaining code needed — the chain assembles itself.
array set xerrname {1 BadRequest 2 BadValue 3 BadWindow 4 BadPixmap 5 BadAtom
    6 BadCursor 7 BadFont 8 BadMatch 9 BadDrawable 10 BadAccess 11 BadAlloc
    12 BadColor 13 BadGC 14 BadIDChoice 15 BadName 16 BadLength 17 BadImplementation}
set xerr_last ""
set xerr_n 0
proc xerror-flush {} {
    if {$::xerr_n > 1} {
        puts "WM:   (previous X error repeated [expr {$::xerr_n - 1}] more times)"
    }
    set ::xerr_last ""; set ::xerr_n 0
}
proc xerror {edpy ev} {
    # XErrorEvent (LP64): type@0 display@8 resourceid@16 serial@24
    # error_code@32 request_code@33 minor_code@34. No X calls in here!
    # Consecutive identical errors are collapsed (Tk's colormap walk over a
    # dying hierarchy produces bursts).
    if {[catch {
        binary scan [cffi::memory tobinary! $ev 40] iux4wuwuwucucucu \
            type disp rid serial code req minor
        set nm [expr {[info exists ::xerrname($code)] ? $::xerrname($code) : "code$code"}]
        set conn [expr {[info exists ::dpy] &&
                        $disp == [cffi::pointer address $::dpy] ? "wm" : "tk"}]
        set key "$nm request=$req resource=[format 0x%x $rid] conn=$conn"
        if {$key eq $::xerr_last} {
            incr ::xerr_n
        } else {
            xerror-flush
            set ::xerr_last $key; set ::xerr_n 1
            puts "WM: X error $key — ignored"
        }
    } err]} { catch {puts "WM: X error (decode failed: $err) — ignored"} }
    return 0
}
set has_errhandler [expr {![catch {
    cffi::prototype function XErrHandler int {edpy {pointer unsafe} ev {pointer unsafe}}
    X11 function XSetErrorHandler pointer.unsafe {handler pointer.XErrHandler}
    XSetErrorHandler [cffi::callback new ::XErrHandler ::xerror 0]
} errh]}]
if {!$has_errhandler} { puts "WM: error handler NOT installed: $errh" }

# Only now let Tk in: it will chain its ErrorProc on top of our handler.
package require Tk
wm withdraw .   ;# our own real toplevel must never hit our own redirect

set dpy [XOpenDisplay $::env(DISPLAY)]
if {[cffi::pointer isnull $dpy]} {puts "WM: cannot open display"; exit 1}
set root [XDefaultRootWindow $dpy]
# SubstructureRedirect|SubstructureNotify|FocusChange — the last one so we
# SEE when something external (Xephyr on outer focus crossings!) resets the
# input focus to PointerRoot, and can re-assert ours.
XSelectInput $dpy $root [expr {(1 << 20) | (1 << 19) | (1 << 21)}]
XSync $dpy 0
chan configure stdout -buffering line
puts "WM: redirect armed on root [format 0x%x $root]"

set WM_PROTOCOLS      [XInternAtom $dpy WM_PROTOCOLS 0]
set WM_DELETE_WINDOW  [XInternAtom $dpy WM_DELETE_WINDOW 0]
set WM_STATE          [XInternAtom $dpy WM_STATE 0]

# ---------------- EWMH minimum ----------------
# Enough for toolkits to see "a WM is present": _NET_SUPPORTING_WM_CHECK on
# root pointing at a dummy window that points back at itself and carries
# _NET_WM_NAME. (GTK apps probe this early; its absence is the prime
# suspect in gimp's startup crash.)
proc set-prop-longs {win prop type values} {
    # format=32 properties take an array of C longs on LP64
    set b ""
    foreach v $values { append b [binary format wu $v] }
    set p [cffi::memory frombinary $b unsafe]
    XChangeProperty $::dpy $win $prop $type 32 0 $p [llength $values]
    cffi::memory free $p
}
proc set-prop-utf8 {win prop str} {
    set b [encoding convertto utf-8 $str]
    set p [cffi::memory frombinary $b unsafe]
    XChangeProperty $::dpy $win $prop $::UTF8 8 0 $p [string length $b]
    cffi::memory free $p
}
if {[catch {
    set NET_CHECK     [XInternAtom $dpy _NET_SUPPORTING_WM_CHECK 0]
    set NET_SUPPORTED [XInternAtom $dpy _NET_SUPPORTED 0]
    set NET_WM_NAME   [XInternAtom $dpy _NET_WM_NAME 0]
    set UTF8          [XInternAtom $dpy UTF8_STRING 0]
    set wmcheck [XCreateSimpleWindow $dpy $root -100 -100 1 1 0 0 0]
    set-prop-longs $root    $NET_CHECK 33 [list $wmcheck]   ;# XA_WINDOW
    set-prop-longs $wmcheck $NET_CHECK 33 [list $wmcheck]
    set-prop-utf8  $wmcheck $NET_WM_NAME tk9wm
    set-prop-longs $root $NET_SUPPORTED 4 \
        [list $NET_CHECK $NET_WM_NAME]                      ;# XA_ATOM
    XSync $dpy 0
    puts "WM: EWMH minimum up (_NET_SUPPORTING_WM_CHECK=[format 0x%x $wmcheck])"
} err]} { puts "WM: EWMH setup failed: $err" }

set evbuf [cffi::memory allocate 256 unsafe]

proc evbytes {n} {
    if {[catch {cffi::memory tobinary $::evbuf $n} b]} {
        set b [cffi::memory tobinary! $::evbuf $n]
    }
    return $b
}

# LP64 XEvent prefix: type@0 serial@8 send_event@16 display@24 A@32 B@40;
# ConfigureRequest tail: x@48 y@52 w@56 h@60 bw@64 above@72 detail@80 mask@88.
proc decode {} {
    binary scan [evbytes 96] iux4wuiux4wuwuwuiiiiix4wuiux4wu \
        type serial sendev disp A B x y w h bw above detail vmask
    list $type $A $B $x $y $w $h $bw $above $detail $vmask
}

# ---------------- event dispatch ----------------
proc handle-event {} {
    lassign [decode] type A B x y w h bw above detail vmask
    switch -- $type {
        23 { # ConfigureRequest: managed → the frame follows the client;
            # unmanaged → honor verbatim and remember the size
            if {[info exists ::managed($B)]} {
                resize-client $B $w $h $vmask
            } else {
                set ::geomof($B) [list $w $h]
                if {[catch {
                    set chg [cffi::memory frombinary \
                        [binary format iiiiix4wuix4 $x $y $w $h $bw $above $detail] unsafe]
                    XConfigureWindow $::dpy $B $vmask $chg
                    cffi::memory free $chg
                } err]} { puts "WM: honor ConfigureRequest failed: $err" }
                puts "WM: ConfigureRequest 0x[format %x $B] ${w}x${h} honored"
            }
        }
        20 { manage $B }
        17 { unmanage $B 1 }
        19 { # MapNotify (self-report): the client is now really on screen
            # and past its own map bookkeeping — tell it where it is once
            # more, see tell-where-you-are.
            if {$A == $B && [info exists ::managed($B)]} {
                send-synthetic-configure $B
            }
        }
        18 { # UnmapNotify: the client withdrew itself. Trust only the
            # StructureNotify self-report (event==window — the root's
            # SubstructureNotify copy has event=root) and skip the unmap
            # echo generated by our own adoption reparent.
            if {$A == $B && [info exists ::managed($B)]} {
                if {[info exists ::skip_unmap($B)]} {
                    unset ::skip_unmap($B)
                } else {
                    puts "WM: client 0x[format %x $B] withdrew itself"
                    unmanage $B
                }
            }
        }
        9 { # FocusIn: window@32 mode@40 detail@44
            binary scan [evbytes 48] iux4wuiux4wuwuiuiu \
                _t _s _se _d win mode detail
            if {$win == $::root && ($detail == 6 || $detail == 7)} {
                # PointerRoot(6)/None(7): something external reset the
                # focus (Xephyr does this on outer focus crossings) —
                # re-assert our focused window
                if {$::focused != 0 && [info exists ::managed($::focused)]} {
                    puts "WM: external focus reset (detail=$detail) —\
 re-asserting 0x[format %x $::focused]"
                    XSetInputFocus $::dpy $::focused 2 0
                    XSync $::dpy 0
                }
            } elseif {[info exists ::managed($win)] && $mode == 0 && $detail < 5} {
                # focus moved behind our back (e.g. focus -force):
                # honor it, keep the highlight honest
                if {$::focused != $win} { paint-focus $win }
            }
        }
        4 { # ButtonPress via our sync grab: let the policy react (focus,
            # raise, whatever), then replay the frozen click to the client.
            # XButtonEvent: window@32 root@40 subwindow@48 time@56.
            binary scan [evbytes 64] iux4wuiux4wuwuwuwuwu \
                _t _s _se _d win rootw subw time
            catch {
                if {[info exists ::managed($win)]} { policy-client-click $win }
            }
            # NEVER skip this: a sync grab left unanswered freezes the pointer
            XAllowEvents $::dpy 2 $time   ;# ReplayPointer
            XSync $::dpy 0
        }
    }
}

# ---------------- facts the policy layer asks about ----------------
# Screen size, read fresh from the server at the moment of the decision:
# the root can be resized under us (RandR — Xephyr's -resizeable does
# exactly that), and a placement policy that cached the startup size
# would put windows off-screen for the rest of the session.
proc screen-size {} {
    if {$::has_geometry && ![catch {XGetGeometry $::dpy $::root rr rx ry rw rh rbw rd}]} {
        return [list $rw $rh]
    }
    return [list [winfo screenwidth .] [winfo screenheight .]]
}

# ICCCM WM_TRANSIENT_FOR: "this window is a dialog FOR that one". Returns
# 0 when unset. Placement and, later, focus-return policy need it.
proc transient-for {w} {
    if {!$::has_transient} { return 0 }
    if {[catch {XGetTransientForHint $::dpy $w parent} ok] || !$ok} { return 0 }
    return $parent
}

# ICCCM 4.1.3.1: a managed window must carry WM_STATE (state + icon
# window). Toolkits and every wmctrl/xdotool-class tool use its presence
# to tell "managed by a WM" from "still wild" — we never set it, which
# left GTK guessing about our clients.
proc set-wm-state {w state} {
    if {[catch {
        set b [binary format wuwu $state 0]      ;# NormalState=1, WithdrawnState=0
        set p [cffi::memory frombinary $b unsafe]
        XChangeProperty $::dpy $w $::WM_STATE $::WM_STATE 32 0 $p 2
        cffi::memory free $p
    } err]} { puts "WM: WM_STATE update failed: $err" }
}

# ---------------- manage / unmanage ----------------
proc manage {w} {
    global dpy
    if {[info exists ::managed($w)]} { XMapWindow $dpy $w; return }
    set cw 200; set ch 120
    if {[info exists ::geomof($w)]} { lassign $::geomof($w) cw ch }
    set ::geomof($w) [list $cw $ch]
    set slot [policy-attach $w $cw $ch]
    set ::managed($w) 1
    # StructureNotify (Destroy/Unmap) + FocusChange (honest highlight even
    # when focus moves behind our back)
    XSelectInput $dpy $w [expr {(1 << 17) | (1 << 21)}]
    # After the reparent the client is no longer a child of root, so root's
    # SubstructureRedirect no longer covers it: keep redirecting its
    # ConfigureRequests by holding the mask on the frame slot as well.
    # (Our own requests are exempt — the redirecting client is never
    # redirected by itself.)
    XSelectInput $dpy $slot [expr {1 << 20}]
    # Click-to-focus inside the client: passive SYNC grab on any button.
    # The press freezes the pointer and wakes us (ButtonPress above); after
    # the policy reacts we XAllowEvents(ReplayPointer) so the client still
    # gets the click un-eaten.
    XGrabButton $dpy 0 0x8000 $w 0 4 0 1 0 0
    ;# AnyButton, AnyModifier, owner_events=False, ButtonPressMask,
    ;# GrabModeSync pointer, GrabModeAsync keyboard, no confine, no cursor
    XAddToSaveSet $dpy $w
    XReparentWindow $dpy $w $slot 0 0
    XMapWindow $dpy $w
    set-wm-state $w 1          ;# NormalState — ICCCM, see set-wm-state
    XSync $dpy 0
    puts "WM: managed 0x[format %x $w]: slot [format 0x%x $slot] client ${cw}x${ch}"
    policy-managed $w
    tell-where-you-are $w
}

# ICCCM 4.1.5 says WHAT to send; it does not say a client will be in a
# state to believe it. Live case (smsrc, a Tk app under Wine, 2026-07-27):
# the app kept a false idea of its position right after being framed —
# clicks missed, menus, tooltips and combo dropdowns landed offset — and
# the first title-bar drag repaired it. Sending the very same event by
# hand from outside repaired it too, which pins the cause: the CONTENT
# was right, the MOMENT was wrong. A client busy with its own startup
# geometry (waiting for its own configure to come back) drops what
# arrives mid-flight; anything later lands.
#
# So state the fact more than once — at manage time, on the client's
# MapNotify, and twice more shortly after. A ConfigureNotify is an
# idempotent statement of where the window is, so repeating it is free
# and cannot confuse a client that already got the message.
proc tell-where-you-are {w} {
    send-synthetic-configure $w
    after 400  [list resend-configure $w]
    after 1500 [list resend-configure $w]
}
proc resend-configure {w} {
    if {[info exists ::managed($w)]} { send-synthetic-configure $w }
}

proc unmanage {w {dead 0}} {
    if {![info exists ::managed($w)]} return
    # Give the client window back to root BEFORE destroying the frame:
    # the client lives INSIDE the frame's slot, and destroying a Tk
    # toplevel destroys its whole X subtree — this used to kill an
    # application that merely did wm withdraw (and later deiconify).
    # Skip for clients that are already destroyed.
    if {!$dead} {
        set x 0; set y 0
        catch { lassign [policy-origin $w] x y }
        catch {
            set-wm-state $w 0      ;# WithdrawnState before letting it go
            XReparentWindow $::dpy $w $::root $x $y
            XSync $::dpy 0
        }
    }
    policy-detach $w
    unset ::managed($w)
    puts "WM: unmanaged 0x[format %x $w], frame destroyed"
    # Refocus not only when OUR records say the dead window was focused:
    # a client may have grabbed focus behind our back (focus -force) and
    # died — then the server reverts to None/PointerRoot and input starts
    # following the pointer. Ask the server and repair either way.
    set stale [expr {$::focused == $w}]
    if {!$stale && $::has_getfocus && ![catch {XGetInputFocus $::dpy f r}]
            && $f <= 1} {   ;# None (0) or PointerRoot (1)
        puts "WM: server focus reverted to [expr {$f ? "PointerRoot" : "None"}] — repairing"
        set stale 1
    }
    if {$stale} {
        set ::focused 0
        set nw [policy-pick-refocus]
        if {$nw != 0} { focus-to $nw }
    }
}

# ---------------- focus core ----------------
# The substrate owns the honest server-side focus (XSetInputFocus + the
# verification and repair paths); which window DESERVES focus and how the
# highlight looks is the policy layer's business.
set focused 0
proc paint-focus {w} {
    set ::focused $w
    policy-paint-focus $w
}
proc focus-to {w} {
    if {![info exists ::managed($w)]} { return 0 }
    # RevertToParent (2), NOT PointerRoot: if the focus window dies before
    # we refocus, a parent revert leaves the keyboard silent for a moment,
    # while a PointerRoot revert switches the whole session to
    # focus-follows-pointer behind our back.
    XSetInputFocus $::dpy $w 2 0
    XSync $::dpy 0
    # Record the focus ONLY if the server agrees. A refused XSetInputFocus
    # (swallowed BadMatch when the window stopped being viewable, a client
    # grabbing focus behind our back) used to be logged as MISMATCH and
    # then recorded as focused anyway — after which every path that trusts
    # ::focused was permanently wrong: clicks on that window were treated
    # as "already focused" and never retried, so the keyboard kept going
    # to the previous window while the frame highlight claimed otherwise
    # (live report, GIMP's Quit dialog). Believing the server costs one
    # roundtrip and cannot wedge.
    if {$::has_getfocus && ![catch {XGetInputFocus $::dpy f r}] && $f != $w} {
        puts "WM: focus -> 0x[format %x $w] REFUSED by server\
 (focus=[format 0x%x $f] revert=$r) — not recorded, will retry"
        return 0
    }
    paint-focus $w
    puts "WM: focus -> 0x[format %x $w]"
    return 1
}

# A managed client's ConfigureRequest: the decoration follows (size bits
# only; the position stays WM-controlled), then the client is resized.
proc resize-client {win rw rh vmask} {
    if {($vmask & ((1 << 2) | (1 << 3))) == 0} return   ;# CWWidth|CWHeight
    lassign $::geomof($win) cw ch
    if {$vmask & (1 << 2)} { set cw $rw }
    if {$vmask & (1 << 3)} { set ch $rh }
    set ::geomof($win) [list $cw $ch]
    policy-resize $win $cw $ch
    XResizeWindow $::dpy $win $cw $ch
    XSync $::dpy 0
    send-synthetic-configure $win
    puts "WM: resize 0x[format %x $win] -> ${cw}x${ch}, frame follows"
}

# ---------------- close machinery ----------------
# Close: ICCCM WM_DELETE_WINDOW when the client declares it, else XKillClient.
proc client-supports-delete {w} {
    if {!$::has_protocols} { return 1 }   ;# cannot check — assume a modern client
    set found 0
    if {![catch {XGetWMProtocols $::dpy $w protos n} status] && $status && $n > 0} {
        if {![catch {cffi::memory tobinary! $protos [expr {8 * $n}]} bytes]} {
            binary scan $bytes wu$n atoms
            set found [expr {$::WM_DELETE_WINDOW in $atoms}]
        }
        catch {XFree $protos}
    }
    return $found
}
proc send-wm-delete {w} {
    # XClientMessageEvent LP64: type@0 serial@8 send_event@16 display@24
    # window@32 message_type@40 format@48 data.l[0]@56 data.l[1]@64
    set b [binary format iux4wuiux4wuwuwuiux4wuwu \
        33 0 1 0 $w $::WM_PROTOCOLS 32 $::WM_DELETE_WINDOW 0]
    set ev [cffi::memory frombinary [binary format a192 $b] unsafe]
    XSendEvent $::dpy $w 0 0 $ev
    XSync $::dpy 0
    cffi::memory free $ev
}
proc close-client {w} {
    if {[client-supports-delete $w]} {
        puts "WM: close 0x[format %x $w]: sending WM_DELETE_WINDOW"
        send-wm-delete $w
    } else {
        puts "WM: close 0x[format %x $w]: no WM_DELETE_WINDOW, XKillClient"
        XKillClient $::dpy $w
        XSync $::dpy 0
    }
}

# ---------------- adoption ----------------
# Adoption: windows that mapped before the WM started (or survived a WM
# restart via the save-set) are already viewable children of root and never
# produce a MapRequest — walk the tree once at startup and manage them.
proc adopt-existing {} {
    global dpy root
    if {!$::has_querytree} { puts "WM: no XQueryTree — adoption skipped"; return }
    if {[catch {XQueryTree $dpy $root r p children n} status] || !$status || $n == 0} return
    if {[cffi::pointer isnull $children]} return
    binary scan [cffi::memory tobinary! $children [expr {8 * $n}]] wu$n kids
    catch {XFree $children}
    set attrs [cffi::memory allocate 136 unsafe]
    foreach w $kids {
        if {[info exists ::managed($w)]} continue
        if {[catch {XGetWindowAttributes $dpy $w $attrs} ok] || !$ok} continue
        # XWindowAttributes (LP64): width@8 height@12 map_state@92
        # override_redirect@120; IsViewable = 2
        binary scan [cffi::memory tobinary! $attrs 136] x8iuiux76iux24iu aw ah mstate orr
        if {$mstate != 2 || $orr} continue
        set ::geomof($w) [list $aw $ah]
        # reparenting a MAPPED window generates an UnmapNotify we must not
        # mistake for the client withdrawing itself
        set ::skip_unmap($w) 1
        puts "WM: adopting existing window 0x[format %x $w] (${aw}x${ah})"
        manage $w
    }
    cffi::memory free $attrs
}

# ICCCM 4.1.5: when the WM moves a client by moving its FRAME, the client
# gets no event and keeps stale root coordinates (menus and tooltips then
# pop at wrong places) — the WM must send a synthetic ConfigureNotify with
# root-relative x,y after placement, every frame move, and granted resizes.
proc send-synthetic-configure {w} {
    if {![info exists ::managed($w)]} return
    lassign $::geomof($w) cw ch
    if {[catch {lassign [policy-origin $w] x y}]} return
    # XConfigureEvent LP64: type@0 serial@8 send_event@16 display@24
    # event@32 window@40 x@48 y@52 width@56 height@60 border_width@64
    # above@72 override_redirect@80
    set b [binary format iux4wuiux4wuwuwuiiiiix4wuiu \
        22 0 1 0 $w $w $x $y $cw $ch 0 0 0]
    set ev [cffi::memory frombinary [binary format a192 $b] unsafe]
    XSendEvent $::dpy $w 0 131072 $ev   ;# StructureNotifyMask
    XFlush $::dpy   ;# no cffi roundtrip follows during a Tk-side drag
    cffi::memory free $ev
}

# ---------------- fd pump: worker thread + blocking poll() ----------------
set xfd [XConnectionNumber $dpy]
set worker [thread::create -preserved {thread::wait}]
thread::send $worker [list set ::auto_path $::auto_path]
thread::send $worker [list set ::main [thread::id]]
thread::send $worker [list set ::pfdbytes [binary format iss $xfd 1 0]] ;# pollfd{fd,POLLIN,0}
thread::send $worker {
    package require cffi
    cffi::Wrapper create LC libc.so.6
    LC function poll int {fds pointer.unsafe nfds ulong timeout int}
    set ::pfd [cffi::memory frombinary $::pfdbytes unsafe]
    proc go {} {
        poll $::pfd 1 -1
        # main may already be gone at shutdown; a failed ping is fine
        catch {thread::send -async $::main ::drain}
    }
}

proc drain {} {
    while {[XPending $::dpy] > 0} {
        XNextEvent $::dpy $::evbuf
        if {[catch handle-event err]} { puts "WM: handler error: $err" }
    }
    thread::send -async $::worker ::go
}

# Orderly shutdown: release every client back to root before Tk destroys
# the frames (otherwise WM exit would take all clients with it). A hard
# kill still loses them — the split-connection save-set wart, see notes.
rename ::exit ::tk9wm-real-exit
proc ::exit {{code 0}} {
    catch { foreach w [array names ::managed] { unmanage $w } }
    ::tk9wm-real-exit $code
}

# To be called by the assembly once the policy layer is in: start draining
# (the first drain arms the worker; a single token from here on) and adopt
# whatever was already on the screen.
proc substrate-start {} {
    puts "WM: pump: X fd $::xfd watched by worker thread (blocking poll, ping-pong)"
    after idle drain
    adopt-existing
}
