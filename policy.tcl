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
# Border width, all four sides. 6px is a resize GRIP, not just a
# line: the old 2px border left nothing to grab. The top strip above
# the titlebar was 2px for a while (top resize worked but was
# unhittable); the owner asked for grips uniform with the bottom
# (2026-07-28), so the strip is a full border now.
set border 6

# Titlebar typography. TitleFont is OUR named font: it starts as a copy
# of TkDefaultFont, TK9WM_TITLE_FONT overrides it at startup (any Tk
# font spec, e.g. "DejaVu Sans 12"), and set-title-font re-points it
# live. Every vertical measure of the decoration derives from its
# metrics — a 22px strip that was roomy at 96 dpi was visibly too tight
# for the same font at Xft.dpi 144 (live report, 2026-07-27).
font create TitleFont {*}[font actual TkDefaultFont]
if {[info exists ::env(TK9WM_TITLE_FONT)] && $::env(TK9WM_TITLE_FONT) ne ""} {
    if {[catch {font configure TitleFont {*}[font actual $::env(TK9WM_TITLE_FONT)]} err]} {
        puts "WM: TK9WM_TITLE_FONT «$::env(TK9WM_TITLE_FONT)» rejected: $err"
    }
}
# The pseudo-icon lettering (see winlist-icon): TitleFont's family, but
# bold and sized in PIXELS to the badge, not the text line — configured
# at each winlist open, when the badge size is known. The panel keeps
# its own instance: its badge size (panel-icon-size) is independent of
# the winlist row, and the two would fight over one font.
font create IconFont -weight bold
font create PanelIconFont -weight bold
# 3px of air above and below the text line; the strip sits under the
# full top border (a real grip, uniform with the bottom), a 2px gap
# separates it from the client slot.
proc title-metrics {} {
    set ::titleh [expr {[font metrics TitleFont -linespace] + 6}]
    set ::decotop [expr {$::border + $::titleh + 2}]
    btn-images
    puts "WM: titlebar h=$::titleh top=$::decotop\
 font=[font actual TitleFont -family]/[font actual TitleFont -size]"
}

