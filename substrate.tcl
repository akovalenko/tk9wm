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
#   policy-max-client-size  {maxw maxh} a frame on this screen can hold —
#                           an oversized newcomer is shrunk to it at manage
#   policy-detach w         destroy w's decoration
#   policy-origin w         root {x y} of w's client area (for synthetic
#                           ConfigureNotify and for parking a withdrawn
#                           client back on root)
#   policy-resize w cw ch   decoration follows w's new client size
#   policy-paint-focus w    repaint the focus highlight (w is focused)
#   policy-title w title    put the client's (new) title on the frame;
#                           empty string = the client named nothing
#   policy-client-click w   a click landed inside managed client w
#   policy-managed w        w was just managed (initial-focus decision)
#   policy-pick-refocus w   choose a window to refocus after w's unmanage;
#                           called BEFORE policy-detach w (the pick may
#                           need per-frame facts that detach cleans up);
#                           return 0 for none
#
# The substrate provides to the policy layer:
#   focus-to w                  set the input focus honestly + repaint
#   wm-bind spec script         bind a key chord sequence ("<Alt>space",
#                               "<Super>t w m") to a script — see the key
#                               bindings section
#   grab-keys-to cmd            keyboard-modal UI: hold the keyboard and
#                               route every key event to cmd (appended:
#                               press|release, keysym name, modifier
#                               mask); empty cmd releases and restores
#                               the keymap
#   modifier-held mask          is any key of these modifiers physically
#                               down right now (XQueryKeymap)?
#   $::key_invoke_mods          modifier mask of the chord that invoked
#                               the currently running key action
#   kill-client w               unconditional XKillClient (close-client
#                               asks politely first)
#   close-client w              WM_DELETE_WINDOW when supported, else kill
#   send-synthetic-configure w  ICCCM 4.1.5 notify after a frame move
#   wm-resize-client w cw ch    a WM-initiated resize (border/corner drag);
#                               clamps to the client's declared minimum
#   client-min-size w           declared WM_NORMAL_HINTS minimum, {0 0} = none
#   client-size-hints w         {minw minh incw inch basew baseh}; zero
#                               increments = none declared
#   client-class w              WM_CLASS as {instance class}, {"" ""} = none
#   client-machine w            WM_CLIENT_MACHINE, "" = none
#   client-pid w                _NET_WM_PID, 0 = none
#   client-cmdline w            argv of a LOCAL client as a Tcl list
#                               (via /proc), {} for remote/undeclared
#   $::focused                  currently focused client (0 = none)

package require cffi
package require Thread
# NB: Tk is required LATER, after our X error handler is installed — see the
# error handler section for why the order matters.

