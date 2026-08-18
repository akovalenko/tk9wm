# ---- popup menus: the shared shell ----
# One pattern for both menus: an override-redirect toplevel (our own
# redirect leaves those alone) holding a treectrl, driven
# keyboard-modally through the substrate's grab-keys-to router — the
# Tk focus path cannot serve an override-redirect window (see
# grab-keys-to) — while the pointer stays free: a click on an item
# picks it, a click anywhere else does its normal job and closes the
# popup on the way (the popups-close calls in the click paths).
# THE MOUSE IS WELCOME AND SAYS SO. These menus are keyboard-first
# and always took a click as well, with nothing on the screen to admit
# it: the pointer moved over a row and the row said nothing back (the
# owner, 2026-08-02). The obvious cure is the wrong one — moving the
# SELECTION under the pointer is exactly the mouse and the keyboard
# fighting over one piece of state, which he named as the thing he
# hates, and it loses the keyboard's place the moment a sleeve brushes
# the mouse.
#
# So hover is its OWN mark, on its own axis: the selection band stays
# where the keyboard put it, and the row under the pointer is
# UNDERLINED. Two indications that cannot contradict each other,
# because they are not answering the same question — one says "this is
# where you are", the other "this is what you would get". They land on
# the same row often enough, and that reads as agreement rather than
# as a conflict resolved.
#
# An item STATE and not a re-configure, which is what makes it cost
# nothing: treectrl keys the font off the state, so hovering is one
# state flip and no element is rebuilt.
unless-already {[dict exists $::font_kin HoverFont]} {
    wm-font HoverFont -from TitleFont -underline 1
}
proc popup-hover-font {} { list HoverFont hover TitleFont {} }

# ---- a popup that ANSWERS ----
# The desk already waits on the world outside without standing still —
# a process, a round trip to a daemon — by running the errand in a
# coroutine over the future substrate (wm-errand, fut.tcl vendored).
# Waiting on the PERSON in front of the desk is the same shape, and it
# used to be written inside out: the menu did the deed itself, so what
# a pick MEANT lived in the list instead of in whoever opened it. A
# menu that answers lets its caller read top to bottom —
#
#   set w [winlist-choose $wins $where]
#
# — and that is what lets one list carry two meanings (raise this
# window / run another one) without the list knowing either of them.
#
# ARMED BY THE OPENER, and only by it: a popup nobody waits on keeps
# the old callback behaviour exactly, which is what makes the
# conversion piecemeal — winops and the confirmation are untouched
# until they have a reason of their own.
array set popup_fut {}   ;# popup window -> the future its opener parks on

