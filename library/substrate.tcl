# tk9wm substrate — the mechanism layer: everything a WM cannot exist
# without, with zero look-and-feel decisions in it.
#
# One interpreter, ONE X connection: Tk's own. The tkwmx shim — this
# project's own C extension, generic/tkwmx.c — does on that connection
# the three things no script can reach — hold SubstructureRedirect,
# speak the WM half of X, and hand the redirect events to Tk's own
# event loop as dicts. Requests and events therefore share one stream,
# which is what makes the ordering questions ("has the server seen it
# yet?") answerable at all.
#
# It was two connections until the swap: a raw Xlib one over cffi, its
# fd watched by a worker thread blocked in poll(), pinging the main
# thread to drain XPending. That cost a class of ordering bugs, 38
# places decoding structs by LP64 offset — and it could not be done by
# halves, because in X every kind of OWNERSHIP is per-connection: a
# grab belongs to whoever grabbed, so does a select-input, and a sync
# on one connection says nothing about the other.
#
# Sourcing this file loads Tk and the shim, installs the X error sink,
# TAKES THE DESK and arms the dispatcher.  Call substrate-start AFTER
# the policy layer is loaded: it starts dispatching events (whatever
# arrived before is replayed, not lost) and adopts pre-existing windows.
#
# Taking the desk means both halves of it (see "becoming the window
# manager"): the redirect, and the ICCCM manager selection WM_S<screen>
# that makes a manager REPLACEABLE. `-replace` on the command line (or
# ::tk9wm_replace set before the require) asks whoever holds the desk
# to stand down and waits for it; without it, a desk that is taken is a
# refusal. The other direction needs no flag at all — asked to stand
# down, we exit, and exit already hands every client back alive.
#
# The policy layer must implement these hooks (called by the substrate):
#   policy-attach w cw ch   build a decoration for client w (client area
#                           cw x ch), decide placement, and return the X
#                           window id of the slot to reparent w into; must
#                           return only after the slot exists server-side
#   policy-initial-size w cw ch
#                           the client size w OPENS at, given the size it
#                           asked for: the policy clamps an oversized
#                           newcomer to what the screen holds, and a style
#                           may name a size (and a place) of its own
#   policy-detach w         destroy w's decoration
#   policy-origin w         root {x y} of w's client area (for synthetic
#                           ConfigureNotify and for parking a withdrawn
#                           client back on root)
#   policy-resize w cw ch   decoration follows w's new client size
#   policy-paint-focus w    repaint the focus highlight (w is focused)
#   policy-title w title    put the client's (new) title on the frame;
#                           empty string = the client named nothing
#   policy-client-press w state button x y
#                           first refusal on a press inside managed w
#                           (root coords, lock bits stripped from state):
#                           1 = the WM took the gesture and the client
#                           must NOT see the click, 0 = not ours
#   policy-client-click w   a click landed inside managed client w
#   policy-managed w        w was just managed (initial-focus decision)
#   policy-booked w         the model bookkeeping half of policy-managed
#                           (stack seat, layer, desk) — called instead of
#                           it, after the iconify, for a window managed
#                           INTO iconic; optional (guarded) hook
#   policy-pick-refocus w   choose a window to refocus after w's unmanage;
#                           called BEFORE policy-detach w (the pick may
#                           need per-frame facts that detach cleans up);
#                           return 0 for none
#   policy-transient w leader  WM_TRANSIENT_FOR changed on a managed
#                           window; leader freshly re-read (0 = cleared)
#   policy-move-request w x y vmask grav  a managed client with a
#                           declared position claim asked to move; x/y
#                           valid per vmask bits (CWX=1, CWY=2), grav
#                           says what the point aims at (see
#                           client-position-hint)
#   policy-moveresize-request w X Y dir button
#                           a client asks the WM to run a move or a
#                           resize it cannot run itself (EWMH
#                           _NET_WM_MOVERESIZE): X/Y is the root point
#                           it was pressed at, dir is the EWMH
#                           direction (0..7 the eight edges from
#                           top-left clockwise, 8 move, 9 keyboard
#                           resize, 10 keyboard move, 11 cancel), and
#                           button is the one held down (0 for the
#                           keyboard ones). The client has already
#                           ungrabbed the pointer
#   policy-close-unanswered w  a WM_DELETE_WINDOW went unanswered — the
#                           window is still managed after the grace
#                           period; show the user the client is silent
#   policy-minimize-request w  a client asked to be iconified (ICCCM
#                           WM_CHANGE_STATE). The policy DECIDES and
#                           must answer by calling iconify-client w or
#                           refuse-iconify w — ignoring the request is
#                           the one thing that must not happen
#   policy-iconified w      w just went iconic: take its decoration off
#                           the screen (the window stays managed)
#   policy-deiconified w    w is coming back: put the decoration up
#   policy-fullscreen w on  w entered (1) or left (0) EWMH fullscreen:
#                           on the way in, remember the geometry, drop
#                           the decoration and give the client the whole
#                           of ITS MONITOR — not the workarea, fullscreen
#                           covers the panel by definition — and let
#                           nothing of the policy's own stay stacked
#                           above it; on the way out, put back what was
#                           remembered
#   policy-screen-changed   the root changed size under us (RandR);
#                           anything glued to a screen edge re-places
#   policy-tray-attach w    build a slot for tray icon w and return
#                           {slot-window-id size} — the icon is held at
#                           size x size; {0 0} refuses it
#   policy-tray-detach w    the icon left: drop its slot
#   policy-tray-origin w    root {x y} of w's slot (for the synthetic
#                           ConfigureNotify an icon's resize request gets)
#   policy-workarea         {x y w h} of the screen minus whatever the
#                           policy reserves (panel, tray) — published as
#                           EWMH _NET_WORKAREA (one rect: the protocol
#                           predates multihead)
#   policy-workareas        the full per-monitor picture: name ->
#                           {primary 0|1 mon RECT wa RECT}. THIS is
#                           what the substrate watches for change — a
#                           monitor can move under an unchanged
#                           _NET_WORKAREA
#   policy-workarea-changed old new  that picture is not what it was:
#                           both per-monitor dicts, before and after.
#                           Whatever the policy glued to a workarea
#                           edge re-glues — its own furniture is
#                           placed by then, so this is about the
#                           CLIENTS
#   policy-key-echo kind text  a chord sequence has something to say
#                           about itself: `keys` + the chords typed so
#                           far (a sequence is running and the keyboard
#                           is ours), `flash` + a line about a press
#                           that ended it, `none` (nothing is running,
#                           take it down). What that LOOKS like is the
#                           policy's; the substrate only knows when
#                           there is something to say
#
# The substrate provides to the policy layer:
#   focus-to w                  aim the input focus at w. For an ordinary
#                               client that means setting it and believing
#                               the server; for a globally active one
#                               (Wine 10+) it means inviting the client to
#                               take it and touching nothing — so a return
#                               of 1 means "asked", not "done". The
#                               highlight follows the CONFIRMED focus (see
#                               the focus core), never the request
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
#   client-stacking             every managed window, bottom first —
#                               THE POLICY'S word (the model speaks,
#                               the server agrees); the substrate only
#                               publishes it and releases the desk by it
#   kill-client w               unconditional XKillClient (close-client
#                               asks politely first)
#   close-client w              WM_DELETE_WINDOW when supported, else kill
#   send-synthetic-configure w  ICCCM 4.1.5 notify after a frame move
#   wm-resize-client w cw ch    a WM-initiated resize (border/corner drag);
#                               clamps to the client's declared minimum
#   client-min-size w           declared WM_NORMAL_HINTS minimum, {0 0} = none
#   client-size-hints w         {minw minh incw inch basew baseh maxw maxh};
#                               zero increments = none declared, zero
#                               max = unbounded
#   client-fixed-size-p w       min == max on both axes: the client
#                               declared itself non-resizable
#   client-position-hint w      {none|user|program gravity}: does the
#                               client claim its own position
#                               (USPosition/PPosition), and which
#                               win_gravity interprets the point
#   client-initial-position w   root {x y} of the client window at
#                               manage time — the position half of
#                               "-geometry WxH+X+Y"; {} when unknown
#   client-class w              WM_CLASS as {instance class}, {"" ""} = none
#   client-machine w            WM_CLIENT_MACHINE, "" = none
#   client-command w            WM_COMMAND argv as a Tcl list, {} = none
#   client-pid w                _NET_WM_PID, 0 = none
#   client-cmdline w            argv of a LOCAL client as a Tcl list
#                               (via /proc), {} for remote/undeclared
#   iconify-client w            put w in IconicState for real: WM_STATE,
#                               _NET_WM_STATE_HIDDEN, the client unmapped,
#                               the focus moved on. Stays MANAGED
#   deiconify-client w          bring an iconic w back and focus it
#   refuse-iconify w            answer an iconify request with a NO the
#                               client can act on (see the proc)
#   fullscreen-client w         put w in EWMH fullscreen (the same state
#                               a client asks for with _NET_WM_STATE):
#                               the policy re-lays the frame, the
#                               property is republished
#   unfullscreen-client w       ...and take it back out
#   $::iconic(w)                set while w is iconic (array member
#                               absent otherwise)
#   $::fullscreen(w)            set while w is fullscreen (likewise) —
#                               the policy reads it to keep its own
#                               furniture from stacking over such a window
#   $::focused                  currently focused client (0 = none)

package require Tk
# The shim, either way it was delivered: a shared libtkwmx.so built in
# this checkout (or installed as a package), or the static archive
# baked into the interpreter as a battery. Both answer to the same
# `package require` — see pkgIndex.tcl at the tree root.
package require tkwmx
wm withdraw .   ;# our own real toplevel is no client of ours

# NO INPUT METHOD, EVER — a window manager cannot afford to be one's
# hostage, and this is not a precaution: it is a post-mortem (the
# owner's desk, 2026-07-30).
#
# Tk creates an XIC lazily for EVERY window that sees an event — our
# frames, titlebars, panel, menus, the compass, all of them — and
# Tk_DestroyWindow then calls XDestroyIC, which is a SYNCHRONOUS round
# trip to the XIM server (generic/tkWindow.c, generic/tkEvent.c). Kill
# the XIM server on a running desk and the next `destroy` of any Tk
# window of ours blocks in XIfEvent → poll(-1) waiting for a reply
# nobody will ever send — INSIDE the X event handler. The whole desk
# stops: the event loop reads X events and dispatches none of them, no
# window is framed, no chord fires, nothing is logged, and the process
# looks perfectly healthy in ps. It took a backtrace to see, since
# there is no error anywhere: XDestroyIC under Tk_DestroyWindow under
# our own dispatcher.
#
# The trigger was ordinary: the owner swapped his input method
# (uim-xim killed, another to take its place). Restarting an input
# method is a thing people do, and a desk that dies of it is the
# desk's bug, not theirs.
#
# The cost of switching it off is ZERO here. Nothing in this window
# manager accepts typed text — a titlebar, a menu, a panel button and
# a compass cell are all display-only, and every key we care about
# comes through our own grabs, decoded from keycodes by hand (see
# handle-key), never through Tk's IM-composed translation. A GUI that
# WOULD want an input method belongs on the far side of the line drawn
# in wm-window: its own thread, its own connection, its own Tk.
#
# It must be off before any window sees its first event, since that is
# when the context would be created — so it is here, three lines after
# Tk itself.
tk useinputmethods 0

