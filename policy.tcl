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
# at each winlist open, when the badge size is known.
font create IconFont -weight bold
# 3px of air above and below the text line; the strip sits under the 2px
# top edge, a 2px gap separates it from the client slot.
proc title-metrics {} {
    set ::titleh [expr {[font metrics TitleFont -linespace] + 6}]
    set ::decotop [expr {2 + $::titleh + 2}]
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
# icon (a Tk image name, created in the config) — shown for the window
# in the window list, overriding the client's own _NET_WM_ICON.
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
    # frames are placed within the WORKAREA: a new window must not be
    # born with its bottom edge under the panel
    lassign [workarea] wax way sw sh
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
    # WM_TRANSIENT_FOR is read ONCE, now: the refocus pick needs the
    # dialog's leader at a moment when the dialog may already be a dead
    # window that cannot be asked anything.
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
    place $t.title -x $B -y 2 -width $cw -height $::titleh
    $t.slot configure -width $cw -height $ch
    place $t.slot -x $B -y $::decotop
    wm geometry $t [expr {$cw + 2*$B}]x[expr {$ch + $::decotop + $B}]+$X+$Y
}

# The decoration follows the client's new size (position stays put).
proc policy-resize {w cw ch} {
    frame-layout $::frameof($w) $cw $ch
    update idletasks
}

# ---- the decoration underlay ----
# Border background (the canvas -background), a 1px dark outline around
# the perimeter, and fvwm-style corner grips in a lighter shade, cut
# off by thin dark lines — the visible promise that a corner drags
# diagonally. The bottom corners are L-shaped (arms $::border wide,
# length = the corner zone rz-edge uses); the top corners keep only
# the vertical arm: the top strip is 2px, and a horizontal arm
# squeezed into it read as a clipped sliver, not a grip (the 2px strip
# still resizes — the zone just goes unadvertised). Redrawn on
# <Configure>, recolored (via a full cheap redraw) by paint-focus.
proc deco-draw {c W H} {
    $c delete all
    set B $::border; set CZ 24
    set bg [$c cget -background]
    set grip [expr {[info exists ::gripof($bg)] ? $::gripof($bg) : $bg}]
    foreach {x0 y0 x1 y1} [list \
        0 0 $B $CZ \
        [expr {$W-$B}] 0 $W $CZ \
        0 [expr {$H-$CZ}] $B $H             0 [expr {$H-$B}] $CZ $H \
        [expr {$W-$B}] [expr {$H-$CZ}] $W $H \
        [expr {$W-$CZ}] [expr {$H-$B}] $W $H] {
        $c create rectangle $x0 $y0 $x1 $y1 -fill $grip -outline "" -tags grip
    }
    foreach {x0 y0 x1 y1} [list \
        0 $CZ $B $CZ \
        [expr {$W-$B}] $CZ $W $CZ \
        0 [expr {$H-$CZ}] $B [expr {$H-$CZ}]        $CZ [expr {$H-$B}] $CZ $H \
        [expr {$W-$B}] [expr {$H-$CZ}] $W [expr {$H-$CZ}] \
        [expr {$W-$CZ}] [expr {$H-$B}] [expr {$W-$CZ}] $H] {
        $c create line $x0 $y0 $x1 $y1 -fill $::OUTLINE
    }
    $c create rectangle 0 0 [expr {$W-1}] [expr {$H-1}] \
        -outline $::OUTLINE -fill ""
}