# Arm and park in one word. The future is created before the event
# loop can deliver anything (building and showing a popup dispatches no
# user event — popup-show's update idletasks drains idle work only), so
# there is no gap in which an answer could be lost.
proc popup-await {m} {
    set ::popup_fut($m) [fut::new]
    return [fut::take $::popup_fut($m)]
}
# DISARMED BY WHOEVER SETTLES, not by the waiter waking up. The slot
# means «this menu owes somebody an answer», and it stops being true
# the moment the answer is given — a waiter resumes through the event
# loop (the substrate trampolines every wakeup), so clearing it on the
# far side would leave the slot standing over the whole gap between the
# menu going and the caller noticing. That gap is normal, but a slot
# that survives it is not, and it is what the invariant below reads.
# Taking the token out first also makes the second settler on the same
# path (popup-answer closes, and closing hands out an empty answer) find
# nothing rather than talk about a wait that is already over.
proc popup-disarm {m} {
    if {![info exists ::popup_fut($m)]} { return "" }
    set f $::popup_fut($m)
    unset ::popup_fut($m)
    return $f
}
# The answer: settle, then close.
proc popup-answer {m value} {
    set f [popup-disarm $m]
    if {$f ne ""} { fut::fulfill $f $value }
    popups-close
}
# Two ways of NOT getting an answer, and they are different facts.
#
# Dismissed — Escape, a click on a client, another menu over this one —
# is the person doing something else, which is an answer: the empty
# one. Quiet, and the caller quietly does nothing.
#
# YANKED — a reload replaying the layers, a keyboard mode taking the
# router out from under the menu — is nobody answering and nobody going
# to: the waiter is woken with FUT CANCELLED so its failure lands in
# the log under ITS name rather than looking like a decision the person
# made. Collapsing the two into an empty string would make the caller
# who forgets to check quietly do the wrong thing.
proc popup-dismissed {m} {
    set f [popup-disarm $m]
    if {$f eq ""} return
    puts "WM: popup $m: dismissed, nothing picked"
    fut::fulfill $f {}
}
proc popup-yank {why} {
    foreach m [array names ::popup_fut] {
        puts "WM: popup $m: $why — the wait is cancelled"
        fut::cancel [popup-disarm $m] $why
    }
    popups-close
}
# The asks are DELIBERATELY not in popup-yank: it fires on every
# hand-over of the key router — a menu opening, a menu closing — and
# an ask is not keyboard-modal in this process at all, it is a client
# of the ui host, standing while the person thinks. Killing it on
# «the keyboard went to another mode» killed it every time a menu was
# so much as glanced at over a standing question (the owner's report,
# 2026-08-05: a chord after an ask cancelled the ask; the second Ask
# of a script died the same way). What DOES end an ask early: the
# reload sweeping the config's world (ask-yank, below), and a newer
# ask displacing it (in Ask itself — one box, one question).
proc ask-yank {why} {
    foreach id [array names ::ask_fut] {
        puts "WM: ask $id: $why — the wait is cancelled"
        set f $::ask_fut($id)
        unset ::ask_fut($id)
        fut::cancel $f $why
        catch {send -async -- tk9wm-ui [list ui-ask-drop $id]}
    }
}
proc popup-shell {m ih pick} {
    popups-close
    toplevel $m -background $::OUTLINE
    wm overrideredirect $m 1
    treectrl $m.t -showheader no -showroot no -showbuttons no \
        -showlines no -borderwidth 0 -highlightthickness 0 \
        -background [themed raised] -itemheight $ih
    bindtags $m.t [list $m.t all]
    $m.t state define hover
    $m.t element create eSel rect -fill [list [themed select] selected {} {}]
    $m.t element create eTxt text -fill [themed ink] -lines 1 \
        -font [popup-hover-font]
    bind $m.t <Motion> [list popup-hover $m.t %x %y]
    bind $m.t <Leave>  [list popup-hover $m.t -1 -1]
    # PICK is what a row-and-a-point means for this menu, and the shell
    # holds it because there are two ways in: the plain click, and the
    # release that ends a drag begun outside this window
    # (popup-drag-release). Bound in one place, they cannot come apart.
    # The modifier state rides along because a shifted pick is a
    # different reading of the same row (the menu grammar's shift-*
    # words); picks that have no other reading take it and ignore it.
    set ::popup_pick($m) $pick
    bind $m.t <ButtonPress-1> [list $pick %x %y %s]
    # The wheel scrolls the VIEW and only the view — the selection band
    # is the keyboard's axis and stays where the keyboard put it (the
    # same two-axes rule as hover). Bound here for every popup: on a
    # list that fits whole the scroll is a no-op, and the class binding
    # that would normally do this was stripped with the bindtags above.
    # Button-4/5 beside <MouseWheel> as the configurator carries them —
    # whichever spelling this Tk delivers, the wheel works.
    bind $m.t <MouseWheel> [list popup-wheel $m %D]
    bind $m.t <Button-4>   [list popup-wheel $m 120]
    bind $m.t <Button-5>   [list popup-wheel $m -120]
    return $m.t
}
# Which row the pointer is over, marked and unmarked. Off the widget
# (-1 -1 from <Leave>) marks nothing, so a menu the mouse has left
# carries no stale underline while the keyboard goes on working.
proc popup-hover {T x y} {
    set item ""
    if {$x >= 0} {
        set id [$T identify $x $y]
        if {[lindex $id 0] eq "item"} { set item [lindex $id 1] }
    }
    if {[info exists ::popup_hovered($T)] && $::popup_hovered($T) eq $item} return
    foreach it [$T item children root] {
        catch {$T item state set $it {!hover}}
    }
    if {$item ne ""} { catch {$T item state set $item {hover}} }
    set ::popup_hovered($T) $item
}
# ---- a list taller than the glass scrolls ----
# The height a popup MAY take, asked by its builder BEFORE placement —
# before, because a bottom-anchored list (a winlist hanging off a
# panel button) computes its Y from H, so a clamp inside popup-show
# would come too late. The measure is the WORKAREA of the anchor's
# monitor, not the monitor itself: an overgrown list has to stop
# somewhere, and stopping short of the panel strips reads better than
# lying over them.
#
# A list that fits is untouched — same height, same look, not a pixel
# moved. One that does not gets a scroll: two arrow bands over and
# under the treectrl (the mouse's half — a click walks one row, held
# it repeats, the wheel drives the list directly), and the band that
# cannot go further is dimmed rather than hidden — a vanishing arrow
# would shift the rows under a pointer mid-aim, a dimmed one moves
# nothing. The arrows are DRAWN (canvas triangles), not typed: the
# winops bullet was chosen because it renders everywhere, and a
# polygon renders more everywhere still.
proc popup-fit {m n ih X Y} {
    set H [expr {$n * $ih + 2}]
    lassign [workarea-at [list $X $Y 1 1]] - - - wah
    if {$H <= $wah} { return $H }
    set band [expr {max(10, $ih * 3 / 5)}]
    set vis [expr {max(1, ($wah - 2 - 2*$band) / $ih)}]
    set ::popup_scroll($m) [list $n $ih $vis $band]
    foreach {c d} [list $m.up -1 $m.down 1] {
        canvas $c -highlightthickness 0 -borderwidth 0 \
            -background [themed raised]
        bind $c <Configure>       [list popup-arrow-draw $c $d %w %h]
        bind $c <ButtonPress-1>   [list popup-arrow-press $m $d]
        bind $c <ButtonRelease-1> [list popup-arrow-release $m]
    }
    $m.t configure -yscrollcommand [list popup-view-sync $m]
    puts "WM: popup $m: $n rows, $vis shown"
    expr {$vis * $ih + 2*$band + 2}
}
# The triangle, redrawn at the size the band actually got; the fill
# survives the redraw so a band dimmed before its <Configure> stays
# dimmed after it.
proc popup-arrow-draw {c d w h} {
    set fill [themed ink]
    if {[llength [$c find withtag tri]]} { set fill [$c itemcget tri -fill] }
    $c delete tri
    set p 3
    set cx [expr {$w / 2}]
    set s [expr {max(4, $h - 2*$p)}]
    if {$d < 0} {
        set pts [list $cx $p [expr {$cx - $s}] [expr {$h - $p}] \
                     [expr {$cx + $s}] [expr {$h - $p}]]
    } else {
        set pts [list $cx [expr {$h - $p}] [expr {$cx - $s}] $p \
                     [expr {$cx + $s}] $p]
    }
    $c create polygon {*}$pts -fill $fill -outline "" -tags tri
}
# One step of the view, answering whether it MOVED — the press below
# reads the answer to know a dead-end arrow from a live one, and the
# repeat reads it to stop at the wall instead of ticking against it.
proc popup-scroll {m d} {
    set before [$m.t yview]
    $m.t yview scroll $d units
    expr {[$m.t yview] ne $before}
}
# Press-and-hold repeats, the scrollbar's own feel: one row at once,
# then after a beat one row per tick until the button goes up, the
# wall arrives, or the popup closes (popups-close cancels).
proc popup-arrow-press {m d} {
    popup-arrow-release $m
    if {![popup-scroll $m $d]} return
    set ::popup_repeat($m) [after 300 [list popup-arrow-repeat $m $d]]
}
proc popup-arrow-repeat {m d} {
    unset -nocomplain ::popup_repeat($m)
    if {![winfo exists $m] || ![popup-scroll $m $d]} return
    set ::popup_repeat($m) [after 60 [list popup-arrow-repeat $m $d]]
}
proc popup-arrow-release {m} {
    if {[info exists ::popup_repeat($m)]} {
        after cancel $::popup_repeat($m)
        unset ::popup_repeat($m)
    }
}
# The wheel, one row per notch. %D is accumulated to ±120 first: a
# hi-res touchpad delivers the notch in crumbs, and each crumb
# stepping a row would make the list bolt.
proc popup-wheel {m D} {
    incr ::popup_wheelacc($m) $D
    while {$::popup_wheelacc($m) >= 120} {
        incr ::popup_wheelacc($m) -120
        popup-scroll $m -1
    }
    while {$::popup_wheelacc($m) <= -120} {
        incr ::popup_wheelacc($m) 120
        popup-scroll $m 1
    }
}
# Every move of the view lands here (the treectrl's -yscrollcommand):
# repaint the arrows off the fractions, and re-ask what the standing
# pointer hovers — the rows just shifted under it, and a stale
# underline is exactly what the hover mark must never show.
proc popup-view-sync {m args} {
    if {![winfo exists $m.up]} return
    lassign [$m.t yview] first last
    $m.up   itemconfigure tri -fill [themed [expr {$first > 0 ? "ink" : "dim"}]]
    $m.down itemconfigure tri -fill [themed [expr {$last < 1 ? "ink" : "dim"}]]
    lassign [winfo pointerxy $m.t] px py
    popup-hover $m.t [expr {$px - [winfo rootx $m.t]}] \
        [expr {$py - [winfo rooty $m.t]}]
}
proc popup-show {m W H X Y} {
    # clamped into the monitor the ANCHOR POINT is on: a menu asked
    # for near the right edge of the left monitor slides left, it does
    # not walk over onto the neighbour. A CLIPPED list clamps into the
    # workarea instead — its height was measured against it (popup-fit),
    # and a scroll that stops at the panel's edge should stand there too.
    if {[info exists ::popup_scroll($m)]} {
        lassign [workarea-at [list $X $Y 1 1]] wax way waw wah
        set X [expr {max($wax, min($X, $wax + $waw - $W))}]
        set Y [expr {max($way, min($Y, $way + $wah - $H))}]
        lassign $::popup_scroll($m) - - - band
        place $m.up   -x 1 -y 1 -width [expr {$W - 2}] -height $band
        place $m.t    -x 1 -y [expr {1 + $band}] -width [expr {$W - 2}] \
            -height [expr {$H - 2 - 2*$band}]
        place $m.down -x 1 -y [expr {$H - 1 - $band}] \
            -width [expr {$W - 2}] -height $band
    } else {
        lassign [monitor-of-rect [list $X $Y 1 1]] mx my mw mh
        set X [expr {max($mx, min($X, $mx + $mw - $W))}]
        set Y [expr {max($my, min($Y, $my + $mh - $H))}]
        place $m.t -x 1 -y 1 -width [expr {$W - 2}] -height [expr {$H - 2}]
    }
    wm geometry $m ${W}x${H}+$X+$Y
    stack-layer $m $::LAYER_POPUP
    update idletasks
    # The clipped list opens SHOWING its selection — a cycle that walks
    # up at open wraps to the last row, and the last row must be on the
    # glass. Done here, after the geometry settled: a `see` against an
    # unplaced widget measures nothing.
    if {[info exists ::popup_scroll($m)]} {
        set sel [lindex [$m.t selection get] 0]
        if {$sel ne ""} { $m.t see $sel }
        popup-view-sync $m
    }
    # Posted with the button still down — the drag that follows is the
    # same gesture and has to reach this menu (popup-drag-* below).
    # Nothing else arms it: a menu opened by a key, or by a press whose
    # path does not hand its events over, simply never sees a drag.
    if {[gesture-held]} { set ::popup_drag [list $m 0] }
    return [list $X $Y]
}

# ---- the point a gesture happened at ----
# A window command does not take a place to happen at — the seam hands
# it a window and nothing else, and that is what lets a config put any
# command on any part. But a command that puts a MENU on the screen
# does want one: a menu called up by the hand belongs under the hand,
# while the same menu called up by <Alt>space has no hand to belong to
# and belongs to the window (the owner, 2026-08-03).
#
# So the point rides BESIDE the call instead of in it: a mouse path
# wraps its dispatch in `gesture-at`, and whatever runs inside can ask
# where the hand was and whether it is still holding the button down.
# The command vocabulary keeps its single argument, and everything that
# does not care never mentions any of this.
keep gesture {}   ;# {X Y button} while a mouse gesture's command runs
proc gesture-at {X Y n script} {
    set save $::gesture
    set ::gesture [list $X $Y $n]
    try {
        uplevel 1 $script
    } finally {
        set ::gesture $save
    }
}
# Where the hand is, in root coordinates — {} when the command came
# from a key; and which button is HELD, 0 for none. A titlebar button
# fires on its release, so by then nothing is down and no drag can
# follow; the strip's own gestures fire on the press, and one can.
proc gesture-point {} { lrange $::gesture 0 1 }
proc gesture-held {} {
    expr {[llength $::gesture] ? [lindex $::gesture 2] : 0}
}

