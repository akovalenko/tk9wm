# ---- place: the geometry a client is born with ----
# The style key `place` — a list of terms, comma OR whitespace
# separated, so both {30%bottom 50%right} and "30%bottom,50%right"
# read the same.
#
#   term  = [SIZE]EDGE
#   SIZE  = N%            (of the WORKAREA — the panel is never covered)
#   EDGE  = left|right|hcenter | top|bottom|vcenter | center
#
# The EDGE picks the axis as well as the alignment, which is what makes
# "50%right" say everything it needs to in seven characters. A term
# WITH a size sets both the size and the alignment on its axis; a term
# WITHOUT one keeps the window's own size and only pins it. `center` is
# shorthand for `hcenter vcenter`. Two terms on one axis: the later
# wins, the way a later style rule does.
#
# An axis NO term claims is FILLED — that is the rule that makes
# 50%right the right half at full height. Its flip side, worth knowing
# before it surprises: a lone `place right` is full height at the right
# edge, and "pin it, leave the size alone" is written with a term per
# axis ({right bottom}).
#
# `max` is the whole workarea — the same grammar's {100%left 100%top},
# spelled the way one thinks of it.
#
# Returns {haxis vaxis}, each {size align} with size "" for sizeless
# and align in start|end|center.
# `force` is a term of the spec and not a placement: it says this rule
# outranks the window's OWN claim on where it goes. Split out before
# anything reads the terms.
proc place-force {spec} {
    set terms {}
    set forced 0
    foreach term [split [string map {, " "} $spec]] {
        if {$term eq ""} continue
        if {$term eq "force"} { set forced 1; continue }
        lappend terms $term
    }
    list $terms $forced
}
proc parse-place {spec} {
    if {[string trim $spec] eq "max"} { set spec {100%left 100%top} }
    set ax [dict create]
    foreach term [split [string map {, " "} $spec]] {
        if {$term eq ""} continue
        if {![regexp {^(?:([0-9]+)%)?(left|right|hcenter|top|bottom|vcenter|center)$} \
                 $term -> size edge]} {
            error "place: cannot read term «$term»"
        }
        if {$edge eq "center"} {
            if {$size ne ""} { error "place: center takes no size" }
            dict set ax h [list "" center]
            dict set ax v [list "" center]
            continue
        }
        switch -- $edge {
            left    { dict set ax h [list $size start] }
            right   { dict set ax h [list $size end] }
            hcenter { dict set ax h [list $size center] }
            top     { dict set ax v [list $size start] }
            bottom  { dict set ax v [list $size end] }
            vcenter { dict set ax v [list $size center] }
        }
    }
    if {![dict size $ax]} { error "place: no terms" }
    # the unclaimed axis fills
    foreach a {h v} {
        if {![dict exists $ax $a]} { dict set ax $a {100 start} }
    }
    list [dict get $ax h] [dict get $ax v]
}

# The placement spelled out for one client: {cw ch X Y} — the CLIENT
# size and the FRAME position. The percentages are of the frame (what
# one sees), so the client size is what is left after the decoration;
# the size hints then bind it exactly as they bind maximize — which is
# to say the minimum does and the increments do NOT on the axes the
# rule SIZED: a term that says 50% means half the workarea to the
# pixel, the same tiling reading mutter gives its side-by-side halves,
# and an xterm placed 50%right pads its sub-cell remainder itself. A
# sizeless axis carries the client's own size, which is on its own
# grid already.
proc place-geometry {w cw ch spec} {
    lassign [workarea] wax way ww wh
    lassign [chrome-of $w] B top
    lassign [parse-place $spec] hax vax
    lassign $hax hsize halign
    lassign $vax vsize valign
    set fw [expr {$hsize eq "" ? $cw + 2*$B : $ww * $hsize / 100}]
    set fh [expr {$vsize eq "" ? $ch + $top + $B : $wh * $vsize / 100}]
    set sized {}
    if {$hsize ne ""} { lappend sized h }
    if {$vsize ne ""} { lappend sized v }
    lassign [apply-size-hints $w [expr {max($fw - 2*$B, 1)}] \
                                 [expr {max($fh - $top - $B, 1)}] $sized] cw ch
    set fw [expr {$cw + 2*$B}]
    set fh [expr {$ch + $top + $B}]
    list $cw $ch [place-axis $wax $ww $fw $halign] \
                 [place-axis $way $wh $fh $valign]
}
proc place-axis {origin extent size align} {
    switch -- $align {
        start  { return $origin }
        end    { return [expr {$origin + $extent - $size}] }
        center { return [expr {$origin + ($extent - $size) / 2}] }
    }
}

