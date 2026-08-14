# ---- keyboard move / resize ----
# The winops entries "move" and "resize": a keyboard-modal mode on the
# same grab-keys-to router the menus use (the menu action closes the
# popup, releasing the router; the mode re-grabs it). Arrows — and
# vi's h/j/k/l — step the frame or the client size; Enter and space
# commit, Escape cancels back to the geometry saved at mode entry.
#
# Move steps 10 px, 1 px with Shift, 50 px with Ctrl. Resize steps by
# the client's declared increment when its style respects increments
# and the increment is a REAL grid: an increment of 1 — every Tk
# app's degenerate default — makes any size on-grid, so the plain
# 10 px step serves better (Shift/Ctrl fine/coarse apply then too).
# Sizes funnel through apply-size-hints and wm-resize-client as
# everywhere, so the declared minimum binds and the grid holds.
#
# THE MODE IS VISIBLE, and it has to be: a modal grab with no sign of
# itself reads as a wedged desktop — "why is everything hanging?"
# (owner's report, 2026-07-28). Two marks, both on the window being
# worked on, because that is where the eyes already are: the whole
# frame turns amber for as long as the mode lasts (a fvwm-style
# geometry box in a screen corner was the alternative, and loses —
# the color says "modal" from across the screen, before any number is
# read), and the titlebar lends its text to a live readout, +X+Y while
# moving and WxH while resizing. Both are undone on commit AND on
# cancel; nothing about the client changes, only our decoration.
keep kbmr {}   ;# {move|resize w saved-geometry}, {} = mode off
proc kbmr-owns {w} {
    expr {[llength $::kbmr] && [lindex $::kbmr 1] == $w}
}
# The readout the titlebar carries while the mode runs. Sizes are the
# CLIENT's, in pixels, plus the client's own units in parentheses when
# it declared a real grid and its style respects it — an xterm dragged
# by whole cells should say 80x24, the way fvwm's box does, but the
# pixels stay on show for everything that has no such notion.
proc kbmr-text {} {
    lassign $::kbmr mode w
    if {$mode eq "" || ![info exists ::frameof($w)]} { return "" }
    set t $::frameof($w)
    if {$mode eq "move"} {
        regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fx fy
        return [format "move %+d%+d" $fx $fy]
    }
    set cw [$t.slot cget -width]; set ch [$t.slot cget -height]
    set text "resize ${cw}x${ch}"
    lassign [client-size-hints $w] minw minh incw inch basew baseh
    if {[dict get [style-of $w] increments] eq "respect"
            && ($incw > 1 || $inch > 1)} {
        set cols [expr {$incw > 1 ? ($cw - $basew) / $incw : $cw}]
        set rows [expr {$inch > 1 ? ($ch - $baseh) / $inch : $ch}]
        append text " ($cols x $rows)"
    }
    return $text
}
proc kbmr-readout {} {
    lassign $::kbmr mode w
    if {$mode eq "" || ![info exists ::frameof($w)]} return
    $::frameof($w).title item element configure 1 C0 eTxt -text [kbmr-text]
}
# Enter/leave the mode's look. Leaving reads ::kbmr as already
# cleared — frame-focus-color must give the honest focus color again,
# and the titlebar takes back the title policy-title remembered.
proc kbmr-paint {} {
    lassign $::kbmr mode w
    if {![info exists ::frameof($w)]} return
    frame-recolor $::frameof($w) [frame-focus-color $w]
    kbmr-readout
}
proc kbmr-unpaint {w} {
    if {![info exists ::frameof($w)]} return
    frame-recolor $::frameof($w) [frame-focus-color $w]
    policy-title $w [expr {[info exists ::titleof($w)] ? $::titleof($w) : ""}]
}

