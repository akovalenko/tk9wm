# ---- carrying a window: the slop and the edges ----
#
# A title press is a CLICK until the pointer has travelled a few
# pixels. Without that, aiming at a titlebar to raise or focus a window
# nudges it a pixel or two on the way, which is easy to do by accident
# and annoying every time (the owner, 2026-07-30). The cursor says
# which it is so far: left_ptr while the press is still a click, the
# carrying fleur from the moment it becomes a drag. Once it does, the
# window follows the ORIGINAL press point — the pointer has moved by
# the slop and the window catches up in one step, so the spot that was
# grabbed stays under the pointer for the rest of the drag.
#
# The MODIFIER drag has no slop and wants none: holding a modifier
# before pressing is not something one does by accident.
keep drag_slop 4

# Edge resistance: a carried window STICKS to an edge of the workarea —
# within the resistance the frame sits exactly on it, and it takes that
# much more pointer travel to get past. Flush against a strip is the
# position one is usually aiming for, and hitting it by hand to the
# pixel is aiming nobody should have to do (fvwm's EdgeResistance,
# which the owner missed here). Both edges of both axes, and the
# WORKAREA's rather than the screen's: the edge worth being flush with
# is the one the panel leaves free. 0 switches it off.
keep edge_resist 12
proc resist-axis {pos size start extent} {
    if {abs($pos - $start) < $::edge_resist} { return $start }
    set far [expr {$start + $extent}]
    if {abs($pos + $size - $far) < $::edge_resist} { return [expr {$far - $size}] }
    return $pos
}
# Where a carried frame actually lands. The near edge wins on a window
# too big to fit, the same way the clamps decide it.
proc carry-to {t X Y} {
    if {$::edge_resist <= 0} { return [list $X $Y] }
    # the edges of the monitor UNDER THE DRAG — which makes the seam
    # between two monitors an edge too, and flush against it is a
    # position worth aiming for exactly like flush against a strip
    lassign [workarea-at [list $X $Y [winfo width $t] [winfo height $t]]] \
        wax way ww wh
    list [resist-axis $X [winfo width $t]  $wax $ww] \
         [resist-axis $Y [winfo height $t] $way $wh]
}
# A pointer gesture on the window a KEYBOARD mode is holding is not an
# error: it reads as a helper within that mode (the owner's call,
# 2026-07-30), so the mode stays in charge — its readout follows the
# carrying, and its Escape still undoes everything back to where the
# mode began, the carrying included.
proc carry-told {w} {
    if {$w != 0} { send-synthetic-configure $w }
    if {[kbmr-owns $w]} { kbmr-readout }
}

# Move policy is plain Tk: drag the title bar, the client rides along.
# A title click also raises and focuses. The cursor goes on the TITLE
# widget, since that is where Tk's implicit grab sits for the length of
# the drag, and comes off at the release (press-end).
proc drag-start {t w X Y} {
    popups-close
    # w == 0 is a window of the WM's OWN (see wm-window): there is no
    # client to raise and nothing to give the X focus to — it is
    # override-redirect and takes the keyboard through grab-keys-to.
    if {$w != 0} {
        raise-group $w
        focus-to $w
    }
    $t.title configure -cursor left_ptr   ;# a click until it is a drag
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> wx wy
    set ::drag($t) [list $X $Y $wx $wy 0]
}
proc drag-move {t w X Y} {
    # No state — no drag: the press never landed on this title (a drag
    # that STARTED on the root background is a noop, not a pickup).
    if {![info exists ::drag($t)]} return
    lassign $::drag($t) x0 y0 wx wy carrying
    if {!$carrying} {
        if {abs($X - $x0) < $::drag_slop && abs($Y - $y0) < $::drag_slop} return
        lset ::drag($t) 4 1
        $t.title configure -cursor fleur
    }
    lassign [carry-to $t [expr {$wx + $X - $x0}] [expr {$wy + $Y - $y0}]] nx ny
    wm geometry $t +$nx+$ny
    if {$w == 0} return   ;# our own window: nobody to tell but ourselves
    carry-told $w
}