# The initial CLIENT size, the substrate's one question about a
# newcomer's geometry (it used to clamp by hand and ask the policy only
# for the ceiling — but a `place` needs an exact size, not a maximum,
# and the ceiling itself depends on how much decoration the style gave
# this window, which only the policy knows).
#
# A placement that cannot be read is LOGGED and dropped, not thrown:
# one bad line in a config must not cost the desk its ability to manage
# a window.
proc policy-initial-size {w cw ch} {
    lassign [client-min-size $w] minw minh
    lassign [policy-max-client-size $w] maxw maxh
    set cw [expr {max(min($cw, $maxw), $minw, 1)}]
    set ch [expr {max(min($ch, $maxh), $minh, 1)}]
    set st [style-of $w]
    set spec ""
    set forced 0
    set born [client-initial-maximized $w]   ;# the AXES asked for, {} if none
    if {[dict exists $st place]} {
        lassign [place-force [dict get $st place]] spec forced
        if {$forced} { set born {} }   ;# force means it — over the state too
    }
    if {[llength $born] == 1} {
        # Born maximized on ONE axis — the same pre-map road, but the
        # place language cannot say it (an axis no term claims is
        # FILLED), so the answer is assembled by hand: the held axis
        # takes the workarea, the free one keeps the client's own word,
        # and ::maxsaved keeps what the ordinary placement would have
        # made, exactly as the full case does through its spec.
        puts "WM: 0x[format %x $w] asks to be born maximized ($born)"
        lassign [chrome-of $w] B top
        lassign [place-frame $w [expr {$cw + 2*$B}] \
                                [expr {$ch + $top + $B}]] X0 Y0
        set ::maxsaved($w) [list $cw $ch $X0 $Y0]
        set ::maxaxes($w) $born
        lassign [workarea] wax way ww wh
        set X $X0; set Y $Y0
        if {"h" in $born} { set cw [expr {max($ww - 2*$B, $minw, 1)}]; set X $wax }
        if {"v" in $born} { set ch [expr {max($wh - $top - $B, $minh, 1)}]; set Y $way }
        lassign [apply-size-hints $w $cw $ch $born] cw ch
        set ::placeof($w) [list $X $Y]
        publish-net-wm-state $w   ;# born maximized is EWMH state too
        return [list $cw $ch]
    }
    if {[llength $born] && [dict exists $st place]} {
        # The client's own pre-map "start me maximized" outranks an
        # unforced rule — and its own USSize claim below: the two
        # client words contradict each other, and the state is the
        # later, stronger one. (A forced rule already won above: force
        # means it.)
        set spec max
        set forced 1
        puts "WM: 0x[format %x $w] asks to be born maximized\
 (over its style's place)"
    } elseif {[llength $born]} {
        # "Start me maximized", asked BEFORE the map — and honoring it
        # HERE is the point of the pre-map protocol: the window must
        # be framed at its maximized size the first time, not mapped
        # narrow and pulled wide a beat later. The cost of the beat is
        # real and measured on the owner's desk: telega.el began its
        # redraw at the narrow width and lagged switching over. The
        # request is the client's own word about THIS window, so it
        # does not yield to the -geometry dance below — it forces,
        # the way a rule that means it does; the asked-for geometry
        # is exactly what ::maxsaved keeps as the way back.
        set spec max
        set forced 1
        puts "WM: 0x[format %x $w] asks to be born maximized"
    }
    if {$spec eq ""} { return [list $cw $ch] }
    # A rule is the user speaking IN GENERAL; a `-geometry` is the same
    # user speaking about THIS window. The particular wins, so a place
    # YIELDS to it (the owner's call, 2026-07-30, reversing the day-old
    # rule that it beat everything: with `place max` as a standing
    # policy for half the desk, a rule that also overrode every
    # -geometry would leave no way to ask for anything else). `force`
    # in the spec is how a rule says it means it after all.
    #
    # It yields ASPECT BY ASPECT, because `-geometry` is two claims and
    # they are separately flagged: `xterm -geometry 20x20` sets USSize
    # and no USPosition at all, `+300+200` alone sets USPosition and no
    # USSize, and the full form sets both (measured, 2026-07-30). An
    # all-or-nothing yield read the first of those as no claim and
    # placed the window as if the size had never been asked for
    # (owner's report, same day). So:
    #
    #   the user said HOW BIG  -> the rule's sizes drop and its terms go
    #                             SIZELESS: it may still pull the window
    #                             to the edge it names, at the size that
    #                             was asked for
    #   the user said WHERE    -> the rule's position drops; it may still
    #                             say how big
    #   both                   -> the rule has nothing left to say
    #
    # USPosition/USSize only. The P forms — the program's own idea,
    # which it has for every window whether it thought about it or not —
    # are not a user's word and do not outrank a rule.
    set userpos [expr {[lindex [client-position-hint $w] 0] eq "user"}]
    set usersize [expr {[client-size-hint $w] eq "user"}]
    if {!$forced && ($userpos || $usersize)} {
        if {$userpos && $usersize} {
            puts "WM: place «$spec» on 0x[format %x $w] yields whole to its own\
 -geometry (say `force` to override)"
            return [list $cw $ch]
        }
        if {$usersize} {
            set spec [place-sizeless $spec]
            puts "WM: place on 0x[format %x $w] yields its sizes to the\
 window's own -geometry — «$spec»"
        } else {
            puts "WM: place «$spec» on 0x[format %x $w] yields its position to\
 the window's own -geometry"
        }
    }
    if {[catch {
        # `max` is the maximized STATE and not just a size: without a
        # saved geometry the first "restore" would restore to what the
        # window already is, and the toggle would be a dead key for the
        # rest of the window's life. What gets saved is what the window
        # would have been WITHOUT the style — its own size at the
        # position the ordinary placement would have given it, cascade
        # slot and all.
        if {[string trim $spec] eq "max"} {
            lassign [chrome-of $w] B top
            lassign [place-frame $w [expr {$cw + 2*$B}] \
                                    [expr {$ch + $top + $B}]] X0 Y0
            set ::maxsaved($w) [list $cw $ch $X0 $Y0]
            set ::maxaxes($w) {h v}
            publish-net-wm-state $w   ;# born maximized is EWMH state too
        }
        lassign [place-geometry $w $cw $ch $spec] pw ph X Y
    } err]} {
        puts "WM: place «$spec» on 0x[format %x $w]: $err"
        unset -nocomplain ::maxsaved($w) ::maxaxes($w)
        return [list $cw $ch]
    }
    # The position is the rule's only when the rule still owns it.
    if {$forced || !$userpos} {
        set ::placeof($w) [list $X $Y]
        puts "WM: place 0x[format %x $w] «$spec» -> ${pw}x${ph}+$X+$Y"
    } else {
        puts "WM: place 0x[format %x $w] «$spec» -> ${pw}x${ph}, at its own place"
    }
    list $pw $ph
}
# The same terms with their sizes taken off — what a place has left to
# say when the window itself asked how big to be. `max` is expanded
# first: as a size it is the whole workarea, and what survives of it
# sizeless is the corner it pins to.
proc place-sizeless {spec} {
    if {[string trim $spec] eq "max"} { set spec {100%left 100%top} }
    set terms {}
    foreach term [split [string map {, " "} $spec]] {
        if {$term eq ""} continue
        lappend terms [regsub {^[0-9]+%} $term ""]
    }
    return $terms
}

# Size hints applied the style's way: clamp to the declared minimum
# and maximum always; snap to the increment grid (from the PBaseSize
# origin) only when this client's style says respect. Every
# WM-initiated size decision (border/corner drag, maximize) funnels
# through here; the client's OWN ConfigureRequests are its business
# and stay untouched. `exempt` names the axes the grid does NOT bind
# (h, v) — see below; the maximum binds them anyway, which is what
# stops a maximize at a declared ceiling instead of the workarea.
proc apply-size-hints {w cw ch {exempt {}}} {
    lassign [client-size-hints $w] minw minh incw inch basew baseh maxw maxh
    # The ceiling first: the snap below only rounds DOWN, so a size
    # brought under the max stays under it. The min comes last of all —
    # on broken hints (max < min) the minimum wins.
    if {$maxw > 0} { set cw [expr {min($cw, $maxw)}] }
    if {$maxh > 0} { set ch [expr {min($ch, $maxh)}] }
    if {[dict get [style-of $w] increments] eq "respect"} {
        # ...except on an EXEMPT axis — one a maximize holds or a place
        # rule sized outright. The rule is mutter's, and every desktop's
        # by now: increments quantize the FREE resize, where a hand
        # wants whole cells and the readout says 80x24, but a maximized
        # axis fills its workarea to the pixel — a terminal paints the
        # sub-cell remainder as padding, which beats a strip of desk
        # showing through beside a "maximized" window. KWin has shipped
        # exactly this since 2004 ("the bug is in xterm after all");
        # fullscreen here always worked this way, so the precedent is
        # in-house too. The minimum still binds everywhere.
        if {"h" ni $exempt && $incw > 0 && $cw > $basew} {
            set cw [expr {$basew + ($cw - $basew) / $incw * $incw}]
        }
        if {"v" ni $exempt && $inch > 0 && $ch > $baseh} {
            set ch [expr {$baseh + ($ch - $baseh) / $inch * $inch}]
        }
    }
    list [expr {max($cw, $minw)}] [expr {max($ch, $minh)}]
}

# The client's claimed point, translated to FRAME coordinates per
# win_gravity (ICCCM 4.1.2.3). NorthWest — the default, and every
# gravity this WM does not model yet — aims the point at the frame's
# own top-left; Static (10) aims it at the client area, so the frame
# backs off by its decorations.
proc gravity-frame-xy {w x y grav} {
    if {$grav == 10} {
        lassign [chrome-of $w] B top
        return [list [expr {$x - $B}] [expr {$y - $top}]]
    }
    list $x $y
}