# ---- the compass ----
# Nine digits laid out the way they sit on a numpad, each one drawn AT
# THE POINT IT NAMES — so the compass is not a picture of a keyboard
# but a map: press 7 and the thing 7 stands for happens at the 7.
#
# It stands for two things, over two different rectangles.
#
# In keyboard MOVE it maps DESTINATIONS over the workarea: a press
# sticks the frame to that edge, corner or center, size untouched. The
# placement is the `place` grammar's, sizeless — cell 7 is {left top},
# cell 5 is {center} — and place-axis does the arithmetic, the same
# proc the config's `place` style goes through, so a compass jump and a
# configured placement land in the same pixel.
#
# In keyboard RESIZE it maps HANDLES over the frame itself: which side
# or corner the arrows drag, drawn where that handle is (the owner's
# ask, 2026-07-29). One cell falls out of that: a cell aligned center
# on BOTH axes owns no edge, so 5 is not a handle and the compass has
# the hole in the middle every eight-handle selection box has ever had.
# The hole is derived and not stipulated — it comes out of the same
# table the destinations do.
array set compass_cells {
    7 {start start}   8 {center start}   9 {end start}
    4 {start center}  5 {center center}  6 {end center}
    1 {start end}     2 {center end}     3 {end end}
}
# Which keysym names name a cell. The numpad arrives through the
# router's lock exception (router-key): NumLock on says the digits,
# off says the level-0 names an ordinary pc105 keymap keeps there —
# KP_Home/KP_Up/… Both rows are listed below, which is why this mode
# still does not care about NumLock: either face lands on the same
# cell. KP_1..KP_9 stay for the layouts that put the digit on level 0.
array set compass_key {
    KP_Home 7  KP_Up 8     KP_Prior 9
    KP_Left 4  KP_Begin 5  KP_Right 6
    KP_End 1   KP_Down 2   KP_Next 3
    KP_7 7     KP_8 8      KP_9 9
    KP_4 4     KP_5 5      KP_6 6
    KP_1 1     KP_2 2      KP_3 3
    7 7  8 8  9 9   4 4  5 5  6 6   1 1  2 2  3 3
}
keep compass {}      ;# the cells currently up, {} = no compass
keep compass_s 0     ;# their side, in pixels
keep compass_on {}   ;# the highlighted cell, {} = none
unless-already {[lsearch -exact [font names] CompassFont] >= 0} {font create CompassFont -weight bold}

# The edge a cell names, in the compass-point vocabulary the MOUSE
# resize already speaks (rz-edge, rzcursor): aligned to the start of an
# axis is that axis's near edge, to the end its far one, centered is
# neither. Empty for cell 5, which is what makes it not a handle.
proc compass-edge {cell} {
    lassign $::compass_cells($cell) halign valign
    set e ""
    switch -- $valign { start {append e n} end {append e s} }
    switch -- $halign { start {append e w} end {append e e} }
    return $e
}
proc compass-handles {} {
    set cells {}
    foreach cell {7 8 9 4 5 6 1 2 3} {
        if {[compass-edge $cell] ne ""} { lappend cells $cell }
    }
    return $cells
}
proc compass-cell-of {edge} {
    foreach cell [compass-handles] {
        if {[compass-edge $cell] eq $edge} { return $cell }
    }
    return {}
}