# ---------------- definitions, and the setup they are not ------------
#
# SOURCING EITHER LAYER AGAIN, ON A LIVE DESK, MUST ONLY REDEFINE ITS
# PROCS. That is the development loop the owner wants (2026-07-30):
# edit, press a key, and the running window manager is the new code
# with every client, frame, grab and mode where it was — no restart,
# no logging out of the session the desk IS.
#
# A file that is sourced twice does everything twice, and a window
# manager's file is mostly things that must happen exactly once. The
# first re-source killed the desk outright at the third statement:
# desk-take saw WM_S0 already owned — by our OWN owner window — and
# concluded that another window manager had the desk. Behind that
# waited a second focus holder, a second EWMH check window, an ::exit
# renamed onto itself (an infinite recursion on the way out), a frame
# counter back at 1 colliding with .f1, and — the symptom the owner
# actually reported — a keymap and a grab list wiped while the server
# went on holding the grabs.
#
# So the file says which of the three each statement is:
#
#   proc          a definition. Re-sourcing REPLACES it; that is the point.
#   set / array   a CONSTANT. Re-sourcing re-establishes it, so editing
#                 one and re-sourcing shows the edit.
#   keep          STATE the desk carries — including every knob a config
#                 may have turned. Set on the first load, left alone
#                 afterwards; the running desk keeps what it has.
#   unless-already  a setup step with a side effect out in the world (a
#                 window created, a selection taken, a command renamed).
#                 It asks whether that effect is ALREADY THERE — is the
#                 selection ours, does the font exist — and skips if it
#                 is. Deliberately not a registry of what this process
#                 remembers doing: a registry is empty in a process that
#                 predates this rule, and the first re-source into one
#                 of those would take the desk apart in exactly the way
#                 the rule exists to prevent. The world remembers; we
#                 ask it.
#
# What this CANNOT be is reliable, and it is not meant to be: a proc
# that has gone away stays, a variable whose SHAPE changed keeps the
# old shape, the snapshot of config defaults stays as first taken, and
# a half-finished edit makes a half-finished desk. It is a development
# affordance with an honest edge, not a hot-patch facility.
proc keep {name value} {
    if {![uplevel #0 [list info exists $name]]} {
        uplevel #0 [list set $name $value]
    }
}
proc unless-already {test script} {
    if {[uplevel #0 [list expr $test]]} return
    uplevel #0 $script
}

# ---- a script that may PARK, and a desk that keeps answering ------
# The scripts a config writes — a binding, a launch, an activate hook
# — ran straight in the event loop, so anything synchronous inside
# them stopped the desk dead: the owner bound `exec xedit` and the
# whole desk waited for the editor to be closed (2026-08-02). They run
# in a coroutine of their own now, which is the whole of what makes
# the cooperative `exec` able to park. A script that never parks
# behaves exactly as it did, at the cost of one coroutine.
#
# PARALLEL BY DEFAULT (the owner's answer, same day): every run gets a
# coroutine of its own, so the same chord pressed again while the
# first run is still parked simply starts a second one. Waiting for
# the window, or for the process — the debounce — is something an
# ACTION may come to declare for itself; it is not a rule to impose on
# every script.
#
# The error lands where it always did: in the problem store, under the
# name of whatever ran. That holds after a park too — the catch is
# inside the coroutine, so a failure on the far side of a yield is
# still this script's failure and not the event loop's.
keep script_seq 0
proc run-script {what script} {
    coroutine ::script[incr ::script_seq] apply {{what script} {
        if {[catch {uplevel #0 $script} err opts]} {
            # A CANCELLED WAIT IS NOT A PROBLEM: the person pressed
            # Escape on an ask, a newer ask displaced it, a reload
            # swept the world — the script stopping there is the
            # designed outcome, and recording it as a problem (echo
            # flash and all) made every deliberate cancel nag (the
            # owner's expectation, 2026-08-05: «всё отменяется»).
            # Said calmly in the log, and no further.
            if {[lrange [dict getdef $opts -errorcode {}] 0 1] \
                    eq {FUT CANCELLED}} {
                puts "WM: $what: cancelled — $err"
            } else {
                problem-record $what $err
            }
        }
    }} $what $script
}

# Line buffering FIRST, before anything can have something to say. It
# used to be set where the redirect was armed, which was fine while
# every message before that point was a fatal one on its way to a
# terminal — and wrong the moment a manager could refuse to start with
# stdout redirected to a file: the explanation sat in an unflushed
# buffer and died with the process (measured, run-replace-test.sh).
chan configure stdout -buffering line

# ---------------- soft failures: survived, but never silent ----------------
# A WM has to outlive the errors its clients hand it — a window dies
# mid-request, a property read races the client's exit — so a good
# many calls in this file are wrapped so a failure cannot take the WM
# down. What such a wrapper must NOT do is hide the failure: a bare
# `catch {XFree $data}` looked like sound hygiene for months while the
# call inside it threw on EVERY invocation (the pointer-tag bug,
# ce99c12) and nothing ever said a word.
#
# `soft LABEL SCRIPT ?DEFAULT?` is that catch with a voice. The script
# runs in the CALLER's scope, so out-parameters and `lassign` still
# land where they should; a failure logs one line and yields DEFAULT.
# Repeats of the same (label, message) collapse into a count — a
# per-event failure must not flood the log, the same discipline the X
# error handler keeps for its bursts.
array set soft_n {}
proc soft {label script {default ""}} {
    if {![catch {uplevel 1 $script} res]} { return $res }
    soft-log $label $res
    return $default
}

# An error that escaped to the event loop anyway — a bind script, an
# `after`, anything we did not wrap — gets the same treatment, and for
# a sharper reason than tidiness. Tk's answer to one is a DIALOG, and
# for a window manager that is wrong twice: it is a window we would
# have to manage at the exact moment we are demonstrably confused, and
# what reaches the user is a Tcl stack trace they can neither act on
# nor stop from happening again. (Owner's report, 2026-07-29: the close
# button on the WM's own confirmation dialog threw, and what he got was
# a bgerror box on top of the desk.)
#
# So: the log, with the traceback — which is strictly more than the
# dialog offered, since the log is where everything else about this WM
# already is. Defined rather than registered through `interp bgerror`
# because Tk's own handler is AUTOLOADED on first use: a ::bgerror that
# exists is a ::bgerror that wins.
proc ::bgerror {msg} {
    if {![soft-log "background error" $msg]} return
    if {[info exists ::errorInfo] && $::errorInfo ne ""} {
        foreach line [split [string trimright $::errorInfo] \n] {
            puts "WM:   | $line"
        }
    }
}
# Returns 1 when it actually PRINTED — a caller with more to say (the
# background-error handler and its traceback) must not say it on the
# repeats this collapses.
proc soft-log {label msg} {
    set key $label\n$msg
    if {![info exists ::soft_n($key)]} {
        set ::soft_n($key) 1
        puts "WM: soft failure — $label: $msg"
        return 1
    }
    set n [incr ::soft_n($key)]
    # 10th, 100th, then every thousandth: enough to show a failure is
    # relentless, quiet enough to keep the log readable
    if {$n == 10 || $n == 100 || ($n > 100 && $n % 1000 == 0)} {
        puts "WM: soft failure (x$n) — $label: $msg"
        return 1
    }
    return 0
}

# Our log is UTF-8, whatever locale the session hands us. Client titles
# go into it verbatim, and a title is any script on earth: with stdout
# left on a C-locale (ascii) encoding, the first Cyrillic one makes
# `puts` THROW — inside an event handler, before the title ever reaches
# the frame. The log is ours to define, so define it.
foreach ch {stdout stderr} {
    soft "log encoding ($ch)" {chan configure $ch -encoding utf-8 -profile replace}
}

# (There is no quirks switch any more. It existed to hold timed repeats of
# the synthetic ConfigureNotify while we did not know the right moment to
# send one; running with it OFF proved the moments were missing, reading
# fvwm named them — answer every ConfigureRequest, and copy the notify to
# the frame — and with those in place the live case was fixed with no
# timers at all. A switch with nothing behind it only rots.)

# ---------------- the X transport layer ----------------
# Every X call the substrate makes goes through this section and
# nothing else does. Each proc is now one tkwmx call; until the swap
# each was one cffi call on a second connection, and this layer is
# what made that swap a rewrite of THIRTY-ODD BODIES instead of a
# rewrite of the file — the whole point of it existing.
#
# The rules the signatures follow are the shim's: no pointer ever
# crosses this boundary, out-parameters come back as VALUES (a list or
# a dict, {} for "the server would not say"), event masks are named
# and not numbered, and the display is implicit — the shim takes it
# from Tk's main window, which is the only connection there is now.
proc x-map {w}                  { tkwmx::window map $w }
proc x-unmap {w}                { tkwmx::window unmap $w }
proc x-reparent {w parent x y}  { tkwmx::window reparent $w $parent $x $y }
proc x-resize {w cw ch}         { tkwmx::window resize $w $cw $ch }
proc x-kill-client {w}          { tkwmx::window kill $w }
proc x-save-set-add {w}         { tkwmx::window saveset add $w }
proc x-sync {{discard 0}}       { tkwmx::server sync $discard }
proc x-flush {}                 { tkwmx::server flush }
proc x-intern {name}            { tkwmx::atom intern $name }
proc x-atom-name {id}           { tkwmx::atom name $id }
# A mask is a LIST OF NAMES here (see tkwmx::event masks). On a window
# of OUR OWN the shim adds them to what Tk selected instead of
# replacing it — the single-connection trap, spelled out there.
proc x-select-input {w masks}   { tkwmx::event select $w $masks }
# The answer to a ConfigureRequest, in the request's own terms: only
# the keys present are applied.
proc x-configure {w changes}    { tkwmx::window configure $w $changes }
# The attributes of a window we did not create: with a dict it sets
# them, without one it reads them ({} when the window is gone).
proc x-attrs {w {changes ""}} {
    if {$changes eq ""} { return [tkwmx::window attrs $w] }
    tkwmx::window attrs $w $changes
}
# Our own bare windows (the EWMH check window, the focus holder);
# -override for the ones no manager, ours included, should ever frame.
proc x-create-window {parent x y width height {override ""}} {
    tkwmx::window create $parent $x $y $width $height {*}$override
}
# Repaint a window from its background — the other half of setting one.
# -exposures asks the CLIENT to redraw too, which a foreign window
# needs: its own drawing is not ours to reproduce.
proc x-clear {w {exposures ""}} { tkwmx::window clear $w {*}$exposures }
proc x-allow-events {mode {time 0}} { tkwmx::grab allow $mode $time }
proc x-prop-set {w prop type fmt value {append 0}} {
    tkwmx::prop set $w $prop $type $fmt $value $append
}
# {type format value}, or {} when the property is absent
proc x-prop-get {w prop}        { tkwmx::prop get $w $prop }
# a text property in any encoding, decoded; "" when absent
proc x-prop-text {w prop}       { tkwmx::prop text $w $prop }
proc x-prop-class {w}           { tkwmx::prop class $w }
proc x-prop-hints {w}           { tkwmx::prop hints $w }
proc x-prop-normal-hints {w}    { tkwmx::prop normal-hints $w }
proc x-prop-protocols {w}       { tkwmx::prop protocols $w }
proc x-prop-transient {w}       { tkwmx::prop transient $w }
# RevertToParent is the substrate's only revert mode — see focus-to.
# 1 = the server took it, 0 = it refused.
proc x-focus-set {w {revert parent} {time 0}} { tkwmx::focus set $w $revert $time }
# {window revert-to}, or {} when the server would not say
proc x-focus-get {}             { tkwmx::focus get }
# Refuse Tk the events it claims the focus by — a WM's decorations must
# not take the keyboard for themselves (see the focus holder below).
proc x-focus-tame {on}          { tkwmx::focus tame-implicit $on }
# {x y width height border-width depth}, or {} — the window is gone
proc x-geometry {w}             { tkwmx::window geometry $w }
proc x-shot {w x y width height} { tkwmx::window shot $w $x $y $width $height }
# Raw monitor layouts, one per source — empty when the server has no
# such answer. Merging them (and trusting one) is the policy's call.
proc x-monitors-randr {}        { tkwmx::server monitors }
proc x-monitors-xinerama {}     { tkwmx::server xinerama }
# {root parent {children...}}, or {} — the window is gone
proc x-query-tree {w}           { tkwmx::window tree $w }
# kbdmode: async (default) or sync — sync freezes the press for the
# replay decision (keys-pass); the shim keeps both on purpose.
proc x-grab-key {keycode mods w {kbdmode async}} {
    tkwmx::grab key $keycode $mods $w $kbdmode
}
proc x-ungrab-key {keycode mods w} { tkwmx::grab ungrab-key $keycode $mods $w }
# 1 = the server gave the keyboard, 0 = someone else holds it
proc x-grab-keyboard {w {time 0} {kmode async}}  {
    tkwmx::grab keyboard $w $time $kmode
}
proc x-ungrab-keyboard {{time 0}}  { tkwmx::grab ungrab-keyboard $time }
# The cursor is the GRAB's, and that is the whole reason it is here: a
# drag over somebody else's window can show a drag cursor no other way
# (a client's own cursor is not ours to set, and un-setting it would
# not put back what was there). Named the way Tk names cursors; empty
# leaves the cursor alone.
proc x-grab-pointer {w masks {time 0} {cursor ""}} {
    tkwmx::grab pointer $w $masks $time $cursor
}
proc x-ungrab-pointer {{time 0}}   { tkwmx::grab ungrab-pointer $time }
proc x-grab-button {button mods w masks} {
    tkwmx::grab button $button $mods $w $masks
}
proc x-keysym {name}            { tkwmx::keyboard keysym $name }
proc x-keysym-name {ks}         { tkwmx::keyboard name $ks }
proc x-keycode {keysym}         { tkwmx::keyboard keycode $keysym }
proc x-keysym-at {kc {group 0} {level 0}} { tkwmx::keyboard at $kc $group $level }
proc x-key-autorepeat {onoff}   { tkwmx::keyboard autorepeat $onoff }
# The xkb GROUP, which decides the alphabet a keycode speaks. Read with
# no argument for {locked effective} — the two differ while a momentary
# switch is held — or give an index 0..3 to lock the keyboard into one.
#
# Deliberately not what a chord is looked up by (see handle-key: the
# map is asked for group 0 by hand, so a binding keeps its Latin name
# whatever is being typed). This is the other half of the subject: what
# a desk that wants to SHOW or CHOOSE the layout needs — a panel
# indicator, a key that switches it, per-window layouts. Nothing here
# uses it yet; the owner asked for the capability (2026-07-30).
proc x-group {args} { tkwmx::keyboard group {*}$args }
# which keys are physically down, as a 32-byte bit vector
proc x-keymap {}                { tkwmx::keyboard state }
# a ClientMessage with a verbatim payload — every protocol built on one.
# The send mask is empty by default, which means "to the window's own
# client" (WM_PROTOCOLS, _XEMBED); an announcement to the root instead
# names the mask its audience selected (the MANAGER message).
proc x-send-client {w type data {format 32} {masks {}}} {
    tkwmx::event client $w $type $data $format $masks
}
# The manager selections of ICCCM 2.8 — WM_S0, _NET_SYSTEM_TRAY_S0.
# own: 1 = the server agrees we hold it now; get: the owning window, 0
# for nobody.
proc x-selection-own {sel w time} { tkwmx::selection own $sel $w $time }
proc x-selection-get {sel}        { tkwmx::selection get $sel }
# the synthetic ConfigureNotify of ICCCM 4.1.5
proc x-send-configure {w target x y width height} {
    tkwmx::event configure-notify $w $target $x $y $width $height
}
# a fresh server timestamp — fetched, not guessed (see server-time)
proc x-server-time {w prop}     { tkwmx::server time $w $prop }
proc x-error-text {code}        { tkwmx::server error-text $code }
proc x-error-handler {cmd}      { tkwmx::server error-handler $cmd }
# replace this process with a fresh copy of itself (see restart-wm)
proc x-exec-self {path arglist} { tkwmx::exec-self $path $arglist }
# wait, without blocking, for the children a restart left us holding —
# the pids that are done come back (see adopt-orphans)
proc x-reap {pids} { tkwmx::reap {*}$pids }

# ---------------- the X error sink ----------------
# Xlib's default error handler exits the process; for a WM, BadWindow
# races with dying clients are routine — so: swallow and log.
#
# It used to take a trick to get here: our handler had to be installed
# BEFORE Tk loaded, so that Tk's own tkError.c would save it as its
# fallback. With the shim there is no trick left — `server
# error-handler` IS a Tk_ErrorHandler, so Tk's per-request traps sit
# closer to their calls and are consulted first (they consume the
# errors Tk expects, e.g. colormap walks over dying windows) and
# everything unclaimed arrives here.
keep xerr_last ""
keep xerr_n 0
proc xerror-flush {} {
    if {$::xerr_n > 1} {
        puts "WM:   (previous X error repeated [expr {$::xerr_n - 1}] more times)"
    }
    set ::xerr_last ""; set ::xerr_n 0
}
proc xerror {info} {
    # A dict: serial, error, request, minor, resource. The error's NAME
    # comes from the server itself (x-error-text) — better than a table
    # of names kept by hand. Consecutive identical errors are collapsed
    # (Tk's colormap walk over a dying hierarchy produces bursts).
    if {[catch {
        set key "[x-error-text [dict get $info error]]\
 request=[dict get $info request]\
 resource=[format 0x%x [dict get $info resource]]"
        if {$key eq $::xerr_last} {
            incr ::xerr_n
        } else {
            xerror-flush
            set ::xerr_last $key; set ::xerr_n 1
            puts "WM: X error $key — ignored"
        }
    # The one catch in this file that stays MUTE, deliberately: we are
    # inside the X error callback, and the only thing left to fail is
    # the logging itself — reporting a failed report would recurse out
    # of a callback that has nowhere to throw.
    } err]} { catch {puts "WM: X error (report failed: $err) — ignored"} }
}
x-error-handler xerror

# The root, asked of the server rather than computed: XQueryTree names
# the root of the screen whatever depth it is asked from, and our own
# main window is the one window we are sure of.
set root [lindex [x-query-tree .] 0]
# SubstructureRedirect|SubstructureNotify|FocusChange — the last one so we
# SEE when something external (Xephyr on outer focus crossings!) resets the
# input focus to PointerRoot, and can re-assert ours — plus
# StructureNotify for the root's OWN ConfigureNotify: a RandR resize
# (Xephyr's -resizeable, a mode switch) announces itself there.
#
# ---------------- becoming the window manager ----------------
# Two things make one, and this file used to do only the first.
#
# SUBSTRUCTURE-REDIRECT on the root is the ENFORCED half: the server
# hands it to one client and refuses the next, so an error here means
# somebody else has the desk. That is a fact of the server's, not a
# negotiation, and there is no polite way to ask for it.
#
# The MANAGER SELECTION WM_S<screen> (ICCCM 2.8) is the negotiated
# half, and the negotiation is the whole point: a manager that owns it
# can be ASKED to stand down — the asker takes the selection, the owner
# gets a SelectionClear, releases its clients and leaves, and the asker
# then finds the redirect free. A manager that does not own it cannot be
# replaced at all except by killing it, which loses every client on the
# desk. So we own it, and we honor it in both directions: with -replace
# we take the desk from whoever holds it, and without one we hand it
# over when somebody else asks (see the selection-clear branch of
# handle-event, which just calls exit — and exit already means "release
# every client back to the root alive").
#
# Which screen the selections name. Tk knows ours by name (":0.0"); a
# display spelled without a screen means screen 0.
proc screen-number {} {
    if {[regexp {\.(\d+)$} [winfo screen .] -> n]} { return $n }
    return 0
}
set WM_SELECTION  [x-intern WM_S[screen-number]]
# IS A COMPOSITOR RUNNING? The same protocol shape one screen over:
# a compositing manager owns _NET_WM_CM_S<screen> for as long as it
# runs, and that is the whole of the answer. Asked at startup and at
# a reload, and NOT tracked live on purpose (the owner, 2026-08-02):
# we would not tear the tray down because picom appeared, so
# pretending to follow it would be a lie with moving parts.
proc compositor? {} {
    expr {[x-selection-get [x-intern _NET_WM_CM_S[screen-number]]] != 0}
}
set MANAGER       [x-intern MANAGER]
set TK9WM_TIME    [x-intern TK9WM_TIME]
keep wm_owner_win  0     ;# the window that holds WM_S<n>, 0 = we do not
keep wm_claim_time 0     ;# when we took it (see selection-clear)
# Why we left, in the only language a session script can read. Leaving
# because somebody TOOK the desk is a different event from leaving
# because the user asked to (Quit), and until this code existed a
# .xsession could not tell them apart — which matters more here than
# anywhere, because a session that ends with `exec tk9wm` ENDS when we
# do. That coupling is deliberate for Quit (a desk one cannot leave is
# the joke with a login inside it) and fatal for a replacement: the
# newcomer takes the desk, we stand down as the protocol says, and the
# session goes with us — the owner's report, 2026-07-29, and not a bug
# to be fixed here. ICCCM knows no "hand over and stay": the newcomer
# waits for our owner window to be GONE, which reliably means our
# process is. So the mechanism is one honest number, and the policy —
# whether the session outlives us — belongs to the script that started
# us. See the README for the two .xsession recipes.
set EXIT_REPLACED 3
# How long to wait for a manager we asked to stand down. Generous on
# purpose: the old manager is releasing every client on the desk back to
# the root, and a desk full of windows takes a moment.
set replace_timeout 10000

# The timestamp a claim carries, fetched rather than guessed — the same
# zero-length property append server-time uses, spelled out here because
# this runs long before server-time's own window exists.
proc claim-time {w} {
    if {[catch {x-server-time $w $::TK9WM_TIME} t]} { return 0 }
    return $t
}

# Wait for the manager we just asked to stand down. ICCCM's own signal
# is its owner window going away — the old manager destroys it (or,
# just as final, dies and lets the server do it) only after it has let
# the desk go. Polled rather than awaited on an event: no dispatcher is
# armed yet, and a blocking `after` here disturbs nothing, since there
# is nothing of ours to service.
proc desk-wait {old} {
    set deadline [expr {[clock milliseconds] + $::replace_timeout}]
    while {[clock milliseconds] < $deadline} {
        if {[x-geometry $old] eq ""} { return 1 }
        after 100
    }
    return 0
}

# Arm the redirect, retrying while the outgoing manager lets go: the
# window vanishing and the redirect coming free are two events, in that
# order, and the second is the one we actually need.
proc desk-redirect {{tries 1}} {
    for {set i 0} {$i < $tries} {incr i} {
        if {![catch {x-select-input $::root {substructure-redirect
            substructure-notify focus-change structure-notify}} err]} {
            return ""
        }
        after 100
    }
    return $err
}

# Take the desk, or say why not and leave. `replace` = the -replace
# flag: without it a held selection is a refusal (and a plain one — the
# old message said "another window manager holds it?" with a question
# mark, because a bare BadAccess cannot know), with it a request.
proc desk-take {replace} {
    global root WM_SELECTION MANAGER
    set ::wm_owner_win [x-create-window $root -200 -200 1 1 -override]
    # property-change BEFORE the first timestamp is asked for: the
    # recipe is a zero-length property append and the ANSWER is a
    # PropertyNotify on this very window, so a window with no mask
    # waits for an event the server will never send it (measured — the
    # manager hung before its first line of log).
    x-select-input $::wm_owner_win {property-change}
    set held [x-selection-get $WM_SELECTION]
    if {$held != 0} {
        if {!$replace} {
            puts "WM: 0x[format %x $held] already owns WM_S[screen-number]\
 — another window manager has the desk. Start with -replace to take it."
            exit 1
        }
        puts "WM: asking 0x[format %x $held] to stand down\
 (WM_S[screen-number])"
    }
    set t [claim-time $::wm_owner_win]
    if {![x-selection-own $WM_SELECTION $::wm_owner_win $t]} {
        puts "WM: the server refused WM_S[screen-number] — cannot take the desk"
        exit 1
    }
    set ::wm_claim_time $t
    if {$held != 0 && ![desk-wait $held]} {
        puts "WM: 0x[format %x $held] is still there after\
 [expr {$::replace_timeout / 1000}]s — trying the redirect anyway"
    }
    # One try when the desk was free (the answer is immediate and an
    # error is final); many while somebody is walking off it.
    set err [desk-redirect [expr {$held != 0 ? 30 : 1}]]
    if {$err ne ""} {
        puts "WM: cannot take the redirect on root [format 0x%x $root]: $err"
        if {$held == 0} {
            puts "WM: ...and nobody owns WM_S[screen-number], so there is\
 nobody to ask: a window manager that does not use the manager selection\
 can only be stopped by hand."
        }
        exit 1
    }
    # ICCCM 2.8: a new manager announces itself to the root.
    x-send-client $root $MANAGER \
        [list $t $WM_SELECTION $::wm_owner_win 0 0] 32 {structure-notify}
    x-sync 0
    # The PID is on this line for one reason: a restart is an execv, so
    # the process keeps its pid AND its start time, and `ps` cannot tell
    # a desk that has been re-exec'd five times from one that has been
    # up all day. The log can — two banners with the same pid are one
    # process, restarted — and it is the log that should be asked. (I
    # asked ps and drew the wrong conclusion; the owner was right that
    # a restart must be legible, and it already was, in the other place.)
    puts "WM: redirect armed on root [format 0x%x $root]\
 (WM_S[screen-number] owner 0x[format %x $::wm_owner_win], pid [pid]),\
 input methods [expr {[tk useinputmethods] ? {ON — THIS DESK CAN BE\
 FROZEN BY ITS XIM} : {off}}]"
}

# The flag has to be readable HERE, when the desk is taken — which is
# `package require tk9wm` time, long before tk9wm-main sees an argument
# list. So: the command line if there is one, and ::tk9wm_replace for an
# embedder that builds its own.
unless-already {$::wm_owner_win != 0} {
    desk-take [expr {[info exists ::tk9wm_replace] ? $::tk9wm_replace
        : [expr {[info exists ::argv] && "-replace" in $::argv}]}]
}

set WM_PROTOCOLS      [x-intern WM_PROTOCOLS]
set WM_DELETE_WINDOW  [x-intern WM_DELETE_WINDOW]
set WM_TAKE_FOCUS     [x-intern WM_TAKE_FOCUS]
set WM_STATE          [x-intern WM_STATE]
set WM_CHANGE_STATE   [x-intern WM_CHANGE_STATE]  ;# iconify request
set TK9WM_RESTART     [x-intern TK9WM_RESTART]
set TK9WM_RELOAD      [x-intern TK9WM_RELOAD]   ;# re-read the config in place
# Our own record of which windows are tray icons, kept ON THE ROOT so
# it outlives us — see tray-adopt-orphans for why guessing instead of
# recording was a bug and not a shortcut.
set TK9WM_TRAY_ICONS  [x-intern TK9WM_TRAY_ICONS]
set WM_NAME           39   ;# XA_WM_NAME, predefined
set XA_STRING         31   ;# XA_STRING, predefined — a text property's type
set WM_COMMAND        34   ;# XA_WM_COMMAND, predefined
set WM_CLIENT_MACHINE 36   ;# XA_WM_CLIENT_MACHINE, predefined
set WM_CLASS          67   ;# XA_WM_CLASS, predefined
soft "intern _NET_WM_PID"  { set NET_WM_PID [x-intern _NET_WM_PID] }
soft "intern _NET_WM_ICON" { set NET_WM_ICON [x-intern _NET_WM_ICON] }
# Motif's, and older than everything else here — the property a client
# writes to ask for no decoration at all. Not EWMH and never was; see
# client-motif-decor for why it is still the living answer.
soft "intern _MOTIF_WM_HINTS" { set MOTIF_WM_HINTS [x-intern _MOTIF_WM_HINTS] }

# ---------------- EWMH minimum ----------------
# Enough for toolkits to see "a WM is present": _NET_SUPPORTING_WM_CHECK on
# root pointing at a dummy window that points back at itself and carries
# _NET_WM_NAME. (GTK apps probe this early; its absence is the prime
# suspect in gimp's startup crash.)
proc set-prop-longs {win prop type values} {
    x-prop-set $win $prop $type 32 $values
}
proc set-prop-utf8 {win prop str} {
    x-prop-set $win $prop $::UTF8 8 [encoding convertto utf-8 $str]
}
# How many desks there are and which one we are on. DECLARED HERE, far
# above the desk machinery itself, because the EWMH block right below
# publishes both the moment the redirect is armed — and a property
# publisher that reads a variable the file has not reached yet fails
# the whole setup (measured, the first run of this).
keep ndesks 1                ;# 1 = the mechanism is off
keep desk 0                  ;# where we are
keep adopting 0              ;# the startup sweep is framing the desk back
keep adopt_prev 0            ;# ...and the window it showed last (the next seats under it)
keep releasing 0             ;# a restart/quit is releasing every client at once
keep prev_active 0           ;# what the PREVIOUS instance held active (see below)

unless-already {[info exists ::wmcheck]} {if {[catch {
    set NET_CHECK     [x-intern _NET_SUPPORTING_WM_CHECK]
    set NET_SUPPORTED [x-intern _NET_SUPPORTED]
    set NET_WM_NAME   [x-intern _NET_WM_NAME]
    set NET_ACTIVE    [x-intern _NET_ACTIVE_WINDOW]
    set NET_WM_STATE  [x-intern _NET_WM_STATE]
    set NET_WM_STATE_HIDDEN [x-intern _NET_WM_STATE_HIDDEN]
    # The one state a client both ASKS for and is given. Advertising it
    # is not a formality: xterm and kitty look for this atom in
    # _NET_SUPPORTED and, not finding it, go fullscreen by not asking at
    # all — measured, they send NOTHING and stay their old size, while a
    # wmctrl request on the same window lands on the root in the same
    # breath. So the atom in the list below is what turns their menu
    # item and their -fullscreen / --start-as flag back on.
    set NET_WM_STATE_FULLSCREEN [x-intern _NET_WM_STATE_FULLSCREEN]
    # Maximize, the EWMH spelling — the pair of atoms a client puts in
    # _NET_WM_STATE before mapping ("start me maximized": emacs's
    # `fullscreen: maximized` X resource takes exactly this road) or
    # sends as a state action later (wmctrl -b add,maximized_...).
    # fvwm honored both; a desk that ignores them leaves such a client
    # at whatever size its OTHER claims add up to — the owner's emacs,
    # whose ancient Emacs.geometry resource then ruled alone (measured:
    # a TELEGA frame 1773 wide on a 1920 workarea, the hole exactly
    # where the request went unheard).
    # The stacking pair, which we could not honor at all before there
    # were layers and which every panel-ish client sets on itself.
    set NET_WM_STATE_STICKY [x-intern _NET_WM_STATE_STICKY]
    set NET_WM_STATE_ABOVE [x-intern _NET_WM_STATE_ABOVE]
    set NET_WM_STATE_BELOW [x-intern _NET_WM_STATE_BELOW]
    set NET_WM_STATE_MAXIMIZED_HORZ [x-intern _NET_WM_STATE_MAXIMIZED_HORZ]
    set NET_WM_STATE_MAXIMIZED_VERT [x-intern _NET_WM_STATE_MAXIMIZED_VERT]
    set NET_FRAME_EXTENTS [x-intern _NET_FRAME_EXTENTS]
    set NET_REQUEST_FRAME_EXTENTS [x-intern _NET_REQUEST_FRAME_EXTENTS]
    # The drag a client asks US to run, because it cannot run it
    # itself: a window whose titlebar is its own widget (every GTK4
    # window is one) has nothing of ours to grab, and moving its own
    # toplevel under a REPARENTING manager moves it inside our frame
    # rather than moving the frame. So it presses, ungrabs the pointer
    # and sends this — and gdk looks for the atom in _NET_SUPPORTED
    # first, falling back to exactly that broken self-move when it is
    # not there. Advertising it is half the feature.
    set NET_WM_MOVERESIZE [x-intern _NET_WM_MOVERESIZE]
    # ...and the semantic half of "do not decorate me": a splash
    # screen, a dock or a torn-off toolbar names WHAT it is and lets
    # the decoration follow from that (see client-window-types).
    set NET_WM_WINDOW_TYPE [x-intern _NET_WM_WINDOW_TYPE]
    # The KDE-era twin of the extents, still read by Qt4-vintage
    # clients; four CARDINALs in the same order, so it costs one line
    # to keep them in step and nothing to be wrong about.
    set KDE_FRAME_STRUT [x-intern _KDE_NET_WM_FRAME_STRUT]
    # What the desk looks like from OUTSIDE — the half of EWMH a client
    # reads about the screen rather than about itself. A pager, wmctrl,
    # xdotool and every "place my popup somewhere sensible" toolkit
    # (fcitx among them) start here; we published none of it, which is
    # what a diff against fvwm3's root window says in one line.
    set NET_CLIENT_LIST [x-intern _NET_CLIENT_LIST]
    set NET_CLIENT_LIST_STACKING [x-intern _NET_CLIENT_LIST_STACKING]
    set NET_WORKAREA [x-intern _NET_WORKAREA]
    set NET_NUMBER_OF_DESKTOPS [x-intern _NET_NUMBER_OF_DESKTOPS]
    set NET_CURRENT_DESKTOP [x-intern _NET_CURRENT_DESKTOP]
    set NET_DESKTOP_GEOMETRY [x-intern _NET_DESKTOP_GEOMETRY]
    set NET_DESKTOP_VIEWPORT [x-intern _NET_DESKTOP_VIEWPORT]
    set NET_WM_DESKTOP [x-intern _NET_WM_DESKTOP]
    set UTF8          [x-intern UTF8_STRING]
    set wmcheck [x-create-window $root -100 -100 1 1]
    set-prop-longs $root    $NET_CHECK 33 [list $wmcheck]   ;# XA_WINDOW
    set-prop-longs $wmcheck $NET_CHECK 33 [list $wmcheck]
    set-prop-utf8  $wmcheck $NET_WM_NAME tk9wm
    # PropertyChange on our own window is what makes server-time work: a
    # zero-length property append comes back as a PropertyNotify carrying
    # the server's current time (see server-time). Selected only NOW, so
    # the writes above do not leave stale notifications in the queue for
    # server-time to mistake for the current time.
    x-select-input $wmcheck {property-change}
    # _NET_ACTIVE_WINDOW is load-bearing for Wine 10+: it derives its
    # foreground from this root property, and its focus-stealing guard
    # judges our WM_TAKE_FOCUS invitations against that foreground —
    # kept honest by paint-focus below.
    #
    # ...but READ FIRST: across a restart the property still says what
    # the desk had active, and adoption's one focus decision wants
    # exactly that (policy-adopt-settled). Inline rather than
    # read-prop-long — that proc is defined further down and this
    # block runs at source time.
    catch {
        lassign [x-prop-get $root $NET_ACTIVE] _pa_type _pa_fmt _pa_val
        if {$_pa_fmt eq "32" && [llength $_pa_val]} {
            set prev_active [lindex $_pa_val 0]
        }
    }
    set-prop-longs $root $NET_ACTIVE 33 [list 0]
    # One desktop, no viewport, and we say so rather than staying
    # silent: a client that finds _NET_NUMBER_OF_DESKTOPS missing has
    # to guess, and guessing is what puts things in the wrong place.
    set-prop-longs $root $NET_NUMBER_OF_DESKTOPS 6 [list $ndesks] ;# XA_CARDINAL
    set-prop-longs $root $NET_CURRENT_DESKTOP 6 [list $desk]
    set-prop-longs $root $NET_DESKTOP_VIEWPORT 6 [list 0 0]
    set-prop-longs $root $NET_SUPPORTED 4 \
        [list $NET_CHECK $NET_WM_NAME $NET_ACTIVE \
              $NET_WM_STATE $NET_WM_STATE_HIDDEN $NET_WM_STATE_FULLSCREEN \
              $NET_WM_STATE_ABOVE $NET_WM_STATE_BELOW $NET_WM_STATE_STICKY \
              $NET_WM_STATE_MAXIMIZED_HORZ $NET_WM_STATE_MAXIMIZED_VERT \
              $NET_FRAME_EXTENTS $NET_REQUEST_FRAME_EXTENTS \
              $NET_WM_MOVERESIZE $NET_WM_WINDOW_TYPE \
              $NET_CLIENT_LIST $NET_CLIENT_LIST_STACKING $NET_WORKAREA \
              $NET_NUMBER_OF_DESKTOPS $NET_CURRENT_DESKTOP \
              $NET_DESKTOP_GEOMETRY $NET_DESKTOP_VIEWPORT \
              $NET_WM_DESKTOP]                                 ;# XA_ATOM
    x-sync 0
    puts "WM: EWMH minimum up (_NET_SUPPORTING_WM_CHECK=[format 0x%x $wmcheck])"
} err]} { puts "WM: EWMH setup failed: $err" }}

# ---------------- the focus holder ----------------
# fvwm's NoFocusWin, ported: a real, viewable, off-screen window that
# holds the keyboard focus whenever no client deserves it. The obvious
# alternative — PointerRoot — is a trap we walked into (step 26, cured
# in step 32): PointerRoot IS focus-follows-pointer, so the whole
# session silently changes policy, and worse, it arms Tk's own implicit
# focus machinery (generic/tkFocus.c: a crossing into any Tk window
# whose xcrossing.focus is set makes Tk claim the focus, and the
# matching LeaveNotify makes it call XSetInputFocus(PointerRoot) —
# our frames, grips and panel are Tk windows, so the WM kept knocking
# its own display back into pointer-follows mode).
#
# A real holder has neither problem and keeps the root key grabs alive
# (a passive grab fires when the grab window is an ancestor of the
# focus window — root is an ancestor of this one).
#
# ...and the holder cures the RESULT while this cures the CAUSE: the
# shim refuses Tk the two events it arms that machinery with, so the
# display never falls to PointerRoot in the first place (see
# TameImplicitFocus in tkwmx.c). Both are wanted. Without the taming
# every switch cost three focus transitions — a fall, a park, a re-aim
# — measured at 3904 PointerRoot falls in one session's log; without
# the holder there is nowhere honest to park the focus when no client
# deserves it, and the root key grabs go dead.
#
# Ordered BEFORE the holder is built: from here on no crossing of ours
# can knock the display over, so nothing has to be repaired between
# these two lines.
soft "tame Tk's implicit focus" { x-focus-tame 1 }
keep nofocus 0
unless-already {$::nofocus != 0} {if {[catch {
    # override-redirect: the holder is nobody's client. On one
    # connection our own maps are not redirected to us anyway, but the
    # flag is the honest statement of what this window is — and it is
    # what keeps a NEXT window manager from framing it.
    set nofocus [x-create-window $root -10 -10 10 10 -override]
    x-map $nofocus        ;# must be viewable to hold the focus
    x-sync 0
    puts "WM: focus holder up (0x[format %x $nofocus])"
} err]} { puts "WM: focus holder setup failed: $err"; set nofocus 0 }}

# A fresh server timestamp, fetched — not guessed. Every WM_TAKE_FOCUS
# invitation must carry a time NEWER than the server's last focus change,
# or the client's answer (which echoes our stamp) is silently dropped;
# and Wine additionally refuses an invitation older than its current
# foreground's focus time. Until step 32 we passed an accumulated clock
# fed by whatever events happened to reach us, which went stale exactly
# when it mattered (typing INTO a window is invisible to us) and forced
# a retry timer to paper over it.
#
# The standard recipe (this is what GDK's gdk_x11_get_server_time does):
# a ZERO-LENGTH append to a property on our own window. It changes
# nothing, and the server answers with a PropertyNotify carrying its
# current time.
proc server-time {} {
    if {![info exists ::wmcheck]} { return $::evtime }
    if {[catch {x-server-time $::wmcheck $::TK9WM_TIME} t]} {
        puts "WM: server-time failed ($t) — falling back to the event clock"
        return $::evtime
    }
    if {$t > $::evtime} { set ::evtime $t }
    return $t
}

# ---------------- event dispatch ----------------
# One event, one DICT — named type, named fields, straight from the
# shim. The twenty-two `binary scan`s at hand-counted LP64 offsets this
# used to be are gone, and with them a whole class of bug: a field read
# at the wrong offset still looks like a number.
#
# What the single connection changed is the AUDIENCE. This handler now
# sees every event TK sees — motion over our own widgets, expose,
# clicks on the titlebar, keys typed into the panel — and not just what
# a second connection had selected. So each branch below says out loud
# whose event it acts on, and the ones that answer the server (the sync
# grab's replay) make sure they are answering OUR grab and not
# intruding on Tk's business. The shim's handler never claims an event:
# Tk goes on getting its own.
#
# Errors are caught HERE and logged. Letting one out would reach Tcl's
# background handler, and in a Tk process that means an error DIALOG —
# from the window manager, on a desk whose dialogs it is supposed to be
# managing.
keep evqueue {}      ;# what arrived before the policy layer was in
keep dispatching 0   ;# substrate-start flips this and replays the queue
proc handle-event {ev} {
    # Before substrate-start the events are QUEUED, not dropped: the
    # redirect is armed while this file is sourced, but the policy layer
    # this dispatches into is not loaded yet. (The old pump got this for
    # free — a second connection just held them in its queue.)
    if {!$::dispatching} { lappend ::evqueue $ev; return }
    if {[catch {dispatch-event $ev} err]} { puts "WM: handler error: $err" }
}

# X stack-mode codes, in the order a ConfigureRequest spells them.
set stackmodes {above below top-if bottom-if opposite}

proc dispatch-event {ev} {
    switch -- [dict get $ev type] {
        configure-request { # managed → the frame follows the client;
            # unmanaged → honor verbatim and remember the size
            set B [dict get $ev window]
            set vmask [dict get $ev value-mask]
            set x [dict get $ev x]; set y [dict get $ev y]
            set w [dict get $ev width]; set h [dict get $ev height]
            if {[info exists ::trayicon($B)]} {
                # An icon asking for its own size — answered, not obeyed
                tray-hold-size $B
            } elseif {[info exists ::managed($B)]} {
                # A fullscreen window's geometry is not its own: the
                # request is denied WHOLE, and the synthetic
                # ConfigureNotify below is the answer ICCCM requires.
                # (A terminal re-rounds its size to whole cells on every
                # font change and asks for it; granting that mid-
                # fullscreen leaves a strip of desk down one side.)
                if {[info exists ::fullscreen($B)]} {
                    # denied whole, per the comment above
                } elseif {[info exists ::maxsaved($B)]} {
                    # THE MAXIMIZED SHIELD — fullscreen's rule with a
                    # memory. While the mark holds, the live geometry
                    # belongs to the STATE, not the client: emacs
                    # re-states its own 80x25 idea of itself right
                    # after mapping, and granting that un-maximizes
                    # every frame born maximized (the owner's desk —
                    # born wide, snapped narrow a beat later, telega
                    # mid-recount). The asked-for SIZE is not thrown
                    # away though: it lands in the saved way-back
                    # geometry, so unmaximize restores to what the
                    # client last meant, not to a stale birth size.
                    # Position requests are denied like fullscreen's;
                    # the synthetic ConfigureNotify below tells the
                    # client what remains true either way.
                    # PER AXIS, like the state itself: only the axes
                    # the mark holds are the state's — a tall window
                    # asking for a width is minding its own business,
                    # and that half of the request is granted live,
                    # position claim and all.
                    lassign $::maxsaved($B) scw sch sX sY
                    set held 0
                    set live $vmask
                    if {"h" in $::maxaxes($B)} {
                        if {$vmask & (1 << 2)} { set scw $w; set held 1 }
                        set live [expr {$live & ~((1 << 0) | (1 << 2))}]
                    }
                    if {"v" in $::maxaxes($B)} {
                        if {$vmask & (1 << 3)} { set sch $h; set held 1 }
                        set live [expr {$live & ~((1 << 1) | (1 << 3))}]
                    }
                    set ::maxsaved($B) [list $scw $sch $sX $sY]
                    if {$held} {
                        puts "WM: size request 0x[format %x $B]\
 ${w}x${h} while maximized — saved for the way back"
                    }
                    if {$live & 3} { move-client-request $B $x $y $live }
                    resize-client $B $w $h $live
                } else {
                    if {$vmask & 3} { move-client-request $B $x $y $vmask }
                    resize-client $B $w $h $vmask
                }
                # The stacking bit, orthogonal to the geometry above and
                # heard in every state — a fullscreen window's geometry
                # is not its own, but its place in the stack still is.
                # XRaiseWindow IS a ConfigureRequest: CWStackMode is how
                # Tk's `raise .` arrives, and how emacs surfaces a frame
                # for its own minibuffer question (minibuffer-auto-raise
                # on "revert from disk?" — the prompt nobody saw). For a
                # managed window the bit used to be dropped on the floor
                # unread; it goes to the policy's own verbs — group and
                # layers intact — never to a raw X restack. The sibling
                # half (CWSibling) names a place in a stacking the
                # policy does not promise to keep; EWMH lets a WM ignore
                # the sibling, and saying so beats half-honoring it.
                if {$vmask & (1 << 6)} {
                    set mode [lindex $::stackmodes [dict get $ev detail]]
                    if {$vmask & (1 << 5)} {
                        puts "WM: restack 0x[format %x $B]: sibling ignored"
                    }
                    soft "restack request" { policy-restack-request $B $mode }
                }
                # ICCCM 4.1.5: "If a client's ConfigureWindow request is
                # denied in whole or in part, the window manager must send
                # the client a synthetic ConfigureNotify". A position
                # request is denied unless the client claims positioning
                # (move-client-request above); the denied ones used to get
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
                # Honored in the request's OWN terms: the value-mask
                # decides which keys the shim is given, and the ones it
                # is not given are left alone — the same contract the
                # client asked in, with no struct to lay out by hand.
                set chg {}
                foreach {bit key field} {1 x x   2 y y
                        4 width width            8 height height
                        16 border-width border-width
                        32 sibling above         64 stack-mode detail} {
                    if {$vmask & $bit} { dict set chg $key [dict get $ev $field] }
                }
                if {[dict exists $chg stack-mode]} {
                    dict set chg stack-mode \
                        [lindex $::stackmodes [dict get $chg stack-mode]]
                }
                soft "honor ConfigureRequest" { x-configure $B $chg }
                puts "WM: ConfigureRequest 0x[format %x $B] ${w}x${h} honored"
            }
        }
        map-request { # a tray icon's visibility is _XEMBED_INFO's to
            # decide, not its client's: answer the request by re-reading
            # the property rather than by mapping on demand
            set B [dict get $ev window]
            if {[info exists ::trayicon($B)]} {
                tray-refresh-map $B
            } else {
                manage $B
            }
        }
        destroy-notify {
            set B [dict get $ev window]
            if {[info exists ::trayicon($B)]} {
                tray-undock $B 1
            } else {
                unmanage $B 1
            }
        }
        reparent-notify { # an icon pulled out of our slot by somebody
            # else (a newer tray manager, or its own client): it is no
            # longer ours to size or to map, and reparenting it back
            # would be a fight. Our OWN reparent reports the same event
            # with the slot as parent — that one is just the echo.
            set B [dict get $ev window]
            if {[info exists ::trayicon($B)]
                    && [dict get $ev parent] != $::trayicon($B)} {
                tray-undock $B 1
            }
        }
        selection-clear { # somebody asked for a manager selection we
            # hold — ICCCM 2.8, how a replacement announces itself.
            #
            # ...or the echo of our OWN release. Turning the tray off
            # and on again (a config reload does exactly that) releases
            # the selection and re-takes it, and the SelectionClear for
            # the release arrives AFTER the new claim — read naively,
            # the tray shuts itself down a moment after coming up
            # (measured). ICCCM's own answer is the timestamp: an event
            # older than our latest claim cannot be about it.
            if {$::tray_owner != 0
                    && [dict get $ev selection] == $::TRAY_SELECTION
                    && [dict get $ev time] >= $::tray_claim_time} {
                tray-stop "another system tray took the selection"
            }
            # ...and the DESK's own selection, which is the whole of our
            # side of a replacement: somebody else asked for the desk,
            # and standing down is the answer the protocol promises on
            # our behalf. exit is the entire implementation — it already
            # means "release the tray, hand every client back to the
            # root alive, then go" — and our windows dying with the
            # process is what tells the newcomer the desk is free.
            if {$::wm_owner_win != 0
                    && [dict get $ev selection] == $::WM_SELECTION
                    && [dict get $ev time] >= $::wm_claim_time} {
                puts "WM: another window manager took WM_S[screen-number]\
 — standing down"
                exit $::EXIT_REPLACED
            }
        }
        map-notify { # MapNotify (self-report): the client is now really
            # on screen and past its own map bookkeeping — tell it where
            # it is once more, see tell-where-you-are.
            set B [dict get $ev window]
            if {[dict get $ev event-window] == $B && [info exists ::managed($B)]} {
                send-synthetic-configure $B
            }
        }
        configure-notify { # only the root's own is interesting — the
            # screen changed size (RandR). The SubstructureNotify copies
            # for reparented children arrive here too (event=root,
            # window=child), and so does every move of our own Tk
            # windows: all noise.
            if {[dict get $ev event-window] == $::root
                    && [dict get $ev window] == $::root} {
                puts "WM: screen -> [dict get $ev width]x[dict get $ev height]"
                policy-screen-changed
                publish-workarea   ;# the desk itself just changed size
            }
        }
        unmap-notify { # the client withdrew itself. Trust only the
            # StructureNotify self-report (event==window — the root's
            # SubstructureNotify copy has event=root) and skip the unmap
            # echo generated by our own adoption reparent.
            set B [dict get $ev window]
            if {[dict get $ev event-window] == $B && [info exists ::managed($B)]} {
                # A COUNT, not a flag: more than one unmap of ours can be
                # in flight at once (adopting a minimized window reparents
                # it, which echoes, and then unmaps it to put the iconic
                # state back). A flag swallowed the first and read the
                # second as a withdrawal.
                if {[info exists ::skip_unmap($B)]} {
                    if {[incr ::skip_unmap($B) -1] <= 0} {
                        unset ::skip_unmap($B)
                    }
                } else {
                    puts "WM: client 0x[format %x $B] withdrew itself"
                    close-answered $B
                    unmanage $B
                }
            }
        }
        focus-in {
            set win [dict get $ev window]
            set mode [dict get $ev mode]
            set detail [dict get $ev detail]
            # Normal (0) and WhileGrabbed (3) report a real focus
            # change — WhileGrabbed is Normal's shape while some grab
            # is active, and our own chords ARE such a grab: a client
            # answering a WM_TAKE_FOCUS invitation during Super+N desk
            # switching lands its FocusIn as WhileGrabbed, and dropping
            # it left the frame painted inactive and (worse) the
            # _NET_ACTIVE_WINDOW publish never made — wine reads its
            # foreground off that publish, so its window stayed
            # deactivated for good (stand-proven, 2026-08-12). Only
            # the pairs the grab ITSELF generates (Grab 1, Ungrab 2)
            # are bookkeeping to ignore: they replay standing facts at
            # grab boundaries. ONE further exception below: the
            # PointerRoot/None fall is heeded in EVERY mode.
            #
            # detail says whether THIS window is the new focus window
            # (Ancestor 0, Inferior 2, Nonlinear 3) or merely lies on
            # the path to it (Virtual 1, NonlinearVirtual 4) — the
            # difference between "the focus landed here" and "the focus
            # passed through here on its way to a child".
            if {$win == $::root && ($detail == 6 || $detail == 7)} {
                # PointerRoot(6)/None(7): the focus has no honest
                # home. PointerRoot means the display just silently
                # switched to focus-follows-pointer (Tk's implicit
                # focus release does exactly this — see the focus
                # holder); None means the keyboard is dead and even
                # our root chords stopped firing.
                #
                # Heeded in EVERY mode, not just Normal: while a popup
                # menu holds our own keyboard grab, Tk's implicit
                # release still fires (leaving the focused client's
                # frame — its inferior holds the focus, so the crossing
                # arms the trap) but every focus event arrives as
                # WhileGrabbed, and dropping those left the display in
                # focus-follows-mouse for good (live report,
                # 2026-07-28). A detail-6/7 FocusIn on the root cannot
                # lie: whatever the mode, the real focus is (or just
                # became) PointerRoot/None — the grab pseudo-events
                # only replay that same fact at grab boundaries.
                #
                # ...cannot lie about THEN — but it routinely lies
                # about NOW. The fall it reports happens at the moment
                # a frame is destroyed or unmapped, BEFORE the repair
                # that same teardown runs; by the time this event is
                # read the focus is already parked and re-aimed, and a
                # second repair would yank it off the freshly focused
                # client and hand it back — two focus transitions on an
                # innocent window per iconify/unmanage (358 of them in
                # one session's log, 2026-08-12; flap like that is what
                # chews through a client's async activation
                # bookkeeping). So the server is asked whether the
                # focus is a dead end NOW: root, PointerRoot or None
                # want the repair, anything else makes this event a
                # line in the log. Our own decoration is not skipped
                # here by accident — a revert onto a frame reports
                # itself with its own FocusIn, and that branch below
                # repairs it.
                lassign [x-focus-get] curf -
                if {$curf ne "" && $curf > 1 && $curf != $::root} {
                    puts "WM: stale [expr {$detail == 6 ?
                        "PointerRoot" : "None"}]-fall report — the focus\
 already stands on [format 0x%x $curf]"
                } else {
                    focus-repair [expr {$detail == 6 ?
                        "focus fell to PointerRoot" : "focus fell to None"}]
                }
            } elseif {$mode == 0 || $mode == 3} {
                set is_focus_win [expr {$detail == 0 || $detail == 2 || $detail == 3}]
                if {[info exists ::managed($win)] && $detail < 5} {
                    # A client took the focus: our invitation was
                    # answered, or the focus moved behind our back
                    # (focus -force). Either way this is the moment the
                    # WM may believe it — and the ONLY moment it
                    # publishes _NET_ACTIVE_WINDOW.
                    set ::invited 0
                    if {$::focused != $win} { paint-focus $win }
                } elseif {$is_focus_win
                        && ($win == $::root || [info exists ::ourwin($win)])} {
                    # The focus landed on our own decoration or on the
                    # root: a dead end — nobody there reads the
                    # keyboard. Typical cause: a client that had the
                    # focus unmapped itself and the server reverted the
                    # focus to the parent, which is our frame.
                    set prefer 0
                    if {[info exists ::ourwin($win)]} { set prefer $::ourwin($win) }
                    focus-repair "focus landed on our own window\
 0x[format %x $win]" $prefer
                }
            }
        }
        property-notify { # a
            # title change repaints the frame's titlebar; changed
            # WM_NORMAL_HINTS (XA_ predefined 40) are re-read; a changed
            # WM_TRANSIENT_FOR (XA_ predefined 68) re-aims the dialog —
            # toolkits are free to point a mapped window at a leader
            # (or away from one) at any time.
            # (Step 31 also fed the event clock from here, to freshen
            # invitation stamps. Step 32 fetches the stamp from the
            # server instead — see server-time — so this handler is
            # back to being about properties only.)
            set A [dict get $ev window]
            set B [dict get $ev atom]
            if {[info exists ::trayicon($A)]} {
                # the one property of an icon we watch: it is how a
                # docked client says "hide me" and "show me again"
                if {$B == $::XEMBED_INFO} { tray-refresh-map $A }
            } elseif {[info exists ::managed($A)]} {
                if {$B == $::WM_NAME
                        || ([info exists ::NET_WM_NAME]
                            && $B == $::NET_WM_NAME)} {
                    refresh-title $A
                } elseif {$B == 40} {
                    read-normal-hints $A
                } elseif {$B == 68} {
                    set l [transient-for $A]
                    set ls none
                    if {$l != 0} { set ls [format 0x%x $l] }
                    puts "WM: transient 0x[format %x $A] -> $ls"
                    policy-transient $A $l
                } elseif {[info exists ::NET_WM_ICON] && $B == $::NET_WM_ICON} {
                    icon-invalidate $A   ;# re-read on the next need
                }
            }
        }
        client-message { # The restart knob arrives here: send-restart
            # addresses the wmcheck window, and a zero-mask XSendEvent is
            # delivered to the window's CREATOR — this connection.
            set A [dict get $ev window]
            set B [dict get $ev message-type]
            # data.l as a list of five, and only when the message really
            # is format 32 — a format-8 payload would be a byte array.
            set data [expr {[dict get $ev format] == 32
                ? [dict get $ev data] : {}}]
            if {[info exists ::wmcheck] && $A == $::wmcheck
                    && $B == $::TK9WM_RESTART} {
                restart-wm
            } elseif {[info exists ::wmcheck] && $A == $::wmcheck
                    && $B == $::TK9WM_RELOAD} {
                # The lighter twin of the restart: same code, new
                # config. Defined by the assembly (wm.tcl), which is
                # what knows where a config comes from — the two layers
                # can be sourced without it.
                if {[llength [info commands reload-config]]} {
                    reload-config
                } else {
                    puts "WM: reload requested, but no config layer is loaded"
                }
            } elseif {[info exists ::NET_ACTIVE] && $B == $::NET_ACTIVE
                    && [info exists ::managed($A)]} {
                # An EWMH activation request (data.l: source, timestamp,
                # requestor's active window). This is the recovery path
                # that costs nothing and needs no timer: a client that
                # wanted the focus and did not get it asks again, by
                # itself, when it next has a reason to. Wine does
                # exactly this — which is why _NET_ACTIVE_WINDOW must
                # never lie that the client is already active. Honored
                # as a click would be — raise the group, focus (which
                # invites a globally active window) — plus `fresh`:
                # the asker may believe itself inactive while the
                # focus already stands on it, and only a real
                # FocusOut/FocusIn pair corrects a belief like that.
                set rt [lindex $data 1]
                puts "WM: activation request for 0x[format %x $A] (t=$rt)"
                soft "activation request" { policy-client-activate $A }
            } elseif {[info exists ::NET_WM_DESKTOP] && $B == $::NET_WM_DESKTOP
                    && [info exists ::managed($A)]} {
                # "put this window on that desk" — what a pager sends,
                # and what `wmctrl -r X -t N` is. The all-ones CARDINAL
                # is sticky, same spelling as the property.
                set d [lindex $data 0]
                desk-send $A [expr {$d == 0xffffffff ? "all" : $d}]
            } elseif {[info exists ::NET_CURRENT_DESKTOP]
                    && $B == $::NET_CURRENT_DESKTOP} {
                # ...and "go to that desk", which is the same message
                # aimed at the root.
                #
                # ALL-ONES IS NOT A DESK. A tool that means "go to
                # where this window is" reads the window's
                # _NET_WM_DESKTOP and sends it back — and a sticky
                # window's is the all-ones CARDINAL, which arrives here
                # as -1 (xdotool windowactivate does exactly this,
                # measured). There is nowhere to go: the window is
                # already on this desk, being on all of them.
                set d [lindex $data 0]
                if {$d == 0xffffffff || $d < 0} {
                    puts "WM: «go to desk» for a window that is on all of them\
 — already there"
                } else {
                    desk-go $d
                }
            } elseif {[info exists ::NET_WM_STATE] && $B == $::NET_WM_STATE
                    && [info exists ::managed($A)]} {
                # EWMH's one write into a window's state: data.l[0] is
                # the action (0 remove, 1 add, 2 toggle) and l[1]/l[2]
                # name up to TWO state atoms — the pair exists so a
                # client can ask for both maximize halves at once, and
                # each is answered on its own. Zero means "no second
                # atom". States we do not hold are heard and named in
                # the log rather than silently dropped: the next one to
                # be implemented will announce itself here.
                set act [lindex $data 0]
                # One message may name BOTH maximize atoms (wmctrl
                # does), and each atom is ITS OWN axis now: HORZ acts
                # on h, VERT on v, independently — a toggle of both on
                # a fully-maximized window restores it, on a bare one
                # maximizes it, and on a tall-only one it drops tall
                # and adds wide, which is what the two atoms literally
                # say (and how mutter reads them).
                foreach a [lrange $data 1 2] {
                    if {$a == 0} continue
                    if {[info exists ::NET_WM_STATE_FULLSCREEN]
                            && $a == $::NET_WM_STATE_FULLSCREEN} {
                        set on [expr {$act == 2
                            ? ![info exists ::fullscreen($A)] : $act == 1}]
                        if {$on} { fullscreen-client $A } else {
                            unfullscreen-client $A
                        }
                    } elseif {[info exists ::NET_WM_STATE_MAXIMIZED_HORZ]
                            && ($a == $::NET_WM_STATE_MAXIMIZED_HORZ
                                || $a == $::NET_WM_STATE_MAXIMIZED_VERT)
                            && [llength [info commands maximize-client]]} {
                        set ax [expr {$a == $::NET_WM_STATE_MAXIMIZED_HORZ
                                      ? "h" : "v"}]
                        set held [expr {[info exists ::maxaxes($A)]
                                        && $ax in $::maxaxes($A)}]
                        set on [expr {$act == 2 ? !$held : $act == 1}]
                        if {!$on && [llength [info commands maximize-pinned]]
                                && [maximize-pinned $A]} {
                            # the config's forced max outranks a client
                            # message, exactly as it outranks the
                            # client's -geometry; see maximize-pinned
                            puts "WM: client asks maximize off\
 (0x[format %x $A]) — pinned by place {max force}, refused"
                            publish-net-wm-state $A   ;# re-state the truth
                            continue
                        }
                        puts "WM: client asks maximize $ax\
 [expr {$on ? {on} : {off}}] (0x[format %x $A])"
                        if {$on} { maximize-client $A $ax } else {
                            unmaximize-client $A $ax
                        }
                    } elseif {[info exists ::NET_WM_STATE_ABOVE]
                            && ($a == $::NET_WM_STATE_ABOVE
                                || $a == $::NET_WM_STATE_BELOW)
                            && [llength [info commands layer-set]]} {
                        # The stacking pair at run time: a client asking
                        # to be above (or below) everything is asking
                        # for a LAYER, and now there is one to give it.
                        # Toggle compares with where the window sits, so
                        # a second ask puts it back among the ordinary
                        # windows.
                        set want [expr {$a == $::NET_WM_STATE_ABOVE
                                        ? $::LAYER_ABOVE : $::LAYER_BELOW}]
                        set on [expr {$act == 2
                            ? [layer-declared $A] != $want : $act == 1}]
                        layer-set $A [expr {$on ? $want : $::LAYER_NORMAL}]
                        publish-net-wm-state $A
                    } else {
                        puts "WM: _NET_WM_STATE action $act on\
 [soft "name an atom" { x-atom-name $a } $a] ignored\
 (0x[format %x $A])"
                    }
                }
            } elseif {[info exists ::NET_REQUEST_FRAME_EXTENTS]
                    && $B == $::NET_REQUEST_FRAME_EXTENTS} {
                # EWMH: a client asking how big its decoration WILL be,
                # before it has one — GTK does this while working out
                # where to put its window. The message names the asking
                # window (which is not managed yet), and the answer is
                # the property on that window.
                puts "WM: frame extents requested for 0x[format %x $A]"
                publish-frame-extents $A
            } elseif {[info exists ::NET_WM_MOVERESIZE]
                    && $B == $::NET_WM_MOVERESIZE
                    && [info exists ::managed($A)]} {
                # EWMH 4.3, the client-side drag: data.l is
                # {x_root y_root direction button source}. The press
                # that started it landed in the CLIENT — a GTK
                # headerbar is its own widget — and the client has let
                # the pointer go before sending (the spec makes it),
                # so the gesture is ours to run from here on. Which
                # gesture is the direction's to say, and the policy
                # owns every one of them already.
                lassign $data mrx mry dir btn
                puts "WM: moveresize request dir=$dir button=$btn on\
 0x[format %x $A]"
                soft "moveresize request" {
                    policy-moveresize-request $A $mrx $mry $dir $btn
                }
            } elseif {$::tray_owner != 0 && $A == $::tray_owner
                    && $B == $::TRAY_OPCODE} {
                # The tray protocol's one request: data.l[1] is the
                # opcode, and SYSTEM_TRAY_REQUEST_DOCK (0) names the
                # icon window in data.l[2]. Opcodes 1..3 are the balloon
                # message protocol — heard and logged, not answered:
                # there is nowhere to show one yet.
                if {[lindex $data 1] == 0} {
                    tray-dock [lindex $data 2]
                } else {
                    puts "WM: tray: opcode [lindex $data 1] ignored\
 (balloon messages are not implemented)"
                }
            } elseif {$B == $::WM_CHANGE_STATE && [info exists ::managed($A)]} {
                # ICCCM 4.1.4: the iconify request. data.l[0] carries
                # the wanted state — IconicState (3) is the only one
                # sent this way in practice.
                set want [lindex $data 0]
                if {$want == 3} {
                    puts "WM: iconify request for 0x[format %x $A]"
                    policy-minimize-request $A
                }
            }
        }
        key-press { # from OUR grabs: a top-chord XGrabKey or the
            # sequence's temporary XGrabKeyboard, both taken on the root
            # with owner_events False — so the server reports them
            # against the ROOT, and that is exactly how they are told
            # apart from the keys Tk's own widgets are being typed into.
            if {[dict get $ev window] != $::root} return
            set ::evtime [dict get $ev time]
            # Passive grab and sequence grab are both SYNC, so short of
            # a router's async grab every press arrives FROZEN and
            # awaits its ONE answer — the keyboard twin of button-press
            # below. handle-key answers on the paths that decide
            # (action, prefix, keys-pass, the doubled opener); the
            # finally answers for every path that stays silent —
            # unbound, a bare modifier, an error — and WHICH answer
            # depends on where the press froze. In idle it is the
            # client's: replay does not eat the key, the client gets
            # what the desk had no use for. Inside a sequence it is the
            # desk's: sync-keyboard keeps the queue moving and the
            # discipline standing, and nothing leaks to a client while
            # the sequence lives.
            set ::key_frozen [expr {$::keyrouter eq ""}]
            try {
                handle-key [dict get $ev state] [dict get $ev keycode] \
                    $::evtime
            } finally {
                key-thaw [expr {$::kbd_grabbed ? "sync-keyboard"
                                               : "replay-keyboard"}] $::evtime
            }
        }
        key-release { # a keyboard-modal router reads releases (the
            # alt-tab commit-on-release); the keymap machine ignores
            # them — but under a sequence's SYNC grab a release arrives
            # frozen like everything else and must be answered, or the
            # keyboard stops. One thing is read before the queue moves
            # on: the OPENER's own release, which is what tells a
            # second press of it from the hold's autorepeat (see the
            # doubled-opener forward in handle-key).
            if {[dict get $ev window] != $::root} return
            set ::evtime [dict get $ev time]
            if {$::keyrouter ne ""} {
                route-key release \
                    [keysym-name [router-key [dict get $ev state] \
                                      [dict get $ev keycode]]] \
                    [expr {[dict get $ev state] & ~(2 | 16)}]
                return
            }
            if {!$::kbd_grabbed} return
            try {
                set kc [dict get $ev keycode]
                if {$::keyseq_opener ne ""
                        && [chord-key $kc [x-keysym-at $kc 0 0]]
                           == [lindex [split $::keyseq_opener ,] 1]} {
                    set ::keyseq_opener_up 1
                }
            } finally {
                x-allow-events sync-keyboard $::evtime
                x-sync 0
            }
        }
        mapping-notify { # 2 (pointer) is not ours
            if {[dict get $ev request] == 2} return
            # Xlib's keymap is refreshed by TK, for the same event — but
            # only after every generic handler has had it (tkEvent.c,
            # RefreshKeyboardMappingIfNeeded, which runs past us). So the
            # re-grab waits for idle: doing it here would read the OLD
            # map and re-grab the chords at their old keycodes, which is
            # precisely the bug MappingNotify exists to prevent.
            after cancel keys-remap
            after idle keys-remap
        }
        button-press { # via our sync grab: let the policy react (focus,
            # raise, whatever), then replay the frozen click to the client.
            set win [dict get $ev window]
            # A click on one of OUR OWN widgets (titlebar, grip, panel)
            # is Tk's business and was never frozen — answering the
            # server for it would be answering a grab that does not
            # exist. Everything else got here through our grab.
            if {[our-window $win]} return
            set ::evtime [dict get $ev time]
            # The policy gets first refusal, because a press with the
            # drag modifier down is the WM's gesture and not the
            # client's. Taking it changes the answer to the grab: a
            # REPLAYED press would be delivered to the client after
            # all, and the window would move with a text selection
            # dragging along inside it.
            set taken 0
            soft "click on a client" {
                if {[info exists ::managed($win)]} {
                    set taken [policy-client-press $win \
                        [expr {[dict get $ev state] & ~(2 | 16)}] \
                        [dict get $ev button] \
                        [dict get $ev x-root] [dict get $ev y-root]]
                    if {!$taken} { policy-client-click $win }
                }
            }
            # NEVER skip this: a sync grab left unanswered freezes the pointer
            x-allow-events [expr {$taken ? "async-pointer" : "replay-pointer"}] \
                $::evtime
            x-sync 0
        }
        motion-notify { # only ever ours: nothing selects for motion, so
            # these arrive under the gesture grab and nowhere else
            if {$::pointerrouter eq ""} return
            route-pointer motion [dict get $ev x-root] [dict get $ev y-root]
        }
        button-release {
            if {$::pointerrouter eq ""} return
            set ::evtime [dict get $ev time]
            route-pointer release [dict get $ev x-root] [dict get $ev y-root]
        }
    }
}

# Is this X id one of Tk's own windows — a frame, a grip, the panel? Tk
# answers by name (or refuses to, for a foreign id), which is the one
# honest test now that our clients and our decorations share a
# connection.
proc our-window {id} {
    expr {![catch {winfo pathname -displayof . $id}]}
}

# ---------------- facts the policy layer asks about ----------------
# Screen size, read fresh from the server at the moment of the decision:
# the root can be resized under us (RandR — Xephyr's -resizeable does
# exactly that), and a placement policy that cached the startup size
# would put windows off-screen for the rest of the session.
proc screen-size {} {
    if {[llength [set g [x-geometry $::root]]] == 6} {
        return [lrange $g 2 3]
    }
    return [list [winfo screenwidth .] [winfo screenheight .]]
}

# ICCCM WM_TRANSIENT_FOR: "this window is a dialog FOR that one". Returns
# 0 when unset. Placement and, later, focus-return policy need it.
proc transient-for {w} {
    soft "read WM_TRANSIENT_FOR" { x-prop-transient $w } 0
}

# The client's window title: _NET_WM_NAME (UTF8, the modern spelling)
# when present, else WM_NAME. Empty string = the client named nothing.
#
# WM_NAME is pre-Unicode territory and its TYPE decides the reading, so
# it is read AS A TEXT PROPERTY and not as bytes: UTF8_STRING is plain
# UTF-8, STRING is latin1 by the letter of ICCCM but carries UTF-8 in
# practice (a client started in the C locale — xterm does exactly
# that), and anything else is COMPOUND_TEXT, i.e. ISO 2022 with charset
# designations, a standard in its own right. A Cyrillic xterm title
# arrives as ESC-designated ISO 8859-5 from an en_US.UTF-8 client and
# as JIS X 0208 rows from a ru_RU.UTF-8 one — Xlib picks the charset by
# the CLIENT's locale — and reading either as bytes left the titlebar
# on its "клиент 0x…" fallback (owner's report, 2026-07-28).
#
# That whole ladder now lives in the shim (`prop text`), where Xlib's
# conversion table is one call away instead of four cffi declarations
# and a walk over an array of char*.
proc client-title {w} {
    if {[info exists ::NET_WM_NAME]} {
        set title [soft "read _NET_WM_NAME" { x-prop-text $w $::NET_WM_NAME }]
        if {$title ne ""} { return $title }
    }
    soft "read WM_NAME" { x-prop-text $w $::WM_NAME }
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
    lassign [soft "read property" { x-prop-get $w $prop }] type fmt value
    if {$fmt ne "8"} { return "" }
    return $value
}
proc read-prop-long {w prop} {
    lassign [soft "read property" { x-prop-get $w $prop }] type fmt value
    if {$fmt ne "32" || ![llength $value]} { return 0 }
    lindex $value 0
}

# WM_CLASS: {instance class}, {"" ""} when the client set none. The
# split on the embedded NUL is the shim's now (`prop class`), which
# also means the pair comes back as two Tcl strings and not as bytes.
proc client-class {w} {
    set parts [soft "read WM_CLASS" { x-prop-class $w }]
    list [lindex $parts 0] [lindex $parts 1]
}

# WM_CLIENT_MACHINE, "" when unset.
proc client-machine {w} {
    string trimright [read-prop-bytes $w $::WM_CLIENT_MACHINE] \x00
}

# WM_COMMAND argv as a Tcl list, {} when unset — the session-management
# relic few modern clients still write (xterm does); filter's -command
# falls back to client-cmdline when this comes back empty.
proc client-command {w} {
    set b [read-prop-bytes $w $::WM_COMMAND]
    if {$b eq ""} { return {} }
    split [string trimright $b \x00] \x00
}

# _NET_WM_PID, 0 when unset.
proc client-pid {w} {
    if {![info exists ::NET_WM_PID]} { return 0 }
    read-prop-long $w $::NET_WM_PID
}

# The names this machine goes by, first labels only: clients write
# gethostname() into WM_CLIENT_MACHINE, but Tcl's [info hostname] may
# canonicalize that through /etc/hosts to a DIFFERENT name (nodename
# "tp" -> canonical "somebody-ThinkPad-..."), so the raw kernel name
# is read too and either may vouch.
proc local-names {} {
    set names [list [info hostname]]
    soft "read /proc/sys/kernel/hostname" {
        set f [open /proc/sys/kernel/hostname r]
        lappend names [string trim [read $f]]
        close $f
    }
    lmap n $names { lindex [split $n .] 0 }
}

# The client's command line as a Tcl list, honest only for LOCAL
# clients: _NET_WM_PID is meaningful on the machine named by
# WM_CLIENT_MACHINE, so a remote client (or one declaring nothing)
# yields {} and the predicate decides what that means. Hostnames are
# compared by first label, case-insensitively — any side may carry
# the FQDN.
proc client-cmdline {w} {
    set m [lindex [split [client-machine $w] .] 0]
    if {$m eq "" || [lsearch -exact -nocase [local-names] $m] < 0} { return {} }
    set pid [client-pid $w]
    if {$pid <= 0} { return {} }
    if {[catch {
        set f [open /proc/$pid/cmdline rb]
        set b [read $f]
        close $f
    }]} { return {} }
    split [string trimright $b \x00] \x00
}

# ---------------- the client's declared icon (_NET_WM_ICON) ----------------
# The property is format=32 CARDINAL: any number of images, each
# "width, height, then width*height ARGB pixels" (rows top-down,
# straight alpha). client-icon picks the best of them for the asked
# size — the smallest one still covering it, else the biggest there
# is — resamples it down (nearest neighbor) to fit, and wraps the
# pixels into a PNG built right here: Tcl's zlib does the stream, and
# a PNG is the one photo format that carries the alpha through.
# Cached per window ("" = asked and the client has none); a
# PropertyNotify on _NET_WM_ICON or the unmanage drops the cache.
proc png-chunk {type data} {
    set crc [zlib crc32 $data [zlib crc32 $type]]
    return [binary format Iu [string length $data]]$type$data[binary format Iu $crc]
}
proc rgba-png {w h raw} {
    # raw = RGBA scanlines, each prefixed with the None filter byte
    set ihdr [binary format IuIuccccc $w $h 8 6 0 0 0]
    return "\x89PNG\r\n\x1a\n[png-chunk IHDR $ihdr][png-chunk\
 IDAT [zlib compress $raw]][png-chunk IEND {}]"
}
proc client-icon {w target} {
    if {[info exists ::iconof($w)]} { return $::iconof($w) }
    set ::iconof($w) ""
    if {![info exists ::NET_WM_ICON]} { return "" }
    lassign [soft "read _NET_WM_ICON" { x-prop-get $w $::NET_WM_ICON }] \
        atype afmt vals
    if {$afmt ne "32"} { return "" }
    # A format-32 property arrives as a LIST of integers — the shim has
    # already done the LP64 unpacking that used to be a per-pixel
    # `binary scan` at a computed offset.
    set nitems [llength $vals]
    if {$nitems < 4} { return "" }
    set entries {}
    set pos 0
    while {$pos + 2 <= $nitems} {
        set iw [expr {[lindex $vals $pos] & 0xffffffff}]
        set ih [expr {[lindex $vals [expr {$pos + 1}]] & 0xffffffff}]
        if {$iw < 1 || $ih < 1 || $pos + 2 + $iw*$ih > $nitems} break
        lappend entries [list $iw $ih [expr {$pos + 2}]]
        incr pos [expr {2 + $iw*$ih}]
    }
    if {![llength $entries]} { return "" }
    set pick ""
    foreach e $entries {
        lassign $e iw ih -
        set covers [expr {min($iw, $ih) >= $target}]
        if {$pick eq ""
                || ($covers && (!$pcov || $iw*$ih < $pw*$ph))
                || (!$covers && !$pcov && $iw*$ih > $pw*$ph)} {
            set pick $e; set pcov $covers
            lassign $e pw ph -
        }
    }
    lassign $pick iw ih off
    set ow $iw; set oh $ih
    if {$iw > $target || $ih > $target} {
        if {$iw >= $ih} {
            set ow $target; set oh [expr {max(1, $ih * $target / $iw)}]
        } else {
            set oh $target; set ow [expr {max(1, $iw * $target / $ih)}]
        }
    }
    set raw ""
    for {set y 0} {$y < $oh} {incr y} {
        append raw \x00
        set sy [expr {$y * $ih / $oh}]
        for {set x 0} {$x < $ow} {incr x} {
            set sx [expr {$x * $iw / $ow}]
            set v [lindex $vals [expr {$off + $sy*$iw + $sx}]]
            append raw [binary format cccc \
                [expr {($v >> 16) & 255}] [expr {($v >> 8) & 255}] \
                [expr {$v & 255}] [expr {($v >> 24) & 255}]]
        }
    }
    if {[catch {image create photo -data [rgba-png $ow $oh $raw]} img]} {
        puts "WM: icon 0x[format %x $w]: photo failed: $img"
        return ""
    }
    puts "WM: icon 0x[format %x $w]: _NET_WM_ICON ${iw}x${ih} -> ${ow}x${oh}"
    set ::iconof($w) $img
}
proc icon-invalidate {w} {
    if {[info exists ::iconof($w)]} {
        if {$::iconof($w) ne ""} {
            soft "delete icon image" [list image delete $::iconof($w)]
        }
        unset ::iconof($w)
    }
}

# ICCCM WM_NORMAL_HINTS, the parts we honor: the client's declared
# MINIMUM size (PMinSize; per ICCCM a missing min falls back to
# PBaseSize), its declared MAXIMUM (PMaxSize — how SDL and `wm
# resizable 0 0` spell a fixed-size window, min == max), and its
# resize increments (PResizeInc, with PBaseSize — falling back to the
# minimum — as the increment origin). Read at manage and re-read on
# PropertyNotify — a client is free to change its hints while mapped.
# Whether the increments are respected or ignored is a per-client
# policy decision (the style machinery); the substrate only keeps the
# facts.
proc read-normal-hints {w} {
    set ::minof($w) {0 0}
    set ::maxof($w) {0 0}
    set ::incof($w) {0 0}
    set ::baseof($w) {0 0}
    set ::poshintof($w) none
    set ::sizehintof($w) none
    set ::gravof($w) 1                           ;# NorthWest, the default
    # A dict from the shim, with only the fields the client actually
    # declared present — the flags are decoded there, so the ICCCM
    # fallbacks below are the only arithmetic left here.
    set h [soft "read WM_NORMAL_HINTS" { x-prop-normal-hints $w }]
    if {![dict size $h]} return
    if {[dict exists $h min]} {
        lassign [dict get $h min] minw minh
        set ::minof($w) [list [expr {max($minw,0)}] [expr {max($minh,0)}]]
    } elseif {[dict exists $h base]} {           ;# PBaseSize as min (ICCCM)
        lassign [dict get $h base] basew baseh
        set ::minof($w) [list [expr {max($basew,0)}] [expr {max($baseh,0)}]]
    }
    # Zero stays "unbounded". A max under the min (broken hints) needs
    # no repair here: apply-size-hints clamps the minimum LAST, so the
    # min wins the contradiction wherever the two meet.
    if {[dict exists $h max]} {
        lassign [dict get $h max] maxw maxh
        set ::maxof($w) [list [expr {max($maxw,0)}] [expr {max($maxh,0)}]]
    }
    if {[dict exists $h inc]} {
        lassign [dict get $h inc] winc hinc
        set ::incof($w) [list [expr {max($winc,0)}] [expr {max($hinc,0)}]]
    }
    if {[dict exists $h base]} {                 ;# PBaseSize as inc origin
        lassign [dict get $h base] basew baseh
        set ::baseof($w) [list [expr {max($basew,0)}] [expr {max($baseh,0)}]]
    } else {                                     ;# ICCCM: base defaults to min
        set ::baseof($w) $::minof($w)
    }
    # The position claim: USPosition = the user typed it (xterm
    # -geometry, Tk wm geometry), PPosition = the program picked it.
    # The x/y INSIDE the hints are obsolete — the honest position is
    # the window's own geometry; only the claim matters here.
    if {[dict exists $h position]} {
        set ::poshintof($w) [dict get $h position]
    }
    # The SIZE claim is a separate flag and separately meant: `xterm
    # -geometry 20x20` sets USSize and no USPosition whatever
    # (measured, 2026-07-30), so "the user said where" and "the user
    # said how big" are two questions and this layer keeps both facts.
    if {[dict exists $h size]} {
        set ::sizehintof($w) [dict get $h size]
    }
    if {[dict exists $h gravity]} {
        set grav [dict get $h gravity]
        if {$grav >= 1 && $grav <= 10} { set ::gravof($w) $grav }
    }
}

# The position claim and its gravity, for placement and move requests.
proc client-position-hint {w} {
    set kind none; set grav 1
    if {[info exists ::poshintof($w)]} { set kind $::poshintof($w) }
    if {[info exists ::gravof($w)]}    { set grav $::gravof($w) }
    list $kind $grav
}
# ...and the size claim: user|program|none.
proc client-size-hint {w} {
    if {[info exists ::sizehintof($w)]} { return $::sizehintof($w) }
    return none
}

# Where the client window sat at manage time (root coords, from the
# same XGetGeometry that read its honest size).
proc client-initial-position {w} {
    if {[info exists ::mapxyof($w)]} { return $::mapxyof($w) }
    return {}
}

# The declared minimum, {0 0} when the client declares nothing.
proc client-min-size {w} {
    if {[info exists ::minof($w)]} { return $::minof($w) }
    return {0 0}
}

# Everything a size decision needs: {minw minh incw inch basew baseh
# maxw maxh}. Zero increments = the client declared none; zero max =
# unbounded on that axis.
proc client-size-hints {w} {
    set min {0 0}; set inc {0 0}; set base {0 0}; set max {0 0}
    if {[info exists ::minof($w)]}  { set min $::minof($w) }
    if {[info exists ::incof($w)]}  { set inc $::incof($w) }
    if {[info exists ::baseof($w)]} { set base $::baseof($w) }
    if {[info exists ::maxof($w)]}  { set max $::maxof($w) }
    concat $min $inc $base $max
}

# Both axes pinned (min == max, nonzero): the client declared itself
# non-resizable — SDL's spelling for every window made without
# SDL_WINDOW_RESIZABLE, Tk's for `wm resizable 0 0`. What the fact
# means — which gestures turn into carries, which verbs refuse — is
# the policy's business.
proc client-fixed-size-p {w} {
    lassign [client-size-hints $w] minw minh - - - - maxw maxh
    expr {$maxw > 0 && $maxh > 0 && $minw == $maxw && $minh == $maxh}
}

# ICCCM 4.1.3.1: a managed window must carry WM_STATE (state + icon
# window). Toolkits and every wmctrl/xdotool-class tool use its presence
# to tell "managed by a WM" from "still wild" — we never set it, which
# left GTK guessing about our clients.
proc set-wm-state {w state} {
    # WithdrawnState=0, NormalState=1, IconicState=3; the second long is
    # the icon window, which we do not use.
    if {[catch {x-prop-set $w $::WM_STATE $::WM_STATE 32 [list $state 0]} err]} {
        puts "WM: WM_STATE update failed: $err"
    }
}

# EWMH _NET_FRAME_EXTENTS: how thick the decoration is on each side,
# {left right top bottom}. A client cannot measure this for itself —
# its own geometry is inside the frame — and toolkits use it to place
# what they position by the WINDOW rather than by the widget: menus and
# popups anchored to a corner, "remember my position" arithmetic, input
# method hint windows. Absent, GTK falls back to walking the window
# tree, and whatever it concludes we never confirmed.
#
# Published at manage and again whenever the decoration metrics move
# (the title font). Clients may also ASK before their first map, when
# there is no frame yet to measure — see the request below; our
# decoration is uniform, so the answer is honest either way.
proc publish-frame-extents {w} {
    if {![info exists ::NET_FRAME_EXTENTS]} return
    set e [soft "frame extents" { policy-frame-extents $w } {0 0 0 0}]
    if {[llength $e] != 4} return
    soft "publish _NET_FRAME_EXTENTS" \
        [list set-prop-longs $w $::NET_FRAME_EXTENTS 6 $e]   ;# XA_CARDINAL
    soft "publish _KDE_NET_WM_FRAME_STRUT" \
        [list set-prop-longs $w $::KDE_FRAME_STRUT 6 $e]
}

# ---------------- what the desk looks like from outside ----------------
# _NET_CLIENT_LIST is the managed windows in the order they arrived;
# _NET_CLIENT_LIST_STACKING is the same set bottom-to-top — and that
# answer is THE POLICY'S client-stacking: the model speaks, layer
# first, and the server agrees with the model rather than being asked
# (the comment over it says why that is right even mid-restack). A
# server-walking twin of it lived right here, sure that the server
# was the only honest source, and lost the redefinition race; the one
# tree read still standing is adopt-existing's, at startup, before
# there is a model to ask.
#
# Coalesced through the idle queue: a raise happens on every click, and
# publishing is a round trip plus two property writes.
keep client_order {}          ;# managed windows, oldest first
keep clientlist_pending 0
proc publish-client-list {} {
    if {$::clientlist_pending || ![info exists ::NET_CLIENT_LIST]} return
    set ::clientlist_pending 1
    after idle {set ::clientlist_pending 0; publish-client-list-now}
}
proc publish-client-list-now {} {
    if {![info exists ::NET_CLIENT_LIST]} return
    set live {}
    foreach w $::client_order {
        if {[info exists ::managed($w)]} { lappend live $w }
    }
    set ::client_order $live
    soft "publish _NET_CLIENT_LIST" \
        [list set-prop-longs $::root $::NET_CLIENT_LIST 33 $live]  ;# XA_WINDOW
    soft "publish _NET_CLIENT_LIST_STACKING" \
        [list set-prop-longs $::root $::NET_CLIENT_LIST_STACKING 33 \
            [client-stacking]]
}
# _NET_WORKAREA — the screen minus whatever the policy reserves (our
# panel and tray strips). Toolkits place popups and maximize by it, and
# a WM that leaves it unset makes everyone guess the full screen.
# Republished whenever the policy's furniture moves; _NET_DESKTOP_GEOMETRY
# follows the root's own size, which RandR can change under us.
#
# And it is the one place that knows the workarea CHANGED, which is a
# fact of its own: every cause — a config reload, a panel that moved
# side or grew a row, a tray icon that widened the band, a RandR resize
# under everything — arrives here and nowhere else. So the comparison
# lives here rather than in each of them, and the policy hears about
# the change once, with both rects in hand. The remembered rect is
# updated BEFORE the hook runs, so nothing the policy does inside it can
# be read as a second change.
keep wa_published {}
# HOLD the consequences while a config is being read. Publishing the
# property is fine at any moment — a client that asks gets today's
# answer — but telling the POLICY that the workarea changed is a
# decision about every window on the desk, and it must not be taken
# from half a config.
#
# A reload tears the panel down and builds it again, so the workarea
# flaps: 1745 -> the whole screen -> 1797. The first of those hops used
# to be handled the instant the config's first line touched the panel,
# with the style rules not yet declared — so `increments` read as
# `respect`, maximize-fit snapped, and a window whose size is quantized
# was not recognized as spanning. Three windows out of six moved, the
# three with increments did not, and from then on they were out of sync
# for good: the second hop found them matching no edge at all and
# correctly left them alone. That is the owner's report (2026-07-30),
# and his "it seems to depend on a pause" was the same thing seen from
# outside — what it depended on was WHERE in his config the line that
# rebuilds the panel sat.
#
# So a reload is ONE transition, from the workarea before it to the
# workarea after the whole config has spoken. Held, the intermediate
# hops publish and say nothing; released, the difference is reported
# once. It also stops every window bouncing to full width and back on
# every reload, which was always visible and always pointless.
keep wa_hold 0
proc workarea-held {script} {
    set ::wa_hold 1
    try {
        uplevel 1 $script
    } finally {
        set ::wa_hold 0
        publish-workarea
    }
}
proc publish-workarea {} {
    if {![info exists ::NET_WORKAREA]} return
    set a [soft "workarea" { policy-workarea } {}]
    if {[llength $a] != 4} return
    soft "publish _NET_WORKAREA" \
        [list set-prop-longs $::root $::NET_WORKAREA 6 $a]   ;# XA_CARDINAL
    soft "publish _NET_DESKTOP_GEOMETRY" \
        [list set-prop-longs $::root $::NET_DESKTOP_GEOMETRY 6 [screen-size]]
    if {$::wa_hold} return
    # The change is judged on the PER-MONITOR picture, not on the one
    # published rect: a monitor resized or moved under an unchanged
    # _NET_WORKAREA still moved somebody's workarea, and the windows
    # standing on it have edges to re-glue to.
    set all [soft "workareas" { policy-workareas } {}]
    if {![dict size $all]} return
    if {$all eq $::wa_published} return
    set was $::wa_published
    set ::wa_published $all
    # The FIRST publication is not a change: there was no workarea
    # before it, and there are no windows either.
    if {$was eq ""} return
    # A line PER MONITOR whose workarea moved — the raw dicts are for
    # the policy, not for a log a human greps.
    dict for {key m} $all {
        set nw [dict get $m wa]
        set ow [expr {[dict exists $was $key]
                      ? [dict get $was $key wa] : "—"}]
        if {$ow ne $nw} { puts "WM: workarea ($key) $ow -> $nw" }
    }
    dict for {key m} $was {
        if {![dict exists $all $key]} {
            puts "WM: workarea ($key) [dict get $m wa] -> gone"
        }
    }
    soft "workarea changed" [list policy-workarea-changed $was $all]
}

# _NET_WM_STATE — the EWMH state LIST. Two members are ours:
# _NET_WM_STATE_HIDDEN while a window is iconic (the property EWMH-aware
# clients read to learn they are minimized — wine's X11 driver among
# them — and pagers use to grey an entry out), and
# _NET_WM_STATE_FULLSCREEN while it is fullscreen.
#
# It is a list, and that is the whole reason this is a BUILDER and not a
# literal at each call site. The states are not each other's business: a
# fullscreen window that gets iconified would, published literally as
# "hidden", have its fullscreen quietly un-published — and a client that
# reads the property on the way back would learn it had been taken out
# of a state we are still holding it in. So every publisher says "what
# is true of w now" and nothing else has to remember the rest.
#
# The ORDER of the list is the EWMH spec's own listing order (STICKY,
# MAXIMIZED_VERT, MAXIMIZED_HORZ, HIDDEN, FULLSCREEN, ABOVE/BELOW),
# and it is load-bearing, not tidiness. The property is a SET, but
# emacs folds it left to right into ONE size-state slot (xterm.c,
# x_get_current_wm_state): a MAXIMIZED atom read AFTER the FULLSCREEN
# one overwrites it, the frame concludes it is merely maximized, and
# toggle-frame-fullscreen keeps asking for fullscreen instead of out
# of it — the owner's desk, 2026-08-08: emacs born maximized could
# enter fullscreen and never leave, because we published FULLSCREEN
# first and the maximized pair right after. The desktops emacs grew
# up under publish in the spec's order, so the strongest word lands
# last; now so does ours.
proc net-wm-state-atoms {w} {
    set atoms {}
    if {[llength [info commands desk-sticky-p]] && [desk-sticky-p $w]} {
        lappend atoms $::NET_WM_STATE_STICKY
    }
    # The maximized mark is the policy's (::maxsaved the saved way
    # back, ::maxaxes the axes held), and this builder only READS it:
    # what is published is what the maximize machinery believes,
    # wherever it changed hands — per axis, so a window maximized tall
    # answers MAXIMIZED_VERT alone.
    if {[info exists ::maxaxes($w)]} {
        if {"v" in $::maxaxes($w)} {
            lappend atoms $::NET_WM_STATE_MAXIMIZED_VERT
        }
        if {"h" in $::maxaxes($w)} {
            lappend atoms $::NET_WM_STATE_MAXIMIZED_HORZ
        }
    }
    if {[info exists ::iconic($w)]} { lappend atoms $::NET_WM_STATE_HIDDEN }
    if {[info exists ::fullscreen($w)]} { lappend atoms $::NET_WM_STATE_FULLSCREEN }
    # ...and where the window sits in the stack, when that is a thing
    # it asked for rather than the ordinary place (see layer-declared).
    if {[llength [info commands layer-declared]]} {
        set n [layer-declared $w]
        if {$n > $::LAYER_NORMAL && $n <= $::LAYER_ABOVE} {
            lappend atoms $::NET_WM_STATE_ABOVE
        } elseif {$n < $::LAYER_NORMAL && $n >= $::LAYER_BELOW} {
            lappend atoms $::NET_WM_STATE_BELOW
        }
    }
    return $atoms
}
proc publish-net-wm-state {w} { set-net-wm-state $w [net-wm-state-atoms $w] }
proc set-net-wm-state {w atoms} {
    if {![info exists ::NET_WM_STATE]} return
    soft "publish _NET_WM_STATE" \
        [list set-prop-longs $w $::NET_WM_STATE 4 $atoms]   ;# XA_ATOM
}

# ---------------- iconification ----------------
# ICCCM 4.1.4: a client asks to be iconified by sending WM_CHANGE_STATE
# with IconicState to the root — that is all XIconifyWindow() does, and
# it is the same message Tk's `wm iconify` and wine's Win32 SW_MINIMIZE
# (its X11 driver calls XIconifyWindow for a managed window) end up
# sending. Ignoring it is NOT neutral: the asking side often minimizes
# on its own account first and then waits for the WM to agree, so the
# window sits there mapped while the app behind it believes itself
# hidden and stops painting (owner's report on wine, 2026-07-28).
#
# So the request always gets an ANSWER, and the policy layer picks
# which: iconify-client (do it) or refuse-iconify (say no, audibly).
# An iconic window stays MANAGED — it has to come back — and the way
# back is the window list, which shows it with its state.
proc iconify-client {w} {
    if {![info exists ::managed($w)] || [info exists ::iconic($w)]} return
    set ::iconic($w) 1
    # An iconic globally-active window starts CLEAN: ::wine_dirty
    # flips to 1 the moment another client takes the focus while it
    # sits iconic (paint-focus) — the exact ingredient that poisons
    # wine's restore, and the only case deiconify-client arms the
    # restore bounce for. Windows restored untouched dance nothing.
    if {[client-globally-active $w]} { set ::wine_dirty($w) 0 }
    # THE FOCUS-LOSS ORDER IS PER-MODEL, and both halves were paid for
    # in blood on the live desk.
    #
    # For everyone ordinary (passive and locally-active — chromium,
    # signal, the toolkits) THE FOCUS LEAVES BEFORE THE WINDOW DOES.
    # Unmapping the focus window makes the SERVER move the focus — a
    # revert walks it up to our frame, and the client reads the loss
    # off a dirty pair: FocusOut(mode=Grab) from the chord's passive
    # grab, FocusOut(mode=WhileGrabbed) from the revert, no closing
    # Ungrab ever. Chromium's platform layer survives that arithmetic
    # but its views activation does not: the window came back to an
    # honest FocusIn(Normal) and stayed keyboard-dead until the focus
    # left and returned once more — alt-tab-away-and-back, the manual
    # cure that named the fix (the owner's live wedge, 2026-08-12,
    # A/B-proved on the desk). Parked FIRST, the revert never exists
    # and every such client sees the plain FocusOut(Normal) of an
    # ordinary SetInputFocus while it is still mapped.
    #
    # The GLOBALLY ACTIVE client (input=False + WM_TAKE_FOCUS — wine)
    # wants the OPPOSITE: the loss hidden BEHIND the UnmapNotify, the
    # order the July war installed (2026-07-28, WINEDEBUG=+focus,
    # +event). A FocusOut it reads while still mapped kills its Win32
    # focus while the minimize keeps its foreground — and the
    # invitation on the way back becomes a SetForegroundWindow onto
    # the window that never stopped being foreground: a no-op, the
    # Win32 focus stays dead, and no amount of re-activation revives
    # it (measured on smsrc, 2026-08-12: every minimize round with
    # the park first wedged it; the same round with the loss hidden
    # is what wine has always survived — seeing the UnmapNotify
    # first, it flags the window as reparenting and IGNORES the
    # revert that follows, keeping its inner focus to restore).
    #
    # The refocus is DEFERRED either way (refocus-soon): a burst —
    # Super+d minimizing the desk — parks once and aims once at idle,
    # instead of handing each next victim a focus it loses a
    # millisecond later. "Was it focused" is decided here and not
    # re-read below: the X calls can run a nested event drain inside
    # which the watchdog parks and clears ::focused (owner's report,
    # 2026-07-28 — the mouse gesture handed the focus to nobody while
    # the keyboard gesture handed it on).
    set was_focused [expr {$::focused == $w}]
    set hides [expr {$was_focused && [client-globally-active $w]}]
    if {$was_focused && !$hides} {
        set ::focused 0
        focus-park "the focused window is being iconified"
        refocus-soon
    }
    incr ::skip_unmap($w)      ;# our own unmap is not the client withdrawing
    # WM_STATE SPEAKS BEFORE THE WINDOW GOES (experiment): with
    # IconicState already read, wine's UnmapNotify handler does not
    # take the unmap for a reparent (its condition is literally
    # «current wm_state == NormalState») — it knows this is a
    # minimize, processes the loss honestly, and the return
    # invitation activates for real.
    set-wm-state $w 3          ;# IconicState
    publish-net-wm-state $w
    # XSync between the client's unmap and the frame going down on
    # Tk's side: the round trip guarantees the server processed the
    # client unmap before the decoration speaks.
    x-unmap $w
    x-sync 0
    policy-iconified $w        ;# the decoration goes with it
    x-sync 0
    puts "WM: iconified 0x[format %x $w]"
    if {$hides} {
        set ::focused 0
        focus-park "the focused window was iconified"
        refocus-soon
    }
}
proc deiconify-client {w} {
    if {![info exists ::managed($w)] || ![info exists ::iconic($w)]} return
    unset ::iconic($w)
    # the dirty verdict is read (and the mark retired) HERE, before any
    # early return: an off-desk restore must not leave a stale mark for
    # paint-focus to keep dirtying
    set dirty 0
    if {[info exists ::wine_dirty($w)]} {
        set dirty $::wine_dirty($w)
        unset ::wine_dirty($w)
    }
    set-wm-state $w 1          ;# NormalState
    publish-net-wm-state $w
    # ...AND IT COMES BACK ON ITS OWN DESK. Minimizing never moved the
    # window anywhere — ::deskof is untouched by the whole iconic
    # business — so restoring must not move it either. Unconditional,
    # this mapped the window wherever the user happened to be standing,
    # and a window belonging to desk 1 sat on desk 2 looking sticky
    # until the next switch swept it off (the owner, 2026-08-04: "при
    # deiconify оно становится как бы sticky").
    #
    # Nobody is short-changed by that: every road a HAND takes to a
    # window — a panel button, a row of the list — goes through
    # panel-focus-hit, which follows the desk first and only then asks
    # for this. What is left is a CLIENT restoring ITSELF, and a client
    # has no business pulling a window onto the desk in front of
    # somebody else's eyes.
    if {![desk-here-p $w]} {
        set ::offdesk($w) 1    ;# invisible for a second reason now
        puts "WM: deiconified 0x[format %x $w] — on desk [desk-name [desk-of $w]],\
 not this one"
        return
    }
    unset -nocomplain ::offdesk($w)
    policy-deiconified $w
    x-map $w
    x-sync 0
    puts "WM: deiconified 0x[format %x $w]"
    focus-to $w
    # THE RESTORE AND THE FOCUS ARE FED SEPARATELY (wine workaround):
    # wine 11.15 pumps the restore's activation while WS_MINIMIZE is
    # still set (win32u message.c orders SetActiveWindow before the
    # SC_RESTORE that clears the style). Harmless — unless the Win32
    # focus was LOST while the window sat iconic, i.e. the focus
    # visited another client in between (the ::wine_dirty verdict
    # above): then the hand-off inside that activation dies against
    # the minimized-window refusal and seals, and only a full
    # deactivate/activate cycle brings the keyboard back — the manual
    # alt-tab-away-and-back cure, which the two beats below automate.
    # The invitation already went out (the window focuses as fast as
    # any other); beat 2 then deactivates, beat 3 re-invites.
    #
    # The beats are spaced by TIMERS, not signals, because no signal
    # exists: wine's re-ask fires only when its tracked
    # _NET_ACTIVE_WINDOW disagrees and its WM_STATE serials are
    # settled (on the stand it showed in one round out of two), and
    # the app's PUMPING of a publish — the thing each beat must wait
    # out — is invisible from X. Each beat re-verifies the desk
    # instead: any interference (another activation, a desk switch, a
    # re-minimize, the window leaving) dissolves the dance with a log
    # line and the interfering action stands.
    if {$dirty && [info exists ::NET_ACTIVE] && $::nofocus != 0} {
        puts "WM: deiconify 0x[format %x $w]: restore bounce armed"
        after $::wine_bounce_ms \
            [list wine-restore-beat2 $w [incr ::wine_bounce_gen] 0]
    }
}
# The restore bounce pacing. One knob-less global: the stand passed
# down to 60 ms with an idle app; 150 keeps a 2.5× margin for a busy
# one, and the whole dance stays a ~300 ms blink.
keep wine_bounce_ms 150
keep wine_bounce_gen 0       ;# any newer dance retires older beats
# Beat 2 of the restore bounce: the deactivation. It only counts while
# wine believes the window is FOREGROUND (a foreground loss at
# previous==hwnd is the one shape that clears the active window and
# the poisoned hwndFocus) — the invitation's confirmed FocusIn has
# made that true by now, or we wait one more beat for it. Parking
# through focus-park keeps the books straight: ::focused drops to 0,
# so beat 3's confirmed FocusIn is a CHANGE again and paint-focus
# re-publishes the window — the publish that drives wine's
# reactivation (a raw x-focus-set left ::focused standing and the
# re-publish never happened: a day of dead stands).
proc wine-restore-beat2 {w g retry} {
    if {$g != $::wine_bounce_gen} return
    if {![info exists ::managed($w)] || [info exists ::iconic($w)]
            || ![desk-here-p $w]} {
        puts "WM: restore bounce 0x[format %x $w]: called off (the\
 window left)"
        return
    }
    if {$::focused != $w} {
        if {$::invited == $w && $retry < 2} {
            # our invitation is still unanswered — wine is slow today;
            # give it one more beat (twice, then give up)
            after $::wine_bounce_ms \
                [list wine-restore-beat2 $w $g [incr retry]]
            return
        }
        puts "WM: restore bounce 0x[format %x $w]: called off (the\
 focus went elsewhere)"
        return
    }
    puts "WM: restore bounce 0x[format %x $w]: park + holder publish"
    focus-park "restore bounce"
    # the park published None; overwrite with the holder's real id — a
    # foreign window resolves to wine's desktop and actually
    # deactivates, a None value resolves to nothing and is a no-op
    soft "publish _NET_ACTIVE_WINDOW (restore bounce)" \
        { set-prop-longs $::root $::NET_ACTIVE 33 [list $::nofocus] }
    after $::wine_bounce_ms [list wine-restore-beat3 $w $g]
}
proc wine-restore-beat3 {w g} {
    if {$g != $::wine_bounce_gen} return
    if {![info exists ::managed($w)] || [info exists ::iconic($w)]
            || ![desk-here-p $w]} {
        puts "WM: restore bounce 0x[format %x $w]: called off (the\
 window left)"
        return
    }
    if {$::focused != 0 || $::invited != 0} {
        puts "WM: restore bounce 0x[format %x $w]: called off (somebody\
 took the focus mid-dance)"
        return
    }
    puts "WM: restore bounce 0x[format %x $w]: re-inviting"
    focus-to $w
}

# ---------------- virtual desks ----------------
#
# Several independent sets of windows on one screen, fvwm's Desks. The
# whole of the mechanism is VISIBILITY: a window belongs to a desk (or
# to all of them — sticky), the desk one is on decides which windows
# are on the screen, and NOTHING about geometry changes. That is what
# makes it cheap, and it is the reason the other half of fvwm's model —
# Pages, a viewport scrolling over one big virtual screen — is
# deliberately not here: pages are a COORDINATE SYSTEM, and every clamp,
# maximize, resistance and placement decision on this desk would have to
# subtract a viewport origin (the owner's call, 2026-08-04).
#
# THE STATE A WINDOW ELSEWHERE IS IN is the one real decision, and it is
# fvwm's answer (the owner, same day): the frame is unmapped and WM_STATE
# stays NormalState. ICCCM does not describe that combination — the
# formally clean alternative is IconicState, which metacity uses — but a
# client told it is iconic believes it was MINIMIZED, and the ones that
# paint by their state (emacs, telega) stop painting. So the window is
# taken off the screen and told nothing, which is the truth: nobody
# minimized it.
#
# The cost of that choice is that "not here" and "iconic" stop being
# distinguishable from the outside, so we keep the difference ourselves
# — ::offdesk, an array parallel to ::iconic. Every list, every refocus
# and every count asks the two separately.
array set deskof {}          ;# client -> its desk, or "all" for sticky
array set offdesk {}         ;# client -> on the screen? absent = yes
proc desk-of {w} {
    expr {[info exists ::deskof($w)] ? $::deskof($w) : $::desk}
}
proc desk-sticky-p {w} { expr {[desk-of $w] eq "all"} }
# DESKS ARE COUNTED FROM ONE WHEREVER A HUMAN READS THEM, and from zero
# everywhere else. The protocol has no choice — EWMH's
# _NET_CURRENT_DESKTOP and _NET_WM_DESKTOP are zero-based and stay so —
# and neither has the code, which indexes. But the keys say Super+1 for
# the first desk, so a list or a log that called it 0 would be the desk
# contradicting itself (the owner, 2026-08-04). One proc, and every
# human-facing string goes through it.
proc desk-name {d} { expr {$d eq "all" ? "all" : $d + 1} }
proc desk-here-p {w} {
    set d [desk-of $w]
    expr {$d eq "all" || $d == $::desk}
}
# How many desks there are. One is not a special case anywhere below —
# it just means every window is here — but it IS the default, so a desk
# that was never told about desks behaves exactly as it always did.
# A WISH, NOT A DEED — like every other knob a config turns. A config
# file and a customization both get to say how many desks there are,
# and the LAST word is the one that counts; if the first were applied
# on the spot, `set-desks 1` in the config would collapse every window
# onto the first desk and the customization's `set-desks 2` would
# restore the count over a desk that had already been flattened (the
# owner, 2026-08-04). So this records the number and the consequences
# run ONCE, at idle, on whatever the number finally is.
keep desks_pending 0
proc desks-apply-soon {} {
    if {$::desks_pending} return
    set ::desks_pending 1
    after idle {set ::desks_pending 0; desks-apply}
}
# ...and here is what a count actually costs, once the config has
# stopped talking.
proc desks-apply {} {
    set n $::ndesks
    if {$::desk >= $n} { desk-go [expr {$n - 1}] }
    publish-desk-count
    # A window parked on a desk that no longer exists comes home rather
    # than becoming unreachable — a mechanism one turns DOWN must not
    # eat windows.
    foreach w [array names ::deskof] {
        set d $::deskof($w)
        if {$d ne "all" && $d >= $n} { set ::deskof($w) [expr {$n - 1}] }
    }
    # ...and NOBODY IS LEFT DESKLESS. Every road into ::managed now
    # declares a desk (policy-booked covers the one that used to skip
    # it — a window managed INTO iconic), but a LIVE desk can still be
    # carrying windows from before that was true: procs are replaced
    # under a running desk and its state is kept (Reread, and the
    # restart keeps the windows), so a window managed by yesterday's
    # code has no ::deskof entry, desk-of answers "wherever you are",
    # and it follows every switch — worse, it CAMPS at the head of the
    # focus history, always «here», refocused and re-crowned most
    # recent by every switch, a loop nothing on the desk could break
    # (the owner's live desk, 2026-08-08: a PDF minimized across a
    # restart stole the focus on every return, from UNDER other
    # windows). So the invariant is also SEALED here, where the count
    # settles: whoever has no desk gets one, and the declaration reads
    # the window's own _NET_WM_DESKTOP first — the desk it remembers is
    # the desk it gets.
    foreach w [array names ::managed] {
        if {![info exists ::deskof($w)]
                && [llength [info commands client-desk-declare-and-paint]]} {
            soft "declare a desk for the deskless" \
                [list client-desk-declare-and-paint $w]
        }
        publish-desk-of $w
        desk-visibility $w
    }
    # The keys follow the count: the bundle binds one digit per desk,
    # so the number changing is the one thing that makes its member
    # list wrong. Re-applied with whatever parameters it is wearing.
    if {[llength [info commands wm-keys]] && [dict exists $::key_bundles desks]} {
        set p [dict get $::key_bundles desks params]
        soft "re-apply the desks bundle" \
            [list wm-keys desks {*}[concat {*}[lmap {k v} $p {list -$k $v}]]]
    }
}
proc publish-desk-count {} {
    if {![info exists ::NET_NUMBER_OF_DESKTOPS]} return
    soft "publish _NET_NUMBER_OF_DESKTOPS" \
        { set-prop-longs $::root $::NET_NUMBER_OF_DESKTOPS 6 [list $::ndesks] }
    soft "publish _NET_CURRENT_DESKTOP" \
        { set-prop-longs $::root $::NET_CURRENT_DESKTOP 6 [list $::desk] }
}
# What the WINDOW says about its own desk, if anything: the EWMH
# property, read as a request before the map and as a memory after a
# restart. "" when it says nothing, `all` for the all-ones CARDINAL.
proc client-asked-desk {w} {
    if {![info exists ::NET_WM_DESKTOP]} { return "" }
    lassign [soft "read _NET_WM_DESKTOP" {
        x-prop-get $w $::NET_WM_DESKTOP
    }] type fmt value
    if {$fmt ne "32" || ![llength $value]} { return "" }
    set d [lindex $value 0]
    expr {$d == 0xffffffff ? "all" : $d}
}
# _NET_WM_DESKTOP, per window: the desk it is on, or the all-ones
# CARDINAL that EWMH spells sticky.
proc publish-desk-of {w} {
    if {![info exists ::NET_WM_DESKTOP]} return
    set d [desk-of $w]
    soft "publish _NET_WM_DESKTOP" [list set-prop-longs $w $::NET_WM_DESKTOP 6 \
        [list [expr {$d eq "all" ? 0xffffffff : $d}]]]
}
# Put w where it belongs on the screen — the one place that maps or
# unmaps for a desk, so the bookkeeping cannot drift from the picture.
#
# The unmap is the client's own, and the ORDER is the one iconify
# fought for: the client's unmap reaches the server before the frame
# goes, or wine sees a bare FocusOut and comes back keyboard-dead. What
# is NOT done here is the other half of iconify — WM_STATE is left at
# NormalState, which is the whole point (see above).
proc desk-visibility {w} {
    if {![info exists ::managed($w)]} return
    if {[info exists ::iconic($w)]} return   ;# minimized outranks: it is already off
    set want [desk-here-p $w]
    set now [expr {![info exists ::offdesk($w)]}]
    if {$want == $now} return
    if {$want} {
        unset -nocomplain ::offdesk($w)
        policy-deiconified $w      ;# the decoration comes back up
        x-map $w
        x-sync 0
    } else {
        # The per-model focus-loss order — the iconify rule, see
        # iconify-client: parked before the unmap for everyone
        # ordinary, hidden behind it for the globally active.
        set was_focused [expr {$::focused == $w}]
        set hides [expr {$was_focused && [client-globally-active $w]}]
        if {$was_focused && !$hides} {
            set ::focused 0
            focus-park "the focused window is leaving the screen"
            refocus-soon
        }
        set ::offdesk($w) 1
        incr ::skip_unmap($w)      ;# our own unmap is not the client withdrawing
        x-unmap $w
        x-sync 0
        policy-iconified $w        ;# ...and the decoration goes with it
        x-sync 0
        if {$hides} {
            set ::focused 0
            focus-park "the focused window left the screen"
            refocus-soon
        }
    }
}
# EVERY WINDOW AT ONCE, which is not the same as every window one at a
# time. The leavers go first — the screen empties before it fills, so
# nothing arrives on top of something that is about to vanish — and the
# arrivals come back TOPMOST FIRST, each seated under the one before
# it (policy-desk-under). One flush at the end instead of one per
# window: `wm deiconify` waits for its own MapNotify, so ten windows
# used to cost ten round trips with the screen redrawn between them,
# which is exactly what one could see happening.
proc desk-apply {} {
    set hide {}
    set show {}
    foreach w [array names ::managed] {
        if {[info exists ::iconic($w)]} continue    ;# minimized outranks
        set here [desk-here-p $w]
        set on [expr {![info exists ::offdesk($w)]}]
        if {$here && !$on} {
            lappend show $w
        } elseif {!$here && $on} {
            lappend hide $w
        }
    }
    # The per-model focus-loss order (the iconify rule, see
    # iconify-client): parked ahead of the unmaps for everyone
    # ordinary — the switch never makes the server revert off a
    # vanishing focus window, and the leaver reads a plain
    # FocusOut(Normal) while still mapped. The globally active leaver
    # keeps its loss hidden behind the UnmapNotify and is parked
    # after. desk-go aims at the new desk's window right after this
    # returns; the deferred refocus is only the net under a caller
    # that does not.
    set leaver 0
    if {$::focused != 0 && [lsearch -exact $hide $::focused] >= 0} {
        set leaver $::focused
    }
    if {$leaver != 0 && ![client-globally-active $leaver]} {
        set ::focused 0
        focus-park "the focused window is leaving the desk"
        refocus-soon
        set leaver 0
    }
    foreach w $hide {
        set ::offdesk($w) 1
        incr ::skip_unmap($w)    ;# our own unmap is not the client withdrawing
        x-unmap $w
    }
    if {[llength $hide]} {
        x-sync 0                 ;# the client unmaps land before the frames go
        foreach w $hide { policy-desk-hide $w }
    }
    if {$leaver != 0} {
        set ::focused 0
        focus-park "the focused window left the desk"
        refocus-soon
    }
    set prev ""
    foreach w [policy-desk-order $show] {
        unset -nocomplain ::offdesk($w)
        policy-desk-show $w
        x-map $w
        policy-desk-under $w $prev
        set prev $w
    }
    if {[llength $show] || [llength $hide]} {
        update idletasks
        x-sync 0
        puts "WM: desk $::desk: [llength $show] shown, [llength $hide] hidden"
    }
}

# Go to desk n. The focus follows: the most recently focused window
# that is THERE, else the topmost thing there that can take a focus,
# and the holder only when the desk is truly empty — a desk one
# switches to with the keyboard still aimed at a window one can no
# longer see would be a trap.
proc desk-go {n} {
    if {![string is integer -strict $n] || $n < 0 || $n >= $::ndesks} {
        puts "WM: no desk [desk-name $n]: there are $::ndesks"
        return
    }
    if {$n == $::desk} return
    set was $::desk
    set ::desk $n
    desk-apply
    publish-desk-count
    puts "WM: desk [desk-name $was] -> [desk-name $n]"
    policy-desk-changed $was $n
    set want 0
    foreach cand $::focus_hist {
        if {[info exists ::managed($cand)] && [desk-here-p $cand]
                && ![info exists ::iconic($cand)]} { set want $cand; break }
    }
    if {$want == 0} {
        # A DRY HISTORY IS NOT AN EMPTY DESK. The history starts over
        # with the instance, so right after a restart a desk full of
        # ADOPTED windows has nobody in it — and this switch used to
        # park as if there were nothing to focus, leaving a lone
        # undecorated firefox looking exactly like an active window
        # that eats no keys, until an alt-tab (the owner, 2026-08-14).
        # The deferred refocus is no net here either: it fires inside
        # desk-apply's update idletasks, before the freshly
        # deiconified frame is viewable, so the server refuses that
        # aim — and the refusal used to be the end of it. The
        # fallback is adoption's own (policy-adopt-settled): the
        # topmost window that can take a focus.
        foreach w [lreverse [client-stacking]] {
            if {[refocus-ok $w 0]} { set want $w; break }
        }
    }
    if {$want == 0} {
        # desk-apply already parked when it hid the focus window; a
        # second parking would say the same thing twice.
        if {$::focused != 0} { focus-park "the new desk is empty" }
    } else {
        focus-to $want
    }
}
# Send a window to another desk — or to all of them. The desk does NOT
# follow it: "get this out of my way" would be a poor thing to answer
# by taking the user there.
proc desk-send {w n} {
    if {![info exists ::managed($w)]} return
    if {$n ne "all"} {
        if {![string is integer -strict $n] || $n < 0 || $n >= $::ndesks} {
            puts "WM: no desk [desk-name $n]: there are $::ndesks"
            return
        }
    }
    set was [desk-of $w]
    if {$was eq $n} return
    set ::deskof($w) $n
    publish-desk-of $w
    puts "WM: 0x[format %x $w] desk [desk-name $was] -> [desk-name $n]"
    soft "paint the sticky mark" { policy-window-desk-changed $w }
    set was_focused [expr {$::focused == $w}]
    desk-visibility $w      ;# parks first when it hides the focus window
    if {$was_focused && ![desk-here-p $w]} {
        set refocus [policy-pick-refocus $w]
        if {$refocus != 0} { focus-to $refocus }
    }
}
proc desk-sticky-toggle {w} {
    desk-send $w [expr {[desk-sticky-p $w] ? $::desk : "all"}]
}

# ---------------- fullscreen ----------------
# EWMH _NET_WM_STATE_FULLSCREEN. What it means is stronger than
# maximize and deliberately so: the window gets the whole SCREEN, not
# the workarea, so the panel and the tray go UNDER it — a fullscreen
# video or terminal that stopped at a strip would be neither. The
# decoration goes away with them; the client IS the frame while this
# lasts.
#
# The geometry is the policy's (it owns every measurement of a frame),
# and so is remembering what to put back. This layer holds the STATE,
# answers for it in the property, and stops honoring the client's own
# geometry requests while it lasts — a terminal rounds its size to
# whole cells on every font change, and obeying that mid-fullscreen is
# how a fullscreen window ends up with a strip of desk down its side.
proc fullscreen-client {w} {
    if {![info exists ::managed($w)] || [info exists ::fullscreen($w)]} return
    set ::fullscreen($w) 1
    policy-fullscreen $w 1
    publish-net-wm-state $w
    x-sync 0
    puts "WM: fullscreen 0x[format %x $w]"
}
proc unfullscreen-client {w} {
    if {![info exists ::fullscreen($w)]} return
    unset ::fullscreen($w)
    policy-fullscreen $w 0
    publish-net-wm-state $w
    x-sync 0
    puts "WM: fullscreen off 0x[format %x $w]"
}
# The state a window arrives ALREADY in. EWMH lets a client set
# _NET_WM_STATE on the window BEFORE mapping it, precisely so a WM can
# frame it right the first time instead of building an ordinary frame
# and throwing it away; Tk's own `wm attributes -fullscreen` on an
# unmapped toplevel takes that road (fs-client.tcl).
#
# Which road a client takes is not a thing to assume: `xterm
# -fullscreen` and `kitty --start-as fullscreen` were measured taking
# the OTHER one — they map at their ordinary size and send the
# ClientMessage immediately after, so their startup flag arrives as a
# runtime toggle. Both paths are real and both are tested.
# The state atoms a client set on ITSELF before mapping — what it says
# it wants to be, as opposed to what we hold it in. The layer machinery
# reads it for the ABOVE/BELOW pair.
proc client-net-wm-state {w} {
    if {![info exists ::NET_WM_STATE]} { return {} }
    lassign [soft "read _NET_WM_STATE" { x-prop-get $w $::NET_WM_STATE }] \
        type fmt value
    if {$fmt ne "32"} { return {} }
    return $value
}
proc client-initial-fullscreen {w} {
    if {![info exists ::NET_WM_STATE_FULLSCREEN]} { return 0 }
    lassign [soft "read _NET_WM_STATE" { x-prop-get $w $::NET_WM_STATE }] \
        type fmt value
    if {$fmt ne "32"} { return 0 }
    expr {$::NET_WM_STATE_FULLSCREEN in $value}
}
# ...and "start me maximized", same road, the pair of atoms — answered
# AS AXES ({}, h, v or both): the state is per-axis, so a client that
# set only VERT before mapping is born tall at its own width, not
# swept to full. Emacs's `fullscreen: maximized` X resource (both
# atoms) is the live case (the owner's desk). Callers test emptiness
# with llength: the list is the answer, not a boolean.
proc client-initial-maximized {w} {
    if {![info exists ::NET_WM_STATE_MAXIMIZED_HORZ]} { return {} }
    lassign [soft "read _NET_WM_STATE" { x-prop-get $w $::NET_WM_STATE }] \
        type fmt value
    if {$fmt ne "32"} { return {} }
    set axes {}
    if {$::NET_WM_STATE_MAXIMIZED_HORZ in $value} { lappend axes h }
    if {$::NET_WM_STATE_MAXIMIZED_VERT in $value} { lappend axes v }
    return $axes
}

# ---------------- what a client asks about its DECORATION ----------------
# Two hints and one question: does this window want a frame around it?
# A window that draws its own titlebar inside itself — every GTK4
# window is one, and every GTK3 window with a GtkHeaderBar — has to be
# able to say so, or it wears two titlebars: its own, and ours around
# it.
#
# _MOTIF_WM_HINTS is how it says so, and has been since Motif 1.1.
# Nothing ever replaced it: gtk_window_set_decorated,
# Qt::FramelessWindowHint, SDL's borderless flag and AWT's
# setUndecorated all write THIS — five 32-bit words
# {flags functions decorations input_mode status} whose property TYPE
# is the atom itself rather than CARDINAL (read with AnyPropertyType or
# find nothing). Measured on this machine's own toolkits (2026-08-02):
# gnome-text-editor and zenity, both GTK4, both map carrying
# {0x3 0x1 0x0 0x0 0x0} — the flags claim the functions and decorations
# words, functions are ALL, decorations are NONE.
#
# The answer is the decorations MASK the client meant, or "" for "it
# did not say" — no property, or flags that do not claim that word.
# MWM_DECOR_ALL is folded away here instead of being left for the
# caller: with that bit set the rest of the word says what to TAKE OFF
# the full set, and the complement is what everybody actually wants.
proc client-motif-decor {w} {
    if {![info exists ::MOTIF_WM_HINTS]} { return "" }
    lassign [soft "read _MOTIF_WM_HINTS" { x-prop-get $w $::MOTIF_WM_HINTS }] \
        type fmt value
    if {$fmt ne "32" || [llength $value] < 3} { return "" }
    lassign $value flags functions decor
    if {!($flags & 2)} { return "" }        ;# MWM_HINTS_DECORATIONS
    # BORDER 2, RESIZEH 4, TITLE 8, MENU 16, MINIMIZE 32, MAXIMIZE 64;
    # bit 0 is MWM_DECOR_ALL, the inversion.
    if {$decor & 1} { set decor [expr {~$decor}] }
    expr {$decor & 0x7e}
}

# _NET_WM_WINDOW_TYPE — the same question asked semantically. The list
# is in the client's order of preference and a WM takes the first type
# it recognizes (EWMH 5.6), so the order is kept. Names come back
# stripped of the atom prefix and lowercased — `splash`, `dock`,
# `dialog` — because what a type MEANS is the policy's to decide, and
# it should not have to hold a dozen interned atoms to ask.
proc client-window-types {w} {
    if {![info exists ::NET_WM_WINDOW_TYPE]} { return {} }
    lassign [soft "read _NET_WM_WINDOW_TYPE" {
        x-prop-get $w $::NET_WM_WINDOW_TYPE
    }] type fmt value
    if {$fmt ne "32"} { return {} }
    set names {}
    foreach a $value {
        set n [soft "name a window type" { x-atom-name $a }]
        if {[regexp {^_NET_WM_WINDOW_TYPE_(.+)$} $n -> tail]} {
            lappend names [string tolower $tail]
        }
    }
    return $names
}
# The refusal, and why it can be made to stick: ICCCM gives a WM no way
# to reply "no" to WM_CHANGE_STATE — but WM_STATE is the channel every
# client watches, and stating NormalState at a client that just asked
# for IconicState is precisely what a de-iconify looks like from its
# side. Wine's X11 driver answers an unasked-for NormalState with
# SC_RESTORE, so its Win32 side un-minimizes and the app paints again;
# a Tk client never got as far as believing itself iconic. That is the
# difference between refusing and ignoring — ignoring is what left the
# window on screen with a client convinced it was gone.
proc refuse-iconify {w} {
    if {![info exists ::managed($w)]} return
    set-wm-state $w 1
    set-net-wm-state $w {}
    x-map $w
    x-sync 0
    puts "WM: iconify refused for 0x[format %x $w] — answered NormalState"
}

# ---------------- manage / unmanage ----------------
proc manage {w {asiconic 0}} {
    global dpy
    if {[info exists ::managed($w)]} {
        # A MapRequest for a window we already hold: an iconic client
        # mapping itself IS the ICCCM way to ask for de-iconification
        # (4.1.4 — "the client should map the window"), so honor it as
        # one; an ordinary re-map is just a map.
        if {[info exists ::iconic($w)]} { deiconify-client $w } else {
            x-map $w
        }
        return
    }
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
    if {[llength [set g [x-geometry $w]]] == 6} {
        lassign $g gx gy gw gh
        set cw $gw; set ch $gh
        set aw $gw; set ah $gh    ;# actual size, to skip a no-op resize
        # ... and the position half: where the window put itself before
        # mapping. Placement consults it when the hints claim a position.
        set ::mapxyof($w) [list $gx $gy]
    }
    read-normal-hints $w
    # What size this window OPENS at is the policy's answer and not
    # ours. The substrate used to do the arithmetic itself and ask the
    # policy only for the ceiling — but a style that opens a window
    # maximized (or in the right half of the workarea) needs an exact
    # size rather than a maximum, and the ceiling itself depends on how
    # much decoration that same style gave the window. Both are
    # look-and-feel; what stays here is the client's REQUEST.
    lassign [policy-initial-size $w $cw $ch] cw ch
    set ::geomof($w) [list $cw $ch]
    set slot [policy-attach $w $cw $ch]
    set ::managed($w) 1
    # StructureNotify (Destroy/Unmap) + FocusChange (honest highlight even
    # when focus moves behind our back) + PropertyChange (live titles).
    #
    # A client can DIE between its map and this line — a terminal
    # around a command that finished at once does it every time
    # (`Fire {terminal … run {touch x}}`, measured 2026-08-04). This
    # select is the first call to touch the window after the frame
    # went up, so the death lands here: say so calmly and stop
    # framing — the DestroyNotify already delivered to the slot's
    # SubstructureNotify unmanages what policy-attach built, exactly
    # as it always did. Before the catch this surfaced as a handler
    # error wearing the redirect's own message («another window
    # manager holds it?»), which is two lies about one dead xterm.
    if {[catch {x-select-input $w \
                    {structure-notify focus-change property-change}}]} {
        puts "WM: 0x[format %x $w] died while being framed — released"
        return
    }
    # After the reparent the client is no longer a child of root, so root's
    # SubstructureRedirect no longer covers it: keep redirecting its
    # ConfigureRequests by holding the mask on the frame slot as well.
    # (Our own requests are exempt — the redirecting client is never
    # redirected by itself.)
    #
    # FocusChange on the same window closes the WM's oldest blind spot:
    # the slot is the client's PARENT, so when a client that had the
    # focus unmaps, the server's RevertToParent lands the focus HERE —
    # on a window that reads no keyboard. Until step 32 nothing watched
    # for that, and the wedge was invisible and permanent: the keys went
    # nowhere at all while the frame highlight claimed all was well.
    # The frame toplevel is watched for the same reason (the revert
    # walks up if the slot goes away).
    #
    # Both of these are TK's own windows, and on one connection a plain
    # selection on such a window would replace the mask Tk chose when it
    # built the widget — which Tk never selects again. The shim adds to
    # it instead; the trap and its cure are spelled out there.
    x-select-input $slot {substructure-redirect focus-change}
    set ::ourwin($slot) $w
    set ::decoof($w) [list $slot]
    if {[llength [set fg [policy-frame-geometry $w]]] == 5} {
        set fwin [lindex $fg 0]
        x-select-input $fwin {focus-change}
        set ::ourwin($fwin) $w
        lappend ::decoof($w) $fwin
        # The frame's WRAPPER — Tk puts every toplevel inside one, and
        # it is the wrapper that is the root's child, so it is what a
        # stacking order read off the root has to be translated by.
        set wr [lindex [soft "wrapper of a frame" { x-query-tree $fwin }] 1]
        if {$wr ne ""} { set ::wrapof($w) $wr }
    }
    # Click-to-focus inside the client: passive SYNC grab, one per
    # button, AnyModifier. The press freezes the pointer and wakes us
    # (button-press above); after the policy reacts we allow
    # replay-pointer so the client still gets the click un-eaten.
    #
    # Buttons 1-3 and NOT AnyButton, which is what this was — because
    # what we cannot SEE we must never freeze. Tk rewrites a press of
    # buttons 4-7 (the wheel) into its own MouseWheelEvent BEFORE the
    # generic handlers run, and drops the matching release entirely
    # (tkEvent.c) — so a wheel press through an AnyButton grab woke
    # nobody, was never answered with replay-pointer, and left the
    # pointer frozen for the whole desk, permanently. One scroll over
    # any client was enough (owner's report on the widget demo,
    # 2026-07-28; the desk kept its keyboard and lost its mouse, and
    # the client's own grabs then failed with "another application has
    # grab" — ours, stuck). The wheel is no business of click-to-focus
    # anyway: it now reaches the client untouched.
    foreach b {1 2 3} { x-grab-button $b 0x8000 $w {button-press} }
    x-save-set-add $w
    x-reparent $w $slot 0 0
    if {$cw != $aw || $ch != $ah} { x-resize $w $cw $ch }
    x-map $w
    set-wm-state $w 1          ;# NormalState — ICCCM, see set-wm-state
    publish-frame-extents $w   ;# EWMH — how much decoration is around it
    # ...but the DESK only when the window has said nothing about it.
    # This runs before the policy has decided (client-desk-declare, and
    # it publishes for itself), and desk-of answers "wherever you are"
    # until then — so publishing here unconditionally overwrote the one
    # fact worth reading: the desk this very window was on before a
    # restart, which the previous instance had published (the owner,
    # 2026-08-04, and measured: every window came back to desk one).
    if {[client-asked-desk $w] eq ""} { publish-desk-of $w }
    lappend ::client_order $w
    publish-client-list
    x-sync 0
    puts "WM: managed 0x[format %x $w]: slot [format 0x%x $slot] client ${cw}x${ch}"
    refresh-title $w
    # Is this window going to end up minimized? Three ways in: a client
    # that ASKED to start that way — ICCCM 4.1.4 spells it WM_HINTS
    # initial_state = IconicState, which is what `start /min` under wine
    # sets — a window ADOPTED back into the state a previous instance
    # of us left it in, and the config's own word about this kind of
    # window (the style key `start`, a policy answer — asked through
    # the guarded hook so a bare-substrate spike, having no styles,
    # simply has no word). Framed and mapped first any which way: the
    # frame has to exist for the window list to have anything to bring
    # back.
    #
    # What must NOT happen in between is the initial-focus decision.
    # policy-managed hands the focus over, and on the WM_TAKE_FOCUS
    # models it does so by INVITATION — so a client that answers an
    # invitation for a window we unmap half a breath later is left
    # believing it holds a focus the server has already moved on from.
    # It comes back keyboard-dead until something makes it re-decide,
    # which is what a click does. Only clients that track focus
    # themselves are hit, which is exactly why xterm and emacs looked
    # fine while the rest did not (owner's report, 2026-07-29).
    set styled [expr {[llength [info commands policy-start-state]]
                      ? [policy-start-state $w] : ""}]
    set askiconic [client-initial-iconic $w]
    set toiconic [expr {$asiconic || $askiconic || $styled eq "iconic"}]
    if {!$toiconic} { policy-managed $w }
    tell-where-you-are $w
    if {$toiconic} {
        puts "WM: 0x[format %x $w] [expr {$asiconic  ? {adopted minimized}
                                        : $askiconic ? {asked to start iconic}
                                                     : {styled to start iconic}}]"
        # Through the policy, not straight to iconify-client: a
        # `minimize refuse` style is the user's standing word about this
        # client, and it applies to a window arriving minimized as much
        # as to one being minimized now.
        policy-minimize-request $w
        # Skipping policy-managed must not skip the MODEL: without this
        # the window had no desk (it followed every switch once
        # restored, and camped at the head of the focus history) and no
        # seat in the stack (the desk sweep could not even show it).
        # After the minimize on purpose — see policy-booked.
        if {[llength [info commands policy-booked]]} { policy-booked $w }
    }
    # ...and "start me fullscreen", the EWMH spelling of the same idea
    # — or the style's, for the clients with no flag of their own.
    # After the frame, for the same reason: there has to be a frame for
    # the state to re-lay out, and one to come back to.
    set askfs [client-initial-fullscreen $w]
    if {$askfs || $styled eq "fullscreen"} {
        puts "WM: 0x[format %x $w] [expr {$askfs ? {asked to start fullscreen}
                                                 : {styled to start fullscreen}}]"
        fullscreen-client $w
    } elseif {[llength [set _born [client-initial-maximized $w]]]
              && ![info exists ::maxsaved($w)]
              && [llength [info commands maximize-client]]} {
        # The machinery is the policy's; a substrate running bare (a
        # spike) simply has no maximize to offer. Fullscreen wins when
        # a client asks for both — it is the stronger claim. And a
        # window policy-initial-size already BORE maximized (the mark
        # is set) has nothing left to ask: this branch catches only
        # what the pre-map road could not size — a style whose own
        # `place` spoke first. The asked-for axes ride along.
        puts "WM: 0x[format %x $w] asked to start maximized ($_born)"
        maximize-client $w $_born
    }
}