# Where to put a new frame (fw x fh, decoration included). Three rules,
# in order:
#
#  - a client that CLAIMS its position (USPosition/PPosition in
#    WM_NORMAL_HINTS, the geometry it mapped with) gets it: the user's
#    word (xterm -geometry, Tk wm geometry) is law and lands verbatim;
#    a program's word is clamped to the screen, and the notorious
#    program-said-(0,0) — toolkits stamping PPosition on a position
#    nobody chose — is ignored;
#  - a DIALOG (WM_TRANSIENT_FOR set, and we manage its parent) is centered
#    over its parent's frame — that is where the user is looking;
#  - everything else cascades.
#
# Then the result is CLAMPED to the screen, which the cascade alone never
# was: GIMP's "Quit" dialog landed at +1020+860 on a 1038-tall screen and
# its buttons ended up below the bottom edge, unclickable (live report,
# 2026-07-27). A window bigger than the screen is pinned at the top-left
# corner — better to lose the far edge than the near one.
# What a newcomer CLAIMED about where it goes, for the log. This is the
# input to every placement decision below and it is not observable from
# outside afterwards, which made a live question ("does this app set
# USPosition or not?") a matter of xprop-ing the right window at the
# right moment — and xprop on a tk9wm frame answers about the FRAME,
# which is a Tk toplevel and carries hints Tk put there (owner's desk,
# 2026-07-30). The WM knows; it should say.
#
# Gravity is part of the claim and not a footnote: Static means the
# point is where the CLIENT goes, so the frame backs off by its
# decoration, and NorthWest means it is the frame's own corner. Qt
# declares Static (measured on Qt Creator under fvwm3, 2026-07-30).
# Its own line, and only when there IS a claim: no claim is the
# ordinary case and would be noise, while a line of its own leaves
# every reader of the frame line (the regressions included) alone.
proc log-claim {w} {
    lassign [client-position-hint $w] kind grav
    if {$kind eq "none"} return
    set ipos [client-initial-position $w]
    set where [expr {[llength $ipos] == 2 \
        ? "+[lindex $ipos 0]+[lindex $ipos 1]" : "(position unread)"}]
    puts "WM: 0x[format %x $w] claims $where —\
[expr {$kind eq {user} ? {USPosition} : {PPosition}}],\
 gravity [expr {$grav == 10 ? {Static (the CLIENT's corner)} : $grav}]"
}
proc place-frame {w fw fh} {
    # frames are placed within the WORKAREA: a new window must not be
    # born with its bottom edge under the panel. Which is a RECTANGLE
    # and not a size — a panel on the left or the top moves the
    # workarea's ORIGIN, and a clamp that read the extent as the far
    # edge would put the window under exactly the strip it was meant to
    # keep clear.
    # A `place` style that got this far outranks everything below: it
    # either had `force`, or the window made no user claim to yield to
    # (policy-initial-size). The position itself was settled there,
    # with the size.
    if {[info exists ::placeof($w)]} { return $::placeof($w) }
    lassign [client-position-hint $w] kind grav
    set ipos [client-initial-position $w]
    if {$kind ne "none" && [llength $ipos] == 2} {
        lassign $ipos X Y
        if {$kind eq "user"} {
            # Honored as given — the position a user asked for is in
            # ROOT coordinates and means the screen, panels and all —
            # but clamped to the SCREEN, which is not a policy so much
            # as arithmetic about reachability: Qt Creator's main window
            # asks for +0-2 and arrives with its titlebar off the top
            # edge, which is nobody's intent (owner's desk, 2026-07-30).
            lassign [gravity-frame-xy $w $X $Y $grav] X Y
            return [clamp-to-screen $X $Y $fw $fh]
        }
        if {$X != 0 || $Y != 0} {
            lassign [gravity-frame-xy $w $X $Y $grav] X Y
            # the claim names a monitor too: clamp into the workarea
            # of the glass the claimed rect lands on
            return [clamp-to-rect [workarea-at [list $X $Y $fw $fh]] \
                        $X $Y $fw $fh]
        }
    }
    # The leader is READ at attach, and this proc now runs before that
    # too — policy-initial-size asks it what an un-styled window would
    # have got. A lookup is not the authority on the answer: no entry
    # yet simply means "no leader to center over".
    set parent [expr {[info exists ::leaderof($w)] ? $::leaderof($w) : 0}]
    if {$parent != 0 && [info exists ::frameof($parent)]} {
        set pt $::frameof($parent)
        if {[regexp {^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$} [wm geometry $pt] -> pw ph px py]} {
            set X [expr {$px + ($pw - $fw) / 2}]
            set Y [expr {$py + ($ph - $fh) / 2}]
            # the parent's monitor: a dialog for a window on the second
            # monitor must not be yanked across the desk by the clamp
            return [clamp-to-rect [workarea-at [list $X $Y $fw $fh]] \
                        $X $Y $fw $fh]
        }
    }
    return [cascade-slot $fw $fh]
}

# The cascade used to march forever (110 + 70*n, 80 + 60*n), so on a long
# session every new window walked further down-right until they landed
# fully off-screen (live report, 2026-07-27 — and it applies to ordinary
# windows, not just dialogs). Now the round RESTARTS with the very window
# that would not fit, so the offender itself lands at the top-left slot.
#
# The slots are counted from the workarea's own CORNER, not from the
# screen's: with a panel on the left or the top the two are different
# points, and a cascade that started at the screen's would deal its
# first window out under the strip.
proc cascade-slot {fw fh} {
    lassign [workarea] wax way ww wh
    set X [expr {$wax + 110 + 70*$::ncli}]
    set Y [expr {$way + 80 + 60*$::ncli}]
    if {$X + $fw > $wax + $ww || $Y + $fh > $way + $wh} {
        set ::ncli 0
        set X [expr {$wax + 110}]; set Y [expr {$way + 80}]
    }
    incr ::ncli
    return [clamp-to-workarea $X $Y $fw $fh]
}
# Both edges of both axes, and the NEAR one wins a window too big to
# fit: better to lose the far edge than the one with the title bar on
# it. The near edge is the workarea's origin — which is the panel's
# inner face when the panel is on the left or the top.
proc clamp-to-rect {rect X Y fw fh} {
    lassign $rect rx ry rw rh
    if {$X + $fw > $rx + $rw} { set X [expr {$rx + $rw - $fw}] }
    if {$Y + $fh > $ry + $rh} { set Y [expr {$ry + $rh - $fh}] }
    list [expr {max($X, $rx)}] [expr {max($Y, $ry)}]
}
proc clamp-to-workarea {X Y fw fh} { clamp-to-rect [workarea] $X $Y $fw $fh }
# ...and the screen's own rectangle, for the claim we honor but will
# not let off the edge: a user's position is about the SCREEN, so the
# workarea is the wrong box to hold it in — the panel is entitled to
# overlap a window that asked for the corner.
proc clamp-to-screen {X Y fw fh} {
    clamp-to-rect [list 0 0 {*}[screen-size]] $X $Y $fw $fh
}

# The biggest client area THIS window's frame can hold — an oversized
# newcomer is shrunk to it (never below the client's declared minimum)
# so no edge starts out unreachable. Window-specific because the
# decoration is: an undecorated frame has the whole workarea to give.
proc policy-max-client-size {w} {
    # the primary's workarea: a newcomer has no monitor until it is
    # placed, and placement deals to the primary (see workarea above)
    lassign [workarea] wax way sw sh
    lassign [chrome-of $w] B top
    list [expr {$sw - 2*$B}] [expr {$sh - $top - $B}]
}