# Which cells a frame of fw x fh has anything DISTINCT to offer within
# a rect — the whole answer to "what about a maximized window", and it
# is arithmetic rather than a state flag (a maximized window is not
# frozen here: fvwm semantics, see maximize-client). A frame as wide as
# the workarea lands in the same X whether it is asked for left, center
# or right — that column of the compass is degenerate, and drawing
# three digits on one point would be a lie. So: no slack on either axis
# and there is no compass at all, nothing to offer; no slack on one and
# only the free axis is drawn, three digits down the middle of the
# other. The keys of a degenerate axis stay ACCEPTED — 7 and 9 are then
# honest synonyms of 8 — they are just not worth ink.
proc compass-offer {rect fw fh} {
    lassign $rect - - ww wh
    set hfree [expr {$fw < $ww}]
    set vfree [expr {$fh < $wh}]
    if {!$hfree && !$vfree} { return {} }
    if {!$hfree} { return {8 5 2} }
    if {!$vfree} { return {4 5 6} }
    return {7 8 9 4 5 6 1 2 3}
}
# How big a cell may be over a given box. The lettering wants to scale
# with the user's font and its dpi like the rest of the decoration, but
# it also has to FIT: nine cells sized for the desk, drawn on a 300x200
# window, would be a solid block of digits. So the font's own measure
# is the ceiling and a quarter of the box's short side is the cap, and
# when the cap bites the lettering is scaled down to it.
proc compass-size {rect} {
    lassign $rect - - rw rh
    font configure CompassFont -family [font actual TitleFont -family] \
        -size [expr {-2 * [look default titleh]}]
    set s [expr {[font metrics CompassFont -linespace] + 12}]
    set cap [expr {max(min($rw, $rh) / 4, 18)}]
    if {$s > $cap} {
        set px [expr {[font configure CompassFont -size] * $cap / $s}]
        font configure CompassFont -size [expr {min($px, -6)}]
        set s [expr {[font metrics CompassFont -linespace] + 12}]
    }
    return $s
}
# One override-redirect toplevel per cell, in the mode's own amber with
# the dark outline every piece of our furniture wears, raised over the
# desk (whatever the compass is about passes under it). `active` marks
# one cell as the one in force — the resize handle — in the lighter
# shade the frame's grips wear against that same amber.
proc compass-show {rect cells {active {}}} {
    compass-hide
    if {![llength $cells]} return
    set ::compass_s [compass-size $rect]
    foreach cell $cells {
        set c .compass$cell
        toplevel $c -background $::OUTLINE
        wm overrideredirect $c 1
        label $c.d -text $cell -font CompassFont
        place $c.d -x 1 -y 1 -width [expr {$::compass_s - 2}] \
                             -height [expr {$::compass_s - 2}]
    }
    set ::compass $cells
    compass-highlight $active
    compass-place $rect
    update idletasks
}
# Where the cells sit — once, at the box they were asked about, and
# there they stay for the rest of the mode.
#
# The resize compass used to follow the frame, on the reasoning that a
# handle should stay on its own corner. In use that reads as the digits
# coming unstuck and wandering: only SOME of them move on any given
# step (a west drag pins the east cells and walks the west ones), which
# looks like nothing at all from the outside (owner's report,
# 2026-07-29, not reproducible on demand). A compass that stands still
# is the better object anyway: it is a KEYMAP, drawn once to say which
# key is which handle, not a decoration of the edges — the frame's own
# grips are that.
#
# Clamped to the screen, because the box need not be on it: a window
# dragged half off the right edge would otherwise put its east handles
# where nobody can read them.
proc compass-place {rect} {
    lassign $rect rx ry rw rh
    lassign [monitor-of-rect $rect] mx my mw mh
    set s $::compass_s
    foreach cell $::compass {
        lassign $::compass_cells($cell) halign valign
        set X [place-axis $rx $rw $s $halign]
        set Y [place-axis $ry $rh $s $valign]
        set X [expr {max($mx, min($X, $mx + $mw - $s))}]
        set Y [expr {max($my, min($Y, $my + $mh - $s))}]
        wm geometry .compass$cell ${s}x${s}+$X+$Y
        stack-layer .compass$cell $::LAYER_POPUP
    }
}
proc compass-highlight {cell} {
    set ::compass_on $cell
    foreach c $::compass {
        if {$c eq $cell} {
            .compass$c.d configure -background $::gripof($::KBMR_BG) \
                -foreground $::OUTLINE
        } else {
            .compass$c.d configure -background $::KBMR_BG -foreground white
        }
    }
}
proc compass-hide {} {
    foreach cell $::compass { destroy .compass$cell }
    set ::compass {}
    set ::compass_on {}
}
# Where a frame is, as a rectangle: {X Y W H} in root coordinates.
proc frame-rect {w} {
    if {![info exists ::frameof($w)]} { return {} }
    if {![regexp {^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$} \
              [wm geometry $::frameof($w)] -> fw fh fx fy]} { return {} }
    list $fx $fy $fw $fh
}
# The compass keyboard MOVE puts up: over the workarea, for a frame of
# the size this window has right now (which the mode never changes, so
# it is built once at entry and stands unchanged to the end).
proc compass-for-move {w} {
    set fr [frame-rect $w]
    if {![llength $fr]} return
    set wa [workarea-at $fr]
    set cells [compass-offer $wa [lindex $fr 2] [lindex $fr 3]]
    # A compass short of its nine cells reads as a bug unless it says
    # why, so the short answers are the ones worth a line.
    if {[llength $cells] < 9} {
        lassign $wa - - ww wh
        puts "WM: compass 0x[format %x $w]:\
[expr {[llength $cells] ? "cells $cells" : "nothing to offer"}] —\
 a [lindex $fr 2]x[lindex $fr 3] frame in a ${ww}x${wh} workarea"
    }
    compass-show $wa $cells
}
# The rectangle the RESIZE compass is drawn on: the client area, not
# the whole frame. The handles mark the window's corners either way —
# the border between the two is a few pixels — and staying off the
# decoration keeps them off the TITLEBAR, which in this mode is
# carrying the size readout and has to stay legible. It also leaves the
# frame's own border unpainted, which is the other thing this mode
# shows about itself.
proc client-rect {w} {
    set fr [frame-rect $w]
    if {![llength $fr]} { return {} }
    lassign $fr fx fy fw fh
    lassign [chrome-of $w] B top
    list [expr {$fx + $B}] [expr {$fy + $top}] \
         [expr {$fw - 2*$B}] [expr {$fh - $top - $B}]
}
# ...and the compass keyboard RESIZE puts up: the eight handles, with
# the one in force lit. There is no degenerate case to think about
# here — a window can always be pulled by any of its sides, whatever
# size it happens to be — which is the whole difference from the move
# compass, where a cell can have nowhere to go.
proc compass-for-resize {w cell} {
    set cr [client-rect $w]
    if {![llength $cr]} return
    compass-show $cr [compass-handles] $cell
}

