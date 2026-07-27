# tk9wm policy — the look-and-feel layer: OUR local decisions, none of
# which a WM fundamentally needs to be this way. Tk-widget decorations
# (titlebar / ✕ / slot, highlight colors), cascade placement, title-bar
# drag, click-to-focus, initial focus, refocus pick. Swap this file for a
# different look/behavior; the substrate only ever calls the policy-*
# hooks defined here (contract — see substrate.tcl header and the idea
# file, step 9).
#
# Private state: ::frameof(client) = frame widget, ::leaderof(client) =
# WM_TRANSIENT_FOR leader read at manage time (0 = none), ::focus_hist =
# clients most-recently-focused first, plus the cascade and drag
# bookkeeping. The substrate's client geometry (::geomof) is not touched
# here — sizes always arrive as hook arguments.

package require treectrl   ;# titlebars: its text element cuts a long
                            ;# title with an ellipsis instead of overflowing

set ncli 0
set fid 0
set focus_hist {}

# Where to put a new frame (fw x fh, decoration included). Two rules, in
# order:
#
#  - a DIALOG (WM_TRANSIENT_FOR set, and we manage its parent) is centered
#    over its parent's frame — that is where the user is looking;
#  - everything else cascades.
#
# Then the result is CLAMPED to the screen, which the cascade alone never
# was: GIMP's "Quit" dialog landed at +1020+860 on a 1038-tall screen and
# its buttons ended up below the bottom edge, unclickable (live report,
# 2026-07-27). A window bigger than the screen is pinned at the top-left
# corner — better to lose the far edge than the near one.
proc place-frame {w fw fh} {
    lassign [screen-size] sw sh
    set parent $::leaderof($w)
    if {$parent != 0 && [info exists ::frameof($parent)]} {
        set pt $::frameof($parent)
        if {[regexp {^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$} [wm geometry $pt] -> pw ph px py]} {
            set X [expr {$px + ($pw - $fw) / 2}]
            set Y [expr {$py + ($ph - $fh) / 2}]
            return [clamp-to-screen $X $Y $fw $fh $sw $sh]
        }
    }
    return [cascade-slot $fw $fh $sw $sh]
}

# The cascade used to march forever (110 + 70*n, 80 + 60*n), so on a long
# session every new window walked further down-right until they landed
# fully off-screen (live report, 2026-07-27 — and it applies to ordinary
# windows, not just dialogs). Now the round RESTARTS with the very window
# that would not fit, so the offender itself lands at the top-left slot.
proc cascade-slot {fw fh sw sh} {
    set X [expr {110 + 70*$::ncli}]; set Y [expr {80 + 60*$::ncli}]
    if {$X + $fw > $sw || $Y + $fh > $sh} {
        set ::ncli 0
        set X 110; set Y 80
    }
    incr ::ncli
    return [clamp-to-screen $X $Y $fw $fh $sw $sh]
}
proc clamp-to-screen {X Y fw fh sw sh} {
    if {$X + $fw > $sw} { set X [expr {$sw - $fw}] }
    if {$Y + $fh > $sh} { set Y [expr {$sh - $fh}] }
    list [expr {max($X, 0)}] [expr {max($Y, 0)}]
}

