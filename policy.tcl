# tk9wm policy — the look-and-feel layer: OUR local decisions, none of
# which a WM fundamentally needs to be this way. Tk-widget decorations
# (titlebar / ✕ / slot, highlight colors), cascade placement, title-bar
# drag, click-to-focus, initial focus, refocus pick. Swap this file for a
# different look/behavior; the substrate only ever calls the policy-*
# hooks defined here (contract — see substrate.tcl header and the idea
# file, step 9).
#
# Private state: ::frameof(client) = frame widget, plus the cascade and
# drag bookkeeping. The substrate's client geometry (::geomof) is not
# touched here — sizes always arrive as hook arguments.

set ncli 0
set fid 0

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
    set parent [transient-for $w]
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
    lassign [place-frame $w [expr {$cw + 4}] [expr {$ch + 28}]] X Y
    toplevel $t -background #3465a4
    wm overrideredirect $t 1   ;# frames must bypass our own redirect
    label $t.title -text " клиент 0x[format %x $w]" \
        -background #3465a4 -foreground white -anchor w
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

proc policy-detach {w} {
    if {![info exists ::frameof($w)]} return
    destroy $::frameof($w)
    unset ::frameof($w)
}

# Root coordinates of the CLIENT area: frame position + our border (2)
# and titlebar (26) offsets.
proc policy-origin {w} {
    set t $::frameof($w)
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fx fy
    list [expr {$fx + 2}] [expr {$fy + 26}]
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

# Focus highlight: active frame blue, inactive grey.
proc policy-paint-focus {w} {
    foreach {ww tt} [array get ::frameof] {
        set bg [expr {$ww == $w ? "#3465a4" : "#888a85"}]
        $tt configure -background $bg
        $tt.title configure -background $bg
        $tt.close configure -background $bg
    }
}

# Click-to-focus: a click inside a client's body raises and focuses it.
# focus-to is called UNCONDITIONALLY — the old "skip if ::focused is
# already w" guard turned a single refused XSetInputFocus into a
# permanent wedge (clicks stopped repairing the focus, the keyboard kept
# going to the previous window). One roundtrip per click is the price of
# a click path that always heals.
proc policy-client-click {w} {
    raise $::frameof($w)
    focus-to $w
}

# A newly managed window gets the focus.
proc policy-managed {w} { focus-to $w }

# Refocus pick after an unmanage: an arbitrary managed window for now.
# QUEUED: honor WM_TRANSIENT_FOR and keep a focus history instead (the
# smsrc dialog-close observation — see the idea file).
proc policy-pick-refocus {} {
    foreach w [array names ::frameof] { return $w }
    return 0
}

# Move policy is plain Tk: drag the title bar, the client rides along.
# A title click also raises and focuses.
proc drag-start {t w X Y} {
    raise $t
    focus-to $w
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> wx wy
    set ::drag($t) [list $X $Y $wx $wy]
}
proc drag-move {t w X Y} {
    lassign $::drag($t) x0 y0 wx wy
    wm geometry $t +[expr {$wx + $X - $x0}]+[expr {$wy + $Y - $y0}]
    send-synthetic-configure $w
}