proc move-keyboard {{w 0}} {
    if {$w == 0} { set w $::focused }
    if {$w == 0 || ![info exists ::frameof($w)]} return
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $::frameof($w)] -> fx fy
    kbmr-enter move $w [list $fx $fy]
}
# The handle keyboard resize starts on is the SOUTH-EAST one, which is
# what the mode always did before it could be told otherwise: the arrows
# grew the window down and to the right and the top-left corner stayed
# put. The compass does not change that, it says it out loud.
keep kbmr_edge se
proc resize-keyboard {{w 0}} {
    if {$w == 0} { set w $::focused }
    if {$w == 0 || ![info exists ::frameof($w)]} return
    # A fixed-size window (min == max) gives this mode nothing to do —
    # every arrow would push against both bounds at once. Every entry
    # (winops, wm-bind, EWMH's SIZE_KEYBOARD) is REFUSED, not converted
    # to a move: keyboard move is its own verb, a keystroke away, and a
    # mode that silently became another would be the worse answer (the
    # owner's call, 2026-08-15). The pointer gestures convert instead —
    # a hand already holding the window is better carried than dropped.
    if {[client-fixed-size-p $w]} {
        puts "WM: keyboard resize refused — 0x[format %x $w] is fixed-size"
        return
    }
    set t $::frameof($w)
    set ::kbmr_edge se
    # The saved geometry is the POSITION as well now: a handle on the
    # west or north side moves the frame while it resizes, so an Escape
    # that only put the size back would leave the window somewhere it
    # never was.
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fx fy
    kbmr-enter resize $w [list [$t.slot cget -width] [$t.slot cget -height] \
                               $fx $fy]
}
proc kbmr-enter {mode w orig} {
    set ::kbmr [list $mode $w $orig]
    # Preempted — a menu opened over us with the mouse, a confirmation
    # put up — the mode CANCELS: it never got its Enter, and a window
    # that quietly kept an unfinished move would be the worse surprise.
    if {![grab-keys-to kbmr-key {kbmr-end 0}]} {
        set ::kbmr {}
        puts "WM: keyboard $mode: keyboard not grabbed"
        return
    }
    # A window can be ACTIVE and buried — Lower keeps the focus where it
    # was, which is what makes "drop it, see what is under it, bring it
    # back" work. Opening the ops MENU on such a window is fine and the
    # owner wants it kept (2026-07-30): the menu is a command, and
    # commanding a window one cannot see is exactly the point of that
    # gesture. Dragging one is not fine — the compass and the amber
    # frame end up under other windows and nothing visibly moves.
    #
    # fvwm looks equally odd here, which is what made this look
    # inevitable. It is not, and the answer was already in this layer
    # THREE TIMES: drag-start, rz-start and policy-client-press all
    # raise before they manipulate. So a keyboard move that does not
    # is not us following fvwm, it is us disagreeing with ourselves —
    # one operation, one outcome (the lesson of step 40).
    #
    # Raise only, no focus-to: the mouse paths focus because a CLICK is
    # how one points at a window, and this mode does no pointing — it
    # is entered on the active window by construction. And the raise is
    # NOT undone at the end, by either Enter or Escape: Escape puts back
    # the geometry, which is what the mode changed, while the raise is
    # what manipulating a window does, the way the mouse leaves it too.
    raise-group $w
    kbmr-paint
    # The compass stands for exactly as long as its digits are live —
    # the mode's own lesson, one size down: live keys with no sign of
    # themselves read as a desk that has stopped answering.
    if {$mode eq "move"} {
        compass-for-move $w
        puts "WM: keyboard move 0x[format %x $w] — [kbmr-text]"
    } else {
        compass-for-resize $w [compass-cell-of $::kbmr_edge]
        puts "WM: keyboard resize 0x[format %x $w] — [kbmr-text]\
 by the $::kbmr_edge handle"
    }
}
proc kbmr-end {commit} {
    lassign $::kbmr mode w orig
    set ::kbmr {}
    grab-keys-to {}
    compass-hide
    if {$mode eq ""} return
    if {!$commit && [info exists ::frameof($w)]} {
        if {$mode eq "move"} {
            frame-moveto $w {*}$orig
        } else {
            # size first, then position: a west or north handle moved
            # the frame on the way out, and putting the size back does
            # not put the frame back
            lassign $orig cw ch X Y
            wm-resize-client $w $cw $ch
            frame-moveto $w $X $Y
        }
    }
    kbmr-unpaint $w
    set said [expr {$commit ? "done" : "cancelled"}]
    puts "WM: keyboard $mode 0x[format %x $w] $said"
    invariants-soon
}
# Move a frame and tell its client where it now is — the keyboard
# arrows, the compass and Escape's restore all end up here.
proc frame-moveto {w X Y} {
    if {![info exists ::frameof($w)]} return
    wm geometry $::frameof($w) +$X+$Y
    update idletasks
    send-synthetic-configure $w
}
# One compass cell in RESIZE: it picks the handle and moves nothing.
# Cell 5 names no edge and is not drawn, so it is not a handle either —
# pressing it is not an error, just nothing to do.
proc kbmr-handle {w cell} {
    set e [compass-edge $cell]
    if {$e eq "" || $e eq $::kbmr_edge} return
    set ::kbmr_edge $e
    compass-highlight $cell
    puts "WM: compass 0x[format %x $w]: by the $e handle"
}
# One compass cell in MOVE: the frame keeps its size and takes the
# position that cell names within the workarea.
proc kbmr-jump {w cell} {
    if {![regexp {^(\d+)x(\d+)} [wm geometry $::frameof($w)] -> fw fh]} return
    lassign [workarea-of-frame $::frameof($w)] wax way ww wh
    lassign $::compass_cells($cell) halign valign
    frame-moveto $w [place-axis $wax $ww $fw $halign] \
                    [place-axis $way $wh $fh $valign]
}
proc kbmr-key {kind name mods} {
    if {$kind eq "release"} return
    lassign $::kbmr mode w orig
    if {$mode eq "" || ![info exists ::frameof($w)]} { kbmr-end 1; return }
    # The compass, which means one thing per mode. In MOVE a digit is a
    # destination, and the jump is a STEP AND NOT A VERDICT: it does not
    # commit, which is what keeps Escape's promise (the geometry the
    # mode started on) alive after one — and makes the compass worth
    # looking at twice. 7, then 3, then 5, then Enter. In RESIZE a digit
    # picks the HANDLE the arrows drag, and changes no geometry at all.
    if {[llength $::compass] && [info exists ::compass_key($name)]} {
        set cell $::compass_key($name)
        if {$mode eq "move"} {
            kbmr-jump $w $cell
            kbmr-readout
        } else {
            kbmr-handle $w $cell
        }
        return
    }
    # ...and the way back, which belongs to the MODE and not to the
    # compass: 0 is offered even when the window fills the desk and the
    # compass has nothing to draw. Resize has no such key — its origin
    # is a size, and shrinking back to one is what the arrows are for.
    if {$mode eq "move" && $name in {0 KP_0 KP_Insert}} {
        frame-moveto $w {*}$orig
        kbmr-readout
        return
    }
    set dx 0; set dy 0
    switch -- $name {
        Left - h  { set dx -1 }
        Right - l { set dx 1 }
        Up - k    { set dy -1 }
        Down - j  { set dy 1 }
        Return - KP_Enter - space { kbmr-end 1; return }
        Escape                    { kbmr-end 0; return }
        default return
    }
    set t $::frameof($w)
    if {$mode eq "move"} {
        set step 10
        if {$mods & 1} { set step 1 }
        if {$mods & 4} { set step 50 }
        regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fx fy
        frame-moveto $w [expr {$fx + $dx*$step}] [expr {$fy + $dy*$step}]
    } else {
        lassign [client-size-hints $w] minw minh incw inch basew baseh
        set xstep 10; set ystep 10
        if {$mods & 1} { set xstep 1; set ystep 1 }
        if {$mods & 4} { set xstep 50; set ystep 50 }
        if {[dict get [style-of $w] increments] eq "respect"} {
            if {$incw > 1} { set xstep $incw }
            if {$inch > 1} { set ystep $inch }
        }
        # The arrow moves THE HANDLE, so what it does to the size
        # depends on which edge that handle owns: an east edge grows the
        # window as it travels right, a west edge shrinks it (and the
        # frame follows, so the east edge stays put), and a handle with
        # no freedom on this axis — a bare n or s against a horizontal
        # arrow — does not answer at all.
        set e $::kbmr_edge
        set cw0 [$t.slot cget -width]; set ch0 [$t.slot cget -height]
        set cw $cw0; set ch $ch0
        if {$e in {e ne se}} { incr cw [expr { $dx*$xstep}] }
        if {$e in {w nw sw}} { incr cw [expr {-$dx*$xstep}] }
        if {$e in {s se sw}} { incr ch [expr { $dy*$ystep}] }
        if {$e in {n ne nw}} { incr ch [expr {-$dy*$ystep}] }
        regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fx fy
        resize-by-edge $w $e $cw $ch $cw0 $ch0 $fx $fy
        # ...and the compass stays where it was put — see compass-place
    }
    kbmr-readout
}