# WM_HINTS initial_state == IconicState. The shim's dict carries the
# field only when the StateHint flag actually claims it, so its
# presence IS the claim.
proc client-initial-iconic {w} {
    set h [soft "read WM_HINTS" { x-prop-hints $w }]
    expr {[dict exists $h initial-state] && [dict get $h initial-state] == 3}
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
    close-answered $w      ;# gone is gone: nothing left to wink at
    if {![info exists ::managed($w)]} return
    # Decide the refocus candidate BEFORE the teardown: the policy's pick
    # rests on facts it keeps per-frame (the dialog's leader, the focus
    # history) and policy-detach cleans those up. When the whole desk
    # is being released at once there is nothing to pick — every
    # candidate is about to go the same way (the pre-restart log showed
    # a focus handed to a window unmanaged two lines later).
    set refocus [expr {$::releasing ? 0 : [policy-pick-refocus $w]}]
    # Give the client window back to root BEFORE destroying the frame:
    # the client lives INSIDE the frame's slot, and destroying a Tk
    # toplevel destroys its whole X subtree — this used to kill an
    # application that merely did wm withdraw (and later deiconify).
    # Skip for clients that are already destroyed.
    if {!$dead} {
        set x 0; set y 0
        soft "origin of the window being released" \
            { lassign [policy-origin $w] x y }
        soft "release the client back to root" {
            # WithdrawnState means "this window is not managed by
            # anyone", and about a MINIMIZED window that is a lie the
            # next window manager cannot recover from: it would see an
            # ordinary window and put it back on the screen. WM_STATE is
            # the only place the fact that somebody minimized this
            # window survives an execv, so an iconic client keeps
            # IconicState on the way out and our next instance reads it
            # back in adopt-existing.
            set-wm-state $w [expr {[info exists ::iconic($w)] ? 3 : 0}]
            x-reparent $w $::root $x $y
            if {!$::releasing} { x-sync 0 }   ;# the sweep syncs once
        }
    }
    policy-detach $w
    unset ::managed($w)
    unset -nocomplain ::wrapof($w)
    if {!$::releasing} { publish-client-list }
    icon-invalidate $w
    unset -nocomplain ::iconic($w) ::fullscreen($w) ::skip_unmap($w)
    unset -nocomplain ::wine_dirty($w)
    unset -nocomplain ::minof($w) ::maxof($w) ::incof($w) ::baseof($w)
    unset -nocomplain ::poshintof($w) ::sizehintof($w) ::gravof($w) ::mapxyof($w)
    # The decoration is gone: stop treating its windows as ours, and
    # settle an invitation this window will now never answer (fvwm's
    # ebdd006ea — a mark that outlives its window is a mark that
    # silently misdirects the next repair).
    if {[info exists ::decoof($w)]} {
        foreach id $::decoof($w) { unset -nocomplain ::ourwin($id) }
        unset ::decoof($w)
    }
    if {$::invited == $w} { set ::invited 0 }
    puts "WM: unmanaged 0x[format %x $w], frame destroyed"
    # The whole-desk release skips the focus repair below too: N
    # windows would run N server round trips and hand the focus to N-1
    # doomed candidates in turn, all a beat before the exec (or the
    # exit) throws the lot away.
    if {$::releasing} return
    # Refocus not only when OUR records say the dead window was focused:
    # a client may have grabbed focus behind our back (focus -force) and
    # died — then the server reverts to a dead end (None, PointerRoot, or
    # our own frame) and the keyboard stops working. Ask the server and
    # repair either way.
    set stale [expr {$::focused == $w}]
    if {!$stale} {
        set f [lindex [x-focus-get] 0]
        if {$f ne "" && ($f <= 1 || [info exists ::ourwin($f)])} {
            puts "WM: server focus reverted to a dead end\
 ([format 0x%x $f]) — repairing"
            set stale 1
        }
    }
    if {$stale} {
        set ::focused 0
        # Park first, aim second — the ordering that makes the next
        # invitation's stamp newer than the last focus change (see
        # focus-repair).
        focus-park "the focused window went away"
        if {$refocus != 0} { focus-to $refocus }
    }
}