# Build a decoration for client w (client area cw x ch): blue titlebar
# with a ✕, dark slot below; placement per place-frame above. Returns the
# slot's X window id; the Tk roundtrip before the return guarantees the
# slot exists server-side before the raw connection reparents into it.
proc policy-attach {w cw ch} {
    set t .f[incr ::fid]
    # How much frame this client wears is the style's call, and the
    # answer is pinned to the FRAME here: everything that lays it out
    # later (a resize, a font change, a grip hunt) has $t in hand and
    # not $w.
    set ::chromeof($t) [chrome-of $w]
    lassign $::chromeof($t) B top
    # WM_TRANSIENT_FOR is read NOW and kept: the refocus pick needs the
    # dialog's leader at a moment when the dialog may already be a dead
    # window that cannot be asked anything. A later property change
    # arrives through policy-transient below.
    set ::leaderof($w) [transient-for $w]
    lassign [place-frame $w [expr {$cw + 2*$B}] [expr {$ch + $top + $B}]] X Y
    toplevel $t -background [themed focus]
    wm overrideredirect $t 1   ;# frames must bypass our own redirect
    # Born WITHDRAWN, shown by frame-show once the client is seated
    # inside: the flush below used to map the frame right here — an
    # empty, focus-colored rectangle on the glass a beat before its
    # client arrived, one blink per window and a storm of them on a
    # restart (the owner, 2026-08-06). A window arriving minimized or
    # on another desk now never shows at all, where it used to flash
    # once before hiding. The withdrawn toplevel's children still get
    # their server-side windows (winfo id at the end), so the reparent
    # has its slot either way — measured, not assumed.
    wm withdraw $t
    # The decoration underlay: a canvas filling the whole frame, drawn
    # below every other child (created first — sibling stacking is
    # creation order). It paints the border background, the 1px outline
    # and the corner grips; being a child of $t it inherits the frame's
    # cursor and its events reach the rz-* handlers via the $t bindtag.
    canvas $t.deco -highlightthickness 0 -borderwidth 0 -background [themed focus]
    place $t.deco -x 0 -y 0 -relwidth 1 -relheight 1
    bind $t.deco <Configure> {deco-draw %W %w %h}
    titlebar-build $t $w [client-buttons $w] "client 0x[format %x $w]"
    frame $t.slot -width $cw -height $ch -background [themed slot]
    # Resize by the border: the border strips are the bare toplevel, and a
    # bind on a toplevel fires for its children too — so positions are
    # computed from ROOT coords (%x/%y would be child-relative there) and
    # rz-edge itself decides "not a border" for points inside children.
    # That also un-sticks the resize cursor when the pointer crosses onto
    # the title; crossing into the CLIENT (an X window Tk never hears
    # Motion from) is caught by <Leave> — X sends LeaveNotify with detail
    # Inferior when the pointer dives into a child.
    bind $t <Motion>          [list rz-hover $t $w %X %Y]
    bind $t <Leave>           [list rz-leave $t]
    bind $t <ButtonPress-1>   [list rz-start $t $w %X %Y]
    bind $t <B1-Motion>       [list rz-move  $t $w %X %Y]
    bind $t <ButtonRelease-1> [list press-end $t $w]
    frame-layout $t $cw $ch $X $Y
    update idletasks
    # Cross-connection ordering: a roundtrip on Tk's connection guarantees
    # the slot window exists server-side before the raw connection uses it.
    winfo pointerxy $t
    set ::frameof($w) $t
    log-claim $w
    # A line of its OWN, and the reason is worth the line: this frame
    # line is parsed by a dozen regressions, some for the +X+Y at its
    # tail and some for "for ID at" in its middle, so it has no free
    # space anywhere. Which buttons a frame wears is its own fact
    # anyway — and the first question asked of a window with no
    # minimize box.
    puts "WM: frame $t for 0x[format %x $w] at +$X+$Y"
    puts "WM: frame $t wears [frame-buttons $t]"
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

# EWMH _NET_FRAME_EXTENTS, {left right top bottom}. Our decoration is
# uniform — the same border on three sides, the title strip on top —
# so within one window the answer is three numbers, and it is asked of
# the STYLE rather than of the frame: a client asking BEFORE its first
# map (_NET_REQUEST_FRAME_EXTENTS — not managed yet, no frame to
# measure) is matched by the same predicates as a live one, and gets
# the same honest numbers it will actually be framed with.
proc policy-frame-extents {w} {
    lassign [chrome-of $w] B top
    list $B $B $top $B
}

proc policy-detach {w} {
    if {![info exists ::frameof($w)]} return
    # A keyboard move/resize on this very window dies with it — and the
    # key router has to be handed back HERE: kbmr-key only notices the
    # frame is gone on the next keystroke, and until one arrives every
    # key on the desk would go on feeding a mode with no victim.
    if {[kbmr-owns $w]} {
        set ::kbmr {}
        grab-keys-to {}
        compass-hide
        puts "WM: keyboard mode dropped — 0x[format %x $w] is gone"
    }
    # ...and the same for a mouse gesture in flight, for a sharper
    # reason: the pointer is GRABBED for its duration, and a grab left
    # standing over a dead window is a dead mouse for the whole desk.
    if {[info exists ::mdrag] && [lindex $::mdrag 2] == $w} {
        unset ::mdrag
        rz-end
        soft "release the pointer" { grab-pointer-to {} }
        puts "WM: mouse gesture dropped — 0x[format %x $w] is gone"
    }
    unset -nocomplain ::btn($::frameof($w)) ::fullframe($::frameof($w)) \
        ::chromeof($::frameof($w))
    ;# the frame's own, not the client's
    unset -nocomplain ::btncols($::frameof($w)) ::btnwof($::frameof($w)) \
        ::lookof($::frameof($w))
    destroy $::frameof($w)
    unset ::frameof($w)
    unset -nocomplain ::titleof($w) ::renameof($w)
    unset -nocomplain ::leaderof($w)
    unset -nocomplain ::placeof($w)
    unset -nocomplain ::maxsaved($w) ::maxaxes($w) ::fssaved($w)
    unset -nocomplain ::styleof($w) ::opacityof($w)
    set ::focus_hist [lsearch -exact -all -inline -not $::focus_hist $w]
    stack-drop $w        ;# out of the stacking model, layer and all
    unset -nocomplain ::deskof($w) ::offdesk($w)
    panel-match-kick
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

# The one place that knows where every part of a frame sits: title
# strip, close box, client slot, outer geometry — all derived from the
# frame's chrome (border, top, titleh). Called at attach (with an
# explicit position), on every resize, and when the metrics change
# under a live frame (set-title-font, set-border). Position defaults to
# "stay where you are".
proc frame-layout {t cw ch {X ""} {Y ""}} {
    lassign [frame-chrome $t] B top titleh
    # Fullscreen is a LAYOUT and nothing more, which is why it lives
    # here rather than as a second geometry path elsewhere: the client
    # takes the whole frame, the frame takes the whole screen at the
    # origin, and the title strip is un-placed so no expose can paint a
    # bar over the client's top row. Everything that re-lays a frame —
    # a resize, a font change, a config reload — then keeps the window
    # fullscreen without knowing that it is.
    if {[info exists ::fullframe($t)]} {
        place forget $t.title
        $t.slot configure -width $cw -height $ch
        place $t.slot -x 0 -y 0
        # at the MONITOR's origin, not the screen's: the callers that
        # know the monitor pass it, and everyone else (a font change,
        # a reload re-laying the frame) keeps the origin it stands at
        if {$X eq ""} { regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> X Y }
        wm geometry $t ${cw}x${ch}+${X}+${Y}
        return
    }
    if {$X eq ""} { regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> X Y }
    # A frame the style stripped of its title strip simply never places
    # it — the widget stays built (the title is still tracked, and the
    # window list wants it), it just has nowhere on screen to appear.
    if {$titleh > 0} {
        $t.title configure -itemheight $titleh
        # Which buttons this frame has is the frame's own business — a
        # client wears all three, a window the WM put up for itself
        # wears whatever it asked for. Same layout code either way.
        foreach name [frame-buttons $t] {
            $t.title column configure C$name -width [look [frame-look $t] btnw]
        }
        place $t.title -x $B -y $B -width $cw -height $titleh
    } else {
        place forget $t.title
    }
    $t.slot configure -width $cw -height $ch
    place $t.slot -x $B -y $top
    wm geometry $t [expr {$cw + 2*$B}]x[expr {$ch + $top + $B}]+$X+$Y
}

# The decoration follows the client's new size (position stays put).
proc policy-resize {w cw ch} {
    set t $::frameof($w)
    frame-layout $t $cw $ch
    update idletasks
    # A WINDOW THAT GREW MUST NOT GROW OFF THE DESK. The placement
    # clamp runs once, at birth, and a client that resizes ITSELF
    # afterwards was landing wherever its old origin plus its new
    # size reached — the configurator, grown by a refresh, ended up
    # with its bottom edge under the panel (the owner, 2026-08-01).
    # Only the ORIGIN is touched, and only inwards: a window bigger
    # than the workarea keeps its size and takes the workarea's
    # corner, which is the honest best a move can do. A fullscreen or
    # maximized window is exempt — its geometry is the state's.
    if {[info exists ::fullscreen($w)]} return
    if {![regexp {^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$} [wm geometry $t] \
            -> fw fh fx fy]} return
    lassign [clamp-to-rect [workarea-at [list $fx $fy $fw $fh]] \
                 $fx $fy $fw $fh] nx ny
    if {$nx != $fx || $ny != $fy} {
        wm geometry $t +$nx+$ny
        update idletasks
        puts "WM: 0x[format %x $w] grew past the workarea — moved to +$nx+$ny"
    }
}

# An honored move request: the client named a root position for its
# window and the substrate checked its claim (USPosition/PPosition);
# win_gravity says what the point aims at. A partial request (a lone
# CWX or CWY) keeps the frame's other coordinate. The synthetic
# ConfigureNotify follows from the ConfigureRequest handler — geometry
# must be settled before it fires, hence the update idletasks.
proc policy-move-request {w x y vmask grav} {
    if {![info exists ::frameof($w)]} return
    set t $::frameof($w)
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fx fy
    lassign [gravity-frame-xy $w $x $y $grav] x y
    if {!($vmask & 1)} { set x $fx }
    if {!($vmask & 2)} { set y $fy }
    if {$x == $fx && $y == $fy} return
    wm geometry $t +$x+$y
    update idletasks
    puts "WM: move 0x[format %x $w] -> +$x+$y (client request)"
}

# ---- the decoration underlay ----
# Border background (the canvas -background), a 1px dark outline around
# the perimeter, and fvwm-style corner grips in a lighter shade, cut
# off by thin dark lines — the visible promise that a corner drags
# diagonally. All four corners are L-shaped, arms one border thick and
# one gripz long, one measure top and bottom — both numbers from the
# frame's own chrome verdict. The arms press against what lives just
# inside the border: the client area at the bottom, a titlebar button
# at the top (flush in the strip's corner — see look-derive).
# rz-edge's corner zones are the same measure. Redrawn on <Configure>,
# recolored (via a full cheap redraw) by paint-focus.
proc deco-draw {c W H} {
    $c delete all
    lassign [frame-chrome [winfo parent $c]] B - - CZ
    # No border, nothing to draw — and nothing that MAY be drawn: the
    # client covers the whole frame, so even the 1px outline would be a
    # line under a window nobody sees.
    if {$B == 0} return
    set bg [$c cget -background]
    set grip [expr {[info exists ::gripof($bg)] ? $::gripof($bg) : $bg}]
    foreach {x0 y0 x1 y1} [list \
        0 0 $B $CZ                          0 0 $CZ $B \
        [expr {$W-$B}] 0 $W $CZ             [expr {$W-$CZ}] 0 $W $B \
        0 [expr {$H-$CZ}] $B $H             0 [expr {$H-$B}] $CZ $H \
        [expr {$W-$B}] [expr {$H-$CZ}] $W $H \
        [expr {$W-$CZ}] [expr {$H-$B}] $W $H] {
        $c create rectangle $x0 $y0 $x1 $y1 -fill $grip -outline "" -tags grip
    }
    foreach {x0 y0 x1 y1} [list \
        0 $CZ $B $CZ                        $CZ 0 $CZ $B \
        [expr {$W-$B}] $CZ $W $CZ           [expr {$W-$CZ}] 0 [expr {$W-$CZ}] $B \
        0 [expr {$H-$CZ}] $B [expr {$H-$CZ}]        $CZ [expr {$H-$B}] $CZ $H \
        [expr {$W-$B}] [expr {$H-$CZ}] $W [expr {$H-$CZ}] \
        [expr {$W-$CZ}] [expr {$H-$B}] [expr {$W-$CZ}] $H] {
        $c create line $x0 $y0 $x1 $y1 -fill $::OUTLINE
    }
    $c create rectangle 0 0 [expr {$W-1}] [expr {$H-1}] \
        -outline $::OUTLINE -fill ""
}
# ...and the repaint a knob owes when only the DRAWING moved (a grips
# change): the canvas already knows its size, nothing re-lays out.
proc deco-redraw {t} {
    if {[winfo exists $t.deco]} {
        deco-draw $t.deco [winfo width $t.deco] [winfo height $t.deco]
    }
}

# ---- resize by the border / corner ----
# Which resize grip is under frame-relative (x, y)? All four strips
# are one border thick (the top used to be a 2px sliver — unhittable;
# uniform since 2026-07-28). The corner-zone ends of the strips act
# as diagonal corners, one gripz at every corner — the same measures
# deco-draw advertises, from the same chrome verdict.
proc rz-edge {t x y} {
    set W [winfo width $t]; set H [winfo height $t]
    lassign [frame-chrome $t] B - - CZ
    if {$B == 0} { return "" }   ;# no border, no grip: nothing to grab
    if {($y < $B && $x < $CZ) || ($x < $B && $y < $CZ)} { return nw }
    if {($y < $B && $x >= $W - $CZ) || ($x >= $W - $B && $y < $CZ)} { return ne }
    if {$y < $B} { return n }
    if {$x >= $W - $B || $x < $B || $y >= $H - $B} {
        if {$y >= $H - $CZ && $x >= $W - $CZ} { return se }
        if {$y >= $H - $CZ && $x < $CZ}       { return sw }
        if {$y >= $H - $B} { return s }
        if {$x < $B}       { return w }
        return e
    }
    return ""
}
# Which cursor an edge wears — the hover over a border grip and the
# modifier-resize gesture show the same one, so the table is one table.
# A fixed-size window's border wears the CARRY cursor over every grip
# instead: what a grab there does is move (see rz-start), and a corner
# cursor would advertise a resize nobody is offering.
array set rzcursor {e right_side w left_side s bottom_side n top_side
    se bottom_right_corner sw bottom_left_corner
    ne top_right_corner nw top_left_corner}
proc rz-hover {t w X Y} {
    set e [rz-edge $t [expr {$X - [winfo rootx $t]}] \
                      [expr {$Y - [winfo rooty $t]}]]
    if {$e ne "" && [client-fixed-size-p $w]} {
        $t configure -cursor fleur
        return
    }
    $t configure -cursor [expr {$e eq "" ? "" : $::rzcursor($e)}]
}
proc rz-leave {t} {
    if {![info exists ::rz]} { $t configure -cursor "" }
}
proc rz-start {t w X Y} {
    set e [rz-edge $t [expr {$X - [winfo rootx $t]}] \
                      [expr {$Y - [winfo rooty $t]}]]
    if {$e eq ""} return
    # A window that declared itself non-resizable (min == max) has no
    # resize to offer, but its border is still a handle: the grab
    # CARRIES the window instead — the title's own machinery, marked so
    # rz-move knows to route the motion there. Dropping the press
    # outright would make the border the one dead spot on the frame.
    if {[client-fixed-size-p $w]} {
        set ::rzcarry($t) 1
        drag-start $t $w $X $Y
        return
    }
    popups-close
    raise-group $w
    focus-to $w
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fx fy
    # The window comes LAST because rz-move's lassign reads the first
    # seven and would have to be re-counted otherwise; it is there for
    # the benefit of anyone asking "whose geometry is a hand holding"
    # (geometry-held-p).
    set ::rz [list $e $X $Y [winfo width $t.slot] [winfo height $t.slot] $fx $fy $w]
}
proc rz-move {t w X Y} {
    # The border carry of a fixed-size window (rz-start above). The
    # mark, not bare ::drag($t), is the router: the toplevel's bindtag
    # fires for the TITLE's motion too, and a title drag already feeds
    # drag-move through its own binding — routing on the drag state
    # alone would deliver every such motion twice.
    if {[info exists ::rzcarry($t)]} { drag-move $t $w $X $Y; return }
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
        n  { incr ch [expr {-$dy}] }
        ne { incr cw $dx; incr ch [expr {-$dy}] }
        nw { incr cw [expr {-$dx}]; incr ch [expr {-$dy}] }
    }
    resize-by-edge $w $e $cw $ch $cw0 $ch0 $fx $fy
}
# A resize BY ONE EDGE, which is what both resizes are: the pointer
# drag above and the keyboard mode's arrows once the compass gave them
# a handle. cw0/ch0/fx/fy are what the far edge is measured from — the
# geometry the gesture started on for the mouse, the current one for a
# keyboard step, since each step is its own little drag.
#
# The client's size hints bind HERE, not only in wm-resize-client: the
# west/north anchoring moves the frame by the size delta, and a size
# clamped (or snapped to increments) later than the move would tear the
# dragged edge off the pointer. 40x30 is our own floor — a frame must
# stay big enough to grab.
proc resize-by-edge {w e cw ch cw0 ch0 fx fy} {
    set t $::frameof($w)
    lassign [apply-size-hints $w $cw $ch] cw ch
    set cw [expr {max($cw, 40)}]; set ch [expr {max($ch, 30)}]
    # dragging the west/north edge: the frame moves so the opposite
    # edge stays put
    set nx $fx; set ny $fy
    if {$e in {w sw nw}} { set nx [expr {$fx + $cw0 - $cw}] }
    if {$e in {n ne nw}} { set ny [expr {$fy + $ch0 - $ch}] }
    if {$nx != $fx || $ny != $fy} { wm geometry $t +$nx+$ny }
    # Both interactive resizes funnel through here — the pointer drag
    # and the keyboard arrows — which makes it the one place the
    # maximized mark can be shed by hand, and the only way the two can
    # not disagree about it. A drag that changed NOTHING (pushed against
    # the minimum, say) is not a resize and shed nothing. Shedding is BY
    # AXIS: pulling a tall window's side edge says nothing about its
    # height, so only the axes the hand actually changed drop off the
    # mark — the rest of the state stands, shield and all.
    if {$::maximize eq "drop" && [info exists ::maxsaved($w)]} {
        set shed {}
        if {$cw != $cw0 && "h" in $::maxaxes($w)} { lappend shed h }
        if {$ch != $ch0 && "v" in $::maxaxes($w)} { lappend shed v }
        if {[llength $shed]} {
            set keep {}
            foreach a $::maxaxes($w) { if {$a ni $shed} { lappend keep $a } }
            if {[llength $keep]} {
                set ::maxaxes($w) $keep
                puts "WM: 0x[format %x $w] resized by hand — the mark\
 sheds $shed"
            } else {
                unset ::maxsaved($w) ::maxaxes($w)
                puts "WM: 0x[format %x $w] resized by hand — no longer\
 maximized"
            }
            publish-net-wm-state $w
        }
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
proc press-end {t w} {
    rz-end
    unset -nocomplain ::drag($t) ::rzcarry($t)
    $t.title configure -cursor ""   ;# the carry cursor ends with the carry
    soft "re-hover after a press" { rz-hover $t $w {*}[winfo pointerxy $t] }
}

# A client that named nothing is shown by its id — on the titlebar and
# in the window menu alike.
proc title-or-id {w title} {
    expr {$title eq "" ? "client 0x[format %x $w]" : $title}
}

# The client named (or renamed) itself: put the title on the titlebar.
# The treectrl item is always 1 — a fresh widget per frame, the single
# item created right after it. The title is REMEMBERED as well: a
# keyboard move/resize borrows the bar for its geometry readout, and
# what goes back on the bar afterwards has to come from somewhere —
# and a client that renames itself mid-mode must not shove the readout
# aside, it just updates what will be restored.
#
# ::titleof holds the CLIENT's words, raw — the invariant every layer
# above leans on: filters match it, %t expands to it, the kbmr restore
# feeds it back through here. What the bar SHOWS is visible-title
# (10-look) — the rename and style layers speak between the client
# and the paint.
proc policy-title {w title} {
    if {![info exists ::frameof($w)]} return
    set ::titleof($w) $title
    set shown [visible-title $w]
    if {![kbmr-owns $w]} {
        $::frameof($w).title item element configure 1 C0 eTxt \
            -text [title-or-id $w $shown]
    }
    # _NET_WM_VISIBLE_NAME stands on the client only while the desk
    # shows something OTHER than the client's own words (the EWMH
    # rule): pagers read it in preference to _NET_WM_NAME, and one
    # left behind would freeze a title the desk no longer says. Soft:
    # the property lives on a foreign window, and a client can die
    # between the event and this write.
    if {[info exists ::NET_WM_VISIBLE_NAME]} {
        soft "publish _NET_WM_VISIBLE_NAME" {
            if {$shown ne $title} {
                set-prop-utf8 $w $::NET_WM_VISIBLE_NAME $shown
            } else {
                x-prop-delete $w $::NET_WM_VISIBLE_NAME
            }
        }
    }
    panel-match-kick   ;# a title flip can turn a -title matcher around
}
# Repaint what the desk says for $w without the client having spoken:
# the style rules were re-read, a rename came or went. One caller's
# convenience, policy-title's rules.
proc retitle {w} {
    if {[info exists ::titleof($w)]} { policy-title $w $::titleof($w) }
}

# The substrate re-read WM_TRANSIENT_FOR after a PropertyNotify: a
# client may aim its dialog at a leader (or away from one) after
# mapping. The stored leader feeds raise-group, lower-group and the
# refocus pick from here on; placement is a manage-time decision and
# is deliberately not redone.
proc policy-transient {w leader} {
    if {![info exists ::frameof($w)]} return
    if {$leader == $w} { set leader 0 }   ;# self-transient is no leader
    set ::leaderof($w) $leader
}

# Focus highlight: active frame blue, inactive grey. Every honest focus
# change lands here (server-confirmed focus-to, and focus moved behind
# our back) — which makes it the one place to keep the focus history.
# STICKY HAS TO LOOK LIKE SOMETHING. A window on every desk is
# otherwise indistinguishable from a window on this one, and the state
# is easy to set by accident. fvwm's answer is a TEXTURE on the title,
# and treectrl can do it exactly: an image element takes `-tiled yes`
# and a style is per column, so the title column can carry a pattern
# under its text and nothing else has to know.
#
# The hatch LOOKS like translucent white — a fifth of white over the
# strip's colour — but the image is OPAQUE: the blend is folded in
# right here, once per colour, and the cell carries ground and line as
# plain pixels. A photo with live alpha cannot be blitted without
# asking the server what is under it — fetch, blend, put back, a round
# trip PER TILE, and the hatch painted as a visible sweep (the owner,
# 2026-08-12). An opaque cell is a one-way XCopyArea the server
# pipelines, so the 8x8 cell — whose layout innocence months have
# proved — can stay 8x8. (A screen-wide translucent tile was tried
# instead and failed twice over: drawn solid white somewhere down
# Tk's fallback paths, and its natural size shoved the title text
# sideways.) The price of opacity is a cell per strip colour — blue,
# grey, amber — built on first sight and cached; frame-recolor swaps
# the worn one when the strip changes.
proc sticky-hatch {bg} {
    if {[info exists ::stickyhatch($bg)]} { return $::stickyhatch($bg) }
    set n 8
    set img [image create photo]
    $img put $bg -to 0 0 $n $n
    # the line: a fifth of white folded into the ground — what the
    # server's own blend of #ffffff36 would have made of it. Solid
    # white was tried first and read as a fence across the title.
    lassign [winfo rgb . $bg] r g b
    set a [expr {0x36 / 255.0}]
    set line [format "#%04x%04x%04x" \
        [expr {round($r + (65535 - $r) * $a)}] \
        [expr {round($g + (65535 - $g) * $a)}] \
        [expr {round($b + (65535 - $b) * $a)}]]
    for {set i 0} {$i < $n} {incr i} {
        $img put $line -to $i $i [expr {$i + 1}] [expr {$i + 1}]
    }
    set ::stickyhatch($bg) $img
    return $img
}
proc frame-recolor {t bg} {
    $t configure -background $bg
    $t.deco configure -background $bg
    deco-redraw $t
    $t.title configure -background $bg
    # ...and the ARMED button with it. A pressed button used to fill
    # with the desk's ground, which on a light theme is nearly white
    # under a white glyph — the button vanished exactly while the
    # finger was on it (the owner, 2026-08-04). The titlebar stays dark
    # in both themes and its glyphs are white, so the honest press is
    # the strip's own colour PUSHED IN: same hue, darker, white glyph
    # still legible. Set here because the strip's colour is the frame's
    # and moves with focus.
    catch {$t.title element configure eBox \
        -fill [list [shade $bg 0.65] pressed {} {}]}
    # ...and the sticky hatch: its blend is baked per colour (see
    # sticky-hatch), so the strip that changes colour changes cells.
    catch {$t.title element configure eHatch \
        -image [list [sticky-hatch $bg] sticky {} {}]}
}
# A colour of the same hue, DARKER — what a pressed thing looks like.
# f is what survives of it: 0.65 is a press one can see without the
# glyph losing its ground.
proc shade {colour f} {
    lassign [winfo rgb . $colour] r g b
    format "#%04x%04x%04x" [expr {int($r * $f)}] [expr {int($g * $f)}] \
        [expr {int($b * $f)}]
}
proc frame-focus-color {w} {
    if {[kbmr-owns $w]} { return $::KBMR_BG }   ;# the mode outranks focus
    expr {$w == $::focused ? [themed focus] : [themed unfocus]}
}
# The desk changed under everything: the furniture that counts windows
# has a different set to count now, and the strips re-judge their
# matches. The windows themselves were mapped and unmapped by the
# substrate — visibility is its half — so nothing here moves anything.
# The title wears what the window IS: called wherever a window's own
# desk can change (the substrate's desk-send), and once at framing.
proc frame-sticky-paint {w} {
    if {![info exists ::frameof($w)]} return
    set t $::frameof($w)
    if {![winfo exists $t.title]} return
    catch {$t.title item state forcolumn 1 C0 \
        [expr {[desk-sticky-p $w] ? "sticky" : "!sticky"}]}
}
proc policy-window-desk-changed {w} { frame-sticky-paint $w }
proc policy-desk-changed {was now} {
    panel-match-kick
    restack-soon
    if {[llength [info commands widgets-tick-all]]} { widgets-tick-all }
}
proc policy-paint-focus {w} {
    set ::focus_hist [linsert \
        [lsearch -exact -all -inline -not $::focus_hist $w] 0 $w]
    foreach {ww tt} [array get ::frameof] {
        frame-recolor $tt [frame-focus-color $ww]
    }
    # The top layer belongs to the ACTIVE fullscreen window, so it has
    # to be re-judged whenever the focus moves — and the focus moves
    # without any raise of ours often enough to matter: a window
    # closing hands it on, and a globally-active client answers its
    # invitation a beat after the raise that invited it. On a desk with
    # nothing fullscreen the question does not arise, so it costs
    # nothing to ask.
    if {[array size ::fullscreen]} { restack-soon }
    ask-focus-note $w
}

# ---- fade: how solid a window is ----
#
# A frame's translucency is one property on the frame,
# _NET_WM_WINDOW_OPACITY, which a COMPOSITOR reads and applies; Tk
# spells it `wm attributes -alpha` and puts it on the toplevel's
# wrapper — the very window a compositor composites (tkUnixWm.c:1289).
# So it changes ON THE FLY: set the property on a mapped window and the
# next frame the compositor draws is the new one. No unmap, no remap,
# nothing recreated — measured, not assumed (run-fade-test.sh watches
# the server's own event stream across the change and insists there is
# no map in it).
#
# What CANNOT be done on the fly is the other kind of transparency:
# per-pixel alpha needs a 32-bit ARGB visual, and a window's visual is
# chosen when it is created and never after — the tray's own backdrop
# already lives with that (set-tray-argb). Uniform opacity has no such
# problem, and uniform opacity is what a frame wants.
#
# With no compositor running the property is simply ignored by
# everybody: nothing breaks, nothing fades. That is the compositor's
# half of the bargain, not ours.
keep fade 0.8
# The value a client rests at when nothing has faded it — its style's,
# and solid unless a rule says otherwise.
proc rest-opacity {w} {
    set st [style-of $w]
    if {[dict exists $st opacity]} { return [dict get $st opacity] }
    return 1.0
}
proc frame-opacity {w a} {
    if {![info exists ::frameof($w)]} return
    wm attributes $::frameof($w) -alpha $a
    set ::opacityof($w) $a
    puts "WM: opacity 0x[format %x $w] -> $a"
}
proc window-opacity {w} {
    expr {[info exists ::opacityof($w)] ? $::opacityof($w) : [rest-opacity $w]}
}
# A USER toggles and a PROGRAM does not — the same rule Maximize lives
# by, and for the same reason: `Apply-To-Matching always Fade` means
# make this desk faded, not flip every window and see what happens.
proc fade-command {w} {
    if {[interactive-p] && [window-opacity $w] != [rest-opacity $w]} {
        unfade-command $w
    } else {
        frame-opacity $w $::fade
    }
}
proc unfade-command {w} { frame-opacity $w [rest-opacity $w] }
# At map time, so a style that asks for it is answered before the
# window is ever seen solid. Nothing to do in the common case.
proc apply-opacity {w} {
    set a [rest-opacity $w]
    if {$a != 1.0} { frame-opacity $w $a }
}

# ---- minimize: honored, or refused out loud ----
# What to do when a client asks to be iconified (ICCCM WM_CHANGE_STATE
# — Tk's `wm iconify`, wine's Win32 minimize). Two answers, and the
# knob picks which; there is deliberately no third answer "ignore it",
# because that is the one that misleads: the asking side may have
# minimized on its own account already, and a window left on screen
# with its client convinced it is hidden stops painting (owner's
# report on wine, 2026-07-28).
#
#   iconify (default) — do it: the window goes off screen, its entry in
#     the window list stays and carries the mark, and picking it there
#     (or the panel button that matches it, or the client mapping
#     itself) brings it back.
#   refuse — this desk has no minimize. The refusal is stated to the
#     client (see refuse-iconify) rather than swallowed, so an app that
#     already minimized itself internally is told to come back.
# The desk-wide default; a `minimize` style key overrides it per client
# (wm-style, same predicates as everything else). That per-client escape
# hatch earns its keep on wine: a wine window that goes through a real
# iconify round trip comes back with its Win32 side activated but its
# INNER focus lost, so keystrokes reach the top-level window instead of
# the control that had them — the app answers menu mnemonics and eats
# text (owner's report on whale.exe/smsrc, 2026-07-28; reproduced here
# with notepad, and it reproduces under fvwm3 just as well, so the
# defect is wine's, not the WM's). Until wine grows out of it, the
# honest answer for those windows is to refuse minimize rather than
# hand back a half-dead window:
#   wm-style {filter -class {*.exe *.exe}} {minimize refuse}
keep minimize iconify
proc minimize-mode {w} {
    set st [style-of $w]
    if {[dict exists $st minimize]} { return [dict get $st minimize] }
    return $::minimize
}
proc policy-minimize-request {w} {
    if {[minimize-mode $w] eq "refuse"} { refuse-iconify $w } else {
        iconify-client $w
    }
}

# ---- start: the state a window is BORN in ----
# The style key `start` — iconic|fullscreen|normal. The two words are
# the config's spelling of what a client may ask about itself (WM_HINTS
# initial_state = IconicState; _NET_WM_STATE_FULLSCREEN set before the
# map) — for the world's clients that have no flag to say it: an xterm
# has -iconic and -fullscreen, most programs have neither. `normal`
# says nothing, which is what a later rule needs to cancel an earlier
# one (later rules win per-key). The substrate asks at manage time and
# ORs the answer with the client's own voice; a `minimize refuse` style
# still overrules a `start iconic`, exactly as it overrules the client
# asking — the standing word is judged where the request lands
# (policy-minimize-request), whoever raised it.
proc policy-start-state {w} {
    set st [style-of $w]
    if {![dict exists $st start]} { return "" }
    set v [dict get $st start]
    switch -- $v {
        iconic - fullscreen { return $v }
        normal { return "" }
    }
    puts "WM: start «$v» on 0x[format %x $w]: iconic|fullscreen|normal — ignored"
    return ""
}
proc policy-iconified {w} {
    if {![info exists ::frameof($w)]} return
    wm withdraw $::frameof($w)
    panel-match-kick   ;# a button's live-match count just changed
}
proc policy-deiconified {w} {
    if {![info exists ::frameof($w)]} return
    wm deiconify $::frameof($w)
    raise-group $w
    # Flush Tk's connection before the substrate maps the client on ITS
    # connection: the client lives inside this frame, and a child of an
    # unmapped parent is not viewable — the focus that follows would be
    # refused by the server ("focus REFUSED ... will retry" showed up
    # after every restore until this line).
    update idletasks
    panel-match-kick
}
# THE DESK SWITCH'S OWN SHOW AND HIDE, and they are not the iconify
# pair with a different name — the difference is the whole cure for the
# flicker (the owner, 2026-08-04: "видно как они поочерёдно мапятся
# одно на другом").
#
# What made it visible was three things per window, none of them wrong
# on its own: Tk's `wm deiconify` WAITS for the MapNotify (tkUnixWm.c,
# WaitForMapNotify), policy-deiconified raises the window it restores —
# right when a hand asked for THAT window, wrong for ten of them at
# once — and the flush that follows lands the restack. Ten windows,
# ten round trips, ten reorderings, each one on the glass.
#
# So the desk switch says only "be on the screen" and orders the
# arrivals ITSELF: topmost first, each next one seated under the one
# before it. What the eye gets is the window one is about to use,
# covering the desk, and the rest sliding in behind it — and the model
# already knew that order, so nothing is being decided here twice.
proc policy-desk-hide {w} {
    if {![info exists ::frameof($w)]} return
    wm withdraw $::frameof($w)
}
proc policy-desk-show {w} {
    if {![info exists ::frameof($w)]} return
    wm deiconify $::frameof($w)
}
# ...seated under the one that came before — a relative restack, so
# the arriving window never passes in front of what is already up.
proc policy-desk-under {w prev} {
    if {$prev eq "" || ![info exists ::frameof($w)]
            || ![info exists ::frameof($prev)]} return
    lower $::frameof($w) $::frameof($prev)
}
# The model's own stacking, TOPMOST FIRST, narrowed to these windows.
proc policy-desk-order {wins} {
    set order {}
    foreach w [client-stacking] {
        if {[lsearch -exact $wins $w] >= 0} { lappend order $w }
    }
    return [lreverse $order]
}

# The window list is the way back, so an iconic window must be
# recognizable in it. The mark is the title in SQUARE BRACKETS — the
# way twm and fvwm have shown an iconified entry since the eighties.
# It was a word once ("(свёрнуто)"), which was worse twice over: the
# only piece of prose in a list that is otherwise nothing but client
# titles, and one that had to be translated to travel. Brackets are
# read the same in every language, and they cost two columns instead
# of eleven — in a list whose width is the widest title, that is the
# difference between a mark and a shove.
proc iconic-label {w title} {
    expr {[info exists ::iconic($w)] ? "\[$title\]" : $title}
}

# The wink: a client is not answering its WM_DELETE_WINDOW — pulse the
# frame red a couple of times so the silence is visible. Each pulse
# step re-derives the resting color: the focus may move mid-wink, and
# the frame must settle on the color it then deserves.
proc policy-close-unanswered {w} {
    if {![info exists ::frameof($w)]} return
    puts "WM: wink 0x[format %x $w] — client is silent"
    wink-frame $w 3   ;# odd first = start red: red/rest/red/rest
}
proc wink-frame {w n} {
    if {![info exists ::frameof($w)]} return
    frame-recolor $::frameof($w) \
        [expr {$n % 2 ? [themed alert] : [frame-focus-color $w]}]
    if {$n > 0} { after 160 [list wink-frame $w [expr {$n - 1}]] }
}

# Raise the whole transient group of w: the touched member on top of
# its siblings, transients always above their leader (fvwm ships this
# glue as RaiseTransient + StackTransientParent, both on by default).
# One level deep, like fvwm's own redirect recursion.
#
# One ABSOLUTE raise — the group's top member — then every other
# member is stacked BELOW its upper neighbor with sibling-relative
# restacks. The first cut raised the leader to the very top and then
# raised each transient over it: every click into a dialog flashed
# the leader above it for a frame (live report: Tk widget demo,
# File→About — About blinks under the main window on every click).
# Relative restacks never lift the leader, and when the order is
# already right each one is a server-side no-op — so "re-raise when
# all is well" costs nothing visible either.
#
# Who the group belongs to, and who is in it: the same two questions
# every group gesture starts with, asked in one place. A window with a
# live leader belongs to that leader's group; anything else leads its
# own. Only members with a FRAME count — a dead transient is nobody's
# business.
proc group-leader {w} {
    if {[info exists ::leaderof($w)] && $::leaderof($w) != 0
            && [info exists ::frameof($::leaderof($w))]} {
        return $::leaderof($w)
    }
    return $w
}
proc group-members {leader} {
    set members {}
    foreach {c l} [array get ::leaderof] {
        if {$l == $leader && $c != $leader && [info exists ::frameof($c)]} {
            lappend members $c
        }
    }
    return $members
}