# ---- the key echo: a chord sequence, made visible ----
#
# A prefix takes the whole keyboard. Until now it did that in total
# silence, which leaves the desk indistinguishable from a wedged one at
# the exact moment one is least sure — and made an undefined key inside
# a sequence the quietest event on the desk: nothing happened, nothing
# said so (the owner, 2026-07-30).
#
# So the sequence shows itself, in the same amber the keyboard modes
# wear, because it IS one of them: `Super+t …` while it waits, and
# `Super+t z is undefined` for a moment when a press ends it. The
# trailing ellipsis is the whole message in one character — the desk is
# holding your keyboard and waiting for the rest.
#
# WHEN it appears is a knob and the default is AT ONCE, which is not
# Emacs's default (echo-keystrokes waits a second) and is deliberate:
# Emacs echoes a prefix one types hundreds of times an hour, where a
# box appearing on every C-x would be noise. Here a chord is a rare,
# deliberate thing, and the feedback asked for was "while you type"
# (the owner). Whoever finds the flash of a fast Super+t q too much
# sets a delay and only ever sees the box when hesitating, which is
# Emacs's behaviour and one number away.
#
# It is an override-redirect toplevel like the compass and the menus,
# takes no focus and answers no clicks: it is a readout, not a widget.
# The window is NAMED, which costs nothing and lets a test outside this
# process assert that a box really is on the screen rather than trust
# our own log for it.
keep key_echo 0                  ;# ms of hesitation before it shows; off = never
keep key_echo_place {hcenter bottom}
set KEY_ECHO_PROBLEM_HOLD 8000   ;# a failure is read, not glanced at
set KEY_ECHO_HOLD 1200          ;# how long a flash stands before it goes
set KEY_ECHO_BAD  #a40000       ;# ...and the color it stands in
keep keyecho_kind none           ;# none | keys | flash — what is up right now
keep keyecho_pending ""          ;# the text a delayed `keys` is going to show