# ---------------- focus core ----------------
# The substrate owns the honest server-side focus (XSetInputFocus + the
# verification and repair paths); which window DESERVES focus and how the
# highlight looks is the policy layer's business.
keep focused 0
keep evtime 0   ;# timestamp of the last user input event we parsed
# The window we invited with WM_TAKE_FOCUS and whose answer we are still
# waiting for (0 = none). It carries the INTENT while the X focus still
# says otherwise: an honest WM publishes the focus it HAS, not the one it
# asked for, so between invitation and answer ::focused is still the old
# window and this is the only record of where we are heading. Settled by
# any FocusIn, by any focus we set ourselves, and by the window going
# away. There is no timer behind it: fvwm's mark, same discipline.
keep invited 0
proc paint-focus {w} {
    set ::focused $w
    # a client taking the focus dirties every iconic globally-active
    # window: their Win32 focus is lost for real now, and their
    # restore will need the bounce (see deiconify-client)
    foreach k [array names ::wine_dirty] {
        if {$k != $w} { set ::wine_dirty($k) 1 }
    }
    # every honest focus change publishes _NET_ACTIVE_WINDOW — Wine
    # reads its foreground from here (see the EWMH block)
    if {[info exists ::NET_ACTIVE]} {
        soft "publish _NET_ACTIVE_WINDOW" \
            { set-prop-longs $::root $::NET_ACTIVE 33 [list $w] }
    }
    policy-paint-focus $w
    keys-pass-apply    ;# the new holder's claim, settled (see the apply)
}
# ICCCM input model: the WM_HINTS input member, meaningful when the
# InputHint flag is set; an absent property or flag means input=True —
# the passive default the world's toolkits assume. (The shim's dict
# carries `input` only when the flag claims it, so "absent" and "not
# claimed" are the same answer here, as ICCCM wants.)
proc client-input-hint {w} {
    set h [soft "read WM_HINTS" { x-prop-hints $w }]
    if {![dict exists $h input]} { return 1 }
    dict get $h input
}
# The ICCCM globally-active client — input=False plus WM_TAKE_FOCUS,
# the model Wine 10+ lives in. Its focus is its OWN doing (it answers
# invitations with its own XSetInputFocus), and its Win32 half keeps
# activation state of its own — which is why the focus-loss ORDER is
# per-model (see iconify-client) and why focus-to neither sets nor
# bounces the focus for it.
proc client-globally-active {w} {
    expr {[client-advertises $w $::WM_TAKE_FOCUS 0] && ![client-input-hint $w]}
}
proc focus-to {w {fresh 0}} {
    if {![info exists ::managed($w)]} { return 0 }
    # A FRESH focus is one the client can SEE. When the server already
    # aims at $w, the x-focus-set below is a no-op — not one event is
    # generated — and a client whose inner activation state went stale
    # (chromium's aura layer after a dirty focus loss) stays stale
    # forever: this exact branch is why five activations in a row did
    # nothing while alt-tab-away-and-back cured it (2026-08-12). So an
    # EXPLICIT activation — a chord, a panel button, the window list,
    # an EWMH activation request — asks for `fresh`, and the focus
    # bounces off the holder first: a real FocusOut/FocusIn(Normal)
    # pair the client cannot miss. Silent (no parking, ::focused and
    # _NET_ACTIVE_WINDOW stay put — they are correct and about to be
    # confirmed); never for the globally-active model, whose focus is
    # not ours to bounce; never on ordinary refocus, where the target
    # is a window the focus is NOT on by construction.
    if {$fresh && $::nofocus != 0 && ![client-globally-active $w]
            && [lindex [x-focus-get] 0] == $w} {
        puts "WM: focus -> 0x[format %x $w]: already the focus —\
 bouncing for a fresh FocusIn"
        x-focus-set $::nofocus parent
        x-sync 0
    }
    # The ICCCM "globally active" client — input=False plus
    # WM_TAKE_FOCUS (Wine 10+ lives here) — handles the focus ITSELF.
    # The WM only sends the invitation and must then LEAVE THE X FOCUS
    # ALONE: the client answers with its own XSetInputFocus carrying the
    # invitation's timestamp, and the server silently drops a request
    # older than the last focus change — so any focus op of ours in
    # between (step 28 set the focus right before inviting) makes the
    # answer stale and the window keyboard-dead. The same war was fought
    # and won in fvwm3 (its commit 6ec006d9c; notes/fvwm3-wine-focus.md
    # in thoughts): invite, hands off, let the FocusIn confirm.
    #
    # The stamp is FETCHED from the server at this very moment
    # (server-time), not taken from an accumulated clock: that makes it
    # newer than the last focus change by construction, so the answer
    # cannot arrive stale and no retry timer is needed. And nothing is
    # painted here — ::focused and _NET_ACTIVE_WINDOW move when the
    # FocusIn confirms, not when we hope. That honesty is load-bearing
    # for Wine specifically: it derives its foreground from
    # _NET_ACTIVE_WINDOW, so a premature "you are active" suppresses the
    # very activation request it would otherwise use to recover.
    if {[client-globally-active $w]} {
        set t [server-time]
        set ::invited $w
        puts "WM: focus -> 0x[format %x $w]: WM_TAKE_FOCUS invitation\
 (globally active), t=$t"
        send-protocol $w $::WM_TAKE_FOCUS $t
        return 1
    }
    set ::invited 0
    # RevertToParent (2), NOT PointerRoot: if the focus window dies before
    # we refocus, a parent revert leaves the keyboard silent for a moment,
    # while a PointerRoot revert switches the whole session to
    # focus-follows-pointer behind our back.
    x-focus-set $w parent
    x-sync 0
    # Record the focus ONLY if the server agrees. A refused XSetInputFocus
    # (swallowed BadMatch when the window stopped being viewable, a client
    # grabbing focus behind our back) used to be logged as MISMATCH and
    # then recorded as focused anyway — after which every path that trusts
    # ::focused was permanently wrong: clicks on that window were treated
    # as "already focused" and never retried, so the keyboard kept going
    # to the previous window while the frame highlight claimed otherwise
    # (live report, GIMP's Quit dialog). Believing the server costs one
    # roundtrip and cannot wedge.
    lassign [x-focus-get] f r
    if {$f ne "" && $f != $w} {
        puts "WM: focus -> 0x[format %x $w] REFUSED by server\
 (focus=[format 0x%x $f] revert=$r) — not recorded, will retry"
        return 0
    }
    # The "locally active" client (input=True plus WM_TAKE_FOCUS —
    # Java, old Wine): the X focus works, and the message rides along
    # per ICCCM so the client can move focus among its own windows
    # (dwm ships exactly this XSetInputFocus + ClientMessage pair).
    if {[client-advertises $w $::WM_TAKE_FOCUS 0]} {
        puts "WM: focus -> 0x[format %x $w]: sending WM_TAKE_FOCUS"
        send-protocol $w $::WM_TAKE_FOCUS [server-time]
    }
    paint-focus $w
    puts "WM: focus -> 0x[format %x $w]"
    return 1
}