# ---- carrying a window by a modifier, from anywhere on it ----
# The gesture every desk has and this one did not: hold a modifier,
# press on the window itself, move. It is what makes a window with no
# titlebar and no border usable at all (`decor none` leaves nothing to
# grab), and it is quicker than aiming at a strip even when there is
# one.
#
# The combination is the config's to choose — the owner's call, and
# <Super> is the default because <Alt> is spoken for inside so many
# applications. Button 1 carries the window, button 3 resizes it from
# the nearest corner, which is the second half of what a bare frame
# cannot otherwise do.
#
# Detection costs nothing: the click-to-focus grab already takes every
# button with AnyModifier, so the press arrives here anyway. What it
# takes to CARRY is the substrate's pointer router — the motion and
# the release after such a press are reported to nobody otherwise, and
# the grab is also where a cursor over a foreign window can come from.
keep drag_mods 64                ;# <Super>
proc set-drag-modifier {spec} {
    set mods [parse-mods $spec]
    if {$mods == 0} {
        error "set-drag-modifier: «$spec» names no modifier —\
 <Shift> <Ctrl> <Alt> <Super> <Mod2>..<Mod5>, or several together"
    }
    set ::drag_mods $mods
}

# ---- the cursor over the desk itself ----
# An X server hands the root window the ancient X_cursor — the big
# black X nobody has wanted since the 1980s — and leaves it there until
# somebody says otherwise. That somebody is conventionally the window
# manager, and every desk that looks normal has one doing it (the
# owner's had been running xsetroot by hand for it, 2026-07-29). So we
# do: left_ptr by default, any Tk cursor name from the config, and the
# empty string to keep hands off and leave whatever is there.
keep root_cursor left_ptr
proc set-root-cursor {name} {
    # VALIDATED, and by the only authority there is: Tk's own cursor
    # table. Unchecked, a typo went down into x-attrs and died inside
    # `soft` — logged, survived, and silent to whoever asked (the
    # owner: "не валидируется, не знаю применяется ли"). The probe
    # borrows this interpreter's own main window and puts its cursor
    # back, so nothing on the desk flickers.
    if {$name ne ""} {
        set prev [. cget -cursor]
        if {[catch {. configure -cursor $name}]} {
            error "set-root-cursor: no cursor named «$name» —\
 X cursor names are the ones in cursorfont.h (left_ptr, watch, …)"
        }
        . configure -cursor $prev
    }
    set ::root_cursor $name
    settle-soon cursor
}
proc root-cursor-apply {} {
    if {$::root_cursor eq ""} return
    soft "root cursor «$::root_cursor»" {
        x-attrs $::root [list cursor $::root_cursor]
        puts "WM: root cursor $::root_cursor"
    }
}
# A default has to be APPLIED, not merely declared — and nothing was
# applying this one. Every other knob on this layer reaches the screen
# either through its own setter (the config calls it) or through
# policy-apply, and policy-apply runs on a config RELOAD and nowhere
# else. So a config that never mentions the cursor — the ordinary case,
# it being a default — left the root wearing the server's ancient
# X_cursor until the first reload, and the feature looked forgotten
# (owner's desk, 2026-07-29; it was written, just never reached).
#
# Deferred to idle for the same reason the panel and the tray are: the
# config gets to speak first, so `set-root-cursor {}` still correctly
# keeps our hands off, and a config naming another cursor is not
# overwritten by the default a moment later.
after idle root-cursor-apply