# ---- a menu posted with the button still down ----
# Press, drag onto the entry, release on it — how fvwm and twm were
# driven, and the gesture every toolkit's menus kept. Its events do not
# arrive at the menu on their own: for as long as any button is down Tk
# sends every motion and the release to the widget the press happened
# on (its own button grab, over the X implicit one underneath), and
# that widget is the TITLEBAR, not the popup now standing over it.
# Measured rather than assumed — the popup gets one <Enter>, and only
# after the release.
#
# So the presser hands the events over: root coordinates in, and the
# menu does with them what it would have done with its own <Motion> and
# its own click. Two rules make the gesture read right:
#
#   - the release PICKS only over the menu. Press-and-release in place
#     is the other way to open one — the click that leaves it standing
#     — and its release lands where the press did, off the menu;
#   - having been inside the menu and released outside it is "never
#     mind", and dismisses. A menu the pointer never entered stays.
keep popup_drag {}   ;# {popup entered?} while the posting button is held
proc popup-drag-point {m X Y} {
    set T $m.t
    set x [expr {$X - [winfo rootx $T]}]
    set y [expr {$Y - [winfo rooty $T]}]
    list [expr {$x >= 0 && $y >= 0
                && $x < [winfo width $T] && $y < [winfo height $T]}] $x $y
}
proc popup-drag-motion {X Y} {
    if {![llength $::popup_drag]} return
    lassign $::popup_drag m -
    if {![winfo exists $m]} { set ::popup_drag {}; return }
    lassign [popup-drag-point $m $X $Y] in x y
    if {$in} {
        set ::popup_drag [list $m 1]
        popup-hover $m.t $x $y
    } else {
        popup-hover $m.t -1 -1
    }
}
proc popup-drag-release {X Y {s 0}} {
    if {![llength $::popup_drag]} return
    lassign $::popup_drag m entered
    set ::popup_drag {}
    if {![winfo exists $m]} return
    lassign [popup-drag-point $m $X $Y] in x y
    if {$in} {
        {*}$::popup_pick($m) $x $y $s
    } elseif {[popup-drag-inside $m $X $Y]} {
        # over the shell's own furniture — a scroll arrow: not a row,
        # so no pick, and not "never mind" either — the menu stands
    } elseif {$entered} {
        popups-close
    }
}
# Inside the popup's TOPLEVEL, arrows and border included — the coarse
# question the release above asks when the fine one (over a row) says
# no.
proc popup-drag-inside {m X Y} {
    set x [expr {$X - [winfo rootx $m]}]
    set y [expr {$Y - [winfo rooty $m]}]
    expr {$x >= 0 && $y >= 0
          && $x < [winfo width $m] && $y < [winfo height $m]}
}
# ---- the WM's own windows -------------------------------------------
#
# A window this window manager puts up FOR ITSELF, wearing the same
# decoration every client wears — same border and grips, same titlebar
# font and colors, restyled by the same config knobs.
#
# It has to be override-redirect, and that is not a shortcut. Our own
# windows are the one kind our redirect cannot catch: SubstructureRedirect
# turns a child's map into a MapRequest for whoever selected it, EXCEPT
# when the window is override-redirect or the client asking is the one
# that selected the redirect — and we are always that client. Measured
# rather than assumed (tools/probe-selftoplevel.tcl): a plain toplevel
# from this process maps straight to the root, bare, and no MapRequest
# ever arrives. We could reparent our own window into a frame by hand,
# but then the WM's dialog would be one of the WM's clients — listed in
# the window list, published in _NET_CLIENT_LIST, and swept up by
# `Apply-To-Matching always Minimize` along with everything else.
#
# So instead the decoration is drawn around an override-redirect
# toplevel, which is exactly what the decoration always was: deco-draw,
# frame-layout and the titlebar drag are client-free already, and the
# slot they wrap is an ordinary Tk frame — for a client it is what the
# client's window gets reparented into, and here it is simply where our
# own widgets go. Returns that frame; pack into it.
#
# Keyboard comes from grab-keys-to, the same router the menus use, and
# that fixes what this is FOR. A grab is the right answer for something
# modal — a menu, the Quit confirmation: answer it or dismiss it, and
# nothing else happens meanwhile. It is the wrong answer for a window
# meant to sit on the desk while you work, because such a window wants
# ORDINARY focus: click to take it, alt-tab to reach it, give it up
# when something else is picked. An override-redirect window is
# invisible to all of that.
#
# The way out is not to imitate any of it here. A GUI that wants to be
# a window on equal terms should be a CLIENT, and the window manager
# can host one without leaving the process: a Tcl thread with its own
# Tk opens its own X connection, which makes it a different client to
# the server — so the redirect catches its windows and we frame them
# like anybody else's, focus, alt-tab, minimize and all (owner's idea,
# 2026-07-29; measured in tools/probe-threadgui.tcl, which comes up
# decorated). It buys something else too: a form that blocks can no
# longer freeze the desk, since the WM's event loop is not the one
# running it.
#
# So the line is: modal and short-lived, and it must NOT be a client —
# wm-window. Complex, long-lived, wants to behave like a window — a
# thread and a real connection. Which also settles the two gaps here:
# rz-* (resize by the border) and the maximize pair are still written
# around a client id, and nothing that would want them belongs on this
# side of the line.
proc wm-window {t title cw ch closescript} {
    lassign [list [look default border] [look default decotop] \
        [look default titleh]] B top titleh
    toplevel $t -background [themed focus]
    wm overrideredirect $t 1
    set ::closeof($t) $closescript
    canvas $t.deco -highlightthickness 0 -borderwidth 0 -background [themed focus]
    place $t.deco -x 0 -y 0 -relwidth 1 -relheight 1
    bind $t.deco <Configure> {deco-draw %W %w %h}
    # The same strip every client wears, from the same builder, with a
    # button set of its own: no menu and no maximize on ours (there is
    # no client to command and nothing sensible to maximize), and it is
    # dragged by its titlebar like anything else on this desk.
    titlebar-build $t 0 {close} $title
    frame $t.slot -width $cw -height $ch -background [themed slot]
    # on the monitor under the hand: the WM asks its questions where
    # the user is looking, which the pointer approximates better than
    # any fixed corner of a multihead desk
    lassign [pointer-monitor] mx my sw sh
    set W [expr {$cw + 2*$B}]
    set H [expr {$ch + $top + $B}]
    # Centred, but never off the left or top edge: a question long
    # enough to outgrow the screen would otherwise start off-screen,
    # taking its buttons with it.
    frame-layout $t $cw $ch \
        [expr {max($mx, $mx + ($sw - $W) / 2)}] \
        [expr {max($my, $my + ($sh - $H) / 3)}]
    stack-layer $t $::LAYER_WMWIN
    update idletasks
    # Geometry in the log, because a window of ours is the one thing on
    # this desk nothing else can be asked about: it is override-redirect
    # and carries no client, so xwininfo and every other outside tool
    # sees furniture rather than a window. A test that wants to click
    # its close button has no other way to find it.
    puts "WM: wm-window «$title» [wm geometry $t]"
    return $t.slot
}
# The first thing built on it: a confirmation for a command that cannot
# be taken back. Keyboard-first, because the command it guards is bound
# to a chord and reaching for the mouse to answer a question the
# keyboard asked is a poor joke: Left/Right/Tab move, y and n answer
# outright, Return takes the highlighted one and Escape leaves. The
# safe answer starts selected, so a stray Return costs nothing.
proc confirm {title question yeslabel script} {
    popups-close
    set pad 14
    set lh [font metrics TitleFont -linespace]
    set bh [expr {$lh + 10}]
    set bw [expr {max([font measure TitleFont "  Cancel  "],
                      [font measure TitleFont "  $yeslabel  "]) + 8}]
    set cw [expr {max([font measure TitleFont $question] + 2*$pad,
                      2*$bw + 3*$pad)}]
    set ch [expr {$pad + $lh + $pad + $bh + $pad}]
    set slot [wm-window .confirm $title $cw $ch {}]
    set ::confirm_script $script
    set ::confirm_choice 0        ;# the safe one
    label $slot.q -text $question -font TitleFont \
        -background [themed slot] -foreground [contrast-fg [themed slot]]
    place $slot.q -x $pad -y $pad
    set by [expr {$ch - $pad - $bh}]
    foreach {which text x} [list \
            no  Cancel    [expr {$cw - 2*$pad - 2*$bw}] \
            yes $yeslabel [expr {$cw - $pad - $bw}]] {
        label $slot.$which -text $text -font TitleFont
        place $slot.$which -x $x -y $by -width $bw -height $bh
        bind $slot.$which <ButtonPress-1> [list confirm-fire $which]
    }
    confirm-paint
    update idletasks
    if {![grab-keys-to confirm-key]} {
        puts "WM: confirm: keyboard not grabbed — mouse only"
    }
    puts "WM: confirm «$question»"
}
proc confirm-paint {} {
    foreach {which on} [list no [expr {!$::confirm_choice}] \
                             yes $::confirm_choice] {
        set bg [expr {$on ? [themed focus] : [themed ground]}]
        .confirm.slot.$which configure -background $bg \
            -foreground [contrast-fg $bg]
    }
}
proc confirm-key {kind name mods} {
    if {$kind eq "release" || $mods != 0} return
    switch -- $name {
        y - Y { confirm-fire yes }
        n - N - Escape { confirm-fire no }
        Left - Right - Tab - h - l {
            set ::confirm_choice [expr {!$::confirm_choice}]
            confirm-paint
        }
        Return - KP_Enter - space {
            confirm-fire [expr {$::confirm_choice ? "yes" : "no"}]
        }
    }
}
proc confirm-fire {which} {
    set script $::confirm_script
    set ::confirm_script {}
    popups-close
    if {$which ne "yes"} { puts "WM: confirm: no"; return }
    puts "WM: confirm: yes"
    uplevel #0 $script
}