proc set-key-echo {spec} {
    if {$spec eq "off"} { set ::key_echo off; return }
    if {![string is integer -strict $spec] || $spec < 0} {
        error "set-key-echo: milliseconds of hesitation before the box shows,\
 0 for the moment the prefix lands, or off"
    }
    set ::key_echo $spec
}
# Where it sits, in the `place` grammar's own words — but SIZELESS
# terms only: the box is as big as its text, so a percentage has
# nothing to size. An axis nobody names is centered on the workarea.
proc set-key-echo-place {spec} {
    keyecho-anchor $spec        ;# a typo is reported now, not at the next chord
    set ::key_echo_place $spec
}
proc keyecho-anchor {spec} { anchor-of $spec }
# A corner, in the `place` grammar's own words, SIZELESS: the thing
# being placed is as big as it is, and only the pinning is being asked
# about. Shared by the key echo and by every widget, which is why it
# does not live in either.
proc anchor-of {spec} {
    set h center
    set v center
    foreach term [split [string map {, " "} $spec]] {
        if {$term eq ""} continue
        if {[regexp {^[0-9]+%} $term]} {
            error "a sizeless placement: «$term» has nothing to size"
        }
        switch -- $term {
            left    { set h start }
            right   { set h end }
            hcenter { set h center }
            top     { set v start }
            bottom  { set v end }
            vcenter { set v center }
            center  { set h center; set v center }
            default { error "cannot read the placement term «$term»" }
        }
    }
    list $h $v
}

