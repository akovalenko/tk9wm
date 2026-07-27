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
# Side and bottom border width. 6px is a resize GRIP, not just a line:
# the old 2px border left nothing to grab. The top strip above the
# titlebar stays 2px — the title drag lives there, top resize does not.
set border 6

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

# The biggest client area a frame on this screen can hold — the
# substrate shrinks an oversized newcomer to this (never below the
# client's declared minimum) so no edge starts out unreachable.
proc policy-max-client-size {} {
    lassign [screen-size] sw sh
    set B $::border
    list [expr {$sw - 2*$B}] [expr {$sh - 26 - $B}]
}

# Build a decoration for client w (client area cw x ch): blue titlebar
# with a ✕, dark slot below; placement per place-frame above. Returns the
# slot's X window id; the Tk roundtrip before the return guarantees the
# slot exists server-side before the raw connection reparents into it.
proc policy-attach {w cw ch} {
    set t .f[incr ::fid]
    set B $::border
    # WM_TRANSIENT_FOR is read ONCE, now: the refocus pick needs the
    # dialog's leader at a moment when the dialog may already be a dead
    # window that cannot be asked anything.
    set ::leaderof($w) [transient-for $w]
    lassign [place-frame $w [expr {$cw + 2*$B}] [expr {$ch + 26 + $B}]] X Y
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
    place $t.title -x $B -y 2 -width [expr {$cw - 20}] -height 22
    label $t.close -text ✕ -background #3465a4 -foreground white
    place $t.close -x [expr {$B + $cw - 20}] -y 2 -width 20 -height 22
    bind $t.close <ButtonRelease-1> [list close-client $w]
    frame $t.slot -width $cw -height $ch -background #202020
    place $t.slot -x $B -y 26
    bind $t.title <ButtonPress-1> [list drag-start $t $w %X %Y]
    bind $t.title <B1-Motion>     [list drag-move  $t $w %X %Y]
    # Resize by the border: the border strips are the bare toplevel, and a
    # bind on a toplevel fires for its children too — so positions are
    # computed from ROOT coords (%x/%y would be child-relative there) and
    # rz-edge itself decides "not a border" for points inside children.
    # That also un-sticks the resize cursor when the pointer crosses onto
    # the title; crossing into the CLIENT (an X window Tk never hears
    # Motion from) is caught by <Leave> — X sends LeaveNotify with detail
    # Inferior when the pointer dives into a child.
    bind $t <Motion>          [list rz-hover $t %X %Y]
    bind $t <Leave>           [list rz-leave $t]
    bind $t <ButtonPress-1>   [list rz-start $t $w %X %Y]
    bind $t <B1-Motion>       [list rz-move  $t $w %X %Y]
    bind $t <ButtonRelease-1> [list press-end $t]
    wm geometry $t [expr {$cw + 2*$B}]x[expr {$ch + 26 + $B}]+$X+$Y
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
    set B $::border
    place configure $t.title -width [expr {$cw - 20}]
    place configure $t.close -x [expr {$B + $cw - 20}]
    $t.slot configure -width $cw -height $ch
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> X Y
    wm geometry $t [expr {$cw + 2*$B}]x[expr {$ch + 26 + $B}]+$X+$Y
    update idletasks
}

# ---- resize by the border / corner ----
# Which resize grip is under frame-relative (x, y)? The side strips are
# $::border wide, the bottom strip $::border tall; the 24px ends of the
# bottom-left and bottom-right strips act as diagonal corners. The 2px
# top strip resizes nothing (the title drag lives right under it).
proc rz-edge {t x y} {
    set W [winfo width $t]; set H [winfo height $t]
    set B $::border; set CZ 24
    if {$x >= $W - $B || $x < $B || $y >= $H - $B} {
        if {$y >= $H - $CZ && $x >= $W - $CZ} { return se }
        if {$y >= $H - $CZ && $x < $CZ}       { return sw }
        if {$y >= $H - $B} { return s }
        if {$x < $B}       { return w }
        return e
    }
    return ""
}
proc rz-hover {t X Y} {
    array set cur {e right_side w left_side s bottom_side
        se bottom_right_corner sw bottom_left_corner}
    set e [rz-edge $t [expr {$X - [winfo rootx $t]}] \
                      [expr {$Y - [winfo rooty $t]}]]
    $t configure -cursor [expr {$e eq "" ? "" : $cur($e)}]
}
proc rz-leave {t} {
    if {![info exists ::rz]} { $t configure -cursor "" }
}
proc rz-start {t w X Y} {
    set e [rz-edge $t [expr {$X - [winfo rootx $t]}] \
                      [expr {$Y - [winfo rooty $t]}]]
    if {$e eq ""} return
    raise-group $w
    focus-to $w
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fx fy
    set ::rz [list $e $X $Y [winfo width $t.slot] [winfo height $t.slot] $fx $fy]
}
proc rz-move {t w X Y} {
    if {![info exists ::rz]} return
    lassign $::rz e x0 y0 cw0 ch0 fx fy
    set dx [expr {$X - $x0}]; set dy [expr {$Y - $y0}]
    set cw $cw0; set ch $ch0
    switch -- $e {
        e  { incr cw $dx }
        s  { incr ch $dy }
        se { incr cw $dx; incr ch $dy }
        w  { incr cw [expr {-$dx}] }
        sw { incr cw [expr {-$dx}]; incr ch $dy }
    }
    # The client's declared minimum caps the shrink HERE, not only in
    # wm-resize-client: the left/top anchoring below moves the frame by
    # the size delta, and a size clamped later than the move would tear
    # the dragged edge off the pointer. 40x30 is our own floor — a frame
    # must stay big enough to grab.
    lassign [client-min-size $w] minw minh
    set cw [expr {max($cw, $minw, 40)}]; set ch [expr {max($ch, $minh, 30)}]
    if {$e in {w sw}} {
        # dragging the left edge: the frame moves so the right edge stays
        wm geometry $t +[expr {$fx + $cw0 - $cw}]+$fy
    }
    wm-resize-client $w $cw $ch
}
proc rz-end {} { unset -nocomplain ::rz }

# Button-1 released anywhere on the frame (the toplevel's bindtag makes
# this fire for its children too): close BOTH the resize and the title
# drag. The drag state used to live forever — a later button-down that
# never visited drag-start (pressed on the root, dragged across a title)
# picked the window up with stale coordinates and yanked it. Then re-run
# the hover logic: the pointer may well be resting on the title now, and
# the resize cursor must not outlive the resize.
proc press-end {t} {
    rz-end
    unset -nocomplain ::drag($t)
    catch { rz-hover $t {*}[winfo pointerxy $t] }
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
    # No state — no drag: the press never landed on this title (a drag
    # that STARTED on the root background is a noop, not a pickup).
    if {![info exists ::drag($t)]} return
    lassign $::drag($t) x0 y0 wx wy
    wm geometry $t +[expr {$wx + $X - $x0}]+[expr {$wy + $Y - $y0}]
    send-synthetic-configure $w
}