# No window deserves the focus (the desk is empty), or the focus landed
# somewhere it must not rest — park it on the holder. Never None: with
# focus None the server activates NO passive key grab (GrabKey fires
# only when the grab window is an ancestor of the focus window), so
# every root-grabbed chord, the panel launchers included, goes dead
# (live report, 2026-07-28). And never PointerRoot: that is
# focus-follows-pointer, and it arms Tk's implicit-focus machinery
# against us — see the focus holder above.
proc focus-park {why} {
    puts "WM: parking focus on the holder ($why)"
    set ::invited 0
    if {$::nofocus} {
        x-focus-set $::nofocus parent   ;# revert to the parent = root
    } else {
        x-focus-set pointer-root pointer-root   ;# no holder at all
    }
    x-sync 0
    set ::focused 0
    if {[info exists ::NET_ACTIVE]} {
        soft "clear _NET_ACTIVE_WINDOW" \
            { set-prop-longs $::root $::NET_ACTIVE 33 [list 0] }
    }
    keys-pass-apply    ;# nobody focused, nobody's claim — grabs resume
}
# The focus reached a dead end: it sits on our own decoration, on the
# root, on nothing, or it follows the pointer. Whatever the cause (a
# RevertToParent onto a frame when a client unmapped, Tk's implicit
# focus release, an outer Xephyr crossing), the repair is the same and
# is ORDERED: park FIRST, so the holder's focus change is what the
# server's clock last saw, and only THEN re-aim at the window that
# deserves the focus. That ordering is what makes an invitation
# deterministic — its freshly fetched stamp is newer than the park,
# so the client's answer cannot be dropped as stale. No timers, no
# blind resends: one repair per event that reports the dead end.
# An honest focus target: managed, and not iconic. The second half
# matters while a window is being taken off the screen — the watchdog
# can fire mid-iconify, and aiming at the window that is going away
# earns a refusal from the server ("not viewable") and leaves the desk
# with nobody focused at all.
proc focus-target-ok {w} {
    expr {$w != 0 && [info exists ::managed($w)] && ![info exists ::iconic($w)]
          && [desk-here-p $w]}
}
proc focus-repair {why {prefer 0}} {
    set want 0
    foreach cand [list $prefer $::invited $::focused] {
        if {[focus-target-ok $cand]} { set want $cand; break }
    }
    if {$want == 0} { set want [policy-pick-refocus 0] }
    focus-park $why
    if {[focus-target-ok $want]} {
        focus-to $want
    }
}