# The substrate's hook. Every call cancels both timers first: whatever
# the box was about, it is about this now.
proc policy-key-echo {kind {text ""}} {
    after cancel keyecho-due
    after cancel keyecho-hide
    if {$kind eq "none"} { keyecho-hide; return }
    # `off` means "do not put a box up while I type" — it cannot mean
    # "refuse to answer when I ask", so the help goes through it. The
    # other two kinds are the desk speaking unbidden, and that is
    # exactly what was switched off.
    if {$::key_echo eq "off" && $kind ni {help problem}} return
    switch -- $kind {
        keys {
            set ::keyecho_pending $text
            # Up already, or wanted at once: no second wait. A delay is
            # about the FIRST chord — once the box is on the screen it
            # has to follow the typing, not lag a step behind it.
            if {$::keyecho_kind in {keys help} || $::key_echo == 0} {
                keyecho-due
            } else {
                after $::key_echo keyecho-due
            }
        }
        help {
            # Asked for, so it stands until the sequence moves on —
            # no hold timer, no delay.
            keyecho-show help $text
        }
        flash {
            # Shown whether or not the box had made it up: this one is
            # the report, and a fast typist is exactly who gets no
            # warning otherwise.
            keyecho-show flash $text
            after $::KEY_ECHO_HOLD keyecho-hide
        }
        problem {
            # a string, or {header lines} when there is a body to show
            # A FAILURE IS READ, NOT GLANCED AT, so it holds far
            # longer than a flash — and it has no natural end of its
            # own, so a timer is the end it gets. Anything the desk
            # says next replaces it, which is the closest thing to
            # «until you are done with it» that costs no grab; and
            # the store keeps it, so a message missed or replaced is
            # not a message lost.
            keyecho-show problem $text
            after $::KEY_ECHO_PROBLEM_HOLD keyecho-hide
        }
        default { error "policy-key-echo: unknown kind «$kind»" }
    }
}
proc keyecho-due {} { keyecho-show keys "$::keyecho_pending …" }
# NOTHING MAPS BEFORE IT KNOWS WHERE IT GOES. The box asks the LABEL
# how big it is, and the `update idletasks` that answer needs is also
# what maps a freshly built toplevel — so the first version put the box
# on the screen at Tk's idea of a place and moved it to ours a
# heartbeat later, which reads as a flash in the wrong corner (the
# owner, 2026-07-30).
#
# Hence: built withdrawn, sized, placed, and only then shown — and it
# STAYS from then on, hidden by withdrawing rather than destroyed, so
# the first map is the only one there is. (The menus and the compass
# never met this: neither asks a widget its size — the menu multiplies
# item height by count and measures the font for the width, the compass
# derives a square from font metrics — so neither needs an update
# before `wm geometry`, and their first map already carries the final
# geometry. It is the one question that costs a map.)
#
# Proved rather than asserted, and by the SERVER rather than by us:
# `xev -root -event substructure` is the witness, and the box must map
# with no move after it. With the fix backed out the same leg reads
# what the eye saw — a 200x200 toplevel (Tk's default for an empty one)
# mapping at the origin and only then becoming 92x32 in its corner.
# A flash that short is not a thing a screenshot can be aimed at.
proc keyecho-show {kind text} {
    set b .keyecho
    if {![winfo exists $b]} {
        toplevel $b -background $::OUTLINE
        wm overrideredirect $b 1
        wm withdraw $b
        wm title $b tk9wm-key-echo
    }
    if {$kind eq "help"} {
        lassign $text header rows
    } else {
        set header $text
        set rows {}
    }
    keyecho-build $b $header $rows \
        [expr {$kind in {flash problem} ? $::KEY_ECHO_BAD : $::KBMR_BG}]
    set ::keyecho_kind $kind
    update idletasks            ;# the content sizes itself, still unmapped
    set W [expr {[winfo reqwidth $b.c] + 2}]
    set H [expr {[winfo reqheight $b.c] + 2}]
    lassign [workarea] wax way ww wh
    lassign [keyecho-anchor $::key_echo_place] halign valign
    wm geometry $b ${W}x${H}+[place-axis $wax $ww $W $halign]+[place-axis\
 $way $wh $H $valign]
    update idletasks            ;# ...and the move lands, still unmapped
    wm deiconify $b
    stack-layer $b $::LAYER_POPUP
    update idletasks
    set line $header
    foreach row $rows { append line " | [lindex $row 0] → [lindex $row 1]" }
    puts "WM: key echo ($kind) «$line»"
}
# The listing is laid out by the GRID, not by spaces in one label: a
# proportional font makes padded text a ragged mess, and the columns
# are the whole point of a list one reads down (the owner, 2026-07-30
# — "in the range from the grid geometry manager to tktreectrl").
# Grid is the light end of that range and the fitting one: nothing here
# is selected, scrolled or clicked, so a treectrl would buy a scrollbar
# nobody needs.
#
# COLUMNS when it is long. The number of rows that fit is worked out
# from the font and the workarea, and anything past it starts a new
# pair of columns rather than running off the bottom of the screen.
proc keyecho-build {b header rows bg} {
    set c $b.c
    destroy $c
    frame $c -background $bg
    set n [llength $rows]
    lassign [workarea] - - - wh
    set rowh [expr {[font metrics TitleFont -linespace] + 3}]
    set percol [expr {max(1, ($wh - 4 * $rowh) / $rowh)}]
    if {$n < $percol} { set percol [expr {max(1, $n)}] }
    set ncols [expr {($n + $percol - 1) / $percol}]
    label $c.h -text $header -font TitleFont -background $bg \
        -foreground white -anchor w
    grid $c.h -row 0 -column 0 -columnspan [expr {max(3, 3 * $ncols)}] \
        -sticky w -padx 10 -pady [expr {$n ? {4 2} : 4}]
    set i 0
    foreach row $rows {
        # A ROW OF ONE is a plain line — what a diagnostic is made of.
        # The pairs are the help list's shape (keys → what); a failure
        # has nothing to put on the left of an arrow.
        if {[llength $row] < 2} {
            label $c.p$i -text [lindex $row 0] -font TitleFont \
                -background $bg -foreground white -anchor w
            grid $c.p$i -row [expr {1 + $i % $percol}] \
                -column [expr {3 * ($i / $percol)}] -columnspan 3 \
                -sticky w -padx {18 12} -pady {0 3}
            incr i
            continue
        }
        lassign $row keys what
        set r [expr {1 + $i % $percol}]
        set col [expr {3 * ($i / $percol)}]
        foreach {suffix txt} [list k $keys a → v $what] {
            label $c.$suffix$i -text $txt -font TitleFont -background $bg \
                -foreground white -anchor w
        }
        grid $c.k$i -row $r -column $col       -sticky w -padx {18 0} -pady {0 3}
        grid $c.a$i -row $r -column [expr {$col + 1}] -padx 6 -pady {0 3}
        grid $c.v$i -row $r -column [expr {$col + 2}] -sticky w -padx {0 12} \
            -pady {0 3}
        incr i
    }
    place $c -x 1 -y 1
}
proc keyecho-hide {} {
    set ::keyecho_kind none
    if {![winfo exists .keyecho] || ![winfo ismapped .keyecho]} return
    wm withdraw .keyecho
    puts "WM: key echo off"
}