# ---- resize by the border / corner ----
# Which resize grip is under frame-relative (x, y)? The side strips are
# $::border wide, the bottom strip $::border tall; the 24px corner-zone
# ends of the strips act as diagonal corners — all four now: the top
# corners reach along both the side border and the 2px top strip, and
# the strip between them resizes the top edge (thin, but that is where
# the title drag's roof is).
proc rz-edge {t x y} {
    set W [winfo width $t]; set H [winfo height $t]
    set B $::border; set CZ 24; set T 2
    if {($y < $T && $x < $CZ) || ($x < $B && $y < $CZ)} { return nw }
    if {($y < $T && $x >= $W - $CZ) || ($x >= $W - $B && $y < $CZ)} { return ne }
    if {$y < $T} { return n }
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
        $tt.deco configure -background $bg
        deco-draw $tt.deco [winfo width $tt.deco] [winfo height $tt.deco]
        $tt.title configure -background $bg
    }
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
# placed — the screen minus the panel's bottom strip (zero-height
# when no buttons are declared, see the panel section).
proc workarea {} {
    lassign [screen-size] sw sh
    list 0 0 $sw [expr {$sh - [panel-height]}]
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
proc winlist-icon {w target} {
    set st [style-of $w]
    if {[dict exists $st icon]} {
        set img [dict get $st icon]
        if {$img in [image names]} { return [list image $img] }
        puts "WM: style icon «$img» is not a Tk image — ignored"
    }
    set img [client-icon $w $target]
    if {$img ne ""} { return [list image $img] }
    set name [lindex [client-class $w] 1]
    if {$name eq ""} { set name [title-or-id $w [client-title $w]] }
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
    list pseudo $letters $color
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
    set ::winlist_wins $wins
    set ::winlist_prev $::focused
    set ::winlist_cycle 0
    if {$::winlist_cycle_opt && $::key_invoke_mods != 0
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
    $T selection add [expr {[llength $wins] > 1 ? 2 : 1}]
    bind $T <ButtonPress-1> {winlist-click %x %y}
    lassign [screen-size] sw sh
    set W [expr {min(max($maxw + $numw + $iconw + 28, 200), $sw * 3 / 5)}]
    set H [expr {[llength $wins] * $ih + 2}]
    popup-show .winlist $W $H [expr {($sw - $W) / 2}] [expr {($sh - $H) / 3}]
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

# ---- the panel ----
# Our own bottom-strip panel, wmaker-flavored buttons: a button is
# IDEMPOTENT — fired (by click or by its chord) it FOCUSES the most
# recently used window its predicate matches, and LAUNCHES its command
# when nothing does; the button face flashes the verdict either way
# (green "found it", orange "launching"). Declared from the config:
#
#   panel-button LABEL {match PRED launch SCRIPT icon IMG key CHORD}
#
# match is a predicate command prefix (the wm-style vocabulary — the
# identity accessors), launch any Tcl script, icon a Tk image for the
# button face, key a wm-bind chord spec; every key is optional. The
# panel exists only when at least one button is declared — stock
# behavior is panel-less — and the workarea hands the strip over the
# moment there are buttons, so maximize never covers it. Every
# raise-group ends by lifting the panel back on top: fvwm's
# StaysOnTop for the poor, good enough until layers exist.
set panel_buttons {}
proc panel-button {label settings} {
    lappend ::panel_buttons [list $label $settings]
    if {[dict exists $settings key]} {
        wm-bind [dict get $settings key] \
            [list panel-fire [expr {[llength $::panel_buttons] - 1}]]
    }
    # one rebuild per config's worth of declarations
    if {![info exists ::panel_pending]} {
        set ::panel_pending 1
        after idle {unset ::panel_pending; panel-build}
    }
}
proc panel-height {} {
    expr {[llength $::panel_buttons] ? $::titleh + 12 : 0}
}
proc panel-build {} {
    destroy .panel
    if {![llength $::panel_buttons]} return
    lassign [screen-size] sw sh
    set ph [panel-height]
    toplevel .panel -background $::OUTLINE
    wm overrideredirect .panel 1
    set T [treectrl .panel.t -showheader no -showroot no -showbuttons no \
        -showlines no -borderwidth 0 -highlightthickness 0 \
        -background #2e3436 -orient horizontal -itemheight [expr {$ph - 2}]]
    bindtags $T [list $T all]
    $T state define found    ;# the flash: predicate found a window
    $T state define firing   ;# the flash: launching the command
    $T column create -tags C0
    $T element create eFace rect \
        -fill [list #4e9a06 found #ce5c00 firing #555753 {}] \
        -outline #888a85 -outlinewidth 1
    $T element create eBIcon image
    $T element create eBTxt text -fill white -lines 1 -font TitleFont
    $T style create sBtn
    $T style elements sBtn {eFace eBIcon eBTxt}
    $T style layout sBtn eFace -union {eBIcon eBTxt} -ipadx 8 -ipady 3 \
        -padx 2 -expand ns
    $T style layout sBtn eBIcon -expand ns -padx {0 4}
    $T style layout sBtn eBTxt -expand ns
    foreach b $::panel_buttons {
        lassign $b label settings
        set item [$T item create]
        $T item style set $item C0 sBtn
        $T item element configure $item C0 eBTxt -text $label
        if {[dict exists $settings icon]
                && [dict get $settings icon] in [image names]} {
            $T item element configure $item C0 eBIcon \
                -image [dict get $settings icon]
        }
        $T item lastchild root $item
    }
    bind $T <ButtonPress-1> {panel-click %x %y}
    place $T -x 1 -y 1 -width [expr {$sw - 2}] -height [expr {$ph - 2}]
    wm geometry .panel ${sw}x${ph}+0+[expr {$sh - $ph}]
    raise .panel
    puts "WM: panel up ([llength $::panel_buttons] buttons, $ph px)"
}
proc panel-fire {i} {
    lassign [lindex $::panel_buttons $i] label settings
    set hit 0
    if {[dict exists $settings match]} {
        set pred [dict get $settings match]
        # MRU first — like the winlist, never-focused windows trail
        set cands $::focus_hist
        foreach w [array names ::frameof] {
            if {$w ni $cands} { lappend cands $w }
        }
        foreach w $cands {
            if {![info exists ::frameof($w)]} continue
            if {[catch {uplevel #0 [list {*}$pred $w]} m]} {
                puts "WM: panel $label: predicate error on 0x[format %x $w]: $m"
            } elseif {$m} { set hit $w; break }
        }
    }
    if {$hit != 0} {
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
    panel-fire [expr {$A(item) - 1}]
}
proc panel-on-top {} {
    if {[winfo exists .panel]} { raise .panel }
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