# (There is no quirks switch any more. It existed to hold timed repeats of
# the synthetic ConfigureNotify while we did not know the right moment to
# send one; running with it OFF proved the moments were missing, reading
# fvwm named them — answer every ConfigureRequest, and copy the notify to
# the frame — and with those in place the live case was fixed with no
# timers at all. A switch with nothing behind it only rots.)

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
set has_fetchname [expr {![catch {
    X11 function XFetchName int {dpy pointer.unsafe w ulong name {pointer unsafe out}}
}]}]
set has_getprop [expr {![catch {
    X11 function XGetWindowProperty int {dpy pointer.unsafe w ulong prop ulong
        off long len long delete int reqtype ulong actual_type {ulong out}
        actual_format {int out} nitems {ulong out} bytes_after {ulong out}
        data {pointer unsafe out}}
}]}]
set has_normalhints [expr {![catch {
    X11 function XGetWMNormalHints int {dpy pointer.unsafe w ulong
        hints pointer.unsafe supplied {long out}}
}]}]
set has_keys [expr {![catch {
    X11 function XGrabKey int {dpy pointer.unsafe keycode int modifiers uint
        w ulong owner_events int pointer_mode int keyboard_mode int}
    X11 function XUngrabKey int {dpy pointer.unsafe keycode int modifiers uint w ulong}
    X11 function XGrabKeyboard int {dpy pointer.unsafe w ulong owner_events int
        pointer_mode int keyboard_mode int time ulong}
    X11 function XUngrabKeyboard int {dpy pointer.unsafe time ulong}
    X11 function XStringToKeysym ulong {name string}
    X11 function XKeysymToString pointer.unsafe {keysym ulong}
    X11 function XKeysymToKeycode uchar {dpy pointer.unsafe keysym ulong}
    X11 function XkbKeycodeToKeysym ulong {dpy pointer.unsafe kc uchar group int level int}
    X11 function XRefreshKeyboardMapping int {ev pointer.unsafe}
    X11 function XQueryKeymap int {dpy pointer.unsafe keys pointer.unsafe}
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
set TK9WM_RESTART     [XInternAtom $dpy TK9WM_RESTART 0]
set WM_NAME           39   ;# XA_WM_NAME, predefined
set WM_CLIENT_MACHINE 36   ;# XA_WM_CLIENT_MACHINE, predefined
set WM_CLASS          67   ;# XA_WM_CLASS, predefined
catch { set NET_WM_PID [XInternAtom $dpy _NET_WM_PID 0] }

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
                # ICCCM 4.1.5: "If a client's ConfigureWindow request is
                # denied in whole or in part, the window manager must send
                # the client a synthetic ConfigureNotify". We deny every
                # position request (placement is ours) and used to answer
                # NOTHING — so a client that asked to move went on
                # believing it had moved, and put its menus, tooltips and
                # hit-testing at the position it had asked for. That is
                # the live "the app does not know where it is" report; it
                # is a moment we can name, unlike a timer. fvwm answers
                # every ConfigureRequest the same way (events.c,
                # _handle_cr_on_client).
                send-synthetic-configure $B
            } else {
                # Record only the size bits the mask actually declares:
                # a move-only request carries junk in w/h, and recording
                # that junk as "the size it wants" is how a window gets
                # framed at a size it never asked for.
                set gw 0; set gh 0
                if {[info exists ::geomof($B)]} { lassign $::geomof($B) gw gh }
                if {$vmask & (1 << 2)} { set gw $w }
                if {$vmask & (1 << 3)} { set gh $h }
                set ::geomof($B) [list $gw $gh]
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
        28 { # PropertyNotify (window@32 atom@40 = the generic A B): a
            # title change repaints the frame's titlebar; changed
            # WM_NORMAL_HINTS (XA_ predefined 40) are re-read
            if {[info exists ::managed($A)]} {
                if {$B == $::WM_NAME
                        || ([info exists ::NET_WM_NAME]
                            && $B == $::NET_WM_NAME)} {
                    refresh-title $A
                } elseif {$B == 40} {
                    read-normal-hints $A
                }
            }
        }
        33 { # ClientMessage. The restart knob arrives here: send-restart
            # addresses the wmcheck window, and a zero-mask XSendEvent is
            # delivered to the window's CREATOR — this connection.
            if {[info exists ::wmcheck] && $A == $::wmcheck
                    && $B == $::TK9WM_RESTART} {
                restart-wm
            }
        }
        2 { # KeyPress from our grabs (a top-chord XGrabKey, or the
            # sequence's temporary XGrabKeyboard). XKeyEvent (LP64):
            # time@56 state@80 keycode@84.
            binary scan [evbytes 96] iux4wuiux4wuwuwuwuwux16iuiu \
                _t _s _se _d win rootw subw time state kc
            if {$::has_keys} { handle-key $state $kc $time }
        }
        3 { # KeyRelease: only a keyboard-modal router cares (the
            # alt-tab commit-on-release); the keymap machine ignores
            # releases.
            if {$::has_keys && $::keyrouter ne ""} {
                binary scan [evbytes 96] iux4wuiux4wuwuwuwuwux16iuiu \
                    _t _s _se _d win rootw subw time state kc
                route-key release \
                    [keysym-name [XkbKeycodeToKeysym $::dpy $kc 0 0]] \
                    [expr {$state & ~(2 | 16)}]
            }
        }
        34 { # MappingNotify: request@40 — 2 (pointer) is not ours
            binary scan [evbytes 48] iux4wuiux4wuwuiu _t _s _se _d _w req
            if {$::has_keys && $req != 2} {
                catch {XRefreshKeyboardMapping $::evbuf}
                keys-remap
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

# The client's window title: _NET_WM_NAME (UTF8, the modern spelling)
# when present, else WM_NAME via XFetchName. Empty string = the client
# named nothing. WM_NAME is latin1/COMPOUND_TEXT territory — clients
# that care about non-ASCII set _NET_WM_NAME, so the lossy fallback is
# acceptable.
proc client-title {w} {
    if {$::has_getprop && [info exists ::NET_WM_NAME]
            && ![catch {XGetWindowProperty $::dpy $w $::NET_WM_NAME 0 256 0 \
                    $::UTF8 atype afmt nitems after data} status]
            && $status == 0} {   ;# Success
        set title ""
        if {$afmt == 8 && $nitems > 0 && ![cffi::pointer isnull $data]} {
            set title [encoding convertfrom utf-8 \
                [cffi::memory tobinary! $data $nitems]]
        }
        catch {XFree $data}
        if {$title ne ""} { return $title }
    }
    if {$::has_fetchname && ![catch {XFetchName $::dpy $w np} ok] && $ok
            && ![cffi::pointer isnull $np]} {
        set s [cffi::memory tostring! $np]
        catch {XFree $np}
        return $s
    }
    return ""
}

proc refresh-title {w} {
    set title [client-title $w]
    puts "WM: title 0x[format %x $w] -> «$title»"
    policy-title $w $title
}

# ---------------- client identity, for the policy's predicates ----------------
# Raw bytes of a format-8 property ("" when absent) and the first item
# of a format-32 one (0 when absent). AnyPropertyType: identity facts
# are STRING vs UTF8_STRING territory depending on the toolkit, and a
# predicate wants the value, not the type fight.
proc read-prop-bytes {w prop} {
    if {!$::has_getprop} { return "" }
    if {[catch {XGetWindowProperty $::dpy $w $prop 0 1024 0 0 \
            atype afmt nitems after data} status] || $status != 0} { return "" }
    set b ""
    if {$afmt == 8 && $nitems > 0 && ![cffi::pointer isnull $data]} {
        set b [cffi::memory tobinary! $data $nitems]
    }
    catch {XFree $data}
    return $b
}
proc read-prop-long {w prop} {
    if {!$::has_getprop} { return 0 }
    if {[catch {XGetWindowProperty $::dpy $w $prop 0 1 0 0 \
            atype afmt nitems after data} status] || $status != 0} { return 0 }
    set v 0
    if {$afmt == 32 && $nitems > 0 && ![cffi::pointer isnull $data]} {
        # format=32 property data arrives as C longs on LP64
        binary scan [cffi::memory tobinary! $data 8] wu v
    }
    catch {XFree $data}
    return $v
}

# WM_CLASS: {instance class}, {"" ""} when the client set none.
proc client-class {w} {
    set parts [split [string trimright [read-prop-bytes $w $::WM_CLASS] \x00] \x00]
    list [lindex $parts 0] [lindex $parts 1]
}

# WM_CLIENT_MACHINE, "" when unset.
proc client-machine {w} {
    string trimright [read-prop-bytes $w $::WM_CLIENT_MACHINE] \x00
}

# _NET_WM_PID, 0 when unset.
proc client-pid {w} {
    if {![info exists ::NET_WM_PID]} { return 0 }
    read-prop-long $w $::NET_WM_PID
}

# The client's command line as a Tcl list, honest only for LOCAL
# clients: _NET_WM_PID is meaningful on the machine named by
# WM_CLIENT_MACHINE, so a remote client (or one declaring nothing)
# yields {} and the predicate decides what that means. Hostnames are
# compared by first label, case-insensitively — one side often carries
# the FQDN.
proc client-cmdline {w} {
    set m [lindex [split [client-machine $w] .] 0]
    set h [lindex [split [info hostname] .] 0]
    if {$m eq "" || ![string equal -nocase $m $h]} { return {} }
    set pid [client-pid $w]
    if {$pid <= 0} { return {} }
    if {[catch {
        set f [open /proc/$pid/cmdline rb]
        set b [read $f]
        close $f
    }]} { return {} }
    split [string trimright $b \x00] \x00
}

# ICCCM WM_NORMAL_HINTS, the parts we honor: the client's declared
# MINIMUM size (PMinSize; per ICCCM a missing min falls back to
# PBaseSize) and its resize increments (PResizeInc, with PBaseSize —
# falling back to the minimum — as the increment origin). Read at
# manage and re-read on PropertyNotify — a client is free to change its
# hints while mapped. Whether the increments are respected or ignored
# is a per-client policy decision (the style machinery); the substrate
# only keeps the facts.
proc read-normal-hints {w} {
    set ::minof($w) {0 0}
    set ::incof($w) {0 0}
    set ::baseof($w) {0 0}
    if {!$::has_normalhints} return
    set buf [cffi::memory allocate 96 unsafe]
    if {![catch {XGetWMNormalHints $::dpy $w $buf supplied} ok] && $ok} {
        # XSizeHints (LP64): flags@0; x y width height min_w min_h max_w
        # max_h width_inc height_inc — ints @8..47; aspect pairs @48..63;
        # base_width base_height win_gravity @64..75
        binary scan [cffi::memory tobinary! $buf 80] wuiiiiiiiiiix16iii \
            flags hx hy hw hh minw minh maxw maxh winc hinc basew baseh grav
        if {$flags & 16} {                       ;# PMinSize
            set ::minof($w) [list [expr {max($minw,0)}] [expr {max($minh,0)}]]
        } elseif {$flags & 256} {                ;# PBaseSize as min (ICCCM)
            set ::minof($w) [list [expr {max($basew,0)}] [expr {max($baseh,0)}]]
        }
        if {$flags & 64} {                       ;# PResizeInc
            set ::incof($w) [list [expr {max($winc,0)}] [expr {max($hinc,0)}]]
        }
        if {$flags & 256} {                      ;# PBaseSize as inc origin
            set ::baseof($w) [list [expr {max($basew,0)}] [expr {max($baseh,0)}]]
        } else {                                 ;# ICCCM: base defaults to min
            set ::baseof($w) $::minof($w)
        }
    }
    cffi::memory free $buf
}

# The declared minimum, {0 0} when the client declares nothing.
proc client-min-size {w} {
    if {[info exists ::minof($w)]} { return $::minof($w) }
    return {0 0}
}

# Everything a size decision needs: {minw minh incw inch basew baseh}.
# Zero increments = the client declared none.
proc client-size-hints {w} {
    set min {0 0}; set inc {0 0}; set base {0 0}
    if {[info exists ::minof($w)]}  { set min $::minof($w) }
    if {[info exists ::incof($w)]}  { set inc $::incof($w) }
    if {[info exists ::baseof($w)]} { set base $::baseof($w) }
    concat $min $inc $base
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
    # How big does this window want to be? The truth is its CURRENT
    # geometry: a client that created its window at the right size and
    # mapped it never sends a ConfigureRequest, and the old code framed
    # it at the 200x120 default (kitty arrived ultra-miniature). The
    # recorded ConfigureRequest sizes are only the fallback for a server
    # without XGetGeometry.
    set cw 200; set ch 120
    if {[info exists ::geomof($w)]} {
        lassign $::geomof($w) cw ch
        if {$cw <= 0} { set cw 200 }
        if {$ch <= 0} { set ch 120 }
    }
    set aw 0; set ah 0
    if {$::has_geometry
            && ![catch {XGetGeometry $::dpy $w rr gx gy gw gh gbw gd}]} {
        set cw $gw; set ch $gh
        set aw $gw; set ah $gh    ;# actual size, to skip a no-op resize
    }
    read-normal-hints $w
    # A window wider/taller than the screen leaves its far edge (emacs:
    # the right one) unreachable — shrink it to what fits, but never
    # below its declared minimum: a window that says "no smaller than
    # this" keeps its size and placement pins it at the top-left instead.
    lassign [client-min-size $w] minw minh
    lassign [policy-max-client-size] maxw maxh
    set cw [expr {max(min($cw, $maxw), $minw, 1)}]
    set ch [expr {max(min($ch, $maxh), $minh, 1)}]
    set ::geomof($w) [list $cw $ch]
    set slot [policy-attach $w $cw $ch]
    set ::managed($w) 1
    # StructureNotify (Destroy/Unmap) + FocusChange (honest highlight even
    # when focus moves behind our back) + PropertyChange (live titles)
    XSelectInput $dpy $w [expr {(1 << 17) | (1 << 21) | (1 << 22)}]
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
    if {$cw != $aw || $ch != $ah} { XResizeWindow $dpy $w $cw $ch }
    XMapWindow $dpy $w
    set-wm-state $w 1          ;# NormalState — ICCCM, see set-wm-state
    XSync $dpy 0
    puts "WM: managed 0x[format %x $w]: slot [format 0x%x $slot] client ${cw}x${ch}"
    refresh-title $w
    policy-managed $w
    tell-where-you-are $w
}

# ICCCM 4.1.5 says WHAT to send; it does not say a client will be in a
# state to believe it. Live case (smsrc, a Tk app under Wine, 2026-07-27):
# the app kept a false idea of its position right after being framed —
# clicks missed, menus, tooltips and combo dropdowns landed offset — and
# the first title-bar drag repaired it. Sending the very same event by
# hand from outside repaired it too, which pins the cause: the CONTENT
# was right, the MOMENT was wrong.
#
# The moments, all event-driven and all named: here (the window is where
# we put it), on the client's MapNotify, on every ConfigureRequest we
# answer (see the dispatcher), and on every frame move. Timed repeats
# were tried while these were incomplete and are gone — see the note at
# the top of this file.
proc tell-where-you-are {w} {
    send-synthetic-configure $w
}

proc unmanage {w {dead 0}} {
    if {![info exists ::managed($w)]} return
    # Decide the refocus candidate BEFORE the teardown: the policy's pick
    # rests on facts it keeps per-frame (the dialog's leader, the focus
    # history) and policy-detach cleans those up.
    set refocus [policy-pick-refocus $w]
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
    unset -nocomplain ::minof($w) ::incof($w) ::baseof($w)
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
        if {$refocus != 0} { focus-to $refocus }
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
    puts "WM: resize 0x[format %x $win] -> ${cw}x${ch}, frame follows"
    # the synthetic ConfigureNotify is sent by the ConfigureRequest
    # handler for EVERY request, granted or not — see there
}

# A WM-initiated resize (border/corner drag): the same dance as a
# granted ConfigureRequest — decoration follows, client resized, client
# told where/how big it is — but the size decision is the WM's own.
proc wm-resize-client {w cw ch} {
    if {![info exists ::managed($w)]} return
    # The client's declared minimum binds every WM-initiated resize; the
    # client's OWN requests (resize-client above) are its business.
    lassign [client-min-size $w] minw minh
    set cw [expr {max($cw, $minw)}]; set ch [expr {max($ch, $minh)}]
    if {$::geomof($w) eq [list $cw $ch]} return
    set ::geomof($w) [list $cw $ch]
    policy-resize $w $cw $ch
    XResizeWindow $::dpy $w $cw $ch
    XSync $::dpy 0
    puts "WM: wm-resize 0x[format %x $w] -> ${cw}x${ch}"
    send-synthetic-configure $w
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

# The unconditional kill — the ops menu's "destroy" for a client that
# ignores the polite path above.
proc kill-client {w} {
    puts "WM: destroy 0x[format %x $w]: XKillClient"
    XKillClient $::dpy $w
    XSync $::dpy 0
}

# ---------------- key bindings: grabs + a stumpwm-style sequence machine ----------------
# wm-bind SPEC SCRIPT binds a chord SEQUENCE to a script. A chord is
# any number of <Mod> prefixes and then a keysym name:
#   wm-bind {<Alt>space}   winmenu
#   wm-bind {<Super>t w m} winmenu
# Only the FIRST chord of a sequence is grabbed globally (XGrabKey on
# root); the tail is collected stumpwm-style under a TEMPORARY
# XGrabKeyboard, so the global-hotkey namespace spends one combination
# per prefix and everything behind it stays available to applications.
# Esc or an unbound chord aborts the sequence. Later binds win — the
# config overrides the in-code defaults by simply binding over them.
# No prefix-in-progress indication in v1. The KeyPress events of both
# grab kinds arrive on this raw connection, in the same handle-event
# dispatcher as everything else.

set keymap {}       ;# nested dict: "mods,keysym" -> {action script} | {map submap}
set grabbed_top {}  ;# top chords held by XGrabKey — the MappingNotify re-grab list
set keyseq ""       ;# "" = idle; else the submap we are inside, keyboard grabbed
set kbd_grabbed 0
set keyrouter ""    ;# non-empty: a keyboard-modal UI owns every key event
set key_invoke_mods 0  ;# modifiers of the chord that fired the running action

# Modifier names a chord may use. A static table: Alt is Mod1 and Super
# is Mod4 on any stock map; a layout where that lies wants a dynamic
# XGetModifierMapping walk, which can come when such a layout shows up.
array set modmaskof {
    Shift 1 Control 4 Ctrl 4 Alt 8 Meta 8 Mod1 8
    Mod2 16 Mod3 32 Super 64 Mod4 64 Mod5 128
}
# Which keysyms sit on which modifier bit — for modifier-held below.
# Static like modmaskof; a dynamic XGetModifierMapping walk can come
# when a layout that lies about these shows up.
array set modkeysyms {
    1 {Shift_L Shift_R} 4 {Control_L Control_R}
    8 {Alt_L Alt_R Meta_L Meta_R} 64 {Super_L Super_R Hyper_L Hyper_R}
}
# Keysyms of the modifier keys themselves: pressing one during a
# sequence is not a chord — wait for the real key.
if {$has_keys} {
    foreach name {Shift_L Shift_R Control_L Control_R Alt_L Alt_R
            Meta_L Meta_R Super_L Super_R Hyper_L Hyper_R
            Caps_Lock Shift_Lock Num_Lock Scroll_Lock
            Mode_switch ISO_Level3_Shift ISO_Level5_Shift} {
        if {[set ks [XStringToKeysym $name]] != 0} { set ismodks($ks) 1 }
    }
    set KS_ESC [XStringToKeysym Escape]
} else { puts "WM: key machinery not available in this libX11" }

proc parse-chord {tok} {
    set mods 0
    while {[regexp {^<([^>]+)>(.*)$} $tok -> m rest]} {
        if {![info exists ::modmaskof($m)]} { error "unknown modifier <$m>" }
        set mods [expr {$mods | $::modmaskof($m)}]
        set tok $rest
    }
    if {$tok eq ""} { error "chord without a key" }
    set ks [XStringToKeysym $tok]
    if {$ks == 0} { error "unknown keysym «$tok»" }
    list $mods $ks
}

proc keysym-name {ks} {
    if {![catch {XKeysymToString $ks} p] && ![cffi::pointer isnull $p]} {
        return [cffi::memory tostring! $p]
    }
    format 0x%x $ks
}
proc chord-name {mods ks} {
    set parts {}
    foreach {name bit} {Ctrl 4 Alt 8 Super 64 Mod3 32 Mod5 128 Shift 1} {
        if {$mods & $bit} { lappend parts $name }
    }
    lappend parts [keysym-name $ks]
    join $parts +
}

# Set a key path in a nested keymap dict. A later bind REPLACES what
# was there: an action shadowing a former prefix map drops the whole
# map, and a longer sequence turns a former action into a prefix.
proc keymap-set {node keys script} {
    set k [lindex $keys 0]
    if {[llength $keys] == 1} {
        dict set node $k [list action $script]
    } else {
        set sub {}
        if {[dict exists $node $k]
                && [lindex [dict get $node $k] 0] eq "map"} {
            set sub [lindex [dict get $node $k] 1]
        }
        dict set node $k [list map [keymap-set $sub [lrange $keys 1 end] $script]]
    }
    return $node
}

proc wm-bind {spec script} {
    if {!$::has_keys} { puts "WM: wm-bind: no key machinery"; return }
    set chords [lmap tok $spec {parse-chord $tok}]
    if {![llength $chords]} { error "wm-bind: empty chord sequence" }
    set ::keymap [keymap-set $::keymap [lmap c $chords {join $c ,}] $script]
    set top [lindex $chords 0]
    if {$top ni $::grabbed_top} {
        lappend ::grabbed_top $top
        grab-chord $top
        puts "WM: key top chord [chord-name {*}$top] grabbed"
    }
}

# The quadruple: an X grab matches the modifier state EXACTLY, so every
# chord is grabbed four times over — plain, +Lock (Caps), +Mod2 (Num),
# +both — and the same lock bits are stripped from the state before a
# chord lookup. GrabModeAsync both ways: nothing to freeze, unlike the
# click-to-focus button grab.
proc grab-chord {chord} {
    lassign $chord mods ks
    set kc [XKeysymToKeycode $::dpy $ks]
    if {$kc == 0} {
        puts "WM: no keycode for [keysym-name $ks] — chord not grabbed"
        return
    }
    foreach locks {0 2 16 18} {
        XGrabKey $::dpy $kc [expr {$mods | $locks}] $::root 0 1 1
    }
    XSync $::dpy 0
}

# Keycodes moved under us (setxkbmap and friends): refresh Xlib's
# keysym cache and re-grab every top chord at its new keycode.
proc keys-remap {} {
    XUngrabKey $::dpy 0 32768 $::root      ;# AnyKey, AnyModifier
    foreach chord $::grabbed_top { grab-chord $chord }
    puts "WM: keyboard remapped — [llength $::grabbed_top] top chords re-grabbed"
}

proc keyseq-end {} {
    if {$::kbd_grabbed} {
        XUngrabKeyboard $::dpy 0
        XSync $::dpy 0
        set ::kbd_grabbed 0
    }
    set ::keyseq ""
}
proc keyseq-abort {why} {
    puts "WM: key sequence abort ($why)"
    keyseq-end
}

# Keyboard-modal UI (the menus): hold the keyboard on the raw
# connection and route every key event to cmd, called with press or
# release, the keysym name and the (lock-stripped) modifier mask —
# releases included, and modifier keys unfiltered: the alt-tab commit
# rides on the release of a bare modifier. The Tk focus path is no use
# here: such UI lives in override-redirect toplevels, and Tk refuses
# to XSetInputFocus those (tkUnixFocus.c, an old olvwm-menus hack) —
# Tk's own menus run on grabs for the same reason. An empty cmd
# releases the keyboard and hands keypresses back to the keymap.
proc grab-keys-to {cmd} {
    if {$cmd eq ""} {
        set ::keyrouter ""
        keyseq-end
        return 1
    }
    if {!$::has_keys} { return 0 }
    if {!$::kbd_grabbed} {
        set st [XGrabKeyboard $::dpy $::root 0 1 1 0]
        if {$st != 0} {
            puts "WM: grab-keys-to: XGrabKeyboard refused ($st)"
            return 0
        }
        set ::kbd_grabbed 1
    }
    set ::keyseq ""      ;# the router replaces any sequence in progress
    set ::keyrouter $cmd
    return 1
}
proc route-key {kind name mods} {
    if {[catch {uplevel #0 [list {*}$::keyrouter $kind $name $mods]} err]} {
        puts "WM: key router error: $err"
    }
}

# Is any key of the given modifier mask physically down right now? The
# fvwm alt-tab semantics hinge on "was Alt still held when the list
# opened" and "is it still held after this release" — and a KeyRelease
# that happened before our grab began is something we never saw, so
# the server's live keymap is the only honest answer.
proc modifier-held {mask} {
    if {!$::has_keys} { return 0 }
    set names {}
    foreach {bit syms} [array get ::modkeysyms] {
        if {$mask & $bit} { lappend names {*}$syms }
    }
    if {![llength $names]} { return 0 }
    set buf [cffi::memory allocate 32 unsafe]
    set held 0
    if {![catch {XQueryKeymap $::dpy $buf}]} {
        set v [cffi::memory tobinary! $buf 32]
        foreach n $names {
            set ks [XStringToKeysym $n]
            if {$ks == 0} continue
            set kc [XKeysymToKeycode $::dpy $ks]
            if {$kc == 0} continue
            binary scan $v "x[expr {$kc / 8}]cu" byte
            if {$byte & (1 << ($kc % 8))} { set held 1; break }
        }
    }
    cffi::memory free $buf
    return $held
}

# One KeyPress from our grabs walks the keymap: idle state consults the
# top map (the press came through a top-chord XGrabKey), a sequence in
# progress consults its current submap (the press came through the
# temporary XGrabKeyboard). An unbound press aborts a sequence but is
# ignored in idle state — a stale grab echo is not an error.
proc handle-key {state kc time} {
    set ks [XkbKeycodeToKeysym $::dpy $kc 0 0]
    set mods [expr {$state & ~(2 | 16)}]   ;# Caps/Num make no chord distinct
    if {$::keyrouter ne ""} {
        route-key press [keysym-name $ks] $mods
        return
    }
    if {[info exists ::ismodks($ks)]} return
    if {$::keyseq ne ""} {
        if {$ks == $::KS_ESC} { keyseq-abort Esc; return }
        set node $::keyseq
    } else {
        set node $::keymap
    }
    set k "$mods,$ks"
    if {![dict exists $node $k]} {
        if {$::keyseq ne ""} { keyseq-abort "[chord-name $mods $ks] unbound" }
        return
    }
    lassign [dict get $node $k] kind payload
    if {$kind eq "action"} {
        # release the keyboard BEFORE the action: it may want focus.
        # The chord's own modifiers are published for the action: the
        # window list reads them to decide "am I an alt-tab cycle".
        keyseq-end
        puts "WM: key [chord-name $mods $ks] -> action"
        set ::key_invoke_mods $mods
        if {[catch {uplevel #0 $payload} err]} {
            puts "WM: key action error: $err"
        }
    } else {
        if {$::keyseq eq ""} {
            set st [XGrabKeyboard $::dpy $::root 0 1 1 $time]
            if {$st != 0} {
                puts "WM: key [chord-name $mods $ks]: XGrabKeyboard refused ($st) — sequence dropped"
                return
            }
            set ::kbd_grabbed 1
        }
        puts "WM: key [chord-name $mods $ks] -> prefix"
        set ::keyseq $payload
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
    cffi::memory free $ev
    # And a copy addressed to the DECORATION window. fvwm carries the same
    # workaround (events.c, send_for_frame_too): "for buggy tk, which waits
    # for the real ConfigureNotify on frame instead of the synthetic one on
    # w". A client is free to watch its frame for StructureNotify, and a
    # frame that never moves never produces one — which is why dragging a
    # window has been repairing such clients. Unlike fvwm we put the
    # FRAME's own true geometry in it: our frames are Tk widgets and our
    # own Tk hears this event too, so it must not be lied to.
    if {[llength [set fg [policy-frame-geometry $w]]] == 5} {
        lassign $fg fwin fx fy fw fh
        set fb [binary format iux4wuiux4wuwuwuiiiiix4wuiu \
            22 0 1 0 $fwin $fwin $fx $fy $fw $fh 0 0 0]
        set fev [cffi::memory frombinary [binary format a192 $fb] unsafe]
        XSendEvent $::dpy $fwin 0 131072 $fev
        cffi::memory free $fev
    }
    XFlush $::dpy   ;# no cffi roundtrip follows during a Tk-side drag
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

# Restart in place — the way to pick up freshly pulled sources: release
# every client back to root (orderly, as in exit), then REPLACE this
# process with a fresh copy of itself via execv. Same pid, same stdout,
# fresh code from disk; the X sockets are close-on-exec, so the server
# reaps the old frames itself, and the new WM adopts the released
# clients at startup — adoption is exactly "windows that lived before
# the WM". Tcl has no exec-replacement of its own, so libc's execv is
# one more cffi call.
proc restart-wm {} {
    puts "WM: restart requested — releasing clients, exec'ing myself"
    catch { foreach w [array names ::managed] { unmanage $w } }
    catch { XSync $::dpy 0 }
    set exe [info nameofexecutable]
    if {[catch {
        cffi::Wrapper create LCX libc.so.6
        LCX function execv int {path string argv pointer.unsafe}
        # char *argv[] on LP64: NUL-terminated copies of the strings,
        # their addresses packed as an array with a NULL sentinel
        set addrs ""
        foreach a [list $exe $::argv0 {*}$::argv] {
            set p [cffi::memory frombinary \
                "[encoding convertto utf-8 $a]\x00" unsafe]
            append addrs [binary format wu [cffi::pointer address $p]]
        }
        append addrs [binary format wu 0]
        set argvp [cffi::memory frombinary $addrs unsafe]
        execv $exe $argvp
        error "execv returned: [expr {[info exists ::errorCode] ? $::errorCode : "?"}]"
    } err]} { puts "WM: restart FAILED: $err" }
}

# To be called by the assembly once the policy layer is in: start draining
# (the first drain arms the worker; a single token from here on) and adopt
# whatever was already on the screen.
proc substrate-start {} {
    puts "WM: pump: X fd $::xfd watched by worker thread (blocking poll, ping-pong)"
    after idle drain
    adopt-existing
}