# Deferred refocus, coalesced (restack-soon's idiom). A burst that takes
# focused windows off the screen — minimize-all, a desk sweep — used to
# run a park-and-aim PER WINDOW: eight windows, eight parkings, and six
# of the aims handed a client a focus it was about to lose to the next
# iconify a millisecond later. That flap is expensive exactly where it
# is invisible: a client's own activation bookkeeping (chromium's aura
# layer, wine's Win32 side) chews every transition asynchronously, and
# a focus that blinks faster than the client thinks is how inner state
# goes stale. So the aim waits for idle: whoever parked during the
# burst asks for ONE refocus when the dust settles, and a burst that
# already aimed somewhere honest (a deiconify's own focus-to, say)
# leaves nothing for it to do.
keep refocus_pending 0
proc refocus-soon {} {
    if {$::refocus_pending} return
    set ::refocus_pending 1
    after idle {set ::refocus_pending 0; refocus-now}
}
proc refocus-now {} {
    if {$::focused != 0 || $::invited != 0} return
    set want [policy-pick-refocus 0]
    if {[focus-target-ok $want]} { focus-to $want }
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
    x-resize $win $cw $ch
    x-sync 0
    puts "WM: resize 0x[format %x $win] -> ${cw}x${ch}, frame follows"
    # the synthetic ConfigureNotify is sent by the ConfigureRequest
    # handler for EVERY request, granted or not — see there
}

# A managed client's move request (CWX/CWY bits in a ConfigureRequest):
# honored only for a client that DECLARES its positioning — USPosition
# or PPosition in WM_NORMAL_HINTS, re-read live, so "wm geometry +x+y"
# works exactly when the toolkit stamps the claim. Everyone else keeps
# being placed by the WM, requests and all (the pre-existing rule).
# The actual frame move is the policy's: it owns the decoration
# geometry and the gravity arithmetic.
proc move-client-request {w x y vmask} {
    lassign [client-position-hint $w] kind grav
    if {$kind eq "none"} return
    policy-move-request $w $x $y [expr {$vmask & 3}] $grav
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
    x-resize $w $cw $ch
    x-sync 0
    puts "WM: wm-resize 0x[format %x $w] -> ${cw}x${ch}"
    send-synthetic-configure $w
}

# ---------------- close machinery ----------------
# WM_PROTOCOLS plumbing, shared by the close path (WM_DELETE_WINDOW)
# and the focus path (WM_TAKE_FOCUS). The fallback answers "is the
# protocol there?" when the check itself is unavailable: the close
# path assumes a modern client (1), the focus path stays silent (0)
# — an unadvertised WM_TAKE_FOCUS must never be sent.
proc client-advertises {w atom fallback} {
    if {[catch {x-prop-protocols $w} protos]} {
        soft-log "read WM_PROTOCOLS" $protos
        return $fallback
    }
    expr {$atom in $protos}
}
proc send-protocol {w atom time} {
    # data.l = {atom time}, the ICCCM shape of every WM_PROTOCOLS
    # message; a zero send-mask means "to the window's own client".
    x-send-client $w $::WM_PROTOCOLS [list $atom $time]
    x-sync 0
}
proc close-client {w} {
    if {[client-advertises $w $::WM_DELETE_WINDOW 1]} {
        puts "WM: close 0x[format %x $w]: sending WM_DELETE_WINDOW"
        send-protocol $w $::WM_DELETE_WINDOW 0
        # The polite path has no acknowledgement: a client that honors
        # the request unmaps or dies, a hung one does NOTHING — so we
        # WAIT FOR AN ANSWER, and the answer is the window going away.
        # As a future, which is what turns "start a timer, remember to
        # cancel it in three places" into one errand that either gets
        # its answer or times out (the owner asked for both halves:
        # any unmap must disarm the wink, and the timer belongs on the
        # substrate we now have).
        close-answered $w cancel        ;# a repeated close re-arms
        set ::close_wait($w) [fut::new]
        wm-errand "close 0x[format %x $w]" [list close-await $w]
    } else {
        puts "WM: close 0x[format %x $w]: no WM_DELETE_WINDOW, XKillClient"
        x-kill-client $w
        x-sync 0
    }
}

# Still managed this long after WM_DELETE_WINDOW = the client is not
# answering (hung, or minding a modal question of its own) — the
# policy decides what the user sees. A window that closed in time
# fails the guard and the check dissolves silently.
# The wait itself: two seconds for the window to go. Whichever
# arrives first settles it — the client's own unmap (or its death,
# which unmanages it too) fulfills the future, and the timeout is the
# silence the user is shown.
proc close-await {w} {
    if {![info exists ::close_wait($w)]} return
    if {[catch {fut::take [fut::timeout $::close_wait($w) 2000]}]} {
        unset -nocomplain ::close_wait($w)
        if {![info exists ::managed($w)]} return
        puts "WM: close 0x[format %x $w]: unanswered after 2 s"
        policy-close-unanswered $w
        return
    }
    unset -nocomplain ::close_wait($w)
}
# ANY UNMAP OF A WINDOW WE ASKED TO CLOSE IS AN ANSWER (the owner: an
# applet that withdraws on WM_DELETE_WINDOW was being winked at for
# obeying). Called on the withdrawal path and on unmanage, so a
# client that hides and a client that dies both count as having
# answered.
proc close-answered {w {how done}} {
    if {![info exists ::close_wait($w)]} return
    set f $::close_wait($w)
    unset ::close_wait($w)
    if {$how eq "cancel"} { fut::discard $f } else { fut::fulfill $f 1 }
}

# The unconditional kill — the ops menu's "destroy" for a client that
# ignores the polite path above.
proc kill-client {w} {
    puts "WM: destroy 0x[format %x $w]: XKillClient"
    x-kill-client $w
    x-sync 0
}

# ---------------- the system tray (XEmbed) ----------------
# The OTHER half of the tray protocol: not an application putting an
# icon somewhere, but the manager that takes icons in — freedesktop's
# System Tray Protocol carried on XEMBED.
#
# Not one line of C was needed for it, and that is the shim's three
# escape hatches paying for themselves: the claim is `selection own`
# with a fetched timestamp, the announcement and every _XEMBED message
# are ClientMessages with a verbatim payload, the dock request arrives
# as one (with no mask to select — on ONE connection a ClientMessage
# addressed to a window of ours lands in the generic handler by
# itself), and _XEMBED_INFO is an ordinary property read.
#
# The protocol in the order it happens:
#   1. own _NET_SYSTEM_TRAY_S<screen> with a server timestamp, then
#      announce the takeover to the root with a MANAGER ClientMessage —
#      clients already running dock when they hear it;
#   2. a client sends _NET_SYSTEM_TRAY_OPCODE / SYSTEM_TRAY_REQUEST_DOCK
#      naming its icon window;
#   3. we select on it, put it in the save-set, reparent it into a slot
#      the policy layer builds and send XEMBED_EMBEDDED_NOTIFY;
#   4. _XEMBED_INFO's XEMBED_MAPPED bit — not the client's own map
#      request — decides whether the icon shows; re-read on every
#      PropertyNotify;
#   5. an icon leaves by dying, by being reparented out of our slot, or
#      by another manager taking the selection from us.
#
# ARGB is deliberately NOT offered (_NET_SYSTEM_TRAY_VISUAL stays
# unset). Advertised, it makes a toolkit paint its icon premultiplied
# into a 32-bit window — and a CHILD window's alpha is blended by
# nobody: the server copies its pixels into the parent's storage as
# they are, and a compositor redirects TOP-LEVEL windows only. That is
# the black square around a round icon every tray shows sooner or
# later. Unadvertised, the icon is drawn in the screen's own visual
# over our slot's background, which is the panel's color. (Honest ARGB
# would mean the whole tray strip being a 32-bit top-level and a
# compositor running — a separate experiment, not a primitive we lack.)
#
# The policy layer decides where icons live:
#   policy-tray-attach w   build a slot for icon w; return {slotid size}
#                          — the icon is sized to size x size — or {0 0}
#                          to refuse the icon
#   policy-tray-detach w   the icon is gone: drop its slot
#   policy-tray-origin w   root {x y} of w's slot, for the synthetic
#                          ConfigureNotify
keep tray_owner 0        ;# the selection owner while the tray RUNS, 0 = off
keep tray_owner_win 0    ;# ...the window itself, kept across stops
array set trayicon {}   ;# icon window -> the slot it sits in
array set traysize {}   ;# icon window -> the size we hold it at
keep trayseq {}          ;# the same icons in dock order — the record below
keep tray_freeze 0       ;# hold the record still while the tray goes down
keep tray_claim_time 0   ;# when we last took the selection (see selection-clear)

# The record of what our icons ARE, published on the root so it
# outlives this process — a restart reads it back, and so does a fresh
# instance after a crash (the root survives us; the property with it).
proc publish-tray-icons {} {
    if {$::tray_freeze || ![info exists ::TK9WM_TRAY_ICONS]} return
    soft "publish the tray record" \
        { set-prop-longs $::root $::TK9WM_TRAY_ICONS 33 $::trayseq }  ;# XA_WINDOW
}


# Claim the tray for this display. 0 = there already is one (we do not
# fight for it: two managers on one selection is how icons end up
# nowhere) or the server refused us.
proc tray-start {{orient horizontal} {visual 0}} {
    if {$::tray_owner != 0} { return 1 }
    if {[catch {
        set ::TRAY_SELECTION [x-intern _NET_SYSTEM_TRAY_S[screen-number]]
        set ::TRAY_OPCODE    [x-intern _NET_SYSTEM_TRAY_OPCODE]
        set ::TRAY_ORIENT    [x-intern _NET_SYSTEM_TRAY_ORIENTATION]
        set ::TRAY_VISUAL    [x-intern _NET_SYSTEM_TRAY_VISUAL]
        set ::XEMBED         [x-intern _XEMBED]
        set ::XEMBED_INFO    [x-intern _XEMBED_INFO]
    } err]} {
        puts "WM: tray: cannot intern the atoms: $err"
        return 0
    }
    # The owner window OUTLIVES a stop — there is no way to destroy a
    # window from the shim, and a new one per on/off cycle would be a
    # slow leak. Which is also why the "somebody else has it" check has
    # to know its own face: after a config reload the selection may
    # still be held by the window we are about to reuse.
    if {$::tray_owner_win == 0} {
        set ::tray_owner_win [x-create-window $::root -200 -200 1 1 -override]
    }
    set owner $::tray_owner_win
    set held [soft "read the tray selection" { x-selection-get $::TRAY_SELECTION } 0]
    if {$held != 0 && $held != $owner} {
        puts "WM: tray: 0x[format %x $held] already owns\
 _NET_SYSTEM_TRAY_S[screen-number] — leaving it alone"
        return 0
    }
    # Selecting here is what makes the dock requests ARRIVE, and the
    # reason is a subtlety of XSendEvent worth writing down. A docking
    # client first selects StructureNotify on this very window (to hear
    # it die), and then sends its request with propagate=True and mask
    # StructureNotify|SubstructureNotify — Tk's own systray does exactly
    # this (tkUnixSysTray.c), and so do GTK and Qt. The server delivers
    # such an event to every client selecting one of those types ON THE
    # DESTINATION, and only propagates to the ancestors when there is no
    # such client at all. The requesting client is itself one — so with
    # nothing selected on our side the message went to the ASKER and
    # never to us, the root's SubstructureNotify notwithstanding
    # (measured: the icon was created, the request sent, and the tray
    # heard nothing).
    x-select-input $owner {structure-notify substructure-notify}
    # The orientation is published BEFORE the claim: a client that docks
    # the instant it hears the announcement must not find the window
    # bare. (XA_CARDINAL; 0 = horizontal, 1 = vertical.)
    set-prop-longs $owner $::TRAY_ORIENT 6 \
        [list [expr {$orient eq "vertical" ? 1 : 0}]]
    # ...and the ARGB offer, when the policy built itself a 32-bit
    # strip to back it up. This property is a PROMISE: a toolkit that
    # sees it makes its icon in that visual and paints it with alpha,
    # which is only survivable if our cell has the same depth (so
    # ParentRelative is legal) and a compositor is there to blend the
    # strip. Absent, the toolkit uses the screen's own visual — the
    # safe default, and the reason this is opt-in. (XA_VISUALID = 32.)
    if {$visual != 0} {
        set-prop-longs $owner $::TRAY_VISUAL 32 [list $visual]
    }
    set t [server-time]
    if {![x-selection-own $::TRAY_SELECTION $owner $t]} {
        puts "WM: tray: the server refused the selection"
        return 0
    }
    set ::tray_owner $owner
    set ::tray_claim_time $t
    # ICCCM 2.8: a new manager announces itself to the root, and every
    # client waiting for a tray docks on hearing it. This one has an
    # audience, so it carries a real send mask.
    x-send-client $::root $::MANAGER \
        [list $t $::TRAY_SELECTION $owner 0 0] 32 {structure-notify}
    x-sync 0
    # (the visual spelled OUTSIDE expr: expr would read "0x40" back as
    # a number and print 64, which is the kind of small lie a log line
    # should not tell)
    set vs default
    if {$visual != 0} { set vs [format 0x%x $visual] }
    puts "WM: tray up (owner 0x[format %x $owner],\
 _NET_SYSTEM_TRAY_S[screen-number], $orient, visual $vs)"
    return 1
}

# _XEMBED_INFO = {version, flags}; bit 0 of flags is XEMBED_MAPPED. An
# absent property means the client does not speak XEMBED at all (it
# happens) — read as "show me", which is what every tray does with one.
proc tray-xembed-mapped {w} {
    lassign [soft "read _XEMBED_INFO" { x-prop-get $w $::XEMBED_INFO }] type fmt val
    if {$fmt ne "32" || [llength $val] < 2} { return 1 }
    expr {[lindex $val 1] & 1}
}
proc tray-refresh-map {w} {
    if {![info exists ::trayicon($w)]} return
    if {[tray-xembed-mapped $w]} { x-map $w } else { x-unmap $w }
}

proc tray-dock {w} {
    if {$::tray_owner == 0 || [info exists ::trayicon($w)]} return
    if {[info exists ::managed($w)]} {
        # A window we already frame is not an icon. Nothing sane sends
        # both, and if something does, being a window wins.
        puts "WM: tray: 0x[format %x $w] is a managed client — dock ignored"
        return
    }
    set at [x-attrs $w]
    if {![dict size $at]} {
        puts "WM: tray: 0x[format %x $w] is already gone"
        return
    }
    lassign [policy-tray-attach $w] slot size
    if {$slot eq "" || $slot == 0} {
        puts "WM: tray: no slot for 0x[format %x $w] — refused"
        return
    }
    set ::trayicon($w) $slot
    set ::traysize($w) $size
    # StructureNotify for the icon's death and for a reparent away from
    # us; PropertyChange for _XEMBED_INFO, which owns its visibility.
    x-select-input $w {structure-notify property-change}
    # Redirect on the slot, so the icon's own map and configure requests
    # come to US: an icon is sized by the tray, not by itself. The slot
    # is a window of OURS, where the shim ADDS the mask to Tk's instead
    # of replacing it (the single-connection trap — see x-select-input).
    x-select-input $slot {substructure-redirect}
    x-save-set-add $w       ;# our death must not take the icon with it
    x-reparent $w $slot 0 0
    x-resize $w $size $size
    # XEMBED_EMBEDDED_NOTIFY (opcode 0): data.l = {time, opcode,
    # embedder window, protocol version}. No send mask — an XEMBED
    # message goes to the window's own client, not to onlookers.
    x-send-client $w $::XEMBED [list [server-time] 0 $slot 0 0]
    tray-refresh-map $w
    # Ask the client to paint. A fresh dock gets its Expose from the
    # map anyway; an ADOPTED one may not — it has been sitting unmapped
    # on the root, its client believes nothing in particular about it,
    # and what shows up in the cell otherwise is whatever was in the
    # window when the last tray let go of it.
    soft "ask an icon to repaint" { x-clear $w -exposures }
    lappend ::trayseq $w
    publish-tray-icons
    x-sync 0
    set depth [dict get $at depth]
    puts "WM: tray: docked 0x[format %x $w] in slot\
 0x[format %x $slot] (${size}px, depth $depth)"
    # The depth is logged because ONE mismatched number explains the
    # commonest tray complaint there is, and reading it off the icon
    # costs nothing: we already have its attributes.
    set cell [dict get [x-attrs $slot] depth]
    if {$depth eq $cell && $depth eq [winfo screendepth .]} {
        # Same depth: the icon can be told to take the CELL's
        # background, and that is the classic cure for a transparent
        # icon coming out on black — the client's see-through parts
        # then show our color. Toolkits that already do this for
        # themselves (Tk's systray, GTK's) lose nothing; the ones that
        # forget are exactly the ones that need it. Across depths the
        # server refuses (BadMatch), which is the whole ARGB story
        # below — hence the guard rather than a blind attempt.
        #
        # ...same depth as the ROOT too, or not at all. A ParentRelative
        # window can only ever be reparented under a parent of its own
        # depth — and both roads OUT of the tray lead to the root: the
        # undock (which clears the background first, see tray-undock)
        # and the SAVE-SET rescue when we crash, which clears nothing
        # and just fails, taking the icon down with our connection. A
        # depth-32 icon in a depth-32 cell over a depth-24 root must
        # therefore not wear our ParentRelative: it is an ARGB icon, it
        # paints its own alpha, and the cure would buy it nothing and
        # cost it its crash-survival (run-trayrestart-test.sh).
        soft "parent-relative background for an icon" {
            x-attrs $w {background parent-relative}
            x-clear $w -exposures
        }
    } elseif {$depth ne "" && $cell ne "" && $depth ne $cell} {
        puts "WM: tray: 0x[format %x $w] is depth $depth in a depth-$cell\
 cell — an ARGB icon, though we advertise no ARGB visual (Chrome does\
 this unconditionally; measured 2026-07-29). Nobody blends a CHILD\
 window's alpha, so its transparent pixels come out BLACK, and\
 ParentRelative cannot be forced on it either — that is a BadMatch\
 across depths."
    }
}

# Icons orphaned by a tray that went away — ours across a restart, when
# the save-set (or our own release) hands them back to the root. The
# protocol says a client should re-dock when it hears the next MANAGER
# announcement, and a well-behaved one does; Chrome does not (measured
# on a live desk, 2026-07-29: its icon was lost across a restart of
# tk9wm AND of stalonetray), so the tray goes and gets them.
#
# It goes by its own RECORD, and that distinction is the whole lesson
# here. The first version of this asked the screen instead: every root
# child carrying _XEMBED_INFO was taken for an icon. But that property
# marks an XEmbed PLUG — any embeddable window at all — and fcitx5 puts
# it on its input window and on its menu window as readily as on its
# tray icon. The live desk showed the result: a 425x196 menu window and
# the input window that draws the input-method hint, both squeezed into
# 36x36 tray cells (owner's report, 2026-07-29). A property that says
# "I can be embedded" was read as "I am a tray icon", and those are not
# the same sentence.
#
# So the icons are written down while they are ours (TK9WM_TRAY_ICONS
# on the root, which outlives the process), and only those come back.
# The checks that remain are about the window's fate since: still
# alive, still a child of the root, still a plug.
#
# Runs BEFORE adopt-existing, and the order is load-bearing: an icon
# that is not override-redirect (nm-applet's is not, Chrome's is) would
# otherwise be adopted as an ordinary window and handed a titlebar.
proc tray-adopt-orphans {} {
    if {$::tray_owner == 0} return
    lassign [soft "read the tray record" \
        { x-prop-get $::root $::TK9WM_TRAY_ICONS }] type fmt val
    if {$fmt ne "32"} return
    foreach w $val {
        if {[info exists ::trayicon($w)]} continue   ;# already re-docked itself
        if {![dict size [x-attrs $w]]} continue      ;# died with its client
        # Still a child of the ROOT — that is where the save-set (or our
        # own release) leaves an icon whose tray went away. Anywhere
        # else means somebody took it in already, and taking it back
        # would be a fight.
        set tree [soft "parent of a recorded icon" { x-query-tree $w }]
        if {[llength $tree] < 2 || [lindex $tree 1] != $::root} continue
        lassign [soft "read _XEMBED_INFO" { x-prop-get $w $::XEMBED_INFO }] \
            t f v
        if {$f ne "32" || [llength $v] < 2} continue   ;# no longer a plug
        puts "WM: tray: 0x[format %x $w] was ours and is orphaned — taking it back"
        tray-dock $w
    }
}

# The icon's own ConfigureRequest. A tray decides the size; the client
# is told what it really got, in ICCCM's own terms, so it stops waiting
# for an answer (4.1.5 — the same discipline as a framed window's).
proc tray-hold-size {w} {
    if {![info exists ::trayicon($w)]} return
    set size $::traysize($w)
    x-resize $w $size $size
    set x 0; set y 0
    soft "origin of a tray icon" { lassign [policy-tray-origin $w] x y }
    x-send-configure $w $w $x $y $size $size
    x-flush
}

# The cell size changed under the icons (a config reload can do it):
# hold every one of them at the new size and ask it to paint again.
proc tray-refit {size} {
    foreach w [array names ::trayicon] {
        set ::traysize($w) $size
        soft "refit a tray icon" {
            x-resize $w $size $size
            x-clear $w -exposures
        }
    }
    soft "flush a refit" { x-flush }
}

# gone = the window is already destroyed or has left our slot: touching
# it would be either an error or a fight with whoever took it.
proc tray-undock {w {gone 0}} {
    if {![info exists ::trayicon($w)]} return
    unset ::trayicon($w)
    unset -nocomplain ::traysize($w)
    set ::trayseq [lsearch -exact -all -inline -not $::trayseq $w]
    publish-tray-icons
    if {!$gone} {
        # Hand it back to the root, unmapped. The icon outlives us (it
        # is in the save-set); what to do next is its client's call.
        #
        # The background goes FIRST, and it is load-bearing: reparenting
        # a window that wears a ParentRelative background under a parent
        # of another depth is a BadMatch — an ASYNC one, so the block
        # sails on while the icon silently stays in the slot and dies
        # with our connection. On an ARGB desk that was every restart:
        # depth-32 icon, depth-24 root, one "ignored" BadMatch in the
        # log, and nm-applet taking a fatal X error on the window that
        # went out from under it (measured, run-trayrestart-test.sh,
        # 2026-08-14). `none` is legal at any depth, whoever set what
        # it replaces — us or the client.
        soft "release a tray icon" {
            x-attrs $w {background none}
            x-unmap $w
            x-reparent $w $::root -200 -200
            x-sync 0
        }
    }
    soft "policy-tray-detach" { policy-tray-detach $w }
    puts "WM: tray: undocked 0x[format %x $w]"
}