# Build a decoration for client w (client area cw x ch): blue titlebar
# with a ✕, dark slot below; placement per place-frame above. Returns the
# slot's X window id; the Tk roundtrip before the return guarantees the
# slot exists server-side before the raw connection reparents into it.
proc policy-attach {w cw ch} {
    set t .f[incr ::fid]
    # WM_TRANSIENT_FOR is read ONCE, now: the refocus pick needs the
    # dialog's leader at a moment when the dialog may already be a dead
    # window that cannot be asked anything.
    set ::leaderof($w) [transient-for $w]
    lassign [place-frame $w [expr {$cw + 4}] [expr {$ch + 28}]] X Y
    toplevel $t -background #3465a4
    wm overrideredirect $t 1   ;# frames must bypass our own redirect
    # The titlebar is a treectrl (a one-item, one-column one): its text
    # element with -squeeze x ellipsizes a title that does not fit. The
    # class bindings are stripped — this is a dumb label with our drag
    # binds, not a tree.
    treectrl $t.title -showheader no -showroot no -showbuttons no \
        -showlines no -borderwidth 0 -highlightthickness 0 \
        -background #3465a4 -itemheight 22
    bindtags $t.title [list $t.title all]
    $t.title column create -squeeze yes -tags C0
    $t.title configure -treecolumn C0
    $t.title element create eTxt text -fill white -lines 1
    $t.title style create sTitle
    $t.title style elements sTitle eTxt
    $t.title style layout sTitle eTxt -expand ns -padx 4 -squeeze x
    set item [$t.title item create]   ;# always item 1 in a fresh widget
    $t.title item style set $item C0 sTitle
    $t.title item element configure $item C0 eTxt \
        -text "клиент 0x[format %x $w]"
    $t.title item lastchild root $item
    place $t.title -x 2 -y 2 -width [expr {$cw - 20}] -height 22
    label $t.close -text ✕ -background #3465a4 -foreground white
    place $t.close -x [expr {2 + $cw - 20}] -y 2 -width 20 -height 22
    bind $t.close <ButtonRelease-1> [list close-client $w]
    frame $t.slot -width $cw -height $ch -background #202020
    place $t.slot -x 2 -y 26
    bind $t.title <ButtonPress-1> [list drag-start $t $w %X %Y]
    bind $t.title <B1-Motion>     [list drag-move  $t $w %X %Y]
    wm geometry $t [expr {$cw + 4}]x[expr {$ch + 28}]+$X+$Y
    update idletasks
    # Cross-connection ordering: a roundtrip on Tk's connection guarantees
    # the slot window exists server-side before the raw connection uses it.
    winfo pointerxy $t
    set ::frameof($w) $t
    puts "WM: frame $t for 0x[format %x $w] at +$X+$Y"
    return [winfo id $t.slot]
}

# The decoration window itself: {X-window-id x y width height}, or an
# empty list when there is none. The substrate addresses a copy of the
# synthetic ConfigureNotify here — see send-synthetic-configure.
proc policy-frame-geometry {w} {
    if {![info exists ::frameof($w)]} { return {} }
    set t $::frameof($w)
    list [winfo id $t] [winfo rootx $t] [winfo rooty $t] \
        [winfo width $t] [winfo height $t]
}

proc policy-detach {w} {
    if {![info exists ::frameof($w)]} return
    destroy $::frameof($w)
    unset ::frameof($w)
    unset -nocomplain ::leaderof($w)
    set ::focus_hist [lsearch -exact -all -inline -not $::focus_hist $w]
}

# Root coordinates of the CLIENT area — asked of Tk directly, since the
# slot IS the client's parent. (It used to parse "wm geometry" with a
# regexp and add the 2/26 offsets by hand: when the pattern failed to
# match, the caller's catch swallowed the error and the client silently
# never got its synthetic ConfigureNotify — the very event whose absence
# leaves an app with a false idea of where it is.)
proc policy-origin {w} {
    set t $::frameof($w)
    list [winfo rootx $t.slot] [winfo rooty $t.slot]
}

# The decoration follows the client's new size (position stays put).
proc policy-resize {w cw ch} {
    set t $::frameof($w)
    place configure $t.title -width [expr {$cw - 20}]
    place configure $t.close -x [expr {2 + $cw - 20}]
    $t.slot configure -width $cw -height $ch
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> X Y
    wm geometry $t [expr {$cw + 4}]x[expr {$ch + 28}]+$X+$Y
    update idletasks
}