# The substrate's first-refusal hook on a press inside a client: 1 =
# taken (the click never reaches the client), 0 = not ours. The
# modifier state must match EXACTLY, not merely contain the drag
# combination — otherwise every future gesture built on the same
# modifier plus one more would be swallowed here.
proc policy-client-press {w state button X Y} {
    if {$state != $::drag_mods || $button ni {1 3}} { return 0 }
    if {![info exists ::frameof($w)]} { return 0 }
    set t $::frameof($w)
    popups-close
    raise-group $w
    focus-to $w
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fx fy
    # Button 3 on a fixed-size window (min == max) carries too: there
    # is no resize to give, and the border makes the same conversion
    # for a bare press (rz-start).
    if {$button == 1 || [client-fixed-size-p $w]} {
        set ::mdrag [list move $t $w $X $Y $fx $fy]
        set cursor fleur
    } else {
        # Which corner the press is nearer decides which corner the
        # drag pulls — the same eight-way machinery the border grips
        # feed, entered by hand because the pointer is nowhere near a
        # border, and wearing the same corner cursor rz-hover shows.
        set e [nearest-corner $t $X $Y]
        set ::rz [list $e $X $Y \
            [winfo width $t.slot] [winfo height $t.slot] $fx $fy $w]
        set ::mdrag [list resize $t $w]
        set cursor $::rzcursor($e)
    }
    if {![grab-pointer-to mouse-gesture $cursor]} {
        unset -nocomplain ::mdrag ::rz
        return 0
    }
    puts "WM: gesture [lindex $::mdrag 0] on 0x[format %x $w]"
    return 1
}
proc nearest-corner {t X Y} {
    set cx [expr {[winfo rootx $t] + [winfo width $t] / 2}]
    set cy [expr {[winfo rooty $t] + [winfo height $t] / 2}]
    string cat [expr {$Y < $cy ? "n" : "s"}] [expr {$X < $cx ? "w" : "e"}]
}
# The router the substrate calls for every motion and the release.
proc mouse-gesture {kind X Y} {
    if {![info exists ::mdrag]} { grab-pointer-to {}; return }
    lassign $::mdrag mode t w x0 y0 fx fy
    if {$kind eq "release"} {
        unset -nocomplain ::mdrag
        rz-end
        grab-pointer-to {}
        update idletasks
        send-synthetic-configure $w
        return
    }
    if {$mode eq "move"} {
        lassign [carry-to $t [expr {$fx + $X - $x0}] [expr {$fy + $Y - $y0}]] nx ny
        wm geometry $t +$nx+$ny
        carry-told $w
    } else {
        rz-move $t $w $X $Y
    }
}

# ---- the drag a CLIENT asks for: EWMH _NET_WM_MOVERESIZE ----
# A window that draws its own titlebar has nothing of OURS to grab, so
# it does the only thing left: it presses, lets the pointer go, and
# asks for the gesture by name. Every gesture it can name is already
# here — this is a door onto them and not a second implementation of
# any, which is also why a client-asked drag obeys the same edge
# resistance and the same size hints as one begun by hand.
#
# The directions are EWMH's: 0..7 walk the eight edges from the
# top-left corner clockwise (our own compass, in another order), 8 is
# the move, 9 and 10 are the KEYBOARD modes — which this desk has, and
# which a GTK window menu's Move/Resize items send — and 11 cancels.
array set mrdir {0 nw 1 n 2 ne 3 e 4 se 5 s 6 sw 7 w}
proc policy-moveresize-request {w X Y dir button} {
    if {![info exists ::frameof($w)]} return
    set t $::frameof($w)
    # Cancel ends the gesture WHERE IT STANDS. Not a rollback: the
    # client is saying it lost the button, not that the user changed
    # their mind, and a window snapping back to where the drag began
    # would be the bigger surprise. Undoing is what Escape does inside
    # our own keyboard modes, and it stays theirs.
    if {$dir == 11} {
        if {[info exists ::mdrag]} { mouse-gesture release $X $Y }
        return
    }
    if {$dir == 10} { move-keyboard $w;   return }
    if {$dir == 9}  { resize-keyboard $w; return }
    popups-close
    raise-group $w
    focus-to $w
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fx fy
    if {$dir != 8 && ![info exists ::mrdir($dir)]} {
        puts "WM: moveresize direction $dir is none of EWMH's — ignored"
        return
    }
    # An edge drag asked FOR a fixed-size window (min == max) carries
    # instead — the same conversion the border makes for a press by
    # hand, and a CSD titlebar is exactly a border of the client's own.
    if {$dir == 8 || [client-fixed-size-p $w]} {
        set ::mdrag [list move $t $w $X $Y $fx $fy]
        set cursor fleur
    } else {
        set e $::mrdir($dir)
        set ::rz [list $e $X $Y \
            [winfo width $t.slot] [winfo height $t.slot] $fx $fy $w]
        set ::mdrag [list resize $t $w]
        set cursor $::rzcursor($e)
    }
    # The timestamp this grab needs is the press the client is still
    # holding, and we have it: the click-to-focus grab takes every
    # button with AnyModifier, so that very press came through the
    # substrate and left its time in ::evtime.
    if {![grab-pointer-to mouse-gesture $cursor]} {
        unset -nocomplain ::mdrag ::rz
        return
    }
    puts "WM: gesture [lindex $::mdrag 0] on 0x[format %x $w], asked for"
}