# Another manager took the selection (ICCCM's polite replacement), the
# config turned the tray off, or we are going down: give every icon
# back and stop answering. Clients re-dock with whoever announces next.
proc tray-stop {why} {
    if {$::tray_owner == 0} return
    puts "WM: tray: stopping ($why)"
    # The record is what a NEXT instance adopts by, so it has to survive
    # the teardown that is about to empty it — freeze it while the icons
    # go back to the root.
    set ::tray_freeze 1
    foreach w [array names ::trayicon] { tray-undock $w }
    set ::tray_freeze 0
    # Let the selection go, or nobody can be the tray afterwards —
    # ourselves included. A config reload turns the tray off and on
    # again in one breath, and the second half used to find the
    # selection still held (by our own window) and politely stand down.
    soft "release the tray selection" {
        x-selection-own $::TRAY_SELECTION 0 [server-time]
        x-sync 0
    }
    set ::tray_owner 0
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
# A sequence in progress SHOWS itself (policy-key-echo, and the policy
# decides what that looks like), because a grabbed keyboard that says
# nothing is indistinguishable from a wedged one. The KeyPress events
# of both grab kinds arrive on this raw connection, in the same
# handle-event dispatcher as everything else.

keep keymap {}       ;# nested dict: "mods,keysym" -> {action script} | {map submap}
keep grabbed_top {}  ;# top chords held by XGrabKey — the MappingNotify re-grab list
# WHAT THE CODE SIDE WOULD SAY, chord by chord — the desk's own binds
# and the bundles', remembered PAST being buried. The keymap keeps one
# word per chord, the last one, so it cannot answer «what did my word
# take the chord from» or «what did my silence silence» — and both are
# questions the configurator has to answer (the owner, 2026-08-02:
# a bundle bind overridden or unbound vanished without a trace). Keyed
# by the parsed path, so spelling variants collapse; layers do not
# record here — their words are in layer_knobs already.
keep code_binds {}   ;# parsed path -> {script S name N origin O}
keep keyseq ""       ;# "" = idle; else the submap we are inside, keyboard grabbed
keep keyseq_keys {}  ;# ...and the chords that got us there, for the echo
keep keyseq_mods 0   ;# ...and the modifiers the prefix was held with
# The chord that OPENED the sequence — set when one starts, fresh or
# over (a restart is a start), and read by the doubled-opener forward
# in handle-key. The help opener leaves no trace in keyseq_keys, which
# is why the opener is its own field and not the list's first word.
keep keyseq_opener ""      ;# "mods,ks" of the opener; "" = none
keep keyseq_opener_up 0    ;# its key seen RELEASED since — a press again
                            #  is a second press, not the hold's autorepeat
keep keyseq_opener_keys {} ;# keyseq_keys as the opener left them: doubling
                            #  answers only where the opener still stands

# HOLDING THE MODIFIER THROUGH A CHORD (the owner, 2026-08-02: "someone
# might like <Super>t<Super>w<Super>w without letting go"). Both forms
# for ONE bind, because they are the same intention typed by two kinds
# of hand — a chord written {<Super>t w w} answers to Super+t w w and
# to Super+t Super+w Super+w alike, and nothing has to be declared
# twice. Only the PREFIX'S OWN modifiers count: Super held through a
# Super chord is the hand not letting go, while Ctrl appearing halfway
# through is a different key and stays one.
#
# The exact match is tried FIRST, so a submap that deliberately binds
# <Super>w beside a bare w keeps both, and this only ever fills a gap.
# What it costs is the restart: with the modifier down, a top-level
# chord pressed inside a sequence used to start over, and now it lands
# in the submap when the submap has that letter. That is real, and it
# is why chord-hold-shadows says so out loud rather than leaving it as
# advice about which letters to avoid.
keep chord_hold 0
keep key_double_pass 1  ;# the doubled opener types itself into the window
keep key_dar 0       ;# detectable autorepeat granted (substrate-start) —
                      #  the doubled-opener forward stays off without it:
                      #  a held prefix would read as a stream of doubles
keep kbd_grabbed 0
keep key_frozen 0    ;# a sync-grabbed press awaits its ONE answer (key-thaw)
keep keyrouter ""    ;# non-empty: a keyboard-modal UI owns every key event
keep keyrouter_lost ""   ;# ...and this is its notice, see grab-keys-to
keep key_invoke_mods 0  ;# modifiers of the chord that fired the running action

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
foreach name {Shift_L Shift_R Control_L Control_R Alt_L Alt_R
        Meta_L Meta_R Super_L Super_R Hyper_L Hyper_R
        Caps_Lock Shift_Lock Num_Lock Scroll_Lock
        Mode_switch ISO_Level3_Shift ISO_Level5_Shift} {
    if {[set ks [x-keysym $name]] != 0} { set ismodks($ks) 1 }
}
set KS_ESC [x-keysym Escape]

# A MODIFIER'S NAME IS NOT ITS SPELLING (the owner, 2026-08-02:
# «возможно при биндах super мелкими буквами лучше допускать»). The
# set of modifier names is fixed and closed, and no keysym is one of
# them, so there is nothing ambiguous about taking the case one
# happens to type — while the desk goes on SHOWING the canonical
# spelling everywhere (chord-name, the help list, the echo), which is
# how one comes to write it that way.
proc modmask-of {name} {
    if {[info exists ::modmaskof($name)]} { return $::modmaskof($name) }
    foreach {n bit} [array get ::modmaskof] {
        if {[string equal -nocase $n $name]} { return $bit }
    }
    return ""
}
# Both spellings, and that is the point: <Super>t is how one WRITES a
# chord and Super+t is how the desk SHOWS it (chord-name, the log, the
# echo, the help list), so whatever is on the screen can be typed
# straight back into a config without translating it by hand. The
# <Mod> prefixes are stripped first, then anything left before a `+`
# is a modifier name too — an X keysym name never contains one (the
# key next to Backspace is `plus`), so the last field is always the
# key.
proc parse-chord {tok} {
    set mods 0
    while {[regexp {^<([^>]+)>(.*)$} $tok -> m rest]} {
        set bit [modmask-of $m]
        if {$bit eq ""} { error "unknown modifier <$m>" }
        set mods [expr {$mods | $bit}]
        set tok $rest
    }
    set fields [split $tok +]
    foreach m [lrange $fields 0 end-1] {
        set bit [modmask-of $m]
        if {$bit eq ""} { error "unknown modifier «$m»" }
        set mods [expr {$mods | $bit}]
    }
    set tok [lindex $fields end]
    if {$tok eq ""} { error "chord without a key" }
    set ks [x-keysym $tok]
    # A KEYSYM'S CASE IS MEANING ONLY WHERE TWO NAMES EXIST: `a` and
    # `A` are different keysyms, but there is no `f4` beside `F4` —
    # and the hand that types the modifier loose types the key loose
    # too (the owner, 2026-08-02: Alt+f4). When the exact name is
    # nobody, the title-case and upper-case spellings get their turn;
    # a name that exists exactly is never second-guessed, so the real
    # letter pairs keep their difference.
    if {$ks == 0} { set ks [x-keysym [string totitle $tok]] }
    if {$ks == 0} { set ks [x-keysym [string toupper $tok]] }
    if {$ks == 0} { error "unknown keysym «$tok»" }
    list $mods $ks
}

# The modifier half of a chord, alone: <Super>, <Ctrl><Alt>. A mouse
# gesture is held down rather than struck, so it names modifiers and no
# key — same vocabulary, same spelling, one parser's worth of rules.
proc parse-mods {spec} {
    set mods 0
    set tok $spec
    while {[regexp {^<([^>]+)>(.*)$} $tok -> m rest]} {
        if {![info exists ::modmaskof($m)]} { error "unknown modifier <$m>" }
        set mods [expr {$mods | $::modmaskof($m)}]
        set tok $rest
    }
    foreach m [split $tok +] {          ;# ...and Ctrl+Alt, as a chord may be spelled
        if {$m eq ""} continue
        if {![info exists ::modmaskof($m)]} {
            error "«$spec» is not a modifier combination"
        }
        set mods [expr {$mods | $::modmaskof($m)}]
    }
    if {$mods == 0} { error "«$spec» is not a modifier combination" }
    return $mods
}

proc keysym-name {ks} {
    set name [soft "keysym name" { x-keysym-name $ks }]
    if {$name ne ""} { return $name }
    format 0x%x $ks
}
# A BARE MODIFIER MASK, SPELLED THE WAY IT IS WRITTEN. The desk keeps
# modifiers as a bit mask, which is the right thing to compare and the
# wrong thing to show: the configurator offered «64» where the config
# says «<Super>» (the owner). This is the inverse of parse-mods, and
# its output is legal input to it — the rule every spelling on this
# desk follows.
proc mods-name {mods} {
    set out {}
    foreach {name bit} {Ctrl 4 Alt 8 Super 64 Mod2 16 Mod3 32 Mod5 128 Shift 1} {
        if {$mods & $bit} { append out "<$name>" }
    }
    return $out
}
proc chord-name {mods ks} {
    set parts {}
    foreach {name bit} {Ctrl 4 Alt 8 Super 64 Mod3 32 Mod5 128 Shift 1} {
        if {$mods & $bit} { lappend parts $name }
    }
    lappend parts [keysym-name $ks]
    join $parts +
}

# WHAT IS UNDER THIS PREFIX — Emacs's C-h after a prefix key, and the
# reason it can exist at all is that a sequence holds the whole
# keyboard: the help key spends nothing from the global namespace and
# stays out of every application's way, since it is only ever asked
# for INSIDE a sequence.
#
# The default is <Super>h and the shape of it is the argument (the
# owner, 2026-07-30): coming from <Super>t the thumb is already on
# Super, so it is one roll rather than a regrip — which is the same
# thing that makes C-x C-h comfortable in Emacs.
#
# NOT `?`, which was the first idea and is a trap here. The lookup
# asks the map for group 0 level 0 by hand (see handle-key), so a
# shifted symbol never arrives under its own name: pressing Shift+/
# comes in as <Shift>slash whatever the layout says the pair prints,
# and a binding named `question` could not match on ANY of them. The
# owner's instinct about layouts was right and then some — it is not
# "may not land on shift-slash", it is "cannot land anywhere". Binding
# a shifted symbol is spelled <Shift>slash today; making `question`
# work would mean also looking the event's OWN group and level up and
# trying that keysym too, which is a separate decision about what a
# chord IS, not a fix to make here.
#
# The submap is still asked FIRST, so a prefix that binds this key
# keeps it — the same rule Escape and the top chords live by.
set HELP_CHORD [parse-chord {<Super>h}]
keep help_chord $HELP_CHORD
proc set-key-help {spec} {
    set ::help_chord [expr {$spec eq "off" ? "" : [parse-chord $spec]}]
}

# WHAT HOLDING THE MODIFIER COSTS, said out loud at the moment it is
# switched on instead of left as advice about which letters to avoid.
# With chord-hold on, a top chord pressed inside a sequence lands in
# the SUBMAP whenever the submap has that letter — so <Super>h stops
# asking "what is under this prefix" wherever the prefix binds h, and
# <Super>d stops minimizing. The desk can see every one of those
# coming, so it names them rather than making somebody remember a
# rule. (The owner spotted the h case unaided; the general form is
# "any top chord whose modifiers match a prefix's".)
proc chord-hold-shadows {} {
    if {!$::chord_hold} { return {} }
    set out {}
    dict for {pk pe} $::keymap {
        if {[lindex $pe 0] ne "map"} continue
        lassign [split $pk ,] pmods -
        if {$pmods == 0} continue
        set sub [lindex $pe 1]
        dict for {tk te} $::keymap {
            lassign [split $tk ,] tmods tks
            if {$tmods ne $pmods || $tk eq $pk} continue
            if {![dict exists $sub "0,$tks"]} continue
            lappend out [list [chord-of-key $pk] [chord-of-key $tk]]
        }
    }
    foreach pair $out {
        lassign $pair prefix top
        puts "WM: keys: with chord-hold on, $top inside $prefix is the sequence's own [lindex [split $top +] end] — it will not $top any more"
    }
    return $out
}
# A keymap key ("64,116") back into the name a person types.
proc chord-of-key {k} {
    lassign [split $k ,] mods ks
    chord-name $mods $ks
}

# Set a key path in a nested keymap dict. A later bind REPLACES what
# was there: an action shadowing a former prefix map drops the whole
# map, and a longer sequence turns a former action into a prefix.
#
# A leaf is {action SCRIPT NAME ORIGIN WHERE}: the name is what the
# help calls this binding when the script itself is not a fit thing to
# read (see wm-bind), the origin is WHO bound it (see saying), and the
# where is the file and line they said it in, when it was a file.
proc keymap-set {node keys entry} {
    set k [lindex $keys 0]
    if {[llength $keys] == 1} {
        dict set node $k [linsert $entry 0 action]
    } else {
        set sub {}
        if {[dict exists $node $k]
                && [lindex [dict get $node $k] 0] eq "map"} {
            set sub [lindex [dict get $node $k] 1]
        }
        dict set node $k [list map [keymap-set $sub [lrange $keys 1 end] $entry]]
    }
    return $node
}

# The optional NAME is for the help list, and one case showed how
# general it is: a chord used to bind to `panel-fire dock 2`, and a
# list of those is nonsense to read (the owner, 2026-07-30). The
# script is right for the machinery, and the answer is not to change
# what is CALLED but to let the caller say what it IS — nothing has
# to reverse a name out of a command after the fact. (The actions
# turn later made the scripts readable too — `action-fire mutt` —
# but a wm-bind's raw script still needs the word.)
#
# For an ordinary config binding there is nothing to synthesize and
# nothing is: the script speaks for itself (winops, Quit, or the first
# words of an exec), which is why the name is optional.
# wm-unbind SPEC — the other half of the map, and the customization
# layer needs it: a click that takes a binding away has to be able to
# SAY so, and re-declaring cannot express a removal. Empty submaps are
# pruned, so the help list does not show a prefix that leads nowhere —
# and the grab goes with the last binding under it (keys-drop-orphan).
proc wm-unbind {spec} {
    set chords [lmap tok $spec {parse-chord $tok}]
    if {![llength $chords]} { error "wm-unbind: empty chord sequence" }
    set ::keymap [keymap-unset $::keymap [lmap c $chords {join $c ,}]]
    keys-drop-orphan [lindex $chords 0]
}
# ...AND THE GRAB GOES WITH THE LAST BINDING UNDER IT. A top chord's
# grab is shared by everything beneath it, so no single unbind may
# drop it — but a top chord with NOTHING left under it is a key held
# hostage: the server keeps sending it here for nothing. The owner
# bound a bare `t`, took the binding back, and lost the letter
# (2026-08-02); the note that used to stand here claimed such a chord
# «falls through to the client», and this is what finally makes that
# true. (The sync grab has since softened the hostage's lot — an
# unbound frozen press is REPLAYED now, so the letter reaches the
# client even while the orphan stands — but every press still detours
# through the WM for nothing, and the orphan still leaves.)
proc keys-drop-orphan {top} {
    if {[dict exists $::keymap [join $top ,]]} return
    set i [lsearch -exact $::grabbed_top $top]
    if {$i < 0} return
    set ::grabbed_top [lreplace $::grabbed_top $i $i]
    ungrab-chord $top
    puts "WM: key top chord [chord-name {*}$top] released"
    keys-pass-apply    ;# a suspended chord that left is no claim now
}
# ...and the same, but only if the chord is still OURS. What a family
# of bindings takes away when it leaves is its own contribution and
# nothing else: a chord somebody has since taken for themselves was
# taken for a reason — to keep that one deed out of the family (the
# owner, 2026-08-01). Answers 1 when it did unbind.
proc wm-unbind-owned {spec origin} {
    set chords [lmap tok $spec {parse-chord $tok}]
    if {![llength $chords]} { error "wm-unbind-owned: empty chord sequence" }
    set path [lmap c $chords {join $c ,}]
    if {[keymap-origin $::keymap $path] ne $origin} { return 0 }
    set ::keymap [keymap-unset $::keymap $path]
    # ...and its code-side record goes with it: a bundle leaving takes
    # its own word out of the «would say» table too, or a silence row
    # would go on advertising a family that is off.
    if {[dict exists $::code_binds $path]
            && [dict get $::code_binds $path origin] eq $origin} {
        dict unset ::code_binds $path
    }
    keys-drop-orphan [lindex $chords 0]
    return 1
}
# WHOSE the binding at this chord path is — the fourth word of a
# leaf, empty for a path that binds nothing (or names a prefix map).
proc keymap-origin {node keys} {
    set k [lindex $keys 0]
    if {![dict exists $node $k]} { return "" }
    set entry [dict get $node $k]
    if {[llength $keys] == 1} {
        return [expr {[lindex $entry 0] eq "map" ? "" : [lindex $entry 3]}]
    }
    if {[lindex $entry 0] ne "map"} { return "" }
    return [keymap-origin [lindex $entry 1] [lrange $keys 1 end]]
}
proc keymap-unset {node keys} {
    set k [lindex $keys 0]
    if {![dict exists $node $k]} { return $node }
    if {[llength $keys] == 1} {
        dict unset node $k
        return $node
    }
    set entry [dict get $node $k]
    if {[lindex $entry 0] ne "map"} { return $node }
    set sub [keymap-unset [lindex $entry 1] [lrange $keys 1 end]]
    if {[dict size $sub]} {
        dict set node $k [list map $sub]
    } else {
        dict unset node $k
    }
    return $node
}
# ---------------- who is speaking ----------------
# A binding used to be a script and nothing else, and WHO put it there
# was worked out afterwards by matching the layers' words against the
# live payload — which cannot tell two identical scripts apart and
# cannot say anything at all about a word that has stopped answering.
# It also made a bundle's departure blind: `wm-keys off` swept its
# chords whoever owned them by then, so a bind TAKEN from a bundle
# died with the family it had been taken out of (the owner's desk,
# 2026-08-01, measured in the log).
#
# So the binder says its name. `::saying` is a STACK — the same shape
# the launch door uses for its context — because a bundle body binds
# from inside a layer's own load: the innermost speaker is the
# answer, and it unwinds in a finally whatever the body does.
keep saying {}
proc say-as {who script} {
    lappend ::saying $who
    try {
        uplevel 1 $script
    } finally {
        set ::saying [lrange $::saying 0 end-1]
    }
}
# The layer machinery has half the answer already (::knob_layer is
# config or custom while a layer file is sourced, empty otherwise);
# a bundle pushes its own name over that.
proc saying-now {} {
    if {[llength $::saying]} { return [lindex $::saying end] }
    if {[info exists ::knob_layer] && $::knob_layer ne ""} { return $::knob_layer }
    return code
}
# ...and WHERE it was said, to the line, when it was said in a file.
# `info frame` knows exactly this (the owner's pointer, 2026-08-01):
# walk out to the innermost frame that came from a source, which is
# the config that called us however many procs deep. A word spoken
# through the applet's door comes from no file and says so — until
# the save, after which the replay finds it in one.
# Note which file it skips: OUR OWN. `info frame` gives a proc's body
# the file it was written in, so the innermost source frame is always
# this library — and the question is not where wm-bind lives but who
# called it. The first frame from a file that is not ours is the
# answer; a bundle asked for by a config names the line that asked.
# ...and WHERE it was said — every link of it. `info frame` knows
# the whole chain, and the useful answer is neither its innermost nor
# its outermost end but ALL the frames that land in the reader's own
# files (the owner, 2026-08-01):
#
#     proc auto_define_buttons {} { … panel-button X … }   ;# :42
#     auto_define_buttons {a b c}                          ;# :88
#
# Both lines are his, and knowing only one of them is knowing half of
# where the button came from. So the answer is a LIST, innermost
# first: {…/tk9wm.tcl:42 …/tk9wm.tcl:88}.
#
# ONLY WHILE A LAYER IS BEING READ, and never our own files. Outside
# that, everything on the stack is machinery — the entry script never
# leaves it (it called the event loop), and a desk started through a
# wrapper has the wrapper's file down there too, which is how a live
# edit in the applet came to claim it was said at tk9wm.tcl:35 (the
# owner, same day). No layer, no location: a word spoken through the
# applet's door was said in no file, and saying so is the whole of
# the answer.
set said_where_depth 4    ;# a recursive helper would otherwise unroll
proc said-where {} {
    if {![info exists ::knob_layer] || $::knob_layer eq ""} { return "" }
    set chain {}
    for {set i [info frame]} {$i > 0} {incr i -1} {
        if {[catch {info frame $i} f]} continue
        if {![dict exists $f type] || [dict get $f type] ne "source"} continue
        set file [dict get $f file]
        if {[info exists ::tk9wm_library]
                && [string match "$::tk9wm_library/*" $file]} continue
        if {$file eq [file normalize $::argv0]} continue
        lappend chain "$file:[dict get $f line]"
        if {[llength $chain] >= $::said_where_depth} break
    }
    return $chain
}

# How high a word stands: the custom layer over the config over the
# code and its bundles. wm-bind compares by THIS, not by arrival
# time — see below.
proc origin-rank {origin} {
    switch -- $origin {
        custom { return 3 }
        config { return 2 }
    }
    return 1
}
proc wm-bind {spec script {name ""}} {
    set chords [lmap tok $spec {parse-chord $tok}]
    if {![llength $chords]} { error "wm-bind: empty chord sequence" }
    set path [lmap c $chords {join $c ,}]
    set origin [saying-now]
    set was [keymap-origin $::keymap $path]
    # A LOWER LAYER DOES NOT TAKE A HIGHER ONE'S CHORD. The map used
    # to be last-writer-wins, which was right only because a full
    # load replays the layers in rank order — a bundle re-declared
    # LIVE (its params re-saved) replayed its binds over the custom
    # word that had overridden one of them, while the tree went on
    # calling that word «in force» (the owner, 2026-08-03). A bind is
    # a REQUEST against the map; rank decides, whenever it arrives.
    # The lower word is not lost: it lands in code_binds below, which
    # is exactly the «would say» memory the claimant rows read.
    if {$was ne "" && [origin-rank $was] > [origin-rank $origin]} {
        if {$origin ni {custom config}} {
            dict set ::code_binds $path \
                [dict create script $script name $name origin $origin]
        }
        puts "WM: key [join [lmap c $chords {chord-name {*}$c}] { }]:\
 $was keeps it — ${origin}'s word stands aside"
        return
    }
    # WHO IS LOSING THIS CHORD, if anybody: a bind over somebody
    # else's word is exactly the conflict the desk had no way to
    # mention, and the one line here is what the configurator's
    # warning will be built on.
    if {$was ne "" && $was ne $origin} {
        puts "WM: key [join [lmap c $chords {chord-name {*}$c}] { }]:\
 $origin takes it from $was"
    }
    set ::keymap [keymap-set $::keymap $path \
                      [list $script $name $origin [said-where]]]
    if {$origin ni {custom config}} {
        dict set ::code_binds $path \
            [dict create script $script name $name origin $origin]
    }
    set top [lindex $chords 0]
    if {$top ni $::grabbed_top} {
        lappend ::grabbed_top $top
        grab-chord $top
        puts "WM: key top chord [chord-name {*}$top] grabbed"
        # a top chord arriving under a live claim is claimed at once
        keys-pass-apply
    }
}

# The quadruple: an X grab matches the modifier state EXACTLY, so every
# chord is grabbed four times over — plain, +Lock (Caps), +Mod2 (Num),
# +both — and the same lock bits are stripped from the state before a
# chord lookup. Keyboard-SYNC, like the click-to-focus button grab: an
# idle press stands frozen until the dispatcher answers it — kept for
# the desk (async-keyboard) or handed to the focused client
# (replay-keyboard: an unbound echo, or the keys-pass fallback).
# Uniformly for every chord: per-chord mode bookkeeping is not worth
# saving events that arrive at a human's tempo.
proc grab-chord {chord} {
    # A suspended leader stays lifted: the focused window claims it
    # (keys-pass-apply), and a re-lay — keys-remap, a re-bind — must
    # not hand it back to the desk behind the claim's back.
    if {$chord in $::keys_suspended} return
    lassign $chord mods ks
    set got 0
    foreach k [concat [list $ks] [keypad-twin $ks]] {
        set kc [x-keycode $k]
        if {$kc == 0} continue
        foreach locks {0 2 16 18} {
            x-grab-key $kc [expr {$mods | $locks}] $::root sync
        }
        incr got
    }
    if {!$got} {
        puts "WM: no keycode for [keysym-name $ks] — chord not grabbed"
        return
    }
    x-sync 0
}
# A DIGIT IS A DIGIT WHEREVER IT IS TYPED. With NumLock on, the keypad
# sends KP_1 and not 1 — a different keysym, so a chord bound to the
# digit was simply dead over there (the owner, 2026-08-04). The pair is
# grabbed together and normalized apart: this returns the twin to grab,
# and chord-key below folds an arriving KP_n back onto its digit, so
# ONE binding covers both keys and the help has one line to show.
#
# NumLock OFF is deliberately left alone: the keypad then sends End,
# Down, Prior and friends, which are keys in their own right and belong
# to whoever bound them.
proc keypad-twin {ks} {
    set n [keysym-name $ks]
    if {[regexp {^([0-9])$} $n -> d]} {
        set kp [x-keysym KP_$d]
        if {$kp != 0} { return [list $kp] }
    }
    return {}
}
# ...and the same fold on the way in: the keysym a lookup is keyed on.
#
# The keypad needs its SECOND level read, and this is the part that is
# easy to get wrong: a keypad keycode carries two keysyms, KP_End at
# level 0 and KP_1 at level 1, and which one the server reports depends
# on NumLock. We grabbed the keycode with every lock combination, so
# the press arrives either way — and a fold that only knew KP_1 left
# the NumLock-off press swallowed by our own grab and doing nothing,
# which is the worst of the three outcomes. So the physical key is what
# is folded: whatever it says now, if its level-1 symbol is KP_n then
# it IS the digit n.
proc chord-key {kc ks} {
    if {![string match KP_* [keysym-name $ks]]} { return $ks }
    set lvl1 [x-keysym-at $kc 0 1]
    if {[regexp {^KP_([0-9])$} [keysym-name $lvl1] -> d]} {
        set alt [x-keysym $d]
        if {$alt != 0} { return $alt }
    }
    return $ks
}
# The modal ROUTER hears the keypad with the lock read — the one
# deliberate exception to the non-modified world. A chord must fire
# whatever the locks are doing, so chord-key above folds the keypad
# to its digit unconditionally; but a menu standing under
# grab-keys-to is the one place both faces of a keypad key mean
# something — KP_Down walks the list and KP_2 picks row 2 — and
# NumLock is how the hand says which it meant (the owner,
# 2026-08-10). So with NumLock on a keypad key is its digit, and
# with it off it keeps its level-0 name — KP_Up, KP_Home — for the
# routers' navigation tables.
proc router-key {state kc} {
    set ks [x-keysym-at $kc 0 0]
    if {($state & 16) && [string match KP_* [keysym-name $ks]]} {
        set lvl1 [x-keysym-at $kc 0 1]
        if {[regexp {^KP_([0-9])$} [keysym-name $lvl1] -> d]
                && [set alt [x-keysym $d]] != 0} {
            return $alt
        }
    }
    return $ks
}
# ...and the same, given back — the keypad TWIN included, mirroring
# grab-chord's own enumeration: an ungrab that forgot the twin left a
# digit's keypad half grabbed, which a released orphan could shrug
# off but a keys-pass suspension cannot — the twin's grab would go on
# blipping the focus the suspension exists to keep still.
proc ungrab-chord {chord} {
    lassign $chord mods ks
    foreach k [concat [list $ks] [keypad-twin $ks]] {
        set kc [x-keycode $k]
        if {$kc == 0} continue
        foreach locks {0 2 16 18} {
            x-ungrab-key $kc [expr {$mods | $locks}] $::root
        }
    }
    x-sync 0
}

# ---- keys-pass: a claim LIFTS the grabs it names ----
# The style key keys-pass names leaders the desk gives up while the
# window holds the focus. The first answer was replay — and the
# owner's RDP viewer showed why replay cannot be the whole answer
# (2026-08-15): a passive grab's ACTIVATION generates
# FocusOut(NotifyGrab) at the focused client before the replay
# arrives, and an RDP-class client releases its held modifiers on any
# FocusOut — Alt+Tab landed remotely as a bare Tab. No grab mode
# avoids that blip; the only delivery with the modifier world intact
# is the one no grab touches. So the claim suspends the SERVER GRABS
# themselves: while a claiming window is focused its leaders are not
# grabbed at all, and every press reaches it natively.
#
# DERIVED, NOT TRACKED. The desired set is a pure function of
# (::focused, the styles, the bundles, what is actually grabbed),
# diffed here against ::keys_suspended — idempotent, so every front
# that can move an input just calls it: the two focus funnels
# (paint-focus, focus-park), a top chord coming or going (wm-bind,
# keys-drop-orphan), a bundle re-declaration (wm-keys, deferred to
# its end so a half-moved family is never consulted), and the
# reload's keys settler. A missed front does not eat a key: the sync
# grab still freezes the press and handle-key's verdict replays it —
# degraded for RDP, whole for everyone else, and logged as the
# fallback it is.
keep keys_suspended {}   ;# leaders whose server grabs are lifted
keep keys_pass_defer 0   ;# mid-transaction guard, see wm-keys
proc keys-pass-apply {} {
    if {$::keys_pass_defer} return
    set want {}
    foreach top [policy-keys-pass-set $::focused] {
        if {$top in $::grabbed_top && $top ni $want} { lappend want $top }
    }
    if {$want eq $::keys_suspended} return
    set was $::keys_suspended
    set ::keys_suspended $want
    # the resume first consults the new set (grab-chord skips what is
    # still suspended), so the bookkeeping moves before the grabs do
    foreach top $was {
        if {$top ni $want && $top in $::grabbed_top} { grab-chord $top }
    }
    foreach top $want {
        if {$top ni $was} { ungrab-chord $top }
    }
    if {[llength $want]} {
        puts "WM: keys-pass: 0x[format %x $::focused] claims\
 [join [lmap c $want {chord-name {*}$c}] {, }] — grabs suspended"
    } else {
        puts "WM: keys-pass: grabs resumed ([llength $was])"
    }
}

# Keycodes moved under us (setxkbmap and friends): re-grab every top
# chord at its new keycode. Xlib's own keysym cache is refreshed by Tk
# when the MappingNotify passes through it — which is why the
# dispatcher defers this to idle instead of calling it on the spot.
# Drop every chord this WM holds — the config's and our own alike. A
# config reload needs it: a config binds OVER the in-code defaults, and
# an override cannot be un-bound piecemeal (the map keeps one entry per
# chord, whoever wrote it last). So the floor is swept and re-laid.
proc keys-reset {} {
    x-ungrab-key 0 32768 $::root      ;# AnyKey, AnyModifier
    keyseq-end
    set ::keymap {}
    set ::grabbed_top {}
    # grabs swept wholesale means nothing is suspended: a stale entry
    # here would make grab-chord skip re-laying that chord's floor
    set ::keys_suspended {}
    set ::code_binds {}
    set ::help_chord $::HELP_CHORD    ;# a key binding too, and swept with them
    x-sync 0
    puts "WM: key bindings cleared"
}

proc keys-remap {} {
    x-ungrab-key 0 32768 $::root      ;# AnyKey, AnyModifier
    foreach chord $::grabbed_top { grab-chord $chord }
    puts "WM: keyboard remapped — [llength $::grabbed_top] top chords re-grabbed"
}

proc keyseq-end {} {
    if {$::kbd_grabbed} {
        x-ungrab-keyboard 0
        x-sync 0
        set ::kbd_grabbed 0
        # the ungrab released any queued events with it (Xlib's own
        # words) — the freeze is answered, and the latch must agree
        # or the dispatcher's finally would answer a second time
        set ::key_frozen 0
    }
    set ::keyseq ""
    set ::keyseq_keys {}
    set ::keyseq_opener ""
    policy-key-echo none
}
# The chords typed so far, as one line — what the echo is about.
proc keyseq-text {} { join $::keyseq_keys " " }

# What is bound under the prefix we are standing in: {header rows},
# where a row is {keys what}. The keys are spelled the way a config
# would spell them, which is now the same way the desk shows them
# everywhere else (see parse-chord), so a line here can be typed back
# verbatim.
#
# THE WHOLE SUBTREE, not just the next step. The first version showed
# a submap as "… (2 more)" and the owner was right to call that a
# greedy saving (2026-07-30): a desk has a dozen or so bindings, they
# fit on the screen, and hiding them behind a level buys nothing. It
# would buy something only if a group could say what it IS — and a
# group's meaning cannot be synthesized out of the keys under it, so
# between "expand" and "describe" the honest one is expand.
#
# An action with no name of its own shows its SCRIPT collapsed to one
# line — usually a command (winops, Quit), otherwise the first words of
# it, which is enough to recognize something one wrote oneself.
proc keyseq-help {} {
    list "[keyseq-text] …" \
         [lsort -index 0 -dictionary [keymap-rows $::keyseq {}]]
}
# The same question asked FROM THE TOP (the owner's ask: <Super>h
# should answer at the top level, not only inside a sequence). What
# it does is enter the keymap at its ROOT under the usual sequence
# grab, with the whole tree shown at once: the next press WALKS from
# the root exactly as any sequence step — a top chord carries its own
# modifiers and sits in this very map — Escape leaves, and the help
# key keeps answering deeper down. The welcome mat's link lands here
# too, which is why this is a proc and not a binding's private
# script.
proc key-help-open {} {
    if {$::keyrouter ne ""} {
        puts "WM: key help: a modal holds the keyboard — not now"
        return
    }
    if {![dict size $::keymap]} {
        puts "WM: key help: nothing is bound"
        return
    }
    if {!$::kbd_grabbed} {
        if {![x-grab-keyboard $::root 0 sync]} {
            puts "WM: key help: the keyboard grab was refused"
            return
        }
        set ::kbd_grabbed 1
    }
    set ::keyseq $::keymap
    set ::keyseq_keys {}
    set ::keyseq_mods 0
    # the help chord OPENED this sequence, so doubled it goes through
    # like any opener, box and all (keyseq-end takes the box). Opened
    # from the welcome mat there is no chord — and "" matches no press.
    set ::keyseq_opener [expr {[llength $::help_chord]
                               ? [join $::help_chord ,] : ""}]
    set ::keyseq_opener_up 0
    set ::keyseq_opener_keys {}
    puts "WM: key help from the top\
 ([llength [keymap-rows $::keymap {}]] bindings)"
    policy-key-echo help [keyseq-help]
}
proc keymap-rows {node path} {
    set rows {}
    dict for {k entry} $node {
        lassign [split $k ,] mods ks
        set here [concat $path [list [chord-name $mods $ks]]]
        lassign $entry kind payload name
        if {$kind eq "map"} {
            lappend rows {*}[keymap-rows $payload $here]
        } else {
            lappend rows [list [join $here " "] \
                [expr {$name ne "" ? $name : [help-label $payload]}]]
        }
    }
    return [help-collapse $rows]
}
# A FAMILY OF DIGITS IS ONE LINE. Four desks are four bindings and the
# help would list four of them; nine would be nine, and the list one
# reads to learn the desk would be mostly the same row over and over
# (the owner, 2026-08-04). They collapse to «Super+1..4», with the
# digit standing as N in the words.
#
# Nothing is declared for this and nothing needs to be: rows merge when
# they differ ONLY by a digit — same path before the last chord, same
# modifiers on it, and labels that become the same sentence once each
# has its own digit taken out. That is a strong enough test that an
# accidental merge would have to be two bindings which are already the
# same thing said twice.
#
# The digits are printed as RUNS, so 1 2 3 5 comes out «1..3,5» rather
# than pretending to be a range it is not.
proc help-collapse {rows} {
    set order {}
    set group {}
    foreach row $rows {
        lassign $row keys label
        set words [split $keys " "]
        set last [lindex $words end]
        if {![regexp {^(.*?)([0-9])$} $last -> pre d]
                || ($pre ne "" && ![string match "*+" $pre])} {
            lappend order [list row $row]
            continue
        }
        set canon [string map [list $d "\u0001"] $label]
        set key [list [lrange $words 0 end-1] $pre $canon]
        if {![dict exists $group $key]} {
            lappend order [list group $key]
            dict set group $key {}
        }
        dict lappend group $key $d
    }
    set out {}
    foreach item $order {
        lassign $item kind payload
        if {$kind eq "row"} { lappend out $payload; continue }
        lassign $payload before pre canon
        set digits [lsort -integer [dict get $group $payload]]
        set label [string map [list "\u0001" N] $canon]
        if {[llength $digits] == 1} {
            set label [string map [list "\u0001" [lindex $digits 0]] $canon]
        }
        lappend out [list [string trim "[join $before { }] $pre[digit-runs $digits]"] \
                          $label]
    }
    return $out
}
proc digit-runs {digits} {
    set parts {}
    set from ""
    set prev ""
    foreach d $digits {
        if {$from eq ""} { set from $d; set prev $d; continue }
        if {$d == $prev + 1} { set prev $d; continue }
        lappend parts [expr {$from == $prev ? $from : "$from..$prev"}]
        set from $d
        set prev $d
    }
    if {$from ne ""} {
        lappend parts [expr {$from == $prev ? $from : "$from..$prev"}]
    }
    join $parts ,
}
proc help-label {script} {
    set one [string trim [regsub -all {\s+} $script " "]]
    if {[string length $one] > 46} { set one "[string range $one 0 43]…" }
    return $one
}
# `flash` is what the echo says about the abort AFTER the state is
# gone, so it has to be composed by the caller, while keyseq-text can
# still answer. Empty for a cancel the user asked for: Escape needs no
# report, one already knows.
proc keyseq-abort {why {flash ""}} {
    puts "WM: key sequence abort ($why)"
    keyseq-end
    if {$flash ne ""} { policy-key-echo flash $flash }
}

# Keyboard-modal UI (the menus): hold the keyboard and route every key
# event to cmd, called with press or
# release, the keysym name and the (lock-stripped) modifier mask —
# releases included, and modifier keys unfiltered: the alt-tab commit
# rides on the release of a bare modifier. The Tk focus path is no use
# here: such UI lives in override-redirect toplevels, and Tk refuses
# to XSetInputFocus those (tkUnixFocus.c, an old olvwm-menus hack) —
# Tk's own menus run on grabs for the same reason. An empty cmd
# releases the keyboard and hands keypresses back to the keymap.
#
# THE ROUTER IS A SINGLE SLOT, and taking it hands the previous holder
# its notice: `onlost` is a script run when this router stops being the
# router — whoever ends it, and INCLUDING the holder releasing it
# itself, which is what makes the callback the one place a modal thing
# tears itself down. (So every onlost must be idempotent; they are all
# "end my mode", which is idempotent anyway.)
#
# Silently overwriting was how a keyboard resize survived the window
# menu being opened over it with the mouse — the menu took the router,
# the pick released it, and the mode was left standing with its amber
# frame and its compass and nothing to answer its keys (owner's report,
# 2026-07-29). One slot with no handover is that bug for every pair of
# modal things, present and future; with the handover there is no pair
# left to get wrong.
proc grab-keys-to {cmd {onlost {}}} {
    # The handover runs FIRST and all the way through, grab included: a
    # teardown ends with its own grab-keys-to {}, which lets the
    # keyboard go — done after we had taken it, that release would be
    # the incoming holder's, and the new mode would come up with a
    # router and no keyboard under it.
    keyrouter-lost
    if {$cmd eq ""} {
        set ::keyrouter ""
        keyseq-end
        return 1
    }
    if {!$::kbd_grabbed} {
        if {![x-grab-keyboard $::root]} {
            puts "WM: grab-keys-to: the keyboard grab was refused"
            return 0
        }
        set ::kbd_grabbed 1
    } else {
        # taking over a SEQUENCE's grab: that one is sync (the
        # per-event discipline), a router runs async — a same-client
        # GrabKeyboard replaces the parameters in place, and async
        # thaws anything the old discipline left frozen
        x-grab-keyboard $::root 0 async
    }
    set ::keyseq ""      ;# the router replaces any sequence in progress
    set ::keyrouter $cmd
    set ::keyrouter_lost $onlost
    return 1
}
# The outgoing holder's notice, cleared BEFORE it runs: its own
# teardown will call grab-keys-to again, and a notice still in the slot
# would call it back.
proc keyrouter-lost {} {
    set lost $::keyrouter_lost
    set ::keyrouter_lost ""
    if {$lost eq ""} return
    if {[catch {uplevel #0 $lost} err]} {
        puts "WM: key router handover: $err"
    }
}
proc route-key {kind name mods} {
    if {[catch {uplevel #0 [list {*}$::keyrouter $kind $name $mods]} err]} {
        problem-record "key router" $err
    }
}

# Pointer-modal gesture — grab-keys-to's mouse twin: hold the POINTER
# and route every motion and the release to cmd, called with `motion X
# Y` / `release X Y` in ROOT coordinates. It exists for gestures on
# windows that are not ours: a modifier-drag lands on a CLIENT, where
# no Tk binding can fire and the click-to-focus grab reports the press
# and nothing after it. The grab carries the cursor, too, which is the
# only way to show a drag cursor over a foreign window. An empty cmd
# ends the gesture and lets the pointer go.
keep pointerrouter ""
proc grab-pointer-to {cmd {cursor ""}} {
    if {$cmd eq ""} {
        set ::pointerrouter ""
        x-ungrab-pointer $::evtime
        return 1
    }
    if {![x-grab-pointer $::root {button-release pointer-motion} \
              $::evtime $cursor]} {
        puts "WM: grab-pointer-to: the pointer grab was refused"
        return 0
    }
    set ::pointerrouter $cmd
    return 1
}
proc route-pointer {kind X Y} {
    if {[catch {uplevel #0 [list {*}$::pointerrouter $kind $X $Y]} err]} {
        puts "WM: pointer router error: $err"
        soft "drop a broken gesture" { grab-pointer-to {} }
    }
}

# Is any key of the given modifier mask physically down right now? The
# fvwm alt-tab semantics hinge on "was Alt still held when the list
# opened" and "is it still held after this release" — and a KeyRelease
# that happened before our grab began is something we never saw, so
# the server's live keymap is the only honest answer.
proc modifier-held {mask} {
    set names {}
    foreach {bit syms} [array get ::modkeysyms] {
        if {$mask & $bit} { lappend names {*}$syms }
    }
    if {![llength $names]} { return 0 }
    set v [soft "read the keymap" { x-keymap }]
    if {[string length $v] != 32} { return 0 }
    foreach n $names {
        set ks [x-keysym $n]
        if {$ks == 0} continue
        set kc [x-keycode $ks]
        if {$kc == 0} continue
        binary scan $v "x[expr {$kc / 8}]cu" byte
        if {$byte & (1 << ($kc % 8))} { return 1 }
    }
    return 0
}

# One KeyPress from our grabs walks the keymap: idle state consults the
# top map (the press came through a top-chord XGrabKey), a sequence in
# progress consults its current submap (the press came through the
# temporary XGrabKeyboard). An unbound press aborts a sequence — out
# loud, see keyseq-abort — but in idle state it is REPLAYED to the
# client (the dispatcher's finally): a stale grab echo is no error,
# and no reason to eat a letter either.
#
# A TOP CHORD IS ALWAYS LIVE. Inside a sequence, a press the current
# submap does not know but the TOP map does starts over from there
# instead of aborting: reaching for <Super>t when a forgotten <Super>t
# is already pending is the commonest way to arrive at "undefined key"
# by accident, and the intent behind the press is never "abort" — it
# is "begin" (the owner, 2026-07-30). It costs the sequence nothing:
# THE SUBMAP IS ASKED FIRST, so a config that binds <Super>t under
# <Super>t keeps its meaning exactly where it bound it, and the
# restart applies everywhere else. The same holds for a top chord that
# is an ACTION and not a prefix: a global key stays global, which is
# the same promise read from the other end.
#
# Escape sits BETWEEN the two maps. The submap's own Escape beats the
# cancel — the particular beats the rule — but the cancel beats the
# restart, because a globally bound Escape would otherwise take away
# the one way out that works from anywhere.
# Which bits of a key event's state are none of a chord's business.
# Lock and Mod2 are Caps and Num, which make no chord distinct — and
# neither does the xkb GROUP, which XKB reports in bits 13-14 of the
# CORE event state (XkbGroupForCoreState in X11/extensions/XKB.h, and
# the shim hands that state through untouched).
#
# That one is not cosmetic. A chord's grab keeps working across a group
# change — XKB keeps a separate grab state with no group in it, which
# is what grab_mods is for — so with the layout switched to Russian the
# press still ARRIVES here, gains 0x2000 on the way, and misses a table
# keyed on the bare modifier. The key is swallowed by our grab and
# nothing runs: the chord goes quietly dead for as long as the group is
# switched, which is the worst of the three possible outcomes.
#
# The KEYSYM never had this problem and it is worth saying why, since
# it is the half one expects to break: the lookup asks the map for
# group 0 level 0 by hand rather than trusting the event, so a chord is
# named by its Latin keysym whatever is being typed. <Super>l is
# <Super>l on a Cyrillic group, and a menu hotkey is its Latin letter
# too.
set CHORD_IGNORE [expr {2 | 16 | 0x6000}]
# The sync grab's other half: answer the server EXACTLY once per
# frozen press. The dispatcher arms the latch when a press arrives
# with no active grab of ours; every answer funnels through here, the
# first one wins, and the dispatcher's finally sweeps whatever stayed
# silent into a replay. An unanswered freeze is the failure mode this
# shape exists to make impossible: the keyboard stops for the whole
# display.
proc key-thaw {mode time} {
    if {!$::key_frozen} return
    set ::key_frozen 0
    x-allow-events $mode $time
    x-sync 0
}
# The fallback's line, said once per (chord, window): a held leader
# autorepeats through the WM at full rate, and «why does Alt+Tab not
# work here» needs one line, not a storm. With the suspension doing
# its job this never prints — a claimed leader's grab is lifted and
# no press detours here — so the line standing in a log is itself
# the finding: some front moved the claim without settling it.
keep keys_pass_said {}
proc keys-pass-log {mods ks} {
    set said [list $mods $ks $::focused]
    if {$said eq $::keys_pass_said} return
    set ::keys_pass_said $said
    puts "WM: key [chord-name $mods $ks] -> passed to\
 0x[format %x $::focused] (keys-pass fallback)"
}
proc handle-key {state kc time} {
    set mods [expr {$state & ~$::CHORD_IGNORE}]
    if {$::keyrouter ne ""} {
        # the router reads the keypad through the lock — router-key,
        # the deliberate exception the chord fold must not make
        route-key press [keysym-name [router-key $state $kc]] $mods
        return
    }
    set ks [chord-key $kc [x-keysym-at $kc 0 0]]
    if {[info exists ::ismodks($ks)]} return
    # keys-pass, the FALLBACK half: a claimed leader's grab is lifted
    # (keys-pass-apply), so a frozen press on one means a front was
    # missed — replay it to the window anyway (soft degradation: an
    # RDP-class client gets the key bare, everyone else gets it
    # whole) and let keys-pass-log name the anomaly. Only an idle
    # press can arrive frozen: under a sequence or a router the
    # keyboard is actively ours. Compared AFTER the chord-key fold,
    # so the verdict sees the same (mods, keysym) the lookup would.
    if {$::key_frozen && [policy-key-pass $::focused $mods $ks]} {
        keys-pass-log $mods $ks
        key-thaw replay-keyboard $time
        return
    }
    set k "$mods,$ks"
    set node $::keymap
    set restart 0
    if {$::keyseq ne ""} {
        if {[dict exists $::keyseq $k]} {
            set node $::keyseq
        } elseif {$::chord_hold && $mods == $::keyseq_mods && $mods != 0
                  && [dict exists $::keyseq "0,$ks"]} {
            # The hand never let go: the prefix's own modifiers on an
            # inner key mean the same key.
            set node $::keyseq
            set k "0,$ks"
        } elseif {$k eq $::keyseq_opener && $::key_double_pass && $::key_dar
                  && $::keyseq_keys eq $::keyseq_opener_keys} {
            # THE DOUBLED OPENER GOES THROUGH — screen and tmux's own
            # idiom (C-a C-a types a literal C-a): a second press of
            # the chord that opened the sequence, made where the opener
            # left it, asks for that chord LITERALLY. The replay
            # releases the active grab and the server reprocesses the
            # press ignoring root's passive grabs — native delivery,
            # into the focus, modifiers intact — so keyseq-end below
            # has no grab left to drop. A config's word still beats the
            # idiom: the exact match above (a submap's own <Super>t)
            # and chord-hold's fill (a bare letter with the modifier
            # still down) both come first — the forward takes only the
            # slot the restart-into-itself used to no-op in. Walked
            # deeper, the opener is not standing where it left the keys
            # and restarts as it always did.
            if {!$::keyseq_opener_up} {
                # the opener never came up: this press is the hold's
                # autorepeat, not a second press — stand still (the
                # finally answers sync; detectable autorepeat is what
                # makes the hold readable, and ungranted it keeps this
                # whole branch dark, see key_dar)
                return
            }
            puts "WM: key [chord-name $mods $ks] -> doubled, passed to\
 the window"
            key-thaw replay-keyboard $time
            set ::kbd_grabbed 0
            keyseq-end
            return
        } elseif {$ks == $::KS_ESC} {
            keyseq-abort Esc
            return
        } elseif {[llength $::help_chord] && $k eq [join $::help_chord ,]} {
            # The sequence stands where it is: this was a question, not
            # a step. The next press walks on from the same submap.
            puts "WM: key [chord-name $mods $ks] -> what is under\
 [keyseq-text]"
            policy-key-echo help [keyseq-help]
            return
        } elseif {[dict exists $::keymap $k]} {
            puts "WM: key [chord-name $mods $ks] restarts the sequence"
            set restart 1
        } else {
            keyseq-abort "[chord-name $mods $ks] unbound" \
                "[keyseq-text] [chord-name $mods $ks] is undefined"
            return
        }
    }
    if {![dict exists $node $k]} return
    lassign [dict get $node $k] kind payload
    if {$kind eq "action"} {
        # release the keyboard BEFORE the action: it may want focus.
        # The chord's own modifiers are published for the action: the
        # window list reads them to decide "am I an alt-tab cycle".
        # the WHOLE sequence, spelled as the desk shows it — captured
        # before keyseq-end forgets the prefix, because a failure
        # reported as «key z» names a key nobody bound
        set said [join [concat $::keyseq_keys [chord-name $mods $ks]] " "]
        keyseq-end
        # ...and a frozen press is the desk's to KEEP: answered async
        # before the action runs, which may park or take its time
        key-thaw async-keyboard $time
        puts "WM: key [chord-name $mods $ks] -> action"
        set ::key_invoke_mods $mods
        set t0 [clock milliseconds]
        # IN A COROUTINE, so a script that waits on something parks
        # instead of stopping the desk (run-script). The failure still
        # lands in the problem store under this chord's name — the log
        # is not where a hand on the keyboard is looking — and the
        # measurement below now says what it always meant to: how long
        # the desk was HELD, which for a parking script is only until
        # it parks.
        run-script "key $said" $payload
        # ...and HOW LONG it took, because a desk that stops answering
        # for three seconds is a defect whoever wrote the binding
        # cannot see from the inside
        set held [expr {[clock milliseconds] - $t0}]
        if {[info exists ::key_hold_warn] && $held >= $::key_hold_warn} {
            problem-record "key $said" "this binding held the desk for\
 [format %.1f [expr {$held / 1000.0}]] s — nothing else was answered while\
 it ran (a launch wants `Run`, and a wait wants a coroutine)"
        }
    } else {
        set opened [expr {$::keyseq eq ""}]
        if {$opened} {
            if {![x-grab-keyboard $::root $time sync]} {
                # the dispatcher's finally replays the frozen press:
                # whoever holds the keyboard, the client still types
                puts "WM: key [chord-name $mods $ks]: the keyboard grab was\
 refused — sequence dropped"
                return
            }
            set ::kbd_grabbed 1
            # The SYNC active grab CONTINUES the passive grab's freeze
            # where async used to thaw it; the sync-keyboard answer
            # lets the queue move — until the next key event, which
            # again stands frozen. So the WHOLE sequence runs under the
            # per-event discipline: press, release and autorepeat each
            # wait for their one answer (the doubled-opener forward and
            # its hold detection ride on seeing them all), nothing
            # slips to a client while the sequence lives — which keeps
            # the old race closed the same way the async thaw did: a
            # fast second key waits in the queue and arrives under the
            # grab.
            key-thaw sync-keyboard $time
        }
        if {$restart} { set ::keyseq_keys {} }
        puts "WM: key [chord-name $mods $ks] -> prefix"
        set ::keyseq $payload
        set ::keyseq_mods $mods
        lappend ::keyseq_keys [chord-name $mods $ks]
        if {$opened || $restart} {
            # a sequence STARTED, fresh or over: this chord is its
            # opener, its key is down at this instant, and this is
            # where it left the keys — the doubled-opener forward
            # reads all three
            set ::keyseq_opener $k
            set ::keyseq_opener_up 0
            set ::keyseq_opener_keys $::keyseq_keys
        }
        policy-key-echo keys [keyseq-text]
    }
}

# ---------------- adoption ----------------
# Adoption: windows that mapped before the WM started (or survived a WM
# restart via the save-set) are already viewable children of root and never
# produce a MapRequest — walk the tree once at startup and manage them.
proc adopt-existing {} {
    set tree [x-query-tree $::root]
    if {![llength $tree]} return
    set found {}    ;# {w iconic width height viewable}, bottom first
    foreach w [lindex $tree 2] {
        if {[info exists ::managed($w)]} continue
        # A window OF OURS is not a client to adopt: the frames, the
        # panel and the main window are children of the root too, and on
        # one connection they are in this very list. (With two
        # connections the check was implicit and invisible — our
        # decorations belonged to the OTHER client.)
        if {[our-window $w] || $w == $::nofocus
                || ([info exists ::wmcheck] && $w == $::wmcheck)} continue
        set at [x-attrs $w]
        if {![dict size $at]} continue
        # Override-redirect has declared itself no manager's business.
        if {[dict get $at override-redirect]} continue
        # WM_STATE is what the PREVIOUS window manager left behind, and
        # across a restart that manager was us. IconicState means this
        # window is off the screen because somebody minimized it — not
        # because it is uninteresting — so it is adopted and put right
        # back into that state. Without this a restart silently
        # un-minimized everything, and the windows came back BLANK:
        # a toolkit that tracks its own minimized state (gtk, gecko,
        # electron — xterm and emacs do not) still believed itself
        # iconic and would not paint into a window the server had
        # mapped behind its back. Minimizing and restoring by hand
        # fixed each one, which is the tell (owner's report,
        # 2026-07-29).
        #
        # Such a window can look either of two ways here, and both must
        # be taken. Still unmapped, if nothing touched it — or already
        # remapped behind our back by the SAVE-SET: the X connection is
        # close-on-exec (verified: flags 02004002 on the socket), so
        # execv drops it, and on close-down the server reparents and
        # REMAPS everything the dying manager had unmapped.
        set wmstate [read-prop-long $w $::WM_STATE]
        set iconic [expr {$wmstate == 3}]
        if {[dict get $at map-state] ne "viewable" && !$iconic} continue
        lappend found [list $w $iconic \
            [dict get $at width] [dict get $at height] \
            [expr {[dict get $at map-state] eq "viewable"}]]
    }
    if {![llength $found]} return
    # TOPMOST FIRST — the tree came bottom-first — and under the
    # ::adopting flag: the model seats each arrival at the bottom and
    # frame-show seats its frame under the one shown before it, so the
    # desk reassembles BEHIND its own top window. The desk switch's
    # cure, applied to the restart: reframing bottom-up gave every
    # window a raise and a focus apiece, each on the glass (the owner,
    # 2026-08-06: «адское мигание всего»). The one focus decision
    # waits for the sweep's end.
    set ::adopting 1
    set ::adopt_prev 0
    try {
        foreach f [lreverse $found] {
            lassign $f w iconic aw ah viewable
            set ::geomof($w) [list $aw $ah]
            # Reparenting a MAPPED window generates an UnmapNotify we
            # must not mistake for the client withdrawing itself. An
            # unmapped one does not, and counting an echo that never
            # comes would swallow the next genuine withdrawal instead.
            if {$viewable} { incr ::skip_unmap($w) }
            puts "WM: adopting existing window 0x[format %x $w] (${aw}x${ah})[
                expr {$iconic ? { — minimized, and staying that way} : {}}]"
            # The intent goes IN, so manage can skip the initial-focus
            # decision rather than make it and take it back.
            manage $w $iconic
        }
    } finally {
        set ::adopting 0
        set ::adopt_prev 0
    }
    # ...and the focus, ONCE: to what the desk had active before the
    # restart (read off the root before our announce zeroed it), else
    # to the top. A substrate running bare has no policy to settle.
    if {[llength [info commands policy-adopt-settled]]} {
        soft "settle the adopted focus" { policy-adopt-settled $::prev_active }
    }
}

# ICCCM 4.1.5: when the WM moves a client by moving its FRAME, the client
# gets no event and keeps stale root coordinates (menus and tooltips then
# pop at wrong places) — the WM must send a synthetic ConfigureNotify with
# root-relative x,y after placement, every frame move, and granted resizes.
proc send-synthetic-configure {w} {
    if {![info exists ::managed($w)]} return
    lassign $::geomof($w) cw ch
    if {[catch {lassign [policy-origin $w] x y}]} return
    x-send-configure $w $w $x $y $cw $ch
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
        x-send-configure $fwin $fwin $fx $fy $fw $fh
    }
    x-flush   ;# no round trip follows during a Tk-side drag
}

# ---------------- the pump ----------------
# There is none, and that is the point: `event on` is a
# Tk_CreateGenericHandler, so the redirect's events arrive in the same
# event loop as everything else, the moment Tk processes them. What
# this replaced was a worker thread blocked in poll() on a second
# connection's fd, pinging the main thread with a single token to drain
# XPending — a machine whose only job was to make two connections look
# like one.
tkwmx::event on handle-event

# Orderly shutdown: release every client back to root before Tk destroys
# the frames (otherwise WM exit would take all clients with it). A hard
# kill still loses them — see notes.
unless-already {[llength [info commands ::tk9wm-real-exit]]} \
    {rename ::exit ::tk9wm-real-exit}
proc ::exit {{code 0}} {
    soft "release the tray on exit" { tray-stop "the window manager is exiting" }
    soft "release clients on exit" { release-all-clients }
    ::tk9wm-real-exit $code
}

# Restart in place — the way to pick up freshly pulled sources: release
# every client back to root (orderly, as in exit), then REPLACE this
# process with a fresh copy of itself via execv. Same pid, same stdout,
# fresh code from disk; the X sockets are close-on-exec, so the server
# reaps the old frames itself, and the new WM adopts the released
# clients at startup — adoption is exactly "windows that lived before
# the WM". Tcl has no exec-replacement of its own; the shim does
# (x-exec-self), and returning from it at all means it failed.
# What execv has to be handed to become US again: {executable ?script?}.
# Not one answer, because the same window manager is started in forms
# that disagree about whether there IS a script to name.
#
# ::tk9wm_reexec is the answer for a wrapper that KNOWS — a list in that
# shape, and the entry point is where the knowledge is (the kit's asks
# starkit itself, which says starkit or starpack outright). The default
# below is for everyone else, and it is a guess: an inference from paths
# that were measured rather than assumed, kept honest by the knob above
# it, which is what the next wrapper form is supposed to use instead of
# a patch here.
#
# The four forms, measured 2026-07-29 — argv0, and what execv needs:
#   interpreter + script   /path/tk9wm.tcl        native  name it
#   starkit                /path/wm.kit           tclvfs  name it
#   starpack               <exe>/main.tcl         tclvfs  do NOT
#   whale -app             //zipfs:/app/main.tcl  zipfs   do NOT
# So the question is not which filesystem argv0 is on — a starkit is
# mounted ON ITS OWN PATH, and answers tclvfs while being exactly the
# file that has to be named. The question is whether argv0 lives INSIDE
# the executable's own image: a path there is not something a command
# line can carry, and the executable alone re-runs it.
#
# NORMALIZED, and that is the owner's correction (2026-07-29): argv0 is
# what the user typed and `info nameofexecutable` is normalized to
# within an inch of its life, so comparing them raw is a coin toss.
proc reexec-head {} {
    if {[info exists ::tk9wm_reexec]} { return $::tk9wm_reexec }
    set exe [info nameofexecutable]
    set a0 [file normalize $::argv0]
    if {$a0 eq $exe || [string match "$exe/*" $a0]
            || [lindex [file system $a0] 0] eq "zipfs"} {
        return [list $exe]
    }
    return [list $exe $::argv0]
}

# Release the whole desk, BOTTOM of the stack first: a reparent back
# to root puts a window on top of the root's children, so releasing in
# stacking order leaves the tree carrying the old order for the next
# instance to read back — the hash order this used to walk shuffled
# the desk on every restart (measured 2026-08-06: eight windows came
# back stacked by release order, the active one wherever it fell).
# Under ::releasing the per-window ceremonies stand down (refocus
# pick, focus repair, client-list, sync) — one of each for the sweep.
proc release-all-clients {} {
    set order {}
    if {[llength [info commands client-stacking]]} {
        set order [client-stacking]
    }
    foreach w [array names ::managed] {
        if {$w ni $order} { lappend order $w }
    }
    set ::releasing 1
    try {
        foreach w $order { unmanage $w }
    } finally {
        set ::releasing 0
    }
    publish-client-list
}

proc restart-wm {} {
    set head [reexec-head]
    # Look before letting go. If what execv needs has moved or been
    # deleted since we started, execv still succeeds and the fresh
    # process dies on the missing file instead. With .Xsession exec'ing
    # the window manager, that death is the death of the session. And by
    # then the clients have already been released, which is the part
    # that made it unrecoverable: the old order discovered the problem
    # only after dismantling every frame on the desk. Rename the
    # checkout, pull a commit that renames the entry script, and the
    # restart chord became a logout — a real migration, 2026-07-29.
    foreach f $head {
        if {![file exists $f]} {
            puts "WM: restart REFUSED — $f is gone; nothing released,\
                  the desk is untouched"
            return 0
        }
    }
    puts "WM: restart requested — releasing clients, exec'ing myself"
    # The tray goes back to the root the same way the clients do; the
    # fresh instance announces itself and every icon docks again.
    soft "release the tray on restart" { tray-stop "the window manager is restarting" }
    soft "release clients on restart" { release-all-clients }
    soft "sync before exec" { x-sync 0 }
    # -replace, even when we were not started with it, and for a reason
    # that only appeared once we owned WM_S<n>: execv keeps the PID but
    # drops the X connection, and the server destroys our windows when
    # it notices — which it may not have done yet when the fresh
    # instance looks at the selection. It would then see the owner
    # window of the manager it IS, and refuse to start. Asking a corpse
    # to stand down costs one poll; the alternative is a restart that
    # sometimes ends the session.
    set av $::argv
    if {"-replace" ni $av} { lappend av -replace }
    if {[catch {
        x-exec-self [lindex $head 0] [list {*}[lrange $head 1 end] {*}$av]
    } err]} { puts "WM: restart FAILED: $err" }
}

# ---------------- the children that came with the pid ----------------
# A restart keeps the pid, and keeping the pid means keeping the
# CHILDREN: execv replaces the image under them, so everything the desk
# had launched — terminals, browsers, the ui host — is still ours,
# while Tcl's record of them is not (its detached list lived in the
# memory execv threw away). Nothing waits for them any more, and each
# becomes a zombie for good on its way out. Measured on the owner's
# desk 2026-07-31: 38 of them after a day of restarts, one whale among
# them for every stale ui host that handed its applets over and left —
# which is why the ui LOOKED like the culprit. It was only the most
# regular victim; the restart chord was the cause.
#
# So the fresh image ADOPTS them. What /proc calls our children at
# startup is exactly the inherited set, because this image has not
# spawned anything yet; everything spawned later stays Tcl's business,
# reaped inside the next exec as always. The two sets cannot overlap,
# and that is what makes waiting safe here: this waits for NAMED pids
# and never for -1, so it can never take the exit status an `exec` or
# a pipe's `close` is about to ask for. Nor can a pid go stale under
# us — an unreaped child holds its pid slot, so the number stays the
# one we adopted until we are the ones who let it go.
proc adopt-orphans {} {
    set kids {}
    # per THREAD, which is how the kernel files them: ours are all the
    # main one's, but the glob costs nothing and asks no questions
    # about which thread of which build did the spawning.
    foreach f [glob -nocomplain /proc/self/task/*/children] {
        soft "read $f" {
            set ch [open $f r]
            append kids " " [read $ch]
            close $ch
        }
    }
    set ::orphans [lsort -integer -unique $kids]
    if {[llength $::orphans]} {
        puts "WM: [llength $::orphans] child(ren) came with the pid —\
              this image will wait for them"
        reap-orphans
    }
}

# They are alive when we adopt them, so all that is left is to ask, now
# and then, whether they still are. A minute is a generous interval for
# a thing with all day: what a poll's delay costs is one pid slot per
# dead orphan, and the desk's own habits — a restart every so often —
# put a fresh set here far more often than this timer runs out of work.
proc reap-orphans {} {
    if {![llength $::orphans]} return
    set done [x-reap $::orphans]
    if {[llength $done]} {
        set left {}
        foreach p $::orphans { if {$p ni $done} { lappend left $p } }
        set ::orphans $left
        puts "WM: reaped [llength $done] inherited child(ren),\
              [llength $::orphans] still going"
    }
    if {[llength $::orphans]} { after 60000 reap-orphans }
}

# Once per image, and the guard is the point: a second pass would call
# the children we have spawned SINCE inherited ones, and waiting for
# those is exactly what must not happen here.
unless-already {[info exists ::orphans]} { adopt-orphans }

# Leave for good — the same release a restart does, and then simply
# stop. With .Xsession exec'ing the window manager this ends the X
# session, which is the point of having it: a desk with no way out from
# the inside is the "how do I exit vim" joke with a whole login inside
# it, and the answer should not be another terminal and a kill (owner's
# report, 2026-07-29).
#
# Releasing first is not politeness. Our frames are about to go with the
# process, and a client reparented into one would go with it — the
# save-set is what stops that, but unmanaging deliberately puts every
# client back on the root at its own place, which is also what the NEXT
# window manager will adopt.
proc quit-wm {} {
    puts "WM: quit requested — releasing clients and leaving"
    soft "release the tray on quit" { tray-stop "the window manager is quitting" }
    soft "release clients on quit" { release-all-clients }
    soft "sync before exit" { x-sync 0 }
    puts "WM: bye"
    exit 0
}

# To be called by the assembly once the policy layer is in: start
# dispatching (replaying whatever arrived while it was being loaded)
# and adopt whatever was already on the screen.
proc substrate-start {} {
    # Detectable autorepeat, asked once for this connection: a held key
    # then repeats as press, press, … with ONE release at the end, so
    # «a press with no release between» reads as the hold it is. The
    # doubled-opener forward stands on that reading and stays off
    # ungranted (see key_dar) — without it a held prefix would type a
    # stream of itself into the window. Ours alone: the clients' view
    # of the keyboard is not touched.
    set ::key_dar [x-key-autorepeat 1]
    if {!$::key_dar} {
        puts "WM: detectable autorepeat refused — a doubled prefix will\
 restart, not forward"
    }
    set queued $::evqueue
    set ::evqueue {}
    set ::dispatching 1
    if {[llength $queued]} {
        puts "WM: [llength $queued] event(s) arrived before the policy was\
 in — replaying"
        foreach ev $queued { handle-event $ev }
    }
    publish-workarea     ;# the desk's shape, before anyone asks
    # ...and an EMPTY client list rather than none at all: "no windows"
    # is an answer, "no property" makes the asker guess (fvwm3 states
    # it on an empty desk too, and that is the whole difference a diff
    # of the two root windows showed here).
    publish-client-list-now
    tray-adopt-orphans   ;# before adopt-existing — see the proc
    adopt-existing
    # A fresh X server starts in PointerRoot, and a WM that leaves it
    # there runs the whole session in focus-follows-pointer — plus it
    # keeps Tk's implicit-focus machinery armed (see the focus holder).
    # A restart lands here too: the previous instance's holder died with
    # its connection, so the focus reverted to the root — the same dead
    # end, and one no FocusIn will ever report to us, since we only
    # started listening now. Take the display into a known state; a
    # focus a real client already holds is left alone.
    set f [lindex [x-focus-get] 0]
    if {$f ne "" && ($f <= 1 || $f == $::root)} {
        focus-repair "the display started with no honest focus"
    }
}