proc wm-window-close {t} {
    set script {}
    if {[info exists ::closeof($t)]} { set script $::closeof($t) }
    unset -nocomplain ::closeof($t) ::btncols($t) ::drag($t) ::btn($t)
    grab-keys-to {}
    destroy $t
    if {$script ne ""} { uplevel #0 $script }
}

# Close whatever popup is open. Every click path calls this as "close
# if open"; the router is released only when a popup actually owns it —
# a bare grab-keys-to {} here would abort an unrelated key sequence.
# `except` is the popup the caller is BUSY WITH — and it exists because
# a click on the WM's own window is both "a click somewhere, close the
# popups" and "a click on a popup, keep it". Pressing the confirmation
# dialog's close BUTTON went through here and destroyed the dialog
# mid-press; the very next line of title-press then poked a widget that
# was gone, and the error went all the way out to a bgerror box
# (owner's report, 2026-07-29). Dismissed that way it also skipped its
# own close script — the × on a window of ours means what the window
# said it means, and popups-close is deliberately the path that means
# nothing.
proc popups-close {{except ""}} {
    foreach m {.winlist .winops .confirm .menu} {
        if {$m eq $except} continue
        if {[winfo exists $m]} {
            # Somebody may be parked on this menu's answer, and going
            # away IS an answer — the empty one. Settled BEFORE the
            # window goes, so a waiter never wakes into a half-torn-down
            # menu. (Already answered — popup-answer settles and then
            # calls us — makes this a no-op.)
            popup-dismissed $m
            grab-keys-to {}
            # A dismissed wm-window leaves no bookkeeping behind. Its
            # close SCRIPT is deliberately not run: dismissing IS the
            # cancel, and cancel does nothing by definition.
            popup-arrow-release $m   ;# a held repeat dies with its menu
            unset -nocomplain ::closeof($m) ::btncols($m) ::drag($m) \
                ::btn($m) ::popup_pick($m) ::popup_scroll($m) \
                ::popup_wheelacc($m)
            # ...and a hand-over armed for it dies with it: the button
            # may well still be down, and the release that ends the
            # gesture must not go looking for a menu that is gone.
            if {[lindex $::popup_drag 0] eq $m} { set ::popup_drag {} }
            destroy $m
        }
    }
    invariants-soon
}

# ---- the modal invariants ----
# A window manager's modal things — the keyboard move/resize, the
# popups, a confirmation — each own a grab, some decoration and some
# saved state, and each of them can be interrupted by something that
# knows nothing about it. What goes wrong is never the mode itself; it
# is the INTERLEAVING, and there are more pairs of those than anyone
# checks by hand (the owner's point, 2026-07-29, and he is right that
# ad-hoc checking loses here).
#
# So the WM checks itself instead, and says so in the log, where every
# regression can read it: one grep for INVARIANT turns every scenario
# the suite already runs into an interleaving test, including the
# scenarios nobody wrote for that purpose.
#
# The check is DEFERRED, because a teardown is several steps (release
# the router, drop the decoration, unset the state) and half of one is
# not a violation — only the state left when the event has been fully
# handled is.
#
# `after 0` and not `after idle`, which was the first version and was
# wrong in a way worth keeping written down: BUILDING a popup calls
# update idletasks (popup-show, to settle its geometry), which drains
# the idle queue — so the check ran in the middle of the very
# construction it was waiting for and complained about a popup that had
# not taken the router yet. A timer is not drained by update idletasks;
# it fires when the WM is back at its event loop, which is the moment
# the invariants are actually about.
keep invariants_due 0
proc invariants-soon {} {
    if {$::invariants_due} return
    set ::invariants_due 1
    after 0 invariants-check
}
proc invariants-check {} {
    set ::invariants_due 0
    foreach complaint [wm-invariants] {
        puts "WM: INVARIANT $complaint"
    }
}
# What must be true whenever nothing is mid-gesture. Returns the
# complaints, empty when all is well.
proc wm-invariants {} {
    set bad {}
    set modal [expr {$::keyrouter ne ""}]
    # A keyboard mode and its marks are one thing, alive or dead
    # together — and the mode is the router's holder while it lives.
    if {[llength $::kbmr]} {
        set w [lindex $::kbmr 1]
        if {![info exists ::frameof($w)]} {
            lappend bad "keyboard mode on 0x[format %x $w], which is not framed"
        }
        if {$::keyrouter ne "kbmr-key"} {
            lappend bad "keyboard mode is up but the router is «$::keyrouter»"
        }
    } else {
        if {[llength $::compass]} {
            lappend bad "a compass ([llength $::compass] cells) with no keyboard mode"
        }
        foreach {ww tt} [array get ::frameof] {
            if {[$tt cget -background] eq $::KBMR_BG} {
                lappend bad "0x[format %x $ww] wears the modal amber with no mode"
            }
        }
    }
    # A popup is keyboard-modal by construction: it took the router
    # when it opened, and closing is what gives it back.
    foreach m {.winlist .winops .confirm .menu} {
        if {[winfo exists $m] && !$modal} {
            lappend bad "$m is up with no router"
        }
    }
    # A hand-over is armed for a LIVE menu or not at all: the popup it
    # names went away without clearing it, and the release still to
    # come would look for rows in a destroyed window.
    if {[llength $::popup_drag] && ![winfo exists [lindex $::popup_drag 0]]} {
        lappend bad "a menu hand-over armed for [lindex $::popup_drag 0],\
                     which is gone"
    }
    # A WAIT OUTLIVING ITS MENU is the same class of bug one storey up:
    # not a mode left standing, but a coroutine left PARKED — holding
    # whatever it was in the middle of, answering nothing, invisible.
    # Every way out of a popup settles its future (popup-answer,
    # popup-dismissed, popup-yank); a slot still armed with the window
    # gone means one of them was missed.
    foreach m [array names ::popup_fut] {
        if {![winfo exists $m]} {
            lappend bad "somebody still waits on $m, which is gone"
        }
    }
    # An arrow repeat is an after-timer holding a popup's name: alive
    # only while its popup is (popups-close cancels; the tick itself
    # gives up on a gone window, but a timer still ARMED for one means
    # a teardown path missed the cancel).
    foreach m [array names ::popup_repeat] {
        if {![winfo exists $m]} {
            lappend bad "an arrow repeat armed for $m, which is gone"
        }
    }
    # ...and the grab is held for a router or for a chord in progress,
    # never for its own sake: a keyboard nobody is listening on is a
    # dead desk.
    if {$::kbd_grabbed && !$modal && $::keyseq eq ""} {
        lappend bad "the keyboard is grabbed with no router and no key sequence"
    }
    # The echo is the sequence's own face: it cannot outlive it. (Only
    # the `keys` face — a `flash` is a message ABOUT a sequence that
    # has ended, and standing there for its second is its whole job.)
    if {$::keyecho_kind in {keys help} && $::keyseq eq ""} {
        lappend bad "the key echo shows a sequence that is not running"
    }
    # The maximized mark is two arrays that live and die together:
    # ::maxsaved (the way back) and ::maxaxes (the axes held). One
    # without the other — or an empty axes list still on the books —
    # means some path forgot half of a teardown.
    foreach ww [array names ::maxsaved] {
        if {![info exists ::maxaxes($ww)] || ![llength $::maxaxes($ww)]} {
            lappend bad "0x[format %x $ww] keeps a way back with no held axes"
        }
    }
    foreach ww [array names ::maxaxes] {
        if {![info exists ::maxsaved($ww)]} {
            lappend bad "0x[format %x $ww] holds axes with no way back"
        }
    }
    return $bad
}
# The one alphabet that numbers popup rows: 1-9, then A-Z MINUS the
# vi and emacs motion letters J/K/N/P — a bare letter that is some
# row's hotkey beats navigation (the hotkey branch runs first), so a
# 19th row that swallowed J would turn «down» into a pick on exactly
# the lists crowded enough to need the walking (the owner,
# 2026-08-17). Positional: n keys for n rows, rows past the alphabet
# get none.
proc popup-autokeys {n} {
    set keys {}
    for {set i 1} {$i <= 9 && $i <= $n} {incr i} { lappend keys $i }
    for {set c 65} {$c <= 90 && [llength $keys] < $n} {incr c} {
        set ch [format %c $c]
        if {$ch ni {J K N P}} { lappend keys $ch }
    }
    while {[llength $keys] < $n} { lappend keys "" }
    return $keys
}
# Popup navigation keys (the owner's spec): arrows always; vi (k/j)
# and emacs (p/n) letters on a BARE press — a bare letter that is some
# item's hotkey never reaches here, the hotkey matched first, though
# the four letters themselves are safe (popup-autokeys never hands
# them out; only an EXPLICIT key can claim one); Ctrl+P /
# Ctrl+N run the menu unconditionally, hotkeys or not. The ends of the
# list too (the owner, 2026-08-10): Home and End as every list has
# them, Ctrl+A / Ctrl+E as emacs hands expect — unconditional, like
# their p/n kin — and PgUp/PgDn land on the same ends: these lists
# stand on the glass whole, so a page up is the top and a page down
# is the bottom. The KP_* spellings are the keypad with NumLock off;
# with it on the same keys arrive as digits and mean the hotkeys
# (router-key, the router's own lock exception). Returns -1/1 for a
# step, first/last for the ends, 0 = not a navigation key.
proc popup-nav {name mods} {
    if {$mods & 4} {
        switch -- $name {
            p { return -1 }    n { return 1 }
            a { return first } e { return last }
        }
        return 0
    }
    if {$mods != 0} { return 0 }
    switch -- $name {
        Up - k - p - KP_Up            { return -1 }
        Down - j - n - KP_Down        { return 1 }
        Home - Prior - KP_Home - KP_Prior { return first }
        End - Next - KP_End - KP_Next     { return last }
    }
    return 0
}
# A step WRAPS — walking off either end of a short list is the fastest
# way to the other — and an end is an address, not a walk: Home on the
# first row stays put instead of visiting the last.
proc popup-move {T n d} {
    set cur [lindex [$T selection get] 0]
    if {$cur eq ""} { set cur 1 }
    switch -- $d {
        first   { set i 1 }
        last    { set i $n }
        default { set i [expr {($cur - 1 + $d + $n) % $n + 1}] }
    }
    $T selection clear
    $T selection add $i
    # the keyboard's row is ALWAYS on the glass: a clipped list scrolls
    # under the selection (a no-op on one that fits whole)
    $T see $i
}
# The MOTION a key means, popup-wide: what popup-nav says, plus Tab —
# a step forward, backward under Shift — which the winlist has always
# treated as its own alt-tab step. Returns what popup-nav returns.
proc popup-motion-of {name mods} {
    if {$name eq "Tab"} { return [expr {$mods & 1 ? -1 : 1}] }
    popup-nav $name $mods
}
# ---- cycle mode, the popup layer's half ----
# A popup opened by a chord that MEANS A MOTION, with its (non-Shift)
# modifier set still physically held, may run as a cycle: the motion
# the key means runs at open, and releasing ANY element of the held
# set commits. This pair is the generalized alt-tab: arm answers
# {mask motion} read off the invoking chord ({0 0} = no cycle — the
# hand already let go, or the chord meant no motion, as <Super>grave
# would not), release runs the commit script once the hold is no
# longer whole. Shift is not holdable: it spells the motion's own
# direction (Shift+Tab), so it is stripped from the mask and left in
# the motion. Any popup's key router can ride these two; the winlist
# does.
proc popup-cycle-arm {} {
    set mask [expr {$::key_invoke_mods & ~1}]
    if {$mask == 0 || ![modifiers-all-held $mask]} { return {0 0} }
    set motion [popup-motion-of $::key_invoke_sym \
                    [expr {$::key_invoke_mods & ~$mask}]]
    if {$motion == 0} { return {0 0} }
    list $mask $motion
}
proc popup-cycle-release {mask commit} {
    if {$mask != 0 && ![modifiers-all-held $mask]} {
        uplevel #0 $commit
        return 1
    }
    return 0
}

# ---- the window list (alt-tab) ----
# Every managed window, most-recently-focused first (never-focused
# ones trail behind), centered on the screen; the initial selection
# sits on the SECOND entry — the first is the window the user is
# leaving — so a bare Enter (or a released Alt) toggles to the
# previous window. Entries are numbered with the shared popup
# alphabet (popup-autokeys: 1-9, A-Z minus j/k/n/p) and the number is
# the entry's hotkey — in cycle mode pressed WITH the held modifier
# (releasing it would commit), in the static menu bare, like any menu
# hotkey; either way it picks immediately.
#
# The fvwm alt-tab semantics come as a MODE the list enters when the
# invoking chord MEANT A MOTION and its (non-Shift) modifier set is
# still physically held at open (popup-cycle-arm; asked of the server
# via modifiers-all-held — a release that beat our grab is invisible
# to us, so the one-roundtrip check can only degrade to the static
# menu, never hang). The motion the key means runs at open — Tab's
# own +1 is the classic second row; bind <Super>p to the list and it
# opens walking UP, wrapped to the last row — and further motion keys
# run the selection with wraparound (Tab and Shift+Tab included);
# releasing ANY element of the held set commits. A quick full Alt+Tab
# press-release is then the classic toggle — commit lands on the
# previous window. Invoked with nothing held (the Super-sequence ends
# fully released), or by a chord that means no motion (<Super>grave,
# say), the list is a static menu. set-winlist-cycle off disables the
# mode entirely.
keep winlist_cycle_opt 1

# ---- config-facing icon resolution ----
# The `icon` value (a panel-button key, a wm-style icon key) is
# polymorphic: an existing Tk image name is taken as-is, whatever its
# size; something path-like (a /, a leading ~, a .png tail) is loaded
# lazily — any format Tk's photo reads, so pointing at an .svg by
# hand is the user's own choice; a bare name (firefox) is searched as
# NAME.png through the icon-path directories — png ONLY, deliberately:
# nanosvg renders poorly and the resolver never picks svg FOR the
# user. A loaded image bigger than SIZE is resampled down (nearest
# neighbor, alpha preserved — client-icon's trick with the same
# rgba-png), a smaller one stays smaller. A miss logs once and
# returns "" — the caller shows its no-icon look. Every resolution is
# cached per {spec size}: panel rebuilds reuse, nothing leaks.
# ...AND MORE OF hicolor THAN ONE SIZE OF IT. 48x48 alone missed
# whole applications: kitty ships 256x256 and scalable and nothing
# else, so a button for it had no face at all (the owner, 2026-08-02).
# The order is the preference — the wanted size first, then bigger
# ones (which resample down cleanly), and svg last of all, for which
# see icon-file-of.
keep icon_path [list ~/.local/share/icons/hicolor/48x48/apps \
    ~/.local/share/icons/hicolor/64x64/apps \
    ~/.local/share/icons/hicolor/128x128/apps \
    ~/.local/share/icons/hicolor/256x256/apps \
    ~/.local/share/icons/hicolor/scalable/apps \
    /usr/share/icons/hicolor/48x48/apps \
    /usr/share/icons/hicolor/64x64/apps \
    /usr/share/icons/hicolor/128x128/apps \
    /usr/share/icons/hicolor/256x256/apps \
    /usr/share/icons/hicolor/scalable/apps \
    /usr/share/pixmaps]
proc set-icon-path {dirs} {
    set ::icon_path $dirs
    # The cache needs no clearing: what a spec resolves to is part of
    # every entry, so a spec that now finds its png somewhere else —
    # or nowhere — is noticed by the next resolution and poured into
    # the image the strips are already holding (see resolve-icon).
    if {[llength [info commands panel-rebuild-soon]]} { panel-rebuild-soon }
}
# WHERE a spec's png lives, if anywhere — the search on its own, so
# the answer can be compared with what a cached icon was made from.
# SVG IS THE LAST RESORT, and that is a change of mind with its
# reason intact (the owner, 2026-08-02): nanosvg still renders less
# well than a real png, so every png anywhere on the path beats every
# svg — the extension is the OUTER loop. But a poor icon is better
# than none, which is what the applications that ship scalable-only
# were getting.
proc icon-file-of {spec} {
    # Tcl 9 dropped implicit ~ expansion — expand at use time, so a
    # config-supplied ~ path works too
    if {[string match */* $spec] || [string match ~* $spec]
            || [string match -nocase *.png $spec]
            || [string match -nocase *.svg $spec]} {
        return [file tildeexpand $spec]
    }
    foreach ext {png svg} {
        foreach dir $::icon_path {
            set p [file join [file tildeexpand $dir] $spec.$ext]
            if {[file exists $p]} { return $p }
        }
    }
    return ""
}
proc icon-stamp {path} {
    if {$path eq "" || [catch {file mtime $path} m]} { return "" }
    return $m
}
# AN ICON THAT HAS NOT CHANGED IS NOT RE-READ, and — the part that
# shows — the image OBJECT is never destroyed under a strip that is
# using it. It used to be: every reload dropped the whole cache,
# deleting the photos, and the panel repainted as they went (the
# owner, 2026-08-01). Now the file's path and mtime are the cache's
# guard: the same file gives the same image back untouched, and a
# file that HAS changed is read into a fresh photo and copied INTO
# the standing one, so every widget holding that image name keeps
# holding it and simply shows the new pixels.
#
# Nothing is deleted on a reset any more, and nothing needs to be:
# an entry is at most one photo per {spec size} the config has ever
# named in this session.
keep icon_cache {}    ;# {spec size} -> {img path mtime}
proc resolve-icon {spec size} {
    if {$spec in [image names]} { return $spec }
    set key [list $spec $size]
    set path [icon-file-of $spec]
    set stamp [icon-stamp $path]
    if {[dict exists $::icon_cache $key]} {
        lassign [dict get $::icon_cache $key] img was wasstamp
        if {$path eq $was && $stamp eq $wasstamp} { return $img }
        if {$img ne "" && $path ne ""} {
            if {[catch {icon-refresh $img $path $size} err]} {
                puts "WM: icon «$spec»: $err — keeping the one we had"
            } else {
                puts "WM: icon «$spec»: [file tail $path] changed, re-read in place"
            }
            dict set ::icon_cache $key [list $img $path $stamp]
            return $img
        }
    }
    set img ""
    if {$path eq ""} {
        puts "WM: icon «$spec»: no Tk image, no $spec.png or $spec.svg\
 in icon-path"
    } elseif {[catch {icon-photo $path $size} img]} {
        puts "WM: icon «$spec»: $img"
        set img ""
    } else {
        set img [shrink-photo $img $size]
        puts "WM: icon «$spec»: [file tail $path]\
 [image width $img]x[image height $img]"
    }
    dict set ::icon_cache $key [list $img $path $stamp]
    return $img
}
# ...the swap itself: read into a scratch photo, size it as the
# resolution would, then pour it into the standing image. `-shrink`
# is what makes it a replacement and not an overlay — without it a
# smaller icon would keep the old one's edges around itself.
proc icon-refresh {img path size} {
    set fresh [icon-photo $path $size]
    set fresh [shrink-photo $fresh $size]
    $img blank
    $img copy $fresh -shrink
    image delete $fresh
}
# AN SVG IS DRAWN AT THE SIZE, not drawn and then squeezed: the
# format reader takes the height it should render at, which is the one
# thing vector art is for. Anything else is read as it is and the
# resampler below deals with it.
proc icon-photo {path size} {
    set path [file normalize $path]
    if {[string match -nocase *.svg $path]} {
        return [image create photo -file $path \
                    -format [list svg -scaletoheight $size]]
    }
    return [image create photo -file $path]
}
# Downsample a photo to fit target (nearest neighbor, keeps alpha);
# a fitting image passes through untouched.
proc shrink-photo {img target} {
    set iw [image width $img]; set ih [image height $img]
    if {$iw <= $target && $ih <= $target} { return $img }
    if {$iw >= $ih} {
        set ow $target; set oh [expr {max(1, $ih * $target / $iw)}]
    } else {
        set oh $target; set ow [expr {max(1, $iw * $target / $ih)}]
    }
    set raw ""
    for {set y 0} {$y < $oh} {incr y} {
        append raw \x00
        set sy [expr {$y * $ih / $oh}]
        for {set x 0} {$x < $ow} {incr x} {
            set sx [expr {$x * $iw / $ow}]
            append raw [binary format cccc {*}[$img get $sx $sy -withalpha]]
        }
    }
    set out [image create photo -data [rgba-png $ow $oh $raw]]
    image delete $img
    return $out
}

# Which icon a window-list row shows, in precedence order: the style's
# `icon` key (the user's word beats the app's), the client's own
# _NET_WM_ICON, and last the PSEUDO icon — one-two letters on a color
# badge (the telegram contact-list trick), so every row carries
# something the eye can anchor on. The letters come from the CLASS
# (the app identity — every xterm gets the same badge; the title
# fills in for class-less windows): initials of the first two words,
# a lone word contributing its first two letters. The color is a
# stable hash pick from a small palette keyed by the same name.
# Returns {image NAME} or {pseudo LETTERS COLOR}.
set icon_palette {#cc4444 #d4772f #75507b #4e9a06 #06989a #b3617e #927238}
proc pseudo-badge {name} {
    set words [regexp -all -inline {[^\s[:punct:]]+} $name]
    if {[llength $words] >= 2} {
        set letters [string index [lindex $words 0] 0][string index [lindex $words 1] 0]
    } else {
        set letters [string range [lindex $words 0] 0 1]
    }
    set letters [string toupper $letters]
    if {$letters eq ""} { set letters ? }
    set color [lindex $::icon_palette [expr {
        [zlib crc32 [encoding convertto utf-8 $name]] % [llength $::icon_palette]}]]
    list $letters $color
}
proc winlist-icon {w target} {
    set st [style-of $w]
    if {[dict exists $st icon]} {
        set img [resolve-icon [dict get $st icon] $target]
        if {$img ne ""} { return [list image $img] }
    }
    set img [client-icon $w $target]
    if {$img ne ""} { return [list image $img] }
    set name [lindex [client-class $w] 1]
    if {$name eq ""} { set name [title-or-id $w [visible-title $w]] }
    list pseudo {*}[pseudo-badge $name]
}

# ---- name-tint: the badge trick, said as a word ----
# A stable colour from a name — the hash the pseudo-badges and the
# panel's auto-badges already lean on, published for the config: tint
# twenty ssh terminals by their target's name and they tell apart at
# a glance, nobody choosing anything (the owner's model task,
# 2026-08-04). Where a badge wants saturation, a background wants a
# TINT: the hash picks the hue, `-from white|black` picks the ground
# it leans off (unsaid: the theme's own side), `-amount` how far it
# leans — 0 is the bare ground, 1 the full hue.
proc name-tint {name args} {
    set from ""
    set amount 0.15
    foreach {k v} $args {
        switch -- $k {
            -from   { set from $v }
            -amount { set amount $v }
            default { error "name-tint: unknown option «$k» (-from -amount)" }
        }
    }
    if {$from eq ""} { set from [expr {$::theme eq "light" ? "white" : "black"}] }
    if {$from ni {white black}} {
        error "name-tint: -from is white or black, not «$from»"
    }
    if {![string is double -strict $amount] || $amount < 0 || $amount > 1} {
        error "name-tint: -amount is 0..1, not «$amount»"
    }
    set h [expr {([zlib crc32 [encoding convertto utf-8 $name]] % 360) / 60.0}]
    set x [expr {1.0 - abs(fmod($h, 2.0) - 1.0)}]
    switch [expr {int($h)}] {
        0 { lassign [list 1.0 $x 0.0] r g b }
        1 { lassign [list $x 1.0 0.0] r g b }
        2 { lassign [list 0.0 1.0 $x] r g b }
        3 { lassign [list 0.0 $x 1.0] r g b }
        4 { lassign [list $x 0.0 1.0] r g b }
        5 { lassign [list 1.0 0.0 $x] r g b }
    }
    set base [expr {$from eq "white" ? 1.0 : 0.0}]
    set out "#"
    foreach c [list $r $g $b] {
        append out [format %02x \
            [expr {round(255 * ($base * (1 - $amount) + $c * $amount))}]]
    }
    return $out
}
# Any Tk-legal colour as #rrggbb — what the terminal adapters spell
# their dialects with, normalized ONCE for all of them because
# alacritty knows no X colour names at all. winfo rgb answers 16-bit
# channels; the high byte is the 8-bit truth.
proc color-hex {color} {
    lassign [winfo rgb . $color] r g b
    format #%02x%02x%02x [expr {$r >> 8}] [expr {$g >> 8}] [expr {$b >> 8}]
}

# TWO LISTS, and they are TWO COMMANDS — not one that asks who called
# it (the owner, 2026-08-04). The binding says which list it wants, so
# nothing ever has to work out whether the hand came from Alt+Tab.
#
#   winlist      what the CYCLE flips through, and it stays on THIS
#     desk. A cycle that wandered across desks would break the one
#     promise the gesture makes: that two presses put you back where
#     you were.
#   winlist-all  the INVENTORY — every window there is, each foreign
#     one marked with its desk, and picking one goes there. This is
#     the list one opens to FIND something, so hiding two thirds of
#     the desk from it would be the wrong half of the answer.
proc winlist {} { winlist-of here }
proc winlist-all {} { winlist-of all }
proc winlist-of {scope} {
    set wins {}
    foreach w $::focus_hist {
        if {[info exists ::frameof($w)]} { lappend wins $w }
    }
    foreach w [array names ::frameof] {
        if {$w ni $wins} { lappend wins $w }
    }
    if {$scope ne "all"} {
        set wins [lmap w $wins {expr {[desk-here-p $w] ? $w : [continue]}}]
    }
    if {![llength $wins]} { puts "WM: winlist: no windows"; return }
    winlist-open $wins center toggle
}
# What a row says about where its window lives. Nothing at all on a
# desk with one desk, and nothing for a window one is looking at: the
# mark is for the ones that are NOT here, which is the only case where
# a title alone leaves a question.
proc desk-label {w title} {
    if {$::ndesks <= 1 || [desk-here-p $w]} { return $title }
    return "[desk-name [desk-of $w]]: $title"
}
# The list itself, reusable — and it answers TWO questions that were
# one argument for as long as only two combinations of them existed:
#
#   WHERE it opens — `center`, or {panel NAME ACTION} to hang off a
#     button (the panel's name, because which strip the button is on
#     decides which way the list opens off it, see below);
#   WHAT KIND of list it is — `toggle` (the desk's whole window list,
#     the thing a chord flips through) or `chooser` (pick one of
#     these), which is what decides cycle mode and where the selection
#     starts.
#
# They were welded together because the only centred list was the
# toggle: `center` meant «may enter cycle mode, and preselect the
# SECOND row» — Alt+Tab's two habits, neither of them anything to do
# with being in the middle of the screen. A CENTRED CHOOSER breaks the
# weld: with chord-hold on, the invoking Super is still down when the
# list appears, so a chooser inheriting cycle mode would commit to the
# previous window the moment the hand relaxed, having asked nothing.
proc winlist-open {wins where kind {more ""}} {
    set ::winlist_wins $wins
    # WHAT EACH ROW ANSWERS, which is not the same list as the windows
    # once a chooser can end in a row that is not one: `more` is the
    # deed's own «run another», and it answers with the word `more`
    # rather than with a window id nobody could tell apart from one.
    set ::winlist_rows $wins
    set ::winlist_prev $::focused
    set ::winlist_cycle 0
    set cycle_motion 0
    if {$kind eq "toggle" && $::winlist_cycle_opt} {
        lassign [popup-cycle-arm] ::winlist_cycle cycle_motion
    }
    # Every entry is numbered, and the number IS its hotkey — the
    # shared popup alphabet (popup-autokeys), which is why j/k/n/p
    # keep walking the list however many windows are open. The digit
    # column sits on the left — a numbered list reads that way.
    set ::winlist_keys [popup-autokeys [llength $wins]]
    set ih [expr {[font metrics TitleFont -linespace] + 6}]
    set numw [expr {[font measure TitleFont W] + 14}]
    # the icon cell: a square a hair under the row, the lettering sized
    # to the badge in pixels (IconFont, see its creation)
    set sq [expr {$ih - 4}]
    font configure IconFont -family [font actual TitleFont -family] \
        -size -[expr {max(7, $sq * 5 / 8)}]
    set iconw [expr {$ih + 6}]
    set T [popup-shell .winlist $ih winlist-click]
    $T column create -width $numw -tags Cnum
    $T column create -width $iconw -tags Cicon
    $T column create -squeeze yes -expand yes -tags C0
    $T configure -treecolumn C0
    $T element create eNum text -fill [themed dim] -lines 1 \
        -font [popup-hover-font]
    $T element create eIcon image
    $T element create ePRect rect
    $T element create ePTxt text -fill white -lines 1 -font IconFont
    $T style create sNum
    $T style elements sNum {eSel eNum}
    $T style layout sNum eSel -detach yes -iexpand xy
    $T style layout sNum eNum -expand wns -padx 6
    $T style create sIcon
    $T style elements sIcon {eSel eIcon}
    $T style layout sIcon eSel -detach yes -iexpand xy
    $T style layout sIcon eIcon -expand wens
    $T style create sPseudo
    $T style elements sPseudo {eSel ePRect ePTxt}
    $T style layout sPseudo eSel -detach yes -iexpand xy
    $T style layout sPseudo ePRect -union ePTxt -ipadx 3 -ipady 2 -expand wens
    $T style layout sPseudo ePTxt -expand wens
    $T style create sWin
    $T style elements sWin {eSel eTxt}
    $T style layout sWin eSel -detach yes -iexpand xy
    $T style layout sWin eTxt -expand ns -padx 4 -squeeze x
    set maxw 0
    foreach w $wins key $::winlist_keys {
        set title [desk-label $w \
            [iconic-label $w [title-or-id $w [visible-title $w]]]]
        set maxw [expr {max($maxw, [font measure TitleFont $title])}]
        set item [$T item create]
        $T item style set $item Cnum sNum C0 sWin
        $T item element configure $item Cnum eNum -text $key
        $T item element configure $item C0 eTxt -text $title
        # `face`, and not the `kind` this used to be called: the
        # argument that says what KIND OF LIST this is has that name
        # now, and a row's picture quietly overwriting it left the
        # toggle preselecting the wrong row — silently, since both
        # readings are ordinary words.
        lassign [winlist-icon $w $sq] face a b
        if {$face eq "image"} {
            $T item style set $item Cicon sIcon
            $T item element configure $item Cicon eIcon -image $a
            puts "WM: winlist icon 0x[format %x $w]: image $a"
        } else {
            $T item style set $item Cicon sPseudo
            $T item element configure $item Cicon ePRect -fill $b
            $T item element configure $item Cicon ePTxt -text $a
            puts "WM: winlist icon 0x[format %x $w]: pseudo «$a» $b"
        }
        $T item lastchild root $item
    }
    # THE DEED'S OWN LAST ROW. It carries no hotkey — the digits and
    # letters are window numbers, and one of them meaning something
    # else would make the whole column a thing to read twice — and it
    # is not preselected: a list of windows opens ON a window. A rule
    # above it says it is not one of them; the dim ink says the same
    # thing again, because a rule is easy to miss on a busy desk.
    if {$more ne ""} {
        set maxw [expr {max($maxw, [font measure TitleFont $more])}]
        $T element create eRule rect -fill [themed dim]
        $T element create eMore text -fill [themed dim] -lines 1 \
            -font [popup-hover-font]
        $T style create sMore
        $T style elements sMore {eSel eRule eMore}
        $T style layout sMore eSel -detach yes -iexpand xy
        $T style layout sMore eRule -detach yes -iexpand x -height 1
        $T style layout sMore eMore -expand ns -padx 4 -squeeze x
        set item [$T item create]
        $T item style set $item C0 sMore
        $T item element configure $item C0 eMore -text $more
        $T item lastchild root $item
        lappend ::winlist_rows more
    }
    # A cycle starts where the invoking key was already going — Tab's
    # own +1 is the classic «second row», a Super+P open walks up and
    # wraps to the last. A static toggle keeps the old habit (the
    # second row is the window a bare Enter toggles to); a chooser
    # starts on the most recent, because it is not switching anywhere
    # yet.
    if {$::winlist_cycle != 0} {
        $T selection add 1
        winlist-move $cycle_motion
    } else {
        $T selection add [expr {$kind eq "toggle" && [llength $wins] > 1 ? 2 : 1}]
    }
    # measured against the monitor under the hand — the same glass the
    # popup clamp (popup-show) will hold it to
    lassign [pointer-monitor] mx my sw sh
    set W [expr {min(max($maxw + $numw + $iconw + 28, 200), $sw * 3 / 5)}]
    set H [expr {[llength $::winlist_rows] * $ih + 2}]
    if {$where eq "center"} {
        set X [expr {$mx + ($sw - $W) / 2}]
        set Y [expr {$my + ($sh - $H) / 3}]
    } else {
        # By the button, and always on the strip's INNER face — the list
        # opens over the desk, never off the screen edge the strip is
        # glued to: over a bottom panel, under a top one, beside a
        # vertical one. (popup-show clamps to the screen either way.)
        # The button is named by its ACTION and found through the item
        # map — an item number is not a position promise (panel_items).
        lassign $where - pname aname
        set P [panel-window $pname]
        set T [panel-tree $pname]
        set bitem [expr {[info exists ::panel_items($pname)]
                         && [dict exists $::panel_items($pname) $aname]
                         ? [dict get $::panel_items($pname) $aname] : 1}]
        lassign [$T item bbox $bitem] bx by
        switch -- [panel-cfg $pname side] {
            bottom { set X [expr {[winfo rootx $T] + $bx}]
                     set Y [expr {[winfo y $P] - $H}] }
            top    { set X [expr {[winfo rootx $T] + $bx}]
                     set Y [expr {[winfo y $P] + [winfo height $P]}] }
            right  { set X [expr {[winfo x $P] - $W}]
                     set Y [expr {[winfo rooty $T] + $by}] }
            left   { set X [expr {[winfo x $P] + [winfo width $P]}]
                     set Y [expr {[winfo rooty $T] + $by}] }
        }
    }
    popup-show .winlist $W $H $X $Y
    # The hand-over notice is where a WAIT finds out it is over: another
    # modal thing taking the router is not the person answering, so the
    # list goes and its waiter is cancelled rather than left parked
    # under a menu nobody can reach any more.
    if {![grab-keys-to winlist-key \
              [list popup-yank "the keyboard went to another mode"]]} {
        puts "WM: winlist: keyboard not grabbed — mouse only"
    }
    # The toggle is the unmarked case, so the line reads as it always
    # did and every log-reading regression goes on reading it; what is
    # NEW says so.
    puts "WM: winlist open ([llength $wins] windows[expr {
        $::winlist_cycle ? ", cycle" : ""}][expr {
        $kind eq "chooser" ? ", chooser" : ""}])"
}
# Open a chooser and WAIT for the row — the caller's own line, not a
# callback. Answers the picked window, or empty when nothing was picked
# (Escape, a click elsewhere, another menu over this one). A list yanked
# out from under the wait throws FUT CANCELLED instead: «nobody
# answered» and «nobody is going to» are different facts, and only the
# second belongs in the log.
proc winlist-choose {wins where {more ""}} {
    winlist-open $wins $where chooser $more
    return [popup-await .winlist]
}
proc winlist-key {kind name mods} {
    if {$kind eq "release"} {
        # cycle mode commits when the invoking chord's hold is no
        # longer WHOLE — any element of a Ctrl+Alt set going up is
        # the hand letting go; re-asking the server covers both-Alts
        # pedantry
        popup-cycle-release $::winlist_cycle winlist-pick
        return
    }
    # In cycle mode the held chord modifier is TRANSPARENT: it cannot
    # be released without committing, so Alt+3, Alt+j, Alt+Up must
    # work as 3, j, Up — strip it and dispatch as in the static menu.
    if {$::winlist_cycle != 0} { set mods [expr {$mods & ~$::winlist_cycle}] }
    if {$mods == 0 && [string length $name] == 1} {
        set i [lsearch -exact $::winlist_keys [string toupper $name]]
        if {$i >= 0} {
            .winlist.t selection clear
            .winlist.t selection add [expr {$i + 1}]
            winlist-pick
            return
        }
    }
    # Tab rides the same rail as the arrows and letters now
    # (popup-motion-of): the step that opened a cycle keeps walking it.
    set d [popup-motion-of $name $mods]
    if {$d != 0} { winlist-move $d; return }
    switch -- $name {
        Return - KP_Enter { winlist-pick }
        Escape            { winlist-cancel }
    }
}
proc winlist-move {d} {
    popup-move .winlist.t [llength $::winlist_rows] $d
}
proc winlist-pick {} {
    set cur [lindex [.winlist.t selection get] 0]
    set row [lindex $::winlist_rows [expr {$cur - 1}]]
    # A LIST THAT ANSWERS DOES NOT ACT. With somebody parked on it, the
    # row IS the answer and what it means belongs to whoever asked —
    # raise this window, run another one, edit it: the list cannot know,
    # and the deed's own door (an activate hook, say) is not the list's
    # to skip. With nobody waiting this is the plain window list of old,
    # where a pick has always meant «go there».
    if {[info exists ::popup_fut(.winlist)]} {
        # Spelled outside expr on purpose: expr hands back a NUMBER when
        # the branch it takes looks like one, so «0x400016» came out of
        # the ternary as 4194326 — measured, and the sort of thing that
        # only ever bites in a log line.
        if {$row eq ""} {
            puts "WM: winlist answers nothing"
        } elseif {$row eq "more"} {
            puts "WM: winlist answers more"
        } else {
            puts "WM: winlist answers 0x[format %x $row]"
        }
        popup-answer .winlist $row
        return
    }
    # The plain list carries windows and nothing else — a `more` row is
    # a deed's, and a deed's list always has somebody waiting on it.
    set w $row
    popups-close
    if {$w ne "" && [info exists ::frameof($w)]} {
        puts "WM: winlist pick 0x[format %x $w]"
        panel-focus-hit $w    ;# the desk, the deiconify and the focus
    }
}
proc winlist-click {x y {s 0}} {
    set T .winlist.t
    if {[catch {$T identify -array A $x $y}] || $A(where) ne "item"} return
    $T selection clear
    $T selection add $A(item)
    winlist-pick
}
proc winlist-cancel {} {
    set prev $::winlist_prev
    popups-close
    if {$prev != 0 && [info exists ::frameof($prev)]} { focus-to $prev }
}