# The client named (or renamed) itself: put the title on the titlebar.
# The treectrl item is always 1 — a fresh widget per frame, the single
# item created right after it.
proc policy-title {w title} {
    if {![info exists ::frameof($w)]} return
    if {$title eq ""} { set title "клиент 0x[format %x $w]" }
    set t $::frameof($w)
    $t.title item element configure 1 C0 eTxt -text $title
}

# Focus highlight: active frame blue, inactive grey. Every honest focus
# change lands here (server-confirmed focus-to, and focus moved behind
# our back) — which makes it the one place to keep the focus history.
proc policy-paint-focus {w} {
    set ::focus_hist [linsert \
        [lsearch -exact -all -inline -not $::focus_hist $w] 0 $w]
    foreach {ww tt} [array get ::frameof] {
        set bg [expr {$ww == $w ? "#3465a4" : "#888a85"}]
        $tt configure -background $bg
        $tt.title configure -background $bg
        $tt.close configure -background $bg
    }
}

# Raise the whole transient group of w: the leader first, its transients
# above it, and the member the user touched on top of its siblings.
# fvwm ships this glue as RaiseTransient + StackTransientParent, both on
# by default in its builtin ConfigFvwmDefaults: raising ANY member
# raises the group, and transients always end up above their leader
# (stack.c re-inserts the leader below its transients). One level deep,
# like fvwm's own redirect recursion. Lowering is not glued for a
# simpler reason: we have no lower gesture at all yet.
proc raise-group {w} {
    set leader $w
    if {[info exists ::leaderof($w)] && $::leaderof($w) != 0
            && [info exists ::frameof($::leaderof($w))]} {
        set leader $::leaderof($w)
    }
    raise $::frameof($leader)
    foreach {c l} [array get ::leaderof] {
        if {$l == $leader && $c != $w && [info exists ::frameof($c)]} {
            raise $::frameof($c)
        }
    }
    if {$w != $leader} { raise $::frameof($w) }
}

# Click-to-focus: a click inside a client's body raises and focuses it.
# focus-to is called UNCONDITIONALLY — the old "skip if ::focused is
# already w" guard turned a single refused XSetInputFocus into a
# permanent wedge (clicks stopped repairing the focus, the keyboard kept
# going to the previous window). One roundtrip per click is the price of
# a click path that always heals.
proc policy-client-click {w} {
    raise-group $w
    focus-to $w
}

# A newly managed window is raised with its group — a fresh dialog pulls
# its leader up right under itself, fvwm-style — and gets the focus.
proc policy-managed {w} {
    raise-group $w
    focus-to $w
}

# Refocus pick after w's unmanage (the smsrc observation: an unpatched
# app never refocuses its main window when its dialog closes — that is
# the WM's job). In order:
#  - the closing window's WM_TRANSIENT_FOR leader: a dialog gives focus
#    back to the window it was a dialog FOR, no matter what the user
#    glanced at in between;
#  - the most recently focused window still alive (focus history);
#  - any managed window at all.
proc policy-pick-refocus {w} {
    if {[info exists ::leaderof($w)]} {
        set leader $::leaderof($w)
        if {$leader != 0 && $leader != $w && [info exists ::frameof($leader)]} {
            return $leader
        }
    }
    foreach cand $::focus_hist {
        if {$cand != $w && [info exists ::frameof($cand)]} { return $cand }
    }
    foreach cand [array names ::frameof] {
        if {$cand != $w} { return $cand }
    }
    return 0
}

# Move policy is plain Tk: drag the title bar, the client rides along.
# A title click also raises and focuses.
proc drag-start {t w X Y} {
    raise-group $w
    focus-to $w
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> wx wy
    set ::drag($t) [list $X $Y $wx $wy]
}
proc drag-move {t w X Y} {
    lassign $::drag($t) x0 y0 wx wy
    wm geometry $t +[expr {$wx + $X - $x0}]+[expr {$wy + $Y - $y0}]
    send-synthetic-configure $w
}