# Titlebar buttons, fvwm-style (the owner's frame as the model): a thin
# white outlined square holding a thin white glyph, drawn flat on the
# titlebar color. The glyphs are svg — re-rendered crisp at whatever
# size the font dictates, never scaled bitmaps.
# Frame colors: the focus highlight pair, the matching lighter shade
# for the corner grips, and the constant dark outline that keeps two
# touching frames readable as two windows (before it, several inactive
# titlebars fused into one gray field).
set OUTLINE #2e3436
array set gripof {#3465a4 #6b93c0 #888a85 #a5a7a1}

set SVG_CLOSE {<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
<path d="M3.5 3.5 L12.5 12.5 M12.5 3.5 L3.5 12.5" stroke="#ffffff"
 stroke-width="1.6" stroke-linecap="round" fill="none"/></svg>}
set SVG_MAX {<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
<rect x="3.5" y="3.5" width="9" height="9" stroke="#ffffff"
 stroke-width="1.6" fill="none"/></svg>}
set SVG_MENU {<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
<rect x="3.5" y="6.5" width="9" height="3" stroke="#ffffff"
 stroke-width="1.6" fill="none"/></svg>}
proc btn-images {} {
    # re-creating a photo under the same name updates every user of it
    set g [expr {max($::titleh - 14, 7)}]
    image create photo imgClose -format [list svg -scaletoheight $g] \
        -data $::SVG_CLOSE
    image create photo imgMax -format [list svg -scaletoheight $g] \
        -data $::SVG_MAX
    image create photo imgMenu -format [list svg -scaletoheight $g] \
        -data $::SVG_MENU
}
title-metrics

# Re-derive the metrics and re-lay-out every live frame (same client
# sizes, new strip height); each client then learns its new origin —
# the slot moved inside the frame. The knob for a live font change:
proc set-title-font {args} {
    font configure TitleFont {*}$args
    retitle-frames
}
proc retitle-frames {} {
    title-metrics
    panel-build   ;# the strip height follows the font too
    foreach {w t} [array get ::frameof] {
        frame-layout $t [$t.slot cget -width] [$t.slot cget -height]
    }
    update idletasks
    foreach {w t} [array get ::frameof] { send-synthetic-configure $w }
}
# a ttk theme switch would change TkDefaultFont-derived looks the same
# way; today the only real trigger is set-title-font
bind . <<ThemeChanged>> retitle-frames

# Title alignment knob. The flags feed the text element's -expand in
# the titlebar style: where the layout may ADD space decides where the
# text ends up (ns = left, extra space east+west = centered).
set titlejust left
array set justflags {left ns center wens right wns}
proc set-title-justify {j} {
    if {![info exists ::justflags($j)]} {
        error "set-title-justify: left, center or right"
    }
    set ::titlejust $j
    foreach {w t} [array get ::frameof] {
        $t.title style layout sTitle eTxt -expand $::justflags($j)
    }
}

# ---- per-client style: predicates pick the settings ----
# A rule is {predicate settings}: the predicate is any command prefix
# called with the client window id, truth applies the settings dict.
# ALL matching rules apply, later rules win per-key — order in the
# config is the precedence (the fvwm Style-line convention). Evaluated
# once per client on first need and cached; the substrate's identity
# accessors (client-class, client-machine, client-cmdline, ...) are the
# predicate's vocabulary, so "WM_CLIENT_MACHINE is X and it runs
# /usr/bin/xterm, whatever the title" is a couple of calls — richer
# than a name-pattern string. A predicate that errors is skipped, not
# fatal: one bad config rule must not take styling down with it.
#
# Keys so far: increments (respect|ignore) — WM_NORMAL_HINTS resize
# increments; the default respects them (the world's xterms expect
# integral columns), the owner's config ignores them by taste.
# icon (anything resolve-icon takes: a Tk image name, a file path, a
# bare NAME searched as NAME.png through icon-path) — shown for the
# window in the window list, overriding the client's own _NET_WM_ICON.
set style_rules {}
proc always {w} { return 1 }
proc wm-style {pred settings} {
    lappend ::style_rules [list $pred $settings]
}
proc style-of {w} {
    if {[info exists ::styleof($w)]} { return $::styleof($w) }
    set st [dict create increments respect]
    foreach rule $::style_rules {
        lassign $rule pred settings
        if {[catch {uplevel #0 [list {*}$pred $w]} match]} {
            puts "WM: style predicate error on 0x[format %x $w]: $match"
        } elseif {$match} {
            set st [dict merge $st $settings]
        }
    }
    set ::styleof($w) $st
}

# ---- filter — the declarative match predicate ----
# The workhorse for every match place (wm-style rules, panel-button
# match): a command prefix, the call site appends the window id.
#
#   filter ?-regexp? ?-title PAT? ?-class PAT|{PAT PAT}? \
#       ?-command PAT? ?-machine PAT?
#
# The options AND together; an absent property fails its option — no
# errors, no match. Patterns are globs (string match), whole-string,
# always case-insensitive: the world's WM_CLASS capitalization drifts
# (Firefox vs firefox). -regexp swaps the comparator for regexp —
# unanchored, still nocase, and (?c) inside the pattern turns
# sensitivity back on; alternation covers the OR nobody builds
# combinators for. -class with a single pattern matches EITHER of
# {instance class} — for when you remember the distinctive token but
# not its slot; two patterns are positional, exactly as xprop prints
# the property. -command matches WM_COMMAND joined with spaces and
# falls back to the local client's /proc argv (client-cmdline) when
# the property is absent. A proc predicate stays the escape hatch for
# anything richer.
proc filter {args} {
    set w [lindex $args end]
    set opts [lrange $args 0 end-1]
    set pairs {}
    set cmp {string match -nocase}
    while {[llength $opts]} {
        set opt [lindex $opts 0]
        if {$opt eq "-regexp"} {
            set cmp {regexp -nocase --}
            set opts [lrange $opts 1 end]
            continue
        }
        if {[llength $opts] < 2} { error "filter: $opt wants a pattern" }
        lappend pairs $opt [lindex $opts 1]
        set opts [lrange $opts 2 end]
    }
    foreach {opt pat} $pairs {
        switch -- $opt {
            -class {
                lassign [client-class $w] inst cls
                if {$inst eq "" && $cls eq ""} { return 0 }
                switch -- [llength $pat] {
                    1 { if {![{*}$cmp $pat $inst] && ![{*}$cmp $pat $cls]} {
                            return 0
                    } }
                    2 { lassign $pat pi pc
                        if {![{*}$cmp $pi $inst] || ![{*}$cmp $pc $cls]} {
                            return 0
                    } }
                    default { error "filter -class: one or two patterns" }
                }
            }
            -title - -machine - -command {
                switch -- $opt {
                    -title   { set val [client-title $w] }
                    -machine { set val [client-machine $w] }
                    -command {
                        set c [client-command $w]
                        if {![llength $c]} { set c [client-cmdline $w] }
                        set val [join $c " "]
                    }
                }
                if {$val eq "" || ![{*}$cmp $pat $val]} { return 0 }
            }
            default { error "filter: unknown option $opt" }
        }
    }
    return 1
}

# Size hints applied the style's way: clamp to the declared minimum
# always; snap to the increment grid (from the PBaseSize origin) only
# when this client's style says respect. Every WM-initiated size
# decision (border/corner drag, maximize) funnels through here; the
# client's OWN ConfigureRequests are its business and stay untouched.
proc apply-size-hints {w cw ch} {
    lassign [client-size-hints $w] minw minh incw inch basew baseh
    if {[dict get [style-of $w] increments] eq "respect"} {
        if {$incw > 0 && $cw > $basew} {
            set cw [expr {$basew + ($cw - $basew) / $incw * $incw}]
        }
        if {$inch > 0 && $ch > $baseh} {
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
proc gravity-frame-xy {x y grav} {
    if {$grav == 10} {
        return [list [expr {$x - $::border}] [expr {$y - $::decotop}]]
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
proc place-frame {w fw fh} {
    # frames are placed within the WORKAREA: a new window must not be
    # born with its bottom edge under the panel
    lassign [workarea] wax way sw sh
    lassign [client-position-hint $w] kind grav
    set ipos [client-initial-position $w]
    if {$kind ne "none" && [llength $ipos] == 2} {
        lassign $ipos X Y
        if {$kind eq "user"} {
            return [gravity-frame-xy $X $Y $grav]
        }
        if {$X != 0 || $Y != 0} {
            lassign [gravity-frame-xy $X $Y $grav] X Y
            return [clamp-to-screen $X $Y $fw $fh $sw $sh]
        }
    }
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
    lassign [workarea] wax way sw sh
    set B $::border
    list [expr {$sw - 2*$B}] [expr {$sh - $::decotop - $B}]
}

# Build a decoration for client w (client area cw x ch): blue titlebar
# with a ✕, dark slot below; placement per place-frame above. Returns the
# slot's X window id; the Tk roundtrip before the return guarantees the
# slot exists server-side before the raw connection reparents into it.
proc policy-attach {w cw ch} {
    set t .f[incr ::fid]
    set B $::border
    # WM_TRANSIENT_FOR is read NOW and kept: the refocus pick needs the
    # dialog's leader at a moment when the dialog may already be a dead
    # window that cannot be asked anything. A later property change
    # arrives through policy-transient below.
    set ::leaderof($w) [transient-for $w]
    lassign [place-frame $w [expr {$cw + 2*$B}] [expr {$ch + $::decotop + $B}]] X Y
    toplevel $t -background #3465a4
    wm overrideredirect $t 1   ;# frames must bypass our own redirect
    # The decoration underlay: a canvas filling the whole frame, drawn
    # below every other child (created first — sibling stacking is
    # creation order). It paints the border background, the 1px outline
    # and the corner grips; being a child of $t it inherits the frame's
    # cursor and its events reach the rz-* handlers via the $t bindtag.
    canvas $t.deco -highlightthickness 0 -borderwidth 0 -background #3465a4
    place $t.deco -x 0 -y 0 -relwidth 1 -relheight 1
    bind $t.deco <Configure> {deco-draw %W %w %h}
    # The titlebar is a treectrl (a one-item one): the title text in an
    # expanding column whose -squeeze x text element ellipsizes what does
    # not fit, then two fixed button columns — maximize and close — each
    # a stateful outlined square (rect element) around an svg glyph.
    treectrl $t.title -showheader no -showroot no -showbuttons no \
        -showlines no -borderwidth 0 -highlightthickness 0 \
        -background #3465a4 -itemheight $::titleh
    # class binds stripped (a dumb label, not a tree) — but the FRAME's
    # tag stays: press-end must hear a ButtonRelease that happens over
    # the title, or the drag state outlives the drag (the rz-* handlers
    # riding along are harmless — they compute from root coords and see
    # "not a border" here).
    bindtags $t.title [list $t.title $t all]
    $t.title state define pressed   ;# armed by a press; release-inside fires
    $t.title column create -width $::titleh -tags Cmenu
    $t.title column create -squeeze yes -expand yes -tags C0
    $t.title column create -width $::titleh -tags Cmax
    $t.title column create -width $::titleh -tags Cclose
    $t.title configure -treecolumn C0
    $t.title element create eTxt text -fill white -lines 1 -font TitleFont
    $t.title element create eBox rect -outline white -outlinewidth 1 \
        -fill [list #2e3436 pressed {} {}]
    $t.title element create eMenu image -image imgMenu
    $t.title element create eMax image -image imgMax
    $t.title element create eClose image -image imgClose
    $t.title style create sTitle
    $t.title style elements sTitle eTxt
    $t.title style layout sTitle eTxt -expand $::justflags($::titlejust) \
        -padx 4 -squeeze x
    foreach {st el} {sMenu eMenu sMax eMax sClose eClose} {
        $t.title style create $st
        $t.title style elements $st [list eBox $el]
        $t.title style layout $st eBox -union $el -ipadx 3 -ipady 3 -expand ns
        $t.title style layout $st $el -expand ns
    }
    set item [$t.title item create]   ;# always item 1 in a fresh widget
    $t.title item style set $item \
        Cmenu sMenu C0 sTitle Cmax sMax Cclose sClose
    $t.title item element configure $item C0 eTxt \
        -text "клиент 0x[format %x $w]"
    $t.title item lastchild root $item
    frame $t.slot -width $cw -height $ch -background #202020
    bind $t.title <ButtonPress-1>   [list title-press   $t $w %x %y %X %Y]
    bind $t.title <B1-Motion>       [list title-motion  $t $w %x %y %X %Y]
    bind $t.title <ButtonRelease-1> [list title-release $t $w %x %y]
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
    frame-layout $t $cw $ch $X $Y
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
    unset -nocomplain ::btn($::frameof($w))
    destroy $::frameof($w)
    unset ::frameof($w)
    unset -nocomplain ::leaderof($w)
    unset -nocomplain ::maxsaved($w)
    unset -nocomplain ::styleof($w)
    set ::focus_hist [lsearch -exact -all -inline -not $::focus_hist $w]
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
# border width and the font-driven ::titleh/::decotop. Called at attach
# (with an explicit position), on every resize, and when the metrics
# change under a live frame (set-title-font). Position defaults to
# "stay where you are".
proc frame-layout {t cw ch {X ""} {Y ""}} {
    set B $::border
    if {$X eq ""} { regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> X Y }
    $t.title configure -itemheight $::titleh
    $t.title column configure Cmenu -width $::titleh
    $t.title column configure Cmax -width $::titleh
    $t.title column configure Cclose -width $::titleh
    place $t.title -x $B -y $B -width $cw -height $::titleh
    $t.slot configure -width $cw -height $ch
    place $t.slot -x $B -y $::decotop
    wm geometry $t [expr {$cw + 2*$B}]x[expr {$ch + $::decotop + $B}]+$X+$Y
}

# The decoration follows the client's new size (position stays put).
proc policy-resize {w cw ch} {
    frame-layout $::frameof($w) $cw $ch
    update idletasks
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
    lassign [gravity-frame-xy $x $y $grav] x y
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
# diagonally. All four corners are L-shaped (arms $::border wide,
# length = the corner zone rz-edge uses) — the top strip is a full
# border since the owner asked for uniform grips, so the horizontal
# arms fit up there too. Redrawn on <Configure>, recolored (via a
# full cheap redraw) by paint-focus.
proc deco-draw {c W H} {
    $c delete all
    set B $::border; set CZ 24
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

# ---- resize by the border / corner ----
# Which resize grip is under frame-relative (x, y)? All four strips
# are $::border thick (the top used to be a 2px sliver — unhittable;
# uniform since 2026-07-28), and the 24px corner-zone ends of the
# strips act as diagonal corners.
proc rz-edge {t x y} {
    set W [winfo width $t]; set H [winfo height $t]
    set B $::border; set CZ 24
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
proc rz-hover {t X Y} {
    array set cur {e right_side w left_side s bottom_side n top_side
        se bottom_right_corner sw bottom_left_corner
        ne top_right_corner nw top_left_corner}
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
    popups-close
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
        n  { incr ch [expr {-$dy}] }
        ne { incr cw $dx; incr ch [expr {-$dy}] }
        nw { incr cw [expr {-$dx}]; incr ch [expr {-$dy}] }
    }
    # The client's size hints bind HERE, not only in wm-resize-client:
    # the left/top anchoring below moves the frame by the size delta,
    # and a size clamped (or snapped to increments) later than the move
    # would tear the dragged edge off the pointer. 40x30 is our own
    # floor — a frame must stay big enough to grab.
    lassign [apply-size-hints $w $cw $ch] cw ch
    set cw [expr {max($cw, 40)}]; set ch [expr {max($ch, 30)}]
    # dragging the left/top edge: the frame moves so the opposite edge
    # stays put
    set nx $fx; set ny $fy
    if {$e in {w sw nw}} { set nx [expr {$fx + $cw0 - $cw}] }
    if {$e in {n ne nw}} { set ny [expr {$fy + $ch0 - $ch}] }
    if {$nx != $fx || $ny != $fy} { wm geometry $t +$nx+$ny }
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

# A client that named nothing is shown by its id — on the titlebar and
# in the window menu alike.
proc title-or-id {w title} {
    expr {$title eq "" ? "клиент 0x[format %x $w]" : $title}
}

# The client named (or renamed) itself: put the title on the titlebar.
# The treectrl item is always 1 — a fresh widget per frame, the single
# item created right after it.
proc policy-title {w title} {
    if {![info exists ::frameof($w)]} return
    set t $::frameof($w)
    $t.title item element configure 1 C0 eTxt -text [title-or-id $w $title]
    panel-match-kick   ;# a title flip can turn a -title matcher around
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
proc frame-recolor {t bg} {
    $t configure -background $bg
    $t.deco configure -background $bg
    deco-draw $t.deco [winfo width $t.deco] [winfo height $t.deco]
    $t.title configure -background $bg
}
proc frame-focus-color {w} {
    expr {$w == $::focused ? "#3465a4" : "#888a85"}
}
proc policy-paint-focus {w} {
    set ::focus_hist [linsert \
        [lsearch -exact -all -inline -not $::focus_hist $w] 0 $w]
    foreach {ww tt} [array get ::frameof] {
        frame-recolor $tt [frame-focus-color $ww]
    }
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
        [expr {$n % 2 ? "#cc4444" : [frame-focus-color $w]}]
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
proc raise-group {w} {
    set leader $w
    if {[info exists ::leaderof($w)] && $::leaderof($w) != 0
            && [info exists ::frameof($::leaderof($w))]} {
        set leader $::leaderof($w)
    }
    # top-to-bottom: the touched transient (never the leader — its
    # transients stay above it), the remaining transients, the leader
    set order {}
    if {$w != $leader} { lappend order $w }
    foreach {c l} [array get ::leaderof] {
        if {$l == $leader && $c != $w && [info exists ::frameof($c)]} {
            lappend order $c
        }
    }
    lappend order $leader
    raise $::frameof([lindex $order 0])
    for {set i 1} {$i < [llength $order]} {incr i} {
        lower $::frameof([lindex $order $i]) \
              $::frameof([lindex $order [expr {$i - 1}]])
    }
    panel-on-top
}

# Lower the whole transient group of w — the mirror image, same glue,
# same relative restacks (the ops menu's "lower" is the first lower
# gesture this WM has): one absolute lower — the leader, straight to
# the floor — and every transient re-seated right above it, keeping
# the group's internal order at the bottom of the stack.
proc lower-group {w} {
    if {![info exists ::frameof($w)]} return
    set leader $w
    if {[info exists ::leaderof($w)] && $::leaderof($w) != 0
            && [info exists ::frameof($::leaderof($w))]} {
        set leader $::leaderof($w)
    }
    lower $::frameof($leader)
    foreach {c l} [array get ::leaderof] {
        if {$l == $leader && [info exists ::frameof($c)]} {
            raise $::frameof($c) $::frameof($leader)
        }
    }
}

# Click-to-focus: a click inside a client's body raises and focuses it.
# focus-to is called UNCONDITIONALLY — the old "skip if ::focused is
# already w" guard turned a single refused XSetInputFocus into a
# permanent wedge (clicks stopped repairing the focus, the keyboard kept
# going to the previous window). One roundtrip per click is the price of
# a click path that always heals.
proc policy-client-click {w} {
    popups-close
    raise-group $w
    focus-to $w
}

# A newly managed window is raised with its group — a fresh dialog pulls
# its leader up right under itself, fvwm-style — and gets the focus.
proc policy-managed {w} {
    raise-group $w
    focus-to $w
    panel-match-kick
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

# ---- titlebar dispatch: buttons vs the drag ----
# One press lands on the titlebar treectrl; identify says whether it hit
# a button column. A button press arms that button (pressed state on its
# column only — forcolumn); the action fires on release-inside, classic
# button semantics, so a drag-away cancels. Anything else is the title
# drag.
proc title-button {T x y} {
    if {[catch {$T identify -array A $x $y}]} { return "" }
    if {$A(where) ne "item" || $A(column) eq ""} { return "" }
    foreach tag {Cmenu Cmax Cclose} {
        if {[$T column compare $A(column) == $tag]} { return $tag }
    }
    return ""
}
proc title-press {t w x y X Y} {
    set b [title-button $t.title $x $y]
    if {$b eq ""} { drag-start $t $w $X $Y; return }
    popups-close
    set ::btn($t) $b
    $t.title item state forcolumn 1 $b pressed
}
proc title-motion {t w x y X Y} {
    if {![info exists ::btn($t)]} { drag-move $t $w $X $Y; return }
    set on [expr {[title-button $t.title $x $y] eq $::btn($t)}]
    $t.title item state forcolumn 1 $::btn($t) \
        [expr {$on ? "pressed" : "!pressed"}]
}
proc title-release {t w x y} {
    if {![info exists ::btn($t)]} return
    set b $::btn($t)
    unset ::btn($t)
    $t.title item state forcolumn 1 $b !pressed
    if {[title-button $t.title $x $y] eq $b} {
        switch -- $b {
            Cclose { close-client $w }
            Cmax   { maximize-toggle $w }
            Cmenu  { winops $w }
        }
    }
}

# ---- maximize, fvwm semantics ----
# The workarea: where maximize expands to and where new frames are
# placed — the screen minus the panel's strip along its panel-side
# edge (zero when no buttons are declared, see the panel section).
proc workarea {} {
    lassign [screen-size] sw sh
    if {$::panel_side eq "right"} {
        list 0 0 [expr {$sw - [panel-thickness]}] $sh
    } else {
        list 0 0 $sw [expr {$sh - [panel-thickness]}]
    }
}

# Maximize fills the workarea and remembers what the window was; the
# second toggle restores it. "Maximized" is a saved-geometry flag, not
# a straitjacket: the window can be resized and moved freely meanwhile
# (fvwm semantics, not Windows) — the toggle still restores the
# geometry saved at maximize time.
proc maximize-toggle {w} {
    if {![info exists ::frameof($w)]} return
    set t $::frameof($w)
    set B $::border
    if {[info exists ::maxsaved($w)]} {
        lassign $::maxsaved($w) cw ch X Y
        unset ::maxsaved($w)
        wm geometry $t +$X+$Y
        wm-resize-client $w $cw $ch
    } else {
        regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> X Y
        set ::maxsaved($w) \
            [list [$t.slot cget -width] [$t.slot cget -height] $X $Y]
        lassign [workarea] wx wy ww wh
        wm geometry $t +$wx+$wy
        # increments bind maximize too (an xterm fills to whole cells,
        # slack stays at the workarea edge) — unless styled away
        wm-resize-client $w {*}[apply-size-hints $w \
            [expr {$ww - 2*$B}] [expr {$wh - $::decotop - $B}]]
    }
    # wm-resize-client skips a no-op resize and tells the client nothing
    # then — but the frame MOVED either way, so state the origin once
    # more, from settled Tk geometry.
    update idletasks
    send-synthetic-configure $w
}

# ---- popup menus: the shared shell ----
# One pattern for both menus: an override-redirect toplevel (our own
# redirect leaves those alone) holding a treectrl, driven
# keyboard-modally through the substrate's grab-keys-to router — the
# Tk focus path cannot serve an override-redirect window (see
# grab-keys-to) — while the pointer stays free: a click on an item
# picks it, a click anywhere else does its normal job and closes the
# popup on the way (the popups-close calls in the click paths).
proc popup-shell {m ih} {
    popups-close
    toplevel $m -background $::OUTLINE
    wm overrideredirect $m 1
    treectrl $m.t -showheader no -showroot no -showbuttons no \
        -showlines no -borderwidth 0 -highlightthickness 0 \
        -background #555753 -itemheight $ih
    bindtags $m.t [list $m.t all]
    $m.t element create eSel rect -fill [list #3465a4 selected {} {}]
    $m.t element create eTxt text -fill white -lines 1 -font TitleFont
    return $m.t
}
proc popup-show {m W H X Y} {
    lassign [screen-size] sw sh
    set X [expr {max(0, min($X, $sw - $W))}]
    set Y [expr {max(0, min($Y, $sh - $H))}]
    place $m.t -x 1 -y 1 -width [expr {$W - 2}] -height [expr {$H - 2}]
    wm geometry $m ${W}x${H}+$X+$Y
    raise $m
    update idletasks
}
# Close whatever popup is open. Every click path calls this as "close
# if open"; the router is released only when a popup actually owns it —
# a bare grab-keys-to {} here would abort an unrelated key sequence.
proc popups-close {} {
    foreach m {.winlist .winops} {
        if {[winfo exists $m]} {
            grab-keys-to {}
            destroy $m
        }
    }
}
# Popup navigation keys (the owner's spec): arrows always; vi (k/j)
# and emacs (p/n) letters on a BARE press — a bare letter that is some
# item's hotkey never reaches here, the hotkey matched first; Ctrl+P /
# Ctrl+N run the menu unconditionally, hotkeys or not. Returns -1/1
# for up/down, 0 = not a navigation key.
proc popup-nav {name mods} {
    if {$mods & 4} {
        switch -- $name { p { return -1 } n { return 1 } }
        return 0
    }
    if {$mods != 0} { return 0 }
    switch -- $name {
        Up - k - p   { return -1 }
        Down - j - n { return 1 }
    }
    return 0
}
proc popup-move {T n d} {
    set cur [lindex [$T selection get] 0]
    if {$cur eq ""} { set cur 1 }
    set i [expr {($cur - 1 + $d + $n) % $n + 1}]
    $T selection clear
    $T selection add $i
}

# ---- the window list (alt-tab) ----
# Every managed window, most-recently-focused first (never-focused
# ones trail behind), centered on the screen; the initial selection
# sits on the SECOND entry — the first is the window the user is
# leaving — so a bare Enter (or a released Alt) toggles to the
# previous window. Entries are numbered 1-9/A-Z and the number is the
# entry's hotkey — in cycle mode pressed WITH the held modifier
# (releasing it would commit), in the static menu bare, like any menu
# hotkey; either way it picks immediately.
#
# The fvwm alt-tab semantics come as a MODE the list enters when the
# invoking chord's modifier is still physically held at open (the Alt
# of Alt+Tab; asked of the server via modifier-held — a release that
# beat our grab is invisible to us, so the one-roundtrip check can
# only degrade to the static menu, never hang): further Tab presses
# run the selection with wraparound (Shift+Tab backwards), releasing
# the modifier commits. A quick full Alt+Tab press-release is then the
# classic toggle — commit lands on the previous window. Invoked with
# nothing held (the Super-sequence ends fully released) the list is a
# static menu. set-winlist-cycle off disables the mode entirely.
set winlist_cycle_opt 1
proc set-winlist-cycle {onoff} {
    set ::winlist_cycle_opt [expr {$onoff in {on 1 yes true}}]
}

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
set icon_path [list ~/.local/share/icons/hicolor/48x48/apps \
    /usr/share/icons/hicolor/48x48/apps /usr/share/pixmaps]
proc set-icon-path {dirs} { set ::icon_path $dirs }
proc resolve-icon {spec size} {
    if {$spec in [image names]} { return $spec }
    set key [list $spec $size]
    if {[info exists ::resolvedicon($key)]} { return $::resolvedicon($key) }
    # Tcl 9 dropped implicit ~ expansion — expand at use time, so a
    # config-supplied ~ path works too
    set path ""
    if {[string match */* $spec] || [string match ~* $spec]
            || [string match -nocase *.png $spec]} {
        set path [file tildeexpand $spec]
    } else {
        foreach dir $::icon_path {
            set p [file join [file tildeexpand $dir] $spec.png]
            if {[file exists $p]} { set path $p; break }
        }
    }
    set img ""
    if {$path eq ""} {
        puts "WM: icon «$spec»: no Tk image, no $spec.png in icon-path"
    } elseif {[catch {image create photo -file [file normalize $path]} img]} {
        puts "WM: icon «$spec»: $img"
        set img ""
    } else {
        set img [shrink-photo $img $size]
        puts "WM: icon «$spec»: [file tail $path]\
 [image width $img]x[image height $img]"
    }
    set ::resolvedicon($key) $img
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
    if {$name eq ""} { set name [title-or-id $w [client-title $w]] }
    list pseudo {*}[pseudo-badge $name]
}

proc winlist {} {
    set wins {}
    foreach w $::focus_hist {
        if {[info exists ::frameof($w)]} { lappend wins $w }
    }
    foreach w [array names ::frameof] {
        if {$w ni $wins} { lappend wins $w }
    }
    if {![llength $wins]} { puts "WM: winlist: no windows"; return }
    winlist-open $wins center
}
# The list itself, reusable: winlist passes every window and centers;
# a panel button's arrow zone passes its matches and anchors the
# popup by the button. The anchor is "center" or {panel I}; only the
# centered full list may enter cycle mode and preselects the SECOND
# entry (the toggle) — an anchored filtered list is a plain chooser,
# most recent first.
proc winlist-open {wins anchor} {
    set ::winlist_wins $wins
    set ::winlist_prev $::focused
    set ::winlist_cycle 0
    if {$anchor eq "center" && $::winlist_cycle_opt && $::key_invoke_mods != 0
            && [modifier-held $::key_invoke_mods]} {
        set ::winlist_cycle $::key_invoke_mods
    }
    # Every entry is numbered, and the number IS its hotkey: 1-9, then
    # A-Z; a 36th window simply gets no hotkey. The digit column sits
    # on the left — a numbered list reads that way.
    set ::winlist_keys {}
    foreach w $wins {
        set i [llength $::winlist_keys]
        if {$i < 9} {
            lappend ::winlist_keys [expr {$i + 1}]
        } elseif {$i < 35} {
            lappend ::winlist_keys [format %c [expr {65 + $i - 9}]]
        } else {
            lappend ::winlist_keys ""
        }
    }
    set ih [expr {[font metrics TitleFont -linespace] + 6}]
    set numw [expr {[font measure TitleFont W] + 14}]
    # the icon cell: a square a hair under the row, the lettering sized
    # to the badge in pixels (IconFont, see its creation)
    set sq [expr {$ih - 4}]
    font configure IconFont -family [font actual TitleFont -family] \
        -size -[expr {max(7, $sq * 5 / 8)}]
    set iconw [expr {$ih + 6}]
    set T [popup-shell .winlist $ih]
    $T column create -width $numw -tags Cnum
    $T column create -width $iconw -tags Cicon
    $T column create -squeeze yes -expand yes -tags C0
    $T configure -treecolumn C0
    $T element create eNum text -fill #babdb6 -lines 1 -font TitleFont
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
        set title [title-or-id $w [client-title $w]]
        set maxw [expr {max($maxw, [font measure TitleFont $title])}]
        set item [$T item create]
        $T item style set $item Cnum sNum C0 sWin
        $T item element configure $item Cnum eNum -text $key
        $T item element configure $item C0 eTxt -text $title
        lassign [winlist-icon $w $sq] kind a b
        if {$kind eq "image"} {
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
    $T selection add [expr {$anchor eq "center" && [llength $wins] > 1 ? 2 : 1}]
    bind $T <ButtonPress-1> {winlist-click %x %y}
    lassign [screen-size] sw sh
    set W [expr {min(max($maxw + $numw + $iconw + 28, 200), $sw * 3 / 5)}]
    set H [expr {[llength $wins] * $ih + 2}]
    if {$anchor eq "center"} {
        set X [expr {($sw - $W) / 2}]
        set Y [expr {($sh - $H) / 3}]
    } else {
        # by the button: over a bottom strip, beside a right one
        # (popup-show clamps to the screen either way)
        lassign [.panel.t item bbox [expr {[lindex $anchor 1] + 1}]] bx by
        if {$::panel_side eq "right"} {
            set X [expr {[winfo x .panel] - $W}]
            set Y [expr {[winfo rooty .panel.t] + $by}]
        } else {
            set X [expr {[winfo rootx .panel.t] + $bx}]
            set Y [expr {[winfo y .panel] - $H}]
        }
    }
    popup-show .winlist $W $H $X $Y
    if {![grab-keys-to winlist-key]} {
        puts "WM: winlist: keyboard not grabbed — mouse only"
    }
    puts "WM: winlist open ([llength $wins] windows[expr {
        $::winlist_cycle ? ", cycle" : ""}])"
}
proc winlist-key {kind name mods} {
    if {$kind eq "release"} {
        # cycle mode commits when the invoking chord's modifier is no
        # longer held; re-asking the server covers both-Alts pedantry
        if {$::winlist_cycle != 0 && ![modifier-held $::winlist_cycle]} {
            winlist-pick
        }
        return
    }
    # In cycle mode the held chord modifier is TRANSPARENT: it cannot
    # be released without committing, so Alt+3, Alt+j, Alt+Up must
    # work as 3, j, Up — strip it and dispatch as in the static menu.
    if {$::winlist_cycle != 0} { set mods [expr {$mods & ~$::winlist_cycle}] }
    if {$name eq "Tab"} {
        winlist-move [expr {$mods & 1 ? -1 : 1}]
        return
    }
    if {$mods == 0 && [string length $name] == 1} {
        set i [lsearch -exact $::winlist_keys [string toupper $name]]
        if {$i >= 0} {
            .winlist.t selection clear
            .winlist.t selection add [expr {$i + 1}]
            winlist-pick
            return
        }
    }
    set d [popup-nav $name $mods]
    if {$d != 0} { winlist-move $d; return }
    switch -- $name {
        Return - KP_Enter { winlist-pick }
        Escape            { winlist-cancel }
    }
}
proc winlist-move {d} {
    popup-move .winlist.t [llength $::winlist_wins] $d
}
proc winlist-pick {} {
    set cur [lindex [.winlist.t selection get] 0]
    set w [lindex $::winlist_wins [expr {$cur - 1}]]
    popups-close
    if {$w ne "" && [info exists ::frameof($w)]} {
        puts "WM: winlist pick 0x[format %x $w]"
        raise-group $w
        focus-to $w
    }
}
proc winlist-click {x y} {
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

# ---- the window ops menu ----
# Actions on ONE window — the fvwm-style dropdown: from the titlebar's
# left button, or on the focused window by key. Anchored at the
# window's top-left corner, right below the titlebar. Every action
# carries a hotkey letter (shown right-aligned, fvwm menus underline
# theirs — a column reads better in a treectrl); a bare letter press
# fires it, and the navigation letters yield to hotkeys while
# Ctrl+P/Ctrl+N always navigate (popup-nav).
set winops_actions {
    maximize x {maximize-toggle $w}
    close    c {close-client $w}
    destroy  d {kill-client $w}
    raise    r {raise-group $w}
    lower    l {lower-group $w}
    move     m {move-keyboard $w}
    resize   s {resize-keyboard $w}
}
proc winops {{w 0}} {
    if {$w == 0} { set w $::focused }
    if {$w == 0 || ![info exists ::frameof($w)]} {
        popups-close
        puts "WM: winops: no window"
        return
    }
    set ::winops_win $w
    set n [expr {[llength $::winops_actions] / 3}]
    set ih [expr {[font metrics TitleFont -linespace] + 6}]
    set T [popup-shell .winops $ih]
    $T column create -squeeze yes -expand yes -tags C0
    $T column create -width [expr {$ih + 4}] -tags Ckey
    $T configure -treecolumn C0
    $T element create eKey text -fill #babdb6 -lines 1 -font TitleFont
    $T style create sAct
    $T style elements sAct {eSel eTxt}
    $T style layout sAct eSel -detach yes -iexpand xy
    $T style layout sAct eTxt -expand ns -padx 8
    $T style create sKey
    $T style elements sKey {eSel eKey}
    $T style layout sKey eSel -detach yes -iexpand xy
    $T style layout sKey eKey -expand wns -padx 6
    set maxw 0
    foreach {label key script} $::winops_actions {
        set maxw [expr {max($maxw, [font measure TitleFont $label])}]
        set item [$T item create]
        $T item style set $item C0 sAct Ckey sKey
        $T item element configure $item C0 eTxt -text $label
        $T item element configure $item Ckey eKey -text $key
        $T item lastchild root $item
    }
    $T selection add 1
    bind $T <ButtonPress-1> {winops-click %x %y}
    set t $::frameof($w)
    popup-show .winops [expr {max($maxw + $ih + 40, 160)}] \
        [expr {$n * $ih + 2}] \
        [expr {[winfo rootx $t] + $::border}] \
        [expr {[winfo rooty $t] + $::decotop}]
    if {![grab-keys-to winops-key]} {
        puts "WM: winops: keyboard not grabbed — mouse only"
    }
    puts "WM: winops open 0x[format %x $w]"
}
proc winops-key {kind name mods} {
    if {$kind eq "release"} return
    if {$mods == 0} {
        set i 0
        foreach {label key script} $::winops_actions {
            incr i
            if {$name eq $key} { winops-fire $i; return }
        }
    }
    set d [popup-nav $name $mods]
    if {$d != 0} {
        popup-move .winops.t [expr {[llength $::winops_actions] / 3}] $d
        return
    }
    switch -- $name {
        Return - KP_Enter { winops-fire [lindex [.winops.t selection get] 0] }
        Escape            { popups-close }
    }
}
proc winops-fire {i} {
    if {$i eq "" || $i < 1} { popups-close; return }
    set w $::winops_win
    lassign [lrange $::winops_actions [expr {($i - 1) * 3}] [expr {$i * 3 - 1}]] \
        label key script
    popups-close
    if {![info exists ::frameof($w)]} return
    puts "WM: winops 0x[format %x $w] $label"
    apply [list w $script] $w
}
proc winops-click {x y} {
    set T .winops.t
    if {[catch {$T identify -array A $x $y}] || $A(where) ne "item"} return
    winops-fire $A(item)
}

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
set kbmr {}   ;# {move|resize w saved-geometry}, {} = mode off
proc move-keyboard {{w 0}} {
    if {$w == 0} { set w $::focused }
    if {$w == 0 || ![info exists ::frameof($w)]} return
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $::frameof($w)] -> fx fy
    kbmr-enter move $w [list $fx $fy]
}
proc resize-keyboard {{w 0}} {
    if {$w == 0} { set w $::focused }
    if {$w == 0 || ![info exists ::frameof($w)]} return
    set t $::frameof($w)
    kbmr-enter resize $w [list [$t.slot cget -width] [$t.slot cget -height]]
}
proc kbmr-enter {mode w orig} {
    set ::kbmr [list $mode $w $orig]
    if {![grab-keys-to kbmr-key]} {
        set ::kbmr {}
        puts "WM: keyboard $mode: keyboard not grabbed"
        return
    }
    puts "WM: keyboard $mode 0x[format %x $w]"
}
proc kbmr-end {commit} {
    lassign $::kbmr mode w orig
    set ::kbmr {}
    grab-keys-to {}
    if {$mode eq ""} return
    if {!$commit && [info exists ::frameof($w)]} {
        if {$mode eq "move"} {
            wm geometry $::frameof($w) +[lindex $orig 0]+[lindex $orig 1]
            update idletasks
            send-synthetic-configure $w
        } else {
            wm-resize-client $w {*}$orig
        }
    }
    set said [expr {$commit ? "done" : "cancelled"}]
    puts "WM: keyboard $mode 0x[format %x $w] $said"
}
proc kbmr-key {kind name mods} {
    if {$kind eq "release"} return
    lassign $::kbmr mode w orig
    if {$mode eq "" || ![info exists ::frameof($w)]} { kbmr-end 1; return }
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
        wm geometry $t +[expr {$fx + $dx*$step}]+[expr {$fy + $dy*$step}]
        update idletasks
        send-synthetic-configure $w
    } else {
        lassign [client-size-hints $w] minw minh incw inch basew baseh
        set xstep 10; set ystep 10
        if {$mods & 1} { set xstep 1; set ystep 1 }
        if {$mods & 4} { set xstep 50; set ystep 50 }
        if {[dict get [style-of $w] increments] eq "respect"} {
            if {$incw > 1} { set xstep $incw }
            if {$inch > 1} { set ystep $inch }
        }
        set cw [expr {[$t.slot cget -width]  + $dx*$xstep}]
        set ch [expr {[$t.slot cget -height] + $dy*$ystep}]
        lassign [apply-size-hints $w $cw $ch] cw ch
        wm-resize-client $w [expr {max($cw, 40)}] [expr {max($ch, 30)}]
    }
}

# ---- the panel ----
# Our own strip panel, wmaker-flavored buttons: a button is
# IDEMPOTENT — fired (by click or by its chord) it FOCUSES the most
# recently used window its predicate matches, and LAUNCHES its command
# when nothing does; the button face flashes the verdict either way
# (green "found it", orange "launching"). Declared from the config:
#
#   panel-button LABEL {match PRED launch SCRIPT icon SPEC key CHORD}
#
# match is a predicate command prefix (filter, or any proc — the
# wm-style vocabulary), launch any Tcl script, icon anything
# resolve-icon takes, key a wm-bind chord spec; every key is optional.
# The panel exists only when at least one button is declared — stock
# behavior is panel-less — and the workarea hands the strip over the
# moment there are buttons, so maximize never covers it. Every
# raise-group ends by lifting the panel back on top: fvwm's
# StaysOnTop for the poor, good enough until layers exist.
#
# Where and how, two knobs. set-panel-side bottom|right picks the
# screen edge (a vertical treectrl on the right — only the flow
# orientation, the workarea carve and the geometry corner change, the
# button logic never sees the side). set-panel-preset row|stack picks
# the button layout when any face is iconic: row is <image> Text,
# stack puts the label under the icon — the tall-strip look for a
# thick bottom bar or a narrow right one.
#
# Geometry is precomputed per (re)build — fonts, RandR and the config
# all funnel into panel-build. With no iconic face anywhere the strip
# keeps today's text-chip height (back-compat); once ANY face
# resolves, every iconless button wears the winlist's auto-badge as a
# placeholder (letters of the label on a crc32 color), so the mixed
# case holds one unified height. panel-icon-size (default 48, the
# hicolor stock) is the resolve-icon target; a foreign size is
# resampled by resolve-icon itself.
#
# A button whose match sees a LIVE window says so persistently: an
# indicator bar along the button's bottom edge plus a light tint of
# the face — the same state machinery the flash feedback uses, only
# not timed out (set-panel-live-colors BAR FACE re-paints). More
# than one match grows an ARROW zone at the button's east edge:
# clicking it drops the winlist filtered to the matches, anchored by
# the button (MRU, icons, numbered hotkeys — the shared machinery),
# picking focuses; a body click keeps the old idempotent fire on the
# most recent match. Matches are re-judged on manage, unmanage and
# every title change (a title flip can turn a -title filter around),
# debounced like the RandR rebuild.
set panel_buttons {}
set panel_side bottom    ;# which screen edge holds the strip
set panel_preset row     ;# iconic button layout: row | stack
set panel_icon_size 48   ;# resolve-icon target for button faces
set panel_zone 0         ;# the reserved arrow strip, set per build
proc set-panel-side {side} {
    if {$side ni {bottom right}} { error "set-panel-side: bottom or right" }
    set ::panel_side $side
    panel-rebuild-soon
}
proc set-panel-preset {preset} {
    if {$preset ni {row stack}} { error "set-panel-preset: row or stack" }
    set ::panel_preset $preset
    panel-rebuild-soon
}
proc set-panel-icon-size {px} {
    set ::panel_icon_size $px
    panel-rebuild-soon
}
set panel_live_bar  #8ae234  ;# the indicator strip
set panel_live_face #5d6e59  ;# the face tint under a live match
proc set-panel-live-colors {bar face} {
    set ::panel_live_bar $bar
    set ::panel_live_face $face
    panel-rebuild-soon
}
proc panel-button {label settings} {
    lappend ::panel_buttons [list $label $settings]
    if {[dict exists $settings key]} {
        wm-bind [dict get $settings key] \
            [list panel-fire [expr {[llength $::panel_buttons] - 1}]]
    }
    panel-rebuild-soon
}
# one rebuild per config's worth of declarations (or knob twiddles)
proc panel-rebuild-soon {} {
    if {![info exists ::panel_pending]} {
        set ::panel_pending 1
        after idle {unset ::panel_pending; panel-build}
    }
}
# Every managed window a button's match accepts, MRU first — the
# winlist order, never-focused windows trailing. Feeds the fire (the
# head is the most recent), the live/multi judgement, and the arrow
# zone's filtered list.
proc panel-matches {label settings} {
    if {![dict exists $settings match]} { return {} }
    set pred [dict get $settings match]
    set cands $::focus_hist
    foreach w [array names ::frameof] {
        if {$w ni $cands} { lappend cands $w }
    }
    set hits {}
    foreach w $cands {
        if {![info exists ::frameof($w)]} continue
        if {[catch {uplevel #0 [list {*}$pred $w]} m]} {
            puts "WM: panel $label: predicate error on 0x[format %x $w]: $m"
        } elseif {$m} { lappend hits $w }
    }
    return $hits
}
# Re-judge every button's match against the living windows and set
# the persistent states. Kicked (debounced — one manage can cascade
# a burst of property traffic) from the policy hooks: manage,
# unmanage, title change; run straight at the end of every rebuild.
set panel_reeval_pending ""
proc panel-match-kick {} {
    if {![llength $::panel_buttons]} return
    after cancel $::panel_reeval_pending
    set ::panel_reeval_pending [after 200 panel-reeval]
}
proc panel-reeval {} {
    if {![winfo exists .panel.t]} return
    set i 0
    foreach b $::panel_buttons {
        lassign $b label settings
        set n [llength [panel-matches $label $settings]]
        .panel.t item state set [expr {$i + 1}] \
            [list [expr {$n >= 1 ? "live" : "!live"}] \
                  [expr {$n >= 2 ? "multi" : "!multi"}]]
        incr i
    }
}
# Everything the strip's shape depends on, decided in one place: the
# resolved face of every button ("" = no icon or a miss — one case,
# the badge), whether anything is iconic at all, the item height for
# the preset, and the strip thickness (bottom: the item height;
# right: the widest button). The builder and the workarea's thickness
# question both come here; resolution is cached, so asking is cheap.
proc panel-geometry {} {
    set faces {}
    set iconic 0
    foreach b $::panel_buttons {
        lassign $b label settings
        set img ""
        if {[dict exists $settings icon]} {
            set img [resolve-icon [dict get $settings icon] $::panel_icon_size]
        }
        if {$img ne ""} { set iconic 1 }
        lappend faces $img
    }
    set isz $::panel_icon_size
    set line [font metrics TitleFont -linespace]
    # badge lettering follows the badge size (the winlist formula)
    font configure PanelIconFont -family [font actual TitleFont -family] \
        -size -[expr {max(7, $isz * 5 / 8)}]
    # the arrow zone: once ANY button can match, every button
    # reserves an east strip for the multi arrow — the row reads
    # uniformly, an unarmed button just shows calm space there
    set aw [font measure TitleFont ▾]
    set zoned 0
    foreach b $::panel_buttons {
        if {[dict exists [lindex $b 1] match]} { set zoned 1; break }
    }
    set zone [expr {$zoned ? $aw + 12 : 0}]
    if {!$iconic} {
        set content $line
    } elseif {$::panel_preset eq "stack"} {
        set content [expr {$isz + 2 + $line}]
    } else {
        set content [expr {max($isz, $line)}]
    }
    set itemh [expr {$content + 16}]
    if {![llength $::panel_buttons]} {
        set thick 0
    } elseif {$::panel_side eq "right"} {
        set maxw 0
        foreach b $::panel_buttons f $faces {
            lassign $b label settings
            set tw [font measure TitleFont $label]
            if {!$iconic} {
                set cw $tw
            } else {
                set iw $isz
                if {$f eq ""} {
                    # the badge: at least the square, wide letters grow it
                    set iw [expr {max($isz, [font measure PanelIconFont \
                        [lindex [pseudo-badge $label] 0]])}]
                }
                if {$::panel_preset eq "stack"} {
                    set cw [expr {max($iw, $tw)}]
                } else {
                    set cw [expr {$iw + 4 + $tw}]
                }
            }
            set maxw [expr {max($maxw, $cw + 20 + $zone)}]
        }
        set thick [expr {$maxw + 2}]
    } else {
        set thick [expr {$itemh + 2}]
    }
    dict create faces $faces iconic $iconic itemh $itemh thick $thick \
        zone $zone aw $aw
}
proc panel-thickness {} { dict get [panel-geometry] thick }
proc panel-build {} {
    destroy .panel
    if {![llength $::panel_buttons]} return
    lassign [screen-size] sw sh
    set g [panel-geometry]
    set faces [dict get $g faces]
    set iconic [dict get $g iconic]
    set itemh [dict get $g itemh]
    set thick [dict get $g thick]
    set zone [dict get $g zone]
    set aw [dict get $g aw]
    set ::panel_zone $zone
    set er [expr {8 + $zone}]   ;# the face's east inner pad
    set isz $::panel_icon_size
    set vert [expr {$::panel_side eq "right"}]
    toplevel .panel -background $::OUTLINE
    wm overrideredirect .panel 1
    set T [treectrl .panel.t -showheader no -showroot no -showbuttons no \
        -showlines no -borderwidth 0 -highlightthickness 0 \
        -background #2e3436 -itemheight $itemh \
        -orient [expr {$vert ? "vertical" : "horizontal"}]]
    bindtags $T [list $T all]
    $T state define found    ;# the flash: predicate found a window
    $T state define firing   ;# the flash: launching the command
    $T state define live     ;# persistent: the match sees a window
    $T state define multi    ;# persistent: ... more than one
    $T column create -tags C0
    if {$vert} { $T column configure C0 -width [expr {$thick - 2}] }
    $T element create eFace rect \
        -fill [list #4e9a06 found #ce5c00 firing \
                    $::panel_live_face live #555753 {}] \
        -outline #888a85 -outlinewidth 1
    $T element create eBIcon image
    $T element create ePRect rect
    $T element create ePTxt text -fill white -lines 1 -font PanelIconFont
    $T element create eBTxt text -fill white -lines 1 -font TitleFont
    $T element create eLive rect -fill [list $::panel_live_bar live] \
        -height 3
    $T element create eSep rect -fill #888a85 -width 1 \
        -height [expr {$itemh - 14}]
    $T element create eArrow text -text ▾ -fill #d3d7cf -font TitleFont
    # Three button styles, assigned per item by what its face resolved
    # to: plain (today's text chip — every button when nothing is
    # iconic), icon, and badge; row and stack presets differ in the
    # style's orient and pads only. The badge square is pinned by
    # min-sizing the union MEMBER (the lettering's layout cell, which
    # the union rect then surrounds) — -width/-minwidth/-iexpand on
    # the union element itself are ignored by treectrl.
    $T style create sBtn
    $T style elements sBtn {eFace eBTxt}
    $T style layout sBtn eFace -union eBTxt -ipadx [list 8 $er] -ipady 3 \
        -padx 2 -expand ns
    $T style layout sBtn eBTxt -expand ns
    if {$iconic && $::panel_preset eq "stack"} {
        $T style create sBtnI -orient vertical
        $T style elements sBtnI {eFace eBIcon eBTxt}
        $T style layout sBtnI eFace -union {eBIcon eBTxt} \
            -ipadx [list 8 $er] -ipady 3 -padx 2 -expand wens
        $T style layout sBtnI eBIcon -expand we -pady {0 2}
        $T style layout sBtnI eBTxt -expand we
        $T style create sBtnB -orient vertical
        $T style elements sBtnB {eFace ePRect ePTxt eBTxt}
        $T style layout sBtnB eFace -union {ePRect eBTxt} \
            -ipadx [list 8 $er] -ipady 3 -padx 2 -expand wens
        $T style layout sBtnB ePRect -union ePTxt -expand we -pady {0 2}
        $T style layout sBtnB ePTxt -minwidth $isz -minheight $isz \
            -expand wens
        $T style layout sBtnB eBTxt -expand we
    } elseif {$iconic} {
        $T style create sBtnI
        $T style elements sBtnI {eFace eBIcon eBTxt}
        $T style layout sBtnI eFace -union {eBIcon eBTxt} \
            -ipadx [list 8 $er] -ipady 3 -padx 2 -expand wens
        $T style layout sBtnI eBIcon -expand ns -padx {0 4}
        $T style layout sBtnI eBTxt -expand ns
        $T style create sBtnB
        $T style elements sBtnB {eFace ePRect ePTxt eBTxt}
        $T style layout sBtnB eFace -union {ePRect eBTxt} \
            -ipadx [list 8 $er] -ipady 3 -padx 2 -expand wens
        $T style layout sBtnB ePRect -union ePTxt -expand ns -padx {0 4}
        $T style layout sBtnB ePTxt -minwidth $isz -minheight $isz \
            -expand wens
        $T style layout sBtnB eBTxt -expand ns
    }
    # The live furniture rides every style: the indicator bar along
    # the bottom edge, and — in a zoned panel — the arrow furniture
    # inside the reserved east strip: a separator line and the glyph,
    # both drawn only when the arrow is armed (multi). The whole
    # strip, not the glyph, is the click target — see panel-click.
    foreach s [$T style names] {
        set els [concat [$T style elements $s] {eLive}]
        if {$zone} { lappend els eSep eArrow }
        $T style elements $s $els
        $T style layout $s eLive -detach yes -iexpand x -expand n
        if {$zone} {
            $T style layout $s eSep -detach yes -expand wns \
                -padx [list 0 [expr {2 + $zone}]] -visible {yes multi no {}}
            $T style layout $s eArrow -detach yes -expand wns \
                -padx [list 0 [expr {2 + ($zone - $aw) / 2}]] \
                -visible {yes multi no {}}
        }
    }
    foreach b $::panel_buttons f $faces {
        lassign $b label settings
        set item [$T item create]
        if {!$iconic} {
            $T item style set $item C0 sBtn
        } elseif {$f ne ""} {
            $T item style set $item C0 sBtnI
            $T item element configure $item C0 eBIcon -image $f
        } else {
            $T item style set $item C0 sBtnB
            lassign [pseudo-badge $label] letters color
            $T item element configure $item C0 ePRect -fill $color
            $T item element configure $item C0 ePTxt -text $letters
        }
        $T item element configure $item C0 eBTxt -text $label
        $T item lastchild root $item
    }
    bind $T <ButtonPress-1> {panel-click %x %y}
    if {$vert} {
        set geo ${thick}x${sh}+[expr {$sw - $thick}]+0
        place $T -x 1 -y 1 -width [expr {$thick - 2}] -height [expr {$sh - 2}]
    } else {
        set geo ${sw}x${thick}+0+[expr {$sh - $thick}]
        place $T -x 1 -y 1 -width [expr {$sw - 2}] -height [expr {$thick - 2}]
    }
    wm geometry .panel $geo
    raise .panel
    panel-reeval   ;# a rebuild starts stateless — judge the matches now
    puts "WM: panel up ([llength $::panel_buttons] buttons, $thick px,\
 $::panel_side/$::panel_preset, $geo)"
}
proc panel-fire {i} {
    lassign [lindex $::panel_buttons $i] label settings
    set hit [lindex [panel-matches $label $settings] 0]
    if {$hit ne ""} {
        puts "WM: panel $label: found 0x[format %x $hit]"
        panel-flash $i found
        raise-group $hit
        focus-to $hit
    } elseif {[dict exists $settings launch]} {
        puts "WM: panel $label: launch"
        panel-flash $i firing
        if {[catch {uplevel #0 [dict get $settings launch]} err]} {
            puts "WM: panel $label: launch FAILED: $err"
        }
    } else {
        puts "WM: panel $label: nothing matched, nothing to launch"
    }
}
# The arrow zone: the winlist filtered to this button's matches,
# anchored by the button — picking focuses (winlist-pick). Fewer
# than two matches means the arrow is stale (the debounce window):
# degrade to the plain fire.
proc panel-arrow {i} {
    lassign [lindex $::panel_buttons $i] label settings
    set wins [panel-matches $label $settings]
    if {[llength $wins] < 2} { panel-fire $i; return }
    puts "WM: panel $label: arrow — [llength $wins] matches"
    winlist-open $wins [list panel $i]
}
proc panel-flash {i state} {
    # items are created in declaration order: button i = item i+1
    set item [expr {$i + 1}]
    if {![winfo exists .panel.t]} return
    catch {
        .panel.t item state set $item $state
        after 600 [list catch [list .panel.t item state set $item !$state]]
    }
}
proc panel-click {x y} {
    set T .panel.t
    if {[catch {$T identify -array A $x $y}] || $A(where) ne "item"} return
    set i [expr {$A(item) - 1}]
    # the whole reserved east strip is the arrow's click target, not
    # the glyph — but only while the arrow is armed (multi)
    if {$::panel_zone > 0 && "multi" in [$T item state get $A(item)]} {
        lassign [$T item bbox $A(item)] _x _y x2 _y2
        if {$x >= $x2 - 2 - $::panel_zone} { panel-arrow $i; return }
    }
    panel-fire $i
}
proc panel-on-top {} {
    if {[winfo exists .panel]} { raise .panel }
}

# The screen changed size under us (RandR: a resized Xephyr window, a
# mode switch): the panel is glued to the bottom edge, so re-place it.
# Debounced — an interactive Xephyr resize streams a notify per step,
# and rebuilding the strip on each would thrash.
set panel_resize_pending ""
proc policy-screen-changed {} {
    after cancel $::panel_resize_pending
    set ::panel_resize_pending [after 200 panel-build]
}

# ---- default key bindings ----
# The defaults live IN CODE — the config is an override layer, not a
# preset carrier. The window OPS menu (actions on the focused window)
# answers both the one-chord Alt+Space and the stumpwm-style sequence
# Super+t w m; the window LIST sits on Alt+Tab — where the held Alt
# turns it into the fvwm cycle — and on Super+t w w as a plain static
# menu (the sequence ends with everything released).
wm-bind {<Alt>space} winops
wm-bind {<Super>t w m} winops
wm-bind {<Alt>Tab} winlist
wm-bind {<Super>t w w} winlist

# Move policy is plain Tk: drag the title bar, the client rides along.
# A title click also raises and focuses.
proc drag-start {t w X Y} {
    popups-close
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
