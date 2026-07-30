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

keep ncli 0
keep fid 0
keep focus_hist {}
# Border width, all four sides. 6px is a resize GRIP, not just a
# line: the old 2px border left nothing to grab. The top strip above
# the titlebar was 2px for a while (top resize worked but was
# unhittable); the owner asked for grips uniform with the bottom
# (2026-07-28), so the strip is a full border now.
keep border 6
# Corner grip arm length — ALL four corners, deco-draw and rz-edge
# alike. The top arms briefly ran border+titleh ("hug the buttons"),
# then the buttons briefly shrank to gripz - border to meet 24px
# arms — both misreadings of the same wish (2026-07-28): SHORT arms
# like the bottom, with the buttons drawn flush into the strip's top
# corners, so the border (and the grip riding on it) presses right
# against the button the way the bottom border presses against the
# client area. The grip's cut is just a mark on the border — it does
# not chase the button's edge. Button size — see title-metrics.
keep gripz 24

# Titlebar typography. TitleFont is OUR named font: it starts as a copy
# of TkDefaultFont, TK9WM_TITLE_FONT overrides it at startup (any Tk
# font spec, e.g. "DejaVu Sans 12"), and set-title-font re-points it
# live. Every vertical measure of the decoration derives from its
# metrics — a 22px strip that was roomy at 96 dpi was visibly too tight
# for the same font at Xft.dpi 144 (live report, 2026-07-27).
once fonts-title {font create TitleFont {*}[font actual TkDefaultFont]}
if {[info exists ::env(TK9WM_TITLE_FONT)] && $::env(TK9WM_TITLE_FONT) ne ""} {
    if {[catch {font configure TitleFont {*}[font actual $::env(TK9WM_TITLE_FONT)]} err]} {
        puts "WM: TK9WM_TITLE_FONT «$::env(TK9WM_TITLE_FONT)» rejected: $err"
    }
}
# The pseudo-icon lettering (see winlist-icon): TitleFont's family, but
# bold and sized in PIXELS to the badge, not the text line — configured
# at each winlist open, when the badge size is known. Every panel keeps
# its OWN instance (panel-badge-font): a badge size is per panel — a
# dock of 48px icons beside a taskbar of 24px ones is the ordinary
# case — and panels sharing one font would each be lettered for
# whichever was built last.
once fonts-icon {font create IconFont -weight bold}
# 3px of air above and below the text line; the strip sits under the
# full top border (a real grip, uniform with the bottom), a 2px gap
# separates it from the client slot.
proc title-metrics {} {
    set ::titleh [expr {[font metrics TitleFont -linespace] + 6}]
    set ::decotop [expr {$::border + $::titleh + 2}]
    # The titlebar buttons: squares one grip SHORT of the strip height,
    # flush against the top and side borders. Full-height buttons read
    # too big and pressed right against the client area (the owner,
    # 2026-07-28) — shrinking them by the grip width leaves a hole of
    # about one grip (border + the 2px gap) between the buttons and
    # the client. btnw is the button column width and the click-target
    # size the WM advertises in its metrics line.
    set ::btnw [expr {$::titleh - $::border}]
    btn-images
    puts "WM: titlebar h=$::titleh top=$::decotop btn=$::btnw\
 font=[font actual TitleFont -family]/[font actual TitleFont -size]"
}

# Titlebar buttons, fvwm-style (the owner's frame as the model): a thin
# white outlined square holding a thin white glyph, drawn flat on the
# titlebar color. The glyphs are svg — re-rendered crisp at whatever
# size the font dictates, never scaled bitmaps.
# Frame colors: the focus highlight pair, the modal amber a keyboard
# move/resize wears, the matching lighter shade for each one's corner
# grips, and the constant dark outline that keeps two touching frames
# readable as two windows (before it, several inactive titlebars fused
# into one gray field).
keep OUTLINE #2e3436
set KBMR_BG #c17d11
array set gripof {#3465a4 #6b93c0 #888a85 #a5a7a1 #c17d11 #e0a94a}

set SVG_CLOSE {<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
<path d="M3.5 3.5 L12.5 12.5 M12.5 3.5 L3.5 12.5" stroke="#ffffff"
 stroke-width="1.6" stroke-linecap="round" fill="none"/></svg>}
set SVG_MAX {<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
<rect x="3.5" y="3.5" width="9" height="9" stroke="#ffffff"
 stroke-width="1.6" fill="none"/></svg>}
set SVG_MENU {<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
<rect x="3.5" y="6.5" width="9" height="3" stroke="#ffffff"
 stroke-width="1.6" fill="none"/></svg>}
# Minimize is the bar along the BOTTOM, not the middle — the middle is
# where the menu button's own bar sits, and two thin horizontals at the
# same height would be one glyph read twice.
set SVG_MIN {<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
<path d="M3.5 12 L12.5 12" stroke="#ffffff" stroke-width="1.6"
 stroke-linecap="round" fill="none"/></svg>}

# ---- the titlebar in three layers -----------------------------------
#
# What a titlebar is made of used to be one piece of knowledge smeared
# over six places: the glyphs here, the set of columns in frame-buttons,
# the treectrl construction in policy-attach (with the three names
# hard-coded), a SECOND copy of that construction in wm-window, the
# arming machinery in title-press, and a switch in title-release saying
# what each button does. Adding one button meant editing five of them,
# which is the owner's point (2026-07-30): these are three different
# kinds of decision and they must not be mixed, whether or not a config
# is expected to make them.
#
#   1. THE STRIP — what a titlebar and a grip ARE. Its height and the
#      button cell size (title-metrics), how much of it a window wears
#      (chrome-of), how it is drawn (deco-draw), how it is built
#      (titlebar-build), and the press/arm/release machinery that turns
#      a click into "this part, this gesture" (title-press and friends).
#      It knows there are button cells; it does not know their names.
#
#   2. THE BUTTONS — which buttons exist and what they look like. One
#      catalogue, below. A frame wears a SET of them (frame-buttons),
#      which is per frame because it varies: the WM's own windows wear
#      only close, and a client whose style refuses minimize is not
#      given a button that would only refuse.
#
#   3. THE GESTURES — what pressing something DOES. A table from
#      {part, gesture} to a command, where a part is a button's name or
#      `title` for the strip itself: the same table answers "what does
#      the close button do", "what does a double click on the title
#      do", and "what does button 3 on the title do", because those are
#      one question asked three times.
#
# The seam between 2 and 3 is the one that pays immediately: a button
# is declared once and bound once, and the two declarations do not have
# to be in the same place or come from the same author.

# --- layer 2: the catalogue ---
# titlebar-button NAME -glyph SVG ?-side left|right?
# Order within a side is declaration order, left to right. The name
# becomes a treectrl column tag and an image name, so it is kept to
# lowercase letters.
keep titlebar_buttons {}
proc titlebar-button {name args} {
    if {![regexp {^[a-z][a-z0-9]*$} $name]} {
        error "titlebar-button: «$name» — lowercase letters and digits,\
 it becomes a column tag"
    }
    set side right
    set glyph ""
    foreach {opt val} $args {
        switch -- $opt {
            -side {
                if {$val ni {left right}} {
                    error "titlebar-button $name: -side is left or right"
                }
                set side $val
            }
            -glyph { set glyph $val }
            default { error "titlebar-button $name: unknown option $opt" }
        }
    }
    if {$glyph eq ""} { error "titlebar-button $name: -glyph svg is required" }
    dict set ::titlebar_buttons $name [dict create side $side glyph $glyph]
}
proc titlebar-side  {name} { dict get $::titlebar_buttons $name side }
proc titlebar-image {name} { return imgBtn-$name }
proc btn-images {} {
    # re-creating a photo under the same name updates every user of it;
    # the union box is glyph + 2*3px ipad (the 1px outline draws inside),
    # so this glyph height makes the box exactly btnw square — the full
    # button cell, no inset
    set g [expr {max($::btnw - 6, 7)}]
    dict for {name spec} $::titlebar_buttons {
        image create photo [titlebar-image $name] \
            -format [list svg -scaletoheight $g] -data [dict get $spec glyph]
    }
}

# --- layer 3: what a gesture on a part does ---
# titlebar-bind PART GESTURE COMMAND — PART is a button's name or
# `title`; GESTURE is <1> <2> <3> or <Double-1>; COMMAND is a command
# prefix and the window is appended, which is what makes the window
# COMMANDS (Maximize, Close, Minimize — they take an optional window)
# the natural thing to write here. A button fires on release-inside,
# classic button semantics, so a drag away cancels; a gesture on the
# strip itself fires on the press, the way a menu should.
keep titlebar_gestures {}
proc titlebar-bind {part gesture cmd} {
    if {$part ne "title" && ![dict exists $::titlebar_buttons $part]} {
        error "titlebar-bind: no titlebar button «$part» (and it is not\
 «title»)"
    }
    if {$gesture ni {<1> <2> <3> <Double-1>}} {
        error "titlebar-bind: gesture is <1>, <2>, <3> or <Double-1>"
    }
    if {$part eq "title" && $gesture eq "<1>"} {
        error "titlebar-bind: button 1 on the title carries the window"
    }
    dict set ::titlebar_gestures $part,$gesture $cmd
}
proc titlebar-action {part gesture} {
    if {[dict exists $::titlebar_gestures $part,$gesture]} {
        return [dict get $::titlebar_gestures $part,$gesture]
    }
    return ""
}

# The desk this WM has by default, stated in those two vocabularies and
# nowhere else. Close on the far right, then maximize and minimize
# inward — so the two the hand knows by position keep it — and the menu
# alone on the left.
titlebar-button menu     -side left  -glyph $SVG_MENU
titlebar-button minimize -side right -glyph $SVG_MIN
titlebar-button maximize -side right -glyph $SVG_MAX
titlebar-button close    -side right -glyph $SVG_CLOSE

titlebar-bind menu     <1> winops
titlebar-bind minimize <1> Minimize
titlebar-bind maximize <1> Maximize
titlebar-bind close    <1> Close
# The strip itself. Double click maximizes and button 3 opens the ops
# menu, both being what a hand trained anywhere else already expects.
# What is deliberately NOT here is `titlebar-bind close <3> Destroy`,
# though it was the owner's own example of the kind of thing this layer
# must be able to say: a slip of the right button on the close box
# would kill an application without asking it to save anything. It is
# one line in a config for whoever wants it, and that is the right
# place for a sharp edge.
titlebar-bind title <Double-1> Maximize
titlebar-bind title <3>        winops

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
    panels-build  ;# the strip height follows the font too
    foreach {w t} [array get ::frameof] {
        # Re-asking the style, not just re-reading the metrics: this is
        # also the path a config RELOAD takes, and by then the `decor`
        # verdicts have been dropped with the rest of the style cache.
        # So a reload can take a titlebar off a living window and put
        # it back — while `place`, being a one-shot at map time, leaves
        # every window exactly where it stands.
        set ::chromeof($t) [chrome-of $w]
        # The BUTTON SET is re-asked for the same reason and one more:
        # a reload may have changed the catalogue itself. A set that
        # changed cannot be laid out, it has to be rebuilt — the
        # columns, elements and styles are per widget — so the strip is
        # thrown away and built again, which also puts the title back
        # from where the WM keeps it.
        # ...and the resting opacity, which a rule may have just
        # granted or taken away. A window a COMMAND faded stays faded:
        # that was the user, and a reload is not an answer to him.
        if {![info exists ::opacityof($w)]} { apply-opacity $w }
        set want [client-buttons $w]
        if {$want ne [frame-buttons $t]} {
            unset -nocomplain ::btn($t)
            destroy $t.title
            titlebar-build $t $w $want [title-or-id $w \
                [expr {[info exists ::titleof($w)] ? $::titleof($w) : ""}]]
        }
        frame-layout $t [$t.slot cget -width] [$t.slot cget -height]
    }
    update idletasks
    foreach {w t} [array get ::frameof] {
        send-synthetic-configure $w
        publish-frame-extents $w   ;# the strip's height just moved
    }
}
# a ttk theme switch would change TkDefaultFont-derived looks the same
# way; today the only real trigger is set-title-font
bind . <<ThemeChanged>> retitle-frames

# Title alignment knob. The flags feed the text element's -expand in
# the titlebar style: where the layout may ADD space decides where the
# text ends up (ns = left, extra space east+west = centered).
keep titlejust left
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
# minimize (iconify|refuse) — this client's answer to an iconify
# request, overriding the desk-wide set-minimize.
# decor (full|border|none) — how much frame this client wears; see
# chrome-of. place (a term list) — the geometry it is born with; see
# parse-place.
keep style_rules {}
proc always {w} { return 1 }
proc wm-style {pred settings} {
    lappend ::style_rules [list $pred $settings]
}
proc style-of {w} {
    if {[info exists ::styleof($w)]} { return $::styleof($w) }
    set st [dict create increments respect decor full]
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
#   filter ?-nocase? ?-regexp? ?-title PAT? ?-class PAT|{PAT PAT}? \
#       ?-command PAT? ?-machine PAT?
#
# The options AND together; an absent property fails its option — no
# errors, no match. Patterns are globs (string match), whole-string
# and CASE-SENSITIVE; -nocase relaxes that for the whole call.
#
# Matching used to be nocase unconditionally, on the theory that the
# world's WM_CLASS capitalization drifts (Firefox vs firefox). It cost
# more than it paid (owner's report, 2026-07-28). A plain xterm is
# {xterm XTerm}; the same binary with its instance name overridden
# (xterm -name ninja) is {ninja XTerm} — and a nocase `-class xterm`
# claims BOTH, matching the second one's CLASS slot. The two differ
# only in case, so no glob could separate them; only a regexp with
# (?c) could. Case-sensitive, `-class xterm` is the instance slot and
# nothing else, which is what one means by writing it; capitalization
# drift is a per-call `-nocase` away.
#
# -regexp swaps the comparator for regexp — unanchored, and (?i)
# inside a pattern is nocase for that pattern alone; alternation
# covers the OR nobody builds combinators for. -class with a single
# pattern matches EITHER of {instance class} — for when you remember
# the distinctive token but not its slot; two patterns are positional,
# exactly as xprop prints the property. -command matches WM_COMMAND
# joined with spaces and falls back to the local client's /proc argv
# (client-cmdline) when the property is absent. A proc predicate stays
# the escape hatch for anything richer.
proc filter {args} {
    set w [lindex $args end]
    set opts [lrange $args 0 end-1]
    set pairs {}
    set re 0
    set nocase {}
    while {[llength $opts]} {
        set opt [lindex $opts 0]
        if {$opt eq "-regexp" || $opt eq "-nocase"} {
            if {$opt eq "-regexp"} { set re 1 } else { set nocase -nocase }
            set opts [lrange $opts 1 end]
            continue
        }
        if {[llength $opts] < 2} { error "filter: $opt wants a pattern" }
        lappend pairs $opt [lindex $opts 1]
        set opts [lrange $opts 2 end]
    }
    if {$re} {
        set cmp [list regexp {*}$nocase --]
    } else {
        set cmp [list string match {*}$nocase]
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

# ---- decor: how much frame a client wears ----
# The style key `decor` in three steps, and the middle one is why it is
# not a boolean: full (the default) is titlebar and border; border keeps
# the border and its grips but drops the title strip — the window still
# resizes by the edge, it just carries no name, no buttons and no drag
# handle; none is nothing at all, the frame exactly the size of the
# client. Returns the three measures every layout is built from:
# {border top titleh}, where top is the offset of the client area.
#
# Everything that lays a frame out asks HERE instead of reading
# ::border/::decotop, because those are the desk's numbers and this is
# the window's. A frame remembers its own answer (::chromeof) — the
# style verdict is cached per client, but the frame is what the drawing
# and the resize code has in hand.
proc chrome-of {w} {
    switch -- [dict get [style-of $w] decor] {
        none    { list 0 0 0 }
        border  { list $::border $::border 0 }
        full    { list $::border $::decotop $::titleh }
        default { error "decor: full, border or none" }
    }
}
proc frame-chrome {t} {
    if {[info exists ::chromeof($t)]} { return $::chromeof($t) }
    list $::border $::decotop $::titleh
}
# --- layer 2, per frame: which of the catalogue this one wears ---
# The set is a property of the FRAME, because it varies: the WM's own
# windows wear close alone, and a client whose style refuses minimize
# is not given a button whose only answer would be to refuse. Derived
# once when the frame is built and again on a reload (retitle-frames),
# which is also when a config may have changed the catalogue itself.
proc client-buttons {w} {
    set names {}
    foreach name [dict keys $::titlebar_buttons] {
        if {$name eq "minimize" && [minimize-mode $w] eq "refuse"} continue
        lappend names $name
    }
    return $names
}
proc frame-buttons {t} {
    if {[info exists ::btncols($t)]} { return $::btncols($t) }
    dict keys $::titlebar_buttons
}

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
# the size hints then bind it exactly as they bind maximize, and the
# slack that leaves goes to the side the term did NOT pin — a
# right-aligned xterm keeps its right edge flush and eats the remainder
# on the left.
proc place-geometry {w cw ch spec} {
    lassign [workarea] wax way ww wh
    lassign [chrome-of $w] B top
    lassign [parse-place $spec] hax vax
    lassign $hax hsize halign
    lassign $vax vsize valign
    set fw [expr {$hsize eq "" ? $cw + 2*$B : $ww * $hsize / 100}]
    set fh [expr {$vsize eq "" ? $ch + $top + $B : $wh * $vsize / 100}]
    lassign [apply-size-hints $w [expr {max($fw - 2*$B, 1)}] \
                                 [expr {max($fh - $top - $B, 1)}]] cw ch
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
    if {![dict exists $st place]} { return [list $cw $ch] }
    lassign [place-force [dict get $st place]] spec forced
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
        }
        lassign [place-geometry $w $cw $ch $spec] pw ph X Y
    } err]} {
        puts "WM: place «$spec» on 0x[format %x $w]: $err"
        unset -nocomplain ::maxsaved($w)
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
            return [clamp-to-workarea $X $Y $fw $fh]
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
            return [clamp-to-workarea $X $Y $fw $fh]
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
    titlebar-build $t $w [client-buttons $w] "client 0x[format %x $w]"
    frame $t.slot -width $cw -height $ch -background #202020
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
    unset -nocomplain ::btncols($::frameof($w))   ;# the frame's, not the client's
    destroy $::frameof($w)
    unset ::frameof($w)
    unset -nocomplain ::titleof($w)
    unset -nocomplain ::leaderof($w)
    unset -nocomplain ::placeof($w)
    unset -nocomplain ::maxsaved($w) ::fssaved($w)
    unset -nocomplain ::styleof($w) ::opacityof($w)
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
        wm geometry $t ${cw}x${ch}+0+0
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
            $t.title column configure C$name -width $::btnw
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
# diagonally. All four corners are L-shaped, arms $::border thick and
# $::gripz long, one measure top and bottom. The arms press against
# what lives just inside the border: the client area at the bottom,
# a titlebar button at the top (flush in the strip's corner — see
# title-metrics). rz-edge's corner zones are the same measure.
# Redrawn on <Configure>, recolored (via a full cheap redraw) by
# paint-focus.
proc deco-draw {c W H} {
    $c delete all
    lassign [frame-chrome [winfo parent $c]] B
    set CZ $::gripz
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

# ---- resize by the border / corner ----
# Which resize grip is under frame-relative (x, y)? All four strips
# are $::border thick (the top used to be a 2px sliver — unhittable;
# uniform since 2026-07-28). The corner-zone ends of the strips act
# as diagonal corners, $::gripz at every corner — the same measure
# deco-draw advertises.
proc rz-edge {t x y} {
    set W [winfo width $t]; set H [winfo height $t]
    lassign [frame-chrome $t] B
    set CZ $::gripz
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
array set rzcursor {e right_side w left_side s bottom_side n top_side
    se bottom_right_corner sw bottom_left_corner
    ne top_right_corner nw top_left_corner}
proc rz-hover {t X Y} {
    set e [rz-edge $t [expr {$X - [winfo rootx $t]}] \
                      [expr {$Y - [winfo rooty $t]}]]
    $t configure -cursor [expr {$e eq "" ? "" : $::rzcursor($e)}]
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
    # The window comes LAST because rz-move's lassign reads the first
    # seven and would have to be re-counted otherwise; it is there for
    # the benefit of anyone asking "whose geometry is a hand holding"
    # (geometry-held-p).
    set ::rz [list $e $X $Y [winfo width $t.slot] [winfo height $t.slot] $fx $fy $w]
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
    # the minimum, say) is not a resize and shed nothing.
    if {$::maximize eq "drop" && ($cw != $cw0 || $ch != $ch0)
            && [info exists ::maxsaved($w)]} {
        unset ::maxsaved($w)
        puts "WM: 0x[format %x $w] resized by hand — no longer maximized"
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
    $t.title configure -cursor ""   ;# the carry cursor ends with the carry
    soft "re-hover after a press" { rz-hover $t {*}[winfo pointerxy $t] }
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
proc policy-title {w title} {
    if {![info exists ::frameof($w)]} return
    set ::titleof($w) $title
    if {![kbmr-owns $w]} {
        $::frameof($w).title item element configure 1 C0 eTxt \
            -text [title-or-id $w $title]
    }
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
    if {[kbmr-owns $w]} { return $::KBMR_BG }   ;# the mode outranks focus
    expr {$w == $::focused ? "#3465a4" : "#888a85"}
}
proc policy-paint-focus {w} {
    set ::focus_hist [linsert \
        [lsearch -exact -all -inline -not $::focus_hist $w] 0 $w]
    foreach {ww tt} [array get ::frameof] {
        frame-recolor $tt [frame-focus-color $ww]
    }
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
proc set-fade {a} {
    if {![string is double -strict $a] || $a <= 0.0 || $a > 1.0} {
        error "set-fade: how solid a faded window is, above 0 and up to 1"
    }
    set ::fade $a
}
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
proc set-minimize {mode} {
    if {$mode ni {iconify refuse}} { error "set-minimize: iconify|refuse" }
    set ::minimize $mode
}
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
proc raise-group {w} {
    set leader [group-leader $w]
    # top-to-bottom: the touched transient (never the leader — its
    # transients stay above it), the remaining transients, the leader
    set order {}
    if {$w != $leader} { lappend order $w }
    foreach c [group-members $leader] {
        if {$c != $w} { lappend order $c }
    }
    lappend order $leader
    raise $::frameof([lindex $order 0])
    for {set i 1} {$i < [llength $order]} {incr i} {
        lower $::frameof([lindex $order $i]) \
              $::frameof([lindex $order [expr {$i - 1}]])
    }
    panel-on-top
    publish-client-list   ;# the stacking order just changed (coalesced)
}

# Lower the whole transient group of w — the mirror image, same glue,
# same relative restacks (the ops menu's "lower" is the first lower
# gesture this WM has): one absolute lower — the leader, straight to
# the floor — and every transient re-seated right above it, keeping
# the group's internal order at the bottom of the stack.
proc lower-group {w} {
    if {![info exists ::frameof($w)]} return
    set leader [group-leader $w]
    lower $::frameof($leader)
    foreach c [group-members $leader] {
        raise $::frameof($c) $::frameof($leader)
    }
    publish-client-list   ;# the stacking order just changed (coalesced)
}

# ---- bury: lower, and hand the focus to whatever that uncovered ----
# Lower is a PEEK. It drops the window to the floor and deliberately
# keeps the focus on it, so a glance at what is underneath costs one
# gesture and the way back costs one more — which is exactly right, and
# exactly what is rarely wanted. Bury is the commoner wish and the
# other half of the pair: get this window out of the way AND give me
# what it was covering.
#
# "What it was covering" is meant literally, and is asked of the screen
# rather than of the focus history. After the lower the candidates are
# read TOP DOWN off the server's own stacking order, and the first one
# whose frame actually overlaps the buried group wins: a window that
# never shared a pixel with it was not underneath it in any sense the
# user means, however recently it was focused. Nothing overlapping —
# the topmost other window is the honest fallback. Nothing at all — the
# focus stays where it is, because parking it on the holder would be a
# worse answer than leaving it on a window that is merely at the back.
proc bury-group {w} {
    if {![info exists ::frameof($w)]} return
    set leader [group-leader $w]
    set group [linsert [group-members $leader] 0 $leader]
    lower-group $w
    update idletasks   ;# the restack and the geometry, both settled
    set next [pick-uncovered $group]
    if {$next != 0} { focus-to $next }
    puts "WM: buried 0x[format %x $leader] -> focus\
 [expr {$next ? "0x[format %x $next]" : {nobody else}}]"
}
# The group is what was buried, so the group — not just its leader — is
# what a candidate has to have been under: a dialog can hang well
# outside the window it belongs to.
proc pick-uncovered {group} {
    set best 0
    # bottom-first from the server, so walking it backwards is top-down
    foreach cand [lreverse [client-stacking]] {
        if {$cand in $group || ![info exists ::frameof($cand)]
                || [info exists ::iconic($cand)]} continue
        if {$best == 0} { set best $cand }      ;# the fallback: topmost
        foreach member $group {
            if {[frames-overlap $member $cand]} { return $cand }
        }
    }
    return $best
}
# Do two frames share a pixel? Plain rectangle intersection on settled
# Tk geometry — the frame is what the user sees, so the frame is what
# the question is about, borders and titlebar included.
proc frames-overlap {a b} {
    set fa $::frameof($a); set fb $::frameof($b)
    set ax [winfo rootx $fa]; set ay [winfo rooty $fa]
    set bx [winfo rootx $fb]; set by [winfo rooty $fb]
    expr {$ax < $bx + [winfo width $fb] && $bx < $ax + [winfo width $fa]
       && $ay < $by + [winfo height $fb] && $by < $ay + [winfo height $fa]}
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
    apply-opacity $w
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
        if {$cand != $w && [info exists ::frameof($cand)]
                && ![info exists ::iconic($cand)]} { return $cand }
    }
    foreach cand [array names ::frameof] {
        if {$cand != $w && ![info exists ::iconic($cand)]} { return $cand }
    }
    return 0
}

# ---- layer 1: building the strip, and turning a click into a gesture ----
#
# The titlebar is a treectrl (a one-item one): the title text in an
# expanding column whose -squeeze x text element ellipsizes what does
# not fit, and a fixed square column per button, each a stateful
# outlined box (rect element) around an svg glyph.
#
# ONE builder for both callers. A client's frame and a window the WM
# puts up for itself wear the same strip with different button sets,
# and until this was factored out they wore two COPIES of the same
# forty lines — which is how the two drifted and how adding a button
# would have meant editing both.
#
# What this proc knows about buttons is that they have names, a side
# and a picture. Which ones exist is the catalogue's business and what
# they do is the gesture table's.
proc titlebar-build {t w names title} {
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
    foreach name $names {
        if {[titlebar-side $name] eq "left"} {
            $t.title column create -width $::btnw -tags C$name
        }
    }
    $t.title column create -squeeze yes -expand yes -tags C0
    foreach name $names {
        if {[titlebar-side $name] eq "right"} {
            $t.title column create -width $::btnw -tags C$name
        }
    }
    $t.title configure -treecolumn C0
    $t.title element create eTxt text -fill white -lines 1 -font TitleFont
    $t.title element create eBox rect -outline white -outlinewidth 1 \
        -fill [list #2e3436 pressed {} {}]
    $t.title style create sTitle
    $t.title style elements sTitle eTxt
    $t.title style layout sTitle eTxt -expand $::justflags($::titlejust) \
        -padx 4 -squeeze x
    # the box fills its btnw-wide cell (glyph + ipad == btnw) and is
    # one grip shorter than the strip: -expand s sends the slack south,
    # pinning the box flush against the top border — the hole to the
    # client area opens BELOW the buttons
    set cells {}
    foreach name $names {
        $t.title element create e$name image -image [titlebar-image $name]
        $t.title style create s$name
        $t.title style elements s$name [list eBox e$name]
        $t.title style layout s$name eBox -union e$name -ipadx 3 -ipady 3 \
            -expand s
        $t.title style layout s$name e$name -expand s
        lappend cells C$name s$name
    }
    set item [$t.title item create]   ;# always item 1 in a fresh widget
    $t.title item style set $item C0 sTitle {*}$cells
    $t.title item element configure $item C0 eTxt -text $title
    $t.title item lastchild root $item
    set ::btncols($t) $names
    # Three buttons and the double, because all four are gestures the
    # table can name. w == 0 says "no client behind this frame" to the
    # shared handlers.
    foreach n {1 2 3} {
        bind $t.title <ButtonPress-$n> \
            [list title-press $t $w %x %y %X %Y $n]
        bind $t.title <ButtonRelease-$n> [list title-release $t $w %x %y $n]
    }
    bind $t.title <B1-Motion> [list title-motion $t $w %x %y %X %Y]
    bind $t.title <Double-ButtonPress-1> [list title-double $t $w %x %y]
}

# Which PART of the strip a point is on: a button's name, or "" for the
# strip itself. The columns asked about are THIS FRAME's, not the whole
# catalogue — a `column compare` against a tag the frame never created
# throws, which the confirmation dialog's close button did, all the way
# out to a bgerror box (owner's report, 2026-07-29).
proc title-button {t x y} {
    set T $t.title
    if {[catch {$T identify -array A $x $y}]} { return "" }
    if {$A(where) ne "item" || $A(column) eq ""} { return "" }
    foreach name [frame-buttons $t] {
        if {[$T column compare $A(column) == C$name]} { return $name }
    }
    return ""
}
# A press on a BUTTON arms it (the pressed state on its column alone —
# forcolumn) and the action fires on release-inside, so a drag away
# cancels. A press on the STRIP is the carry for button 1 and fires at
# once for the others: a menu that waited for the release would feel
# stuck. Arming happens only where something is bound, so a gesture
# that does nothing does not light up as if it might.
proc title-press {t w x y X Y n} {
    set b [title-button $t $x $y]
    if {$b eq ""} {
        if {$n == 1} {
            drag-start $t $w $X $Y
        } else {
            titlebar-do $t $w title <$n>
        }
        return
    }
    if {[titlebar-action $b <$n>] eq "" && $w != 0} return
    popups-close $t
    set ::btn($t) [list $b $n]
    $t.title item state forcolumn 1 C$b pressed
}
proc title-motion {t w x y X Y} {
    if {![info exists ::btn($t)]} { drag-move $t $w $X $Y; return }
    lassign $::btn($t) b -
    $t.title item state forcolumn 1 C$b \
        [expr {[title-button $t $x $y] eq $b ? "pressed" : "!pressed"}]
}
proc title-release {t w x y n} {
    if {![info exists ::btn($t)]} return
    lassign $::btn($t) b bn
    if {$n != $bn} return
    unset ::btn($t)
    $t.title item state forcolumn 1 C$b !pressed
    if {[title-button $t $x $y] eq $b} { titlebar-do $t $w $b <$n> }
}
# The second click of a pair. Tk gives it to the Double binding INSTEAD
# of the plain press, so no carry is started by it — and the first
# click's release already ended the one it did start.
proc title-double {t w x y} {
    set b [title-button $t $x $y]
    if {$b eq ""} {
        unset -nocomplain ::drag($t)
        titlebar-do $t $w title <Double-1>
    } else {
        titlebar-do $t $w $b <Double-1>
    }
}

# --- the seam itself: a part and a gesture, resolved and run ---
# The command is a prefix and the window is appended, which is why the
# window COMMANDS fit it exactly — and why a config can put any of them
# on any part without this layer growing a case for each.
proc titlebar-do {t w part gesture} {
    if {$w == 0} {
        # A window of the WM's own is not a client and the window
        # commands have nothing to act on. It answers one gesture: the
        # close box, doing whatever that window said closing means.
        if {$part eq "close" && $gesture eq "<1>"} { wm-window-close $t }
        return
    }
    set cmd [titlebar-action $part $gesture]
    if {$cmd eq ""} return
    puts "WM: titlebar $part $gesture on 0x[format %x $w] -> $cmd"
    if {[catch {uplevel #0 [list {*}$cmd $w]} err]} {
        puts "WM: titlebar $part $gesture: $err"
    }
}

# ---- strips: the furniture glued to the screen's edges ----
# A STRIP is anything the WM glues to a screen edge and reserves room
# for: a button panel, the tray riding on one. Each claims a BAND
# across one edge, and the bands are carved IN DECLARATION ORDER out of
# what is left of the screen — the first panel declared spans its whole
# edge, the next spans what that one left of its own. So the corner
# between two edges belongs to whichever strip was declared first,
# which is a rule the config steers by writing its panels in an order
# and nothing has to negotiate at run time. What survives the last
# carve is the WORKAREA: where maximize expands to and where new frames
# are placed.
#
# The tray is NOT a strip of its own. It rides on the panel it is bound
# to (set-tray-panel): the two share one band, the tray sits at its far
# end, and the band is the THICKER of them — which is what makes the
# pair read as a single bar. Either may be absent, both are opt-in, and
# a panel that nothing asks for reserves nothing at all.
proc carve-band {rect edge thick} {
    lassign $rect x y w h
    # a strip cannot claim more than there is: the workarea must stay a
    # rectangle with sides, whatever a config asks for
    set thick [expr {max(0, min($thick, ($edge in {left right}) ? $w : $h))}]
    switch -- $edge {
        top    { return [list [list $x $y $w $thick] \
                              [list $x [expr {$y + $thick}] $w [expr {$h - $thick}]]] }
        bottom { return [list [list $x [expr {$y + $h - $thick}] $w $thick] \
                              [list $x $y $w [expr {$h - $thick}]]] }
        left   { return [list [list $x $y $thick $h] \
                              [list [expr {$x + $thick}] $y [expr {$w - $thick}] $h]] }
        right  { return [list [list [expr {$x + $w - $thick}] $y $thick $h] \
                              [list $x $y [expr {$w - $thick}] $h]] }
    }
    error "carve-band: no such edge: $edge"
}
# Every band and the workarea in one pass, because they are one answer:
# each band is what its strip took from the running rectangle, and the
# workarea is that rectangle at the end. Returns {bands-dict workarea} —
# a pair and not one dict, so that a panel NAMED workarea could not
# shadow the answer.
proc strip-bands {} {
    set free [list 0 0 {*}[screen-size]]
    set bands {}
    foreach name [strip-order] {
        set thick [panel-thickness $name]
        if {[tray-panel] eq $name} {
            set thick [expr {max($thick, [tray-thickness])}]
        }
        if {$thick <= 0} continue
        lassign [carve-band $free [panel-cfg $name side] $thick] band free
        dict set bands $name $band
    }
    list $bands $free
}
# Who gets to carve, in order. The declared panels — and the tray's own
# panel even when nothing declared it: a config that asks for a tray
# and no buttons at all still gets a bar, which is what it got when the
# tray was the panel's lodger rather than a named panel's.
proc strip-order {} {
    set names [panel-names]
    if {[tray-panel] ni $names} { lappend names [tray-panel] }
    return $names
}
# The band a named panel holds, {} when it reserves nothing (no
# buttons, no tray of its own) — the callers that place furniture.
proc strip-band {name} {
    lassign [strip-bands] bands -
    if {[dict exists $bands $name]} { return [dict get $bands $name] }
    return {}
}
# The band's own edge-hugging sub-strip of THICK px: a panel thinner
# than its band (a fat tray widened it) still hugs the screen edge
# rather than floating in the middle of what it reserved.
proc band-strip {band edge thick} {
    lassign [carve-band $band $edge $thick] strip -
    return $strip
}
proc workarea {} { lindex [strip-bands] 1 }
# ...and the same answer for the world: EWMH's _NET_WORKAREA. What we
# keep for ourselves (maximize, placement) is exactly what a pager or a
# popup-placing toolkit needs, so the hook is a rename and nothing else.
proc policy-workarea {} { workarea }

# ---- maximize, fvwm semantics ----

# Maximize fills the workarea and remembers what the window was; the
# second toggle restores it. "Maximized" is a saved geometry and not a
# state the client is held in: the window can be moved and resized by
# hand meanwhile like any other.
# Three operations, not one with a mood. A MENU naturally toggles — you
# open it over a window, and the entry means "the other way" — but a
# config wants to force: `Apply-To-Matching always Maximize` that
# un-maximized every already-maximized window would be nobody's idea of
# maximizing a desk, and a key bound to Maximize should leave the window
# maximized however many times it is pressed. So the vocabulary forces
# and the menu names the toggle (owner, 2026-07-29).
# What a HAND resize does to the maximized mark: two honest readings, so
# it is a knob (2026-07-29) — and the default is the MEASURED one, since
# the attribution was wrong when the knob was written. fvwm3, driven by
# hand (owner, 2026-07-30):
#
#   drop (default) — fvwm3's own, measured. A hand resize means this is
#     no longer the maximized window: the mark goes, the next toggle
#     MAXIMIZES rather than restoring — in either direction, a window
#     pulled BIGGER maximizes just the same — and it saves the hand-set
#     geometry, so the toggle after that comes back to what the hand
#     made. Windows and GNOME read it this way too.
#   keep — the mark survives; the toggle puts back what was saved AT
#     MAXIMIZE TIME however the window has been pulled about since. This
#     was called fvwm's here and is nobody's that we know of, but it is
#     a coherent reading of "the mark is a saved geometry, full stop"
#     and it stays available.
#
# It is about resizing only. Carrying a maximized window somewhere else
# leaves it maximized under either reading — measured in fvwm3 too — that
# gesture moves a window and says nothing about its size, and the
# desktops that unmaximize on a title drag are doing something else
# entirely (they resize it to the saved size under the pointer, which
# nobody has asked for here).
keep maximize drop
proc set-maximize {mode} {
    if {$mode ni {keep drop}} { error "set-maximize: keep|drop" }
    set ::maximize $mode
}
proc maximize-guard {w} {
    if {![info exists ::frameof($w)]} { return 0 }
    # Fullscreen already owns this window's geometry, and the two would
    # fight over the same saved copy. Refused audibly rather than
    # silently: the request came from a menu the user just used.
    if {[info exists ::fullscreen($w)]} {
        puts "WM: maximize ignored — 0x[format %x $w] is fullscreen"
        return 0
    }
    return 1
}
# The client size maximize gives THIS window in that rect: the rect
# minus this frame's decoration, snapped by the client's own size hints
# — increments bind maximize too (an xterm fills to whole cells, and the
# slack stays at the far edge), unless a style says otherwise.
#
# Its own proc because two callers need the same arithmetic and must not
# each carry a copy: maximize does it TO a window, and the reflow below
# asks whether a window already IS the shape it would have made — which
# is only answerable by the same sum, slack and all.
proc maximize-fit {w rect} {
    lassign [frame-chrome $::frameof($w)] B top
    lassign $rect - - rw rh
    apply-size-hints $w [expr {$rw - 2*$B}] [expr {$rh - $top - $B}]
}
proc maximize-client {w} {
    if {![maximize-guard $w]} return
    set t $::frameof($w)
    # Only the FIRST maximize records where to go back to. Calling this
    # on an already-maximized window re-fits it to the workarea as it is
    # now — and must not overwrite the saved geometry with the maximized
    # one, which would lose the way back entirely.
    if {![info exists ::maxsaved($w)]} {
        regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> X Y
        set ::maxsaved($w) \
            [list [$t.slot cget -width] [$t.slot cget -height] $X $Y]
    }
    set wa [workarea]
    wm geometry $t +[lindex $wa 0]+[lindex $wa 1]
    wm-resize-client $w {*}[maximize-fit $w $wa]
    maximize-settle $w
}
proc unmaximize-client {w} {
    if {![maximize-guard $w]} return
    if {![info exists ::maxsaved($w)]} return   ;# not maximized: nothing to undo
    set t $::frameof($w)
    lassign $::maxsaved($w) cw ch X Y
    unset ::maxsaved($w)
    wm geometry $t +$X+$Y
    wm-resize-client $w $cw $ch
    maximize-settle $w
}
proc maximize-toggle {w} {
    if {[info exists ::maxsaved($w)]} {
        unmaximize-client $w
    } else {
        maximize-client $w
    }
}
# wm-resize-client skips a no-op resize and tells the client nothing
# then — but the frame MOVED either way, so state the origin once more,
# from settled Tk geometry.
proc maximize-settle {w} {
    update idletasks
    send-synthetic-configure $w
}

# ---- fullscreen, the substrate's policy-fullscreen hook ----
# Maximize's stronger cousin, and the differences are all deliberate.
# It takes the SCREEN and not the workarea (a fullscreen window that
# stopped at the panel would be no such thing); the decoration goes
# away with the strips rather than staying around the edge; and the
# size hints do NOT bind it — EWMH says a fullscreen window fills the
# screen, so a terminal shows a few pixels of slack at one edge
# instead of leaving a decorated band there. The saved geometry is its
# own (::fssaved), separate from maximize's: a window can be
# maximized, go fullscreen and come back to being maximized, and each
# toggle still restores what IT remembered.
proc policy-fullscreen {w on} {
    if {![info exists ::frameof($w)]} return
    set t $::frameof($w)
    if {$on} {
        regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> X Y
        set ::fssaved($w) \
            [list [$t.slot cget -width] [$t.slot cget -height] $X $Y]
        set ::fullframe($t) 1
        lassign [screen-size] cw ch
    } else {
        if {![info exists ::fssaved($w)]} return
        lassign $::fssaved($w) cw ch X Y
        unset ::fssaved($w)
        unset -nocomplain ::fullframe($t)
    }
    # The furniture FIRST and the client second, and the frame-layout
    # call is not left to wm-resize-client's: that one skips a resize
    # whose numbers did not move (a window already the size of the
    # screen going fullscreen is exactly that case) and would leave the
    # decoration standing around a window that has none.
    frame-layout $t $cw $ch $X $Y
    wm-resize-client $w $cw $ch
    if {$on} { raise $t } else { panel-on-top }
    update idletasks
    send-synthetic-configure $w
}
# Nothing of ours stays above a fullscreen window — that is what the
# state MEANS, and the panel and the tray are the two that would. Both
# strips lift themselves for their own reasons (a rebuild, an icon
# docking), so the rule cannot live at the moment of going fullscreen:
# it has to run after every one of those lifts.
proc fullscreen-on-top {} {
    foreach w [array names ::fullscreen] {
        if {[info exists ::frameof($w)]} { raise $::frameof($w) }
    }
}
# The user's own toggle (the ops menu, or a config's chord), as opposed
# to the client asking through EWMH. Both end in the substrate's pair,
# which is where the state and the property live.
proc fullscreen-toggle {w} {
    if {[info exists ::fullscreen($w)]} {
        unfullscreen-client $w
    } else {
        fullscreen-client $w
    }
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
    lassign [list $::border $::decotop $::titleh] B top titleh
    toplevel $t -background #3465a4
    wm overrideredirect $t 1
    set ::closeof($t) $closescript
    canvas $t.deco -highlightthickness 0 -borderwidth 0 -background #3465a4
    place $t.deco -x 0 -y 0 -relwidth 1 -relheight 1
    bind $t.deco <Configure> {deco-draw %W %w %h}
    # The same strip every client wears, from the same builder, with a
    # button set of its own: no menu and no maximize on ours (there is
    # no client to command and nothing sensible to maximize), and it is
    # dragged by its titlebar like anything else on this desk.
    titlebar-build $t 0 {close} $title
    frame $t.slot -width $cw -height $ch -background #202020
    lassign [screen-size] sw sh
    set W [expr {$cw + 2*$B}]
    set H [expr {$ch + $top + $B}]
    # Centred, but never off the left or top edge: a question long
    # enough to outgrow the screen would otherwise start off-screen,
    # taking its buttons with it.
    frame-layout $t $cw $ch \
        [expr {max(0, ($sw - $W) / 2)}] [expr {max(0, ($sh - $H) / 3)}]
    raise $t
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
        -background #202020 -foreground white
    place $slot.q -x $pad -y $pad
    set by [expr {$ch - $pad - $bh}]
    foreach {which text x} [list \
            no  Cancel    [expr {$cw - 2*$pad - 2*$bw}] \
            yes $yeslabel [expr {$cw - $pad - $bw}]] {
        label $slot.$which -text $text -font TitleFont -foreground white
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
        .confirm.slot.$which configure \
            -background [expr {$on ? "#3465a4" : "#2e3436"}]
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
    foreach m {.winlist .winops .confirm} {
        if {$m eq $except} continue
        if {[winfo exists $m]} {
            grab-keys-to {}
            # A dismissed wm-window leaves no bookkeeping behind. Its
            # close SCRIPT is deliberately not run: dismissing IS the
            # cancel, and cancel does nothing by definition.
            unset -nocomplain ::closeof($m) ::btncols($m) ::drag($m) ::btn($m)
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
    foreach m {.winlist .winops .confirm} {
        if {[winfo exists $m] && !$modal} {
            lappend bad "$m is up with no router"
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
    return $bad
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
keep winlist_cycle_opt 1
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
keep icon_path [list ~/.local/share/icons/hicolor/48x48/apps \
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
# popup by the button. The anchor is "center" or {panel NAME I} — the
# panel's name, because which strip the button is on decides which way
# the list opens off it (see below); only the
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
        set title [iconic-label $w [title-or-id $w [client-title $w]]]
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
        # By the button, and always on the strip's INNER face — the list
        # opens over the desk, never off the screen edge the strip is
        # glued to: over a bottom panel, under a top one, beside a
        # vertical one. (popup-show clamps to the screen either way.)
        lassign $anchor - pname bi
        set P [panel-window $pname]
        set T [panel-tree $pname]
        lassign [$T item bbox [expr {$bi + 1}]] bx by
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
        if {[info exists ::iconic($w)]} {
            deiconify-client $w    ;# raises and focuses on its own
            return
        }
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

# ---- window commands ------------------------------------------------
#
# An imperative over ONE window, named with a Capital. The rest of the
# config vocabulary is lowercase and DECLARATIVE — set-* knobs,
# wm-style, panel-button, filter, always: they describe a desk and say
# nothing about when. A Capital says the opposite, that this one acts
# the moment it is called; the case is the whole distinction, and it
# costs nothing to see.
#
# It also buys the names outright. Tcl and Tk already own `raise`,
# `lower`, `close` and `destroy`, so a lowercase vocabulary would have
# had to spell four of its ten verbs differently — `close-window` next
# to `minimize` — and a config author would have to remember which four.
# Raise and Close are ours; raise and close are still Tk's.
#
# Each takes the window as an OPTIONAL argument, and without one asks
# the context. That is what makes one definition serve two callers:
#
#   wm-bind {<Ctrl><Shift>z} Minimize          the active window
#   Apply-To-Matching always Minimize          each in turn
#
# and the winops menu, which acts on the window it was opened over. The
# context is a bound subject where there is one, and the focused client
# everywhere else.
keep subject_window 0
proc current-window {} {
    expr {$::subject_window != 0 ? $::subject_window : $::focused}
}
# Run a script with the subject bound. Restores on the way out however
# the script leaves — a window command can throw, and a subject left
# standing would silently retarget every later bare command.
proc with-window {w script} {
    set save $::subject_window
    set ::subject_window $w
    try {
        uplevel 1 $script
    } finally {
        set ::subject_window $save
    }
}

# Who is asking — the user, or a program? This is Emacs's
# called-interactively-p, kept for the same reason it exists there: one
# name should mean the obvious thing in both mouths, and the obvious
# thing differs.
#
# A USER toggles. Open the window menu over a maximized window and pick
# Maximize and you mean "the other way"; there is no other reading,
# because you are looking at the window while you say it. The same goes
# for a key you press yourself.
#
# A PROGRAM does not. `Apply-To-Matching always Maximize` means make
# this desk maximized, and a toggle would un-maximize precisely the
# windows that were already right — a sweep whose result depends on the
# state it found is not a sweep, it is a coin toss per window.
#
# So: interactive unless a program says otherwise, and the program that
# says so is the one driving other commands. Nothing needs to mark the
# menu or a key binding as "the user" — that is the default, and the
# default is the common case.
keep programmatic 0
proc programmatically {script} {
    set save $::programmatic
    set ::programmatic 1
    try {
        uplevel 1 $script
    } finally {
        set ::programmatic $save
    }
}
proc interactive-p {} { expr {!$::programmatic} }

# The two commands that read it. Everything else in the table means one
# thing in either mouth — there is no toggling sense of Close, and
# Minimize has none either (a window you can pick the menu over is on
# the screen by definition).
proc maximize-command {w} {
    if {[interactive-p]} { maximize-toggle $w } else { maximize-client $w }
}
proc fullscreen-command {w} {
    if {[interactive-p]} { fullscreen-toggle $w } else { fullscreen-client $w }
}

# name -> the proc that does the work; every one of them takes a window.
# The Un- pair is unconditional in both mouths: a user who wants the way
# out and no guessing has it, and so does a sweep.
set window_commands {
    Maximize     maximize-command
    Unmaximize   unmaximize-client
    Fullscreen   fullscreen-command
    Unfullscreen unfullscreen-client
    Close        close-client
    Destroy      kill-client
    Raise        raise-group
    Lower        lower-group
    Bury         bury-group
    Move         move-keyboard
    Resize       resize-keyboard
    Minimize     policy-minimize-request
    Fade         fade-command
    Unfade       unfade-command
}
proc window-do {name {w 0}} {
    if {$w == 0} { set w [current-window] }
    if {$w == 0 || ![info exists ::frameof($w)]} {
        puts "WM: $name: no window"
        return 0
    }
    with-window $w [list [dict get $::window_commands $name] $w]
    invariants-soon   ;# a command is the other thing that can pull a rug
    return 1
}
# An alias apiece, so the name IS the command. The shadow check is not
# ceremony: a table entry that collided with a Tk command would replace
# it for the whole interpreter — `destroy` is how every decoration in
# this file is torn down — and the damage would show up somewhere else
# entirely. Failing here, at load, is the cheap end of that.
foreach {_name _impl} $window_commands {
    # An alias of ours from a previous load is not a collision — it is
    # this very line, run before. Anything else that answers to the
    # name IS one, and failing here at load is the cheap end of that.
    if {[llength [info commands ::$_name]]
            && [interp alias {} ::$_name] eq ""} {
        error "window command $_name would shadow the existing command ::$_name"
    }
    interp alias {} ::$_name {} window-do $_name
}

# Commands about the DESK rather than a window — same Capital, nothing
# to resolve. The lowercase originals stay: they are the implementations
# (as close-client is the implementation behind Close), the substrate
# and this file call them by those names, and a config written before
# the vocabulary existed keeps working.
# Quit asks first — but only when a PERSON asked. The same rule as
# Maximize: a program that says Quit means it, and a modal question put
# to a script is a hang rather than a safeguard.
# The question warns rather than reassures, and deliberately does not
# try to work out which it should do.
#
# What the window manager can promise is only its own half: it RELEASES
# every client instead of destroying it, so nothing dies by our hand.
# What happens next is the session's business, and in nearly every real
# setup the session ends with us — .Xsession finishes with `exec wm`,
# or with `wm & … wait`, and either way our exit is the end of the
# script and every window goes with it. Only a window manager started
# by hand inside an existing session leaves its clients standing.
#
# It said "Windows stay open" for one commit, which was true of the
# case almost nobody is in. Detecting the difference was the obvious
# next thought and is a trap (owner, 2026-07-29): pid == session id
# catches `exec wm` and misses `wm & wait` completely — where we are
# NOT the leader and the session ends anyway — so the heuristic would
# print the reassuring line in precisely the case that must not be
# reassured. A guess that fails toward "it's fine" is worse than no
# guess, so: no guess, and the pessimistic wording, which is also the
# true one nearly always.
proc quit-command {} {
    if {![interactive-p]} { quit-wm; return }
    confirm "tk9wm" "Quit? The X session normally ends with the\
        window manager." Quit quit-wm
}
set desk_commands {
    Restart restart-wm
    Reload  reload-config
    Reread  reread-layers
    Quit    quit-command
}
foreach {_name _impl} $desk_commands {
    if {[llength [info commands ::$_name]]
            && [interp alias {} ::$_name] eq ""} {
        error "desk command $_name would shadow the existing command ::$_name"
    }
    # reload-config lives in main.tcl, which is sourced after this file;
    # an alias resolves at call time, so declaring it here is fine.
    interp alias {} ::$_name {} $_impl
}
unset _name _impl

# Run a window command over every window a predicate accepts — the
# sweep behind "minimize everything", and behind anything else worth
# doing to a whole desk at once:
#
#   wm-bind {<Super>d} {Apply-To-Matching always Minimize}
#
# The predicate is the one wm-style and a panel button's match already
# take (`always`, `{filter -class ...}`, a proc of your own), so there
# is one matching language here, not two.
#
# The target list is a SNAPSHOT taken before anything runs. These
# commands unmap, close and unmanage windows — iterating the live set
# would be iterating a list the body is editing — and a window that
# dies mid-sweep is skipped rather than mourned. Order is
# most-recently-focused first, the window list's order: a hash order
# would land differently on every run, which is no way to write a
# regression, and MRU means the focus walks down the history as each
# window leaves rather than jumping about.
#
# Nothing here is allowed to abort the sweep. A predicate that throws
# on one window, or a command that does, costs that window and no
# other: "as many as possible" is the contract, and a desk half swept
# because window three had a bad style rule is not it.
proc Apply-To-Matching {pred command} {
    programmatically { Apply-To-Matching-1 $pred $command }
}
proc Apply-To-Matching-1 {pred command} {
    set targets {}
    foreach w $::focus_hist {
        if {[info exists ::managed($w)]} { lappend targets $w }
    }
    foreach w [array names ::managed] {
        if {$w ni $targets} { lappend targets $w }
    }
    set matched 0
    foreach w $targets {
        if {![info exists ::managed($w)]} continue   ;# gone since the snapshot
        if {[catch {uplevel #0 [list {*}$pred $w]} verdict]} {
            puts "WM: Apply-To-Matching: predicate error on 0x[format %x $w]: $verdict"
            continue
        }
        if {!$verdict} continue
        incr matched
        if {[catch {$command $w} err]} {
            puts "WM: Apply-To-Matching: $command failed on\
                  0x[format %x $w]: $err"
        }
    }
    # Counted as MATCHED and tried, not as succeeded — a window command
    # does not report back, and it should not have to: whether this
    # particular window took the operation is between it and the
    # command (a style that refuses minimization says so in its own
    # line). Claiming a success count here would be inventing one.
    puts "WM: Apply-To-Matching $command: $matched of [llength $targets] matched"
    return $matched
}

# ---- the window ops menu ----
# Actions on ONE window — the fvwm-style dropdown: from the titlebar's
# left button, or on the focused window by key. Anchored at the
# window's top-left corner, right below the titlebar. Every action
# carries a hotkey letter (shown right-aligned, fvwm menus underline
# theirs — a column reads better in a treectrl); a bare letter press
# fires it, and the navigation letters yield to hotkeys while
# Ctrl+P/Ctrl+N always navigate (popup-nav).
#
# fullscreen is on the list and not only on the clients' own keys for a
# plain reason: a fullscreen window has no titlebar and no border, so
# if the client that asked for the state will not take it back — or
# never had a key for it — this menu is the only way out. Alt+Space
# reaches it through the WM's own grab, over the fullscreen window.
# The menu is a SELECTION from the window commands plus a hotkey letter
# apiece — it does not carry its own copy of what each one does. It used
# to, and two lists meaning the same thing is how a menu entry and a key
# binding drift into doing different things.
set winops_actions {
    Maximize   x
    Fullscreen f
    Close      c
    Destroy    d
    Raise      r
    Lower      l
    Bury       b
    Move       m
    Resize     s
    Minimize   i
}
proc winops {{w 0}} {
    if {$w == 0} { set w $::focused }
    if {$w == 0 || ![info exists ::frameof($w)]} {
        popups-close
        puts "WM: winops: no window"
        return
    }
    set ::winops_win $w
    set n [expr {[llength $::winops_actions] / 2}]
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
    foreach {label key} $::winops_actions {
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
    lassign [frame-chrome $t] B top
    popup-show .winops [expr {max($maxw + $ih + 40, 160)}] \
        [expr {$n * $ih + 2}] \
        [expr {[winfo rootx $t] + $B}] \
        [expr {[winfo rooty $t] + $top}]
    if {![grab-keys-to winops-key]} {
        puts "WM: winops: keyboard not grabbed — mouse only"
    }
    puts "WM: winops open 0x[format %x $w]"
}
proc winops-key {kind name mods} {
    if {$kind eq "release"} return
    if {$mods == 0} {
        set i 0
        foreach {label key} $::winops_actions {
            incr i
            if {$name eq $key} { winops-fire $i; return }
        }
    }
    set d [popup-nav $name $mods]
    if {$d != 0} {
        popup-move .winops.t [expr {[llength $::winops_actions] / 2}] $d
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
    lassign [lrange $::winops_actions [expr {($i - 1) * 2}] [expr {$i * 2 - 1}]] \
        command key
    popups-close
    if {![info exists ::frameof($w)]} return
    puts "WM: winops 0x[format %x $w] $command"
    $command $w
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
# Which keysym names name a cell. The numpad arrives by its LEVEL-0
# names and not as digits at all — the key router reads keysym level 0
# (handle-key), where an ordinary pc105 keymap has KP_Home/KP_Up/…
# whatever NumLock is doing, which is why the mode does not care about
# NumLock. KP_1..KP_9 are listed too, for the layouts that do put the
# digit on level 0; on a normal one they simply never arrive.
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
once fonts-compass {font create CompassFont -weight bold}

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
        -size [expr {-2 * $::titleh}]
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
    lassign [screen-size] sw sh
    set s $::compass_s
    foreach cell $::compass {
        lassign $::compass_cells($cell) halign valign
        set X [place-axis $rx $rw $s $halign]
        set Y [place-axis $ry $rh $s $valign]
        set X [expr {max(0, min($X, $sw - $s))}]
        set Y [expr {max(0, min($Y, $sh - $s))}]
        wm geometry .compass$cell ${s}x${s}+$X+$Y
        raise .compass$cell
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
    set wa [workarea]
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
    # inevitable. It is not, and the answer was already in this file
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
    lassign [workarea] wax way ww wh
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
proc keyecho-anchor {spec} {
    set h center
    set v center
    foreach term [split [string map {, " "} $spec]] {
        if {$term eq ""} continue
        if {[regexp {^[0-9]+%} $term]} {
            error "set-key-echo-place: the box is as big as its text —\
 «$term» has nothing to size"
        }
        switch -- $term {
            left    { set h start }
            right   { set h end }
            hcenter { set h center }
            top     { set v start }
            bottom  { set v end }
            vcenter { set v center }
            center  { set h center; set v center }
            default { error "set-key-echo-place: cannot read term «$term»" }
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
    if {$::key_echo eq "off" && $kind ne "help"} return
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
        [expr {$kind eq "flash" ? $::KEY_ECHO_BAD : $::KBMR_BG}]
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
    raise $b
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
# Where and how, two knobs. set-panel-side top|bottom|left|right picks
# the screen edge (left and right are vertical treectrls — only the
# flow orientation and the band's geometry change, the button logic
# never sees the side). set-panel-preset row|stack picks the button
# layout when any face is iconic: row is <image> Text, stack puts the
# label under the icon — the tall-strip look for a thick bottom bar or
# a narrow side one.
#
# There can be MORE THAN ONE. A panel is an instance, named, declared
# with a block:
#
#   panel dock { set-panel-side left; panel-button терм {...} }
#
# and everything said outside a block belongs to the panel named
# `default` — which is why a config that never heard of the plural
# keeps working unchanged. Each panel carries its own side, preset,
# icon size and buttons; the bands they reserve are carved in
# declaration order (see the strips section), so two panels are a
# taskbar and a dock without either knowing about the other.
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
# Every panel's settings in ONE variable, keyed by name — a Tcl dict
# keeps its insertion order, so the dict IS the declaration order the
# bands are carved in, and the config layer's snapshot/restore machinery
# (which knows how to put a variable back) covers panels for free.
# Build products stay OUT of it: the live widget and the arrow zone are
# per-panel too, but they are what a build produced, not what the user
# asked for, and a reset has no business restoring them.
proc panel-defaults {} {
    dict create side bottom preset row icon_size 48 buttons {}
}
# Empty, and `default` is created on first mention like any other name.
# That is what makes the dict's order the CONFIG's order: a `default`
# present from the start would always have been the first band carved,
# whatever the config wrote first, and the corner rule would be a rule
# about our initialization rather than about the config.
keep panels {}
keep panel_target default   ;# whose knobs the config is turning right now
array set panel_win {}     ;# name -> the live top-level, absent = not built
array set panel_zone {}    ;# name -> its reserved arrow strip, set per build
# The block form. `panel NAME BODY` points the knobs at NAME for the
# length of BODY and puts them back afterwards — uplevel, so the body
# is ordinary config code that can call anything, and the target is
# restored even if it throws (a config that dies mid-block must not
# leave every later declaration landing in a panel nobody can see).
proc panel {name body} {
    if {$name eq ""} { error "panel: a panel needs a name" }
    panel-ensure $name
    set outer $::panel_target
    set ::panel_target $name
    set code [catch {uplevel 1 $body} res opts]
    set ::panel_target $outer
    if {$code} { return -options $opts $res }
    return $res
}
proc panel-ensure {name} {
    if {![dict exists $::panels $name]} {
        dict set ::panels $name [panel-defaults]
    }
}
proc panel-names {} { dict keys $::panels }
# A panel nobody declared answers with the CODE's defaults rather than
# throwing: the tray can be pointed at a name that never came to exist
# (a typo, a block that died before its first button), and the honest
# answer to "which edge is it on then" is the default edge — not an
# error that takes the desk's geometry down with it.
proc panel-cfg {name key} {
    if {[dict exists $::panels $name]} { return [dict get $::panels $name $key] }
    return [dict get [panel-defaults] $key]
}
proc panel-set {name key value} {
    panel-ensure $name
    dict set ::panels $name $key $value
    panel-rebuild-soon
}
# The live widgets of a built panel: the top-level and its treectrl.
# "" when this panel has no strip up (no buttons, or not built yet) —
# every caller that pokes at the tree checks, because a panel can be
# rebuilt out from under a deferred callback.
proc panel-window {name} {
    if {[info exists ::panel_win($name)] && [winfo exists $::panel_win($name)]} {
        return $::panel_win($name)
    }
    return ""
}
proc panel-tree {name} {
    set p [panel-window $name]
    expr {$p eq "" ? "" : "$p.t"}
}
proc set-panel-side {side} {
    if {$side ni {top bottom left right}} {
        error "set-panel-side: top, bottom, left or right"
    }
    panel-set $::panel_target side $side
}
proc set-panel-preset {preset} {
    if {$preset ni {row stack}} { error "set-panel-preset: row or stack" }
    panel-set $::panel_target preset $preset
}
proc set-panel-icon-size {px} {
    panel-set $::panel_target icon_size $px
}
keep panel_live_bar  #8ae234  ;# the indicator strip
keep panel_live_face #5d6e59  ;# the face tint under a live match
proc set-panel-live-colors {bar face} {
    set ::panel_live_bar $bar
    set ::panel_live_face $face
    panel-rebuild-soon
}
proc panel-button {label settings} {
    set name $::panel_target
    panel-ensure $name
    set buttons [panel-cfg $name buttons]
    lappend buttons [list $label $settings]
    dict set ::panels $name buttons $buttons
    if {[dict exists $settings key]} {
        # ...and the binding carries the BUTTON'S name, so the help
        # list reads "Super+e → emacs" and not "panel-fire dock 2".
        wm-bind [dict get $settings key] \
            [list panel-fire $name [expr {[llength $buttons] - 1}]] $label
    }
    # `style` is a shorthand and nothing more: the button's own match
    # predicate, handed to wm-style with these settings. It exists
    # because a button and the windows it finds are usually described by
    # the SAME filter, and writing it twice (or hoisting it into a proc
    # to write it once) is bookkeeping the config should not have to do.
    # The rule lands in the list AT THIS POINT, so precedence still
    # reads straight down the config file.
    if {[dict exists $settings style]} {
        if {![dict exists $settings match]} {
            error "panel-button $label: style needs a match to apply to"
        }
        wm-style [dict get $settings match] [dict get $settings style]
    }
    panel-rebuild-soon
}
# one rebuild per config's worth of declarations (or knob twiddles) —
# and it is every panel that is rebuilt, not the one whose knob moved:
# the bands are carved from one another, so a strip that got thicker
# moves the one declared after it too.
proc panel-rebuild-soon {} {
    array unset ::panel_geo    ;# the knob that asked may have changed the shape
    if {![info exists ::panel_pending]} {
        set ::panel_pending 1
        after idle {unset ::panel_pending; panels-build}
    }
}
# Every button of every panel, as {panel index label settings} — the
# sweeps (re-judging matches, counting for a log line) say what they do
# to a button and not which panel it is on.
proc panel-all-buttons {} {
    set out {}
    dict for {name p} $::panels {
        set i 0
        foreach b [dict get $p buttons] {
            lappend out [list $name $i {*}$b]
            incr i
        }
    }
    return $out
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
keep panel_reeval_pending ""
proc panel-match-kick {} {
    if {![llength [panel-all-buttons]]} return
    after cancel $::panel_reeval_pending
    set ::panel_reeval_pending [after 200 panel-reeval]
}
proc panel-reeval {} {
    foreach b [panel-all-buttons] {
        lassign $b name i label settings
        set T [panel-tree $name]
        if {$T eq ""} continue
        set n [llength [panel-matches $label $settings]]
        $T item state set [expr {$i + 1}] \
            [list [expr {$n >= 1 ? "live" : "!live"}] \
                  [expr {$n >= 2 ? "multi" : "!multi"}]]
    }
}
# Everything the strip's shape depends on, decided in one place: the
# resolved face of every button ("" = no icon or a miss — one case,
# the badge), whether anything is iconic at all, the item height for
# the preset, and the strip thickness (horizontal: the item height;
# vertical: the widest button). The builder and the band's thickness
# question both come here; resolution is cached, so asking is cheap.
#
# MEMOIZED per rebuild, and that is a correctness fix and not a saving.
# One rebuild asks this many times — the builder once per panel, then
# every band carve once more — and it has to be the SAME answer every
# time: the band a panel reserves and the strip it draws are two
# consumers of one number.
#
# They came apart for real. Under a stock tclkit's Tk (core X fonts,
# helvetica) the two calls inside ONE build disagreed: 96 px for the
# builder, 70 for the band a moment later, the labels measuring half
# their width the second time. The strip then drew 70 inside a band
# that had reserved 96 and left a dead stripe nothing could use — and
# only the carve's clamp kept it from drawing outside its band
# altogether. Which of Tk's two answers is the honest one is not this
# code's business to adjudicate (an independent interpreter measuring
# that font agrees with the builder's); making the disagreement
# IMPOSSIBLE is. Every path that can change the answer goes through
# panel-rebuild-soon or panels-build, and both drop the memo.
array set panel_geo {}
proc panel-geometry {name} {
    if {![info exists ::panel_geo($name)]} {
	set ::panel_geo($name) [panel-measure $name]
    }
    return $::panel_geo($name)
}
proc panel-measure {name} {
    set buttons [panel-cfg $name buttons]
    set preset [panel-cfg $name preset]
    set isz [panel-cfg $name icon_size]
    set vert [expr {[panel-cfg $name side] in {left right}}]
    set faces {}
    set iconic 0
    foreach b $buttons {
        lassign $b label settings
        set img ""
        if {[dict exists $settings icon]} {
            set img [resolve-icon [dict get $settings icon] $isz]
        }
        if {$img ne ""} { set iconic 1 }
        lappend faces $img
    }
    set line [font metrics TitleFont -linespace]
    # badge lettering follows the badge size (the winlist formula)
    set bfont [panel-badge-font $name]
    font configure $bfont -family [font actual TitleFont -family] \
        -size -[expr {max(7, $isz * 5 / 8)}]
    # the arrow zone: once ANY button can match, every button
    # reserves an east strip for the multi arrow — the row reads
    # uniformly, an unarmed button just shows calm space there
    set aw [font measure TitleFont ▾]
    set zoned 0
    foreach b $buttons {
        if {[dict exists [lindex $b 1] match]} { set zoned 1; break }
    }
    set zone [expr {$zoned ? $aw + 12 : 0}]
    if {!$iconic} {
        set content $line
    } elseif {$preset eq "stack"} {
        set content [expr {$isz + 2 + $line}]
    } else {
        set content [expr {max($isz, $line)}]
    }
    # The two paddings the item's height is made of, named because the
    # live indicator has to find the face's edge again later: FPAD is
    # the face's own inner air (-ipady), FGAP the air between the face
    # and the item's edge.
    set FPAD 3
    set FGAP 5
    set itemh [expr {$content + 2*$FPAD + 2*$FGAP}]
    if {![llength $buttons]} {
        set thick 0
    } elseif {$vert} {
        set maxw 0
        foreach b $buttons f $faces {
            lassign $b label settings
            set tw [font measure TitleFont $label]
            if {!$iconic} {
                set cw $tw
            } else {
                set iw $isz
                if {$f eq ""} {
                    # the badge: at least the square, wide letters grow it
                    set iw [expr {max($isz, [font measure $bfont \
                        [lindex [pseudo-badge $label] 0]])}]
                }
                if {$preset eq "stack"} {
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
        zone $zone aw $aw fpad $FPAD fgap $FGAP vert $vert \
        preset $preset icon_size $isz badge_font $bfont
}
proc panel-thickness {name} { dict get [panel-geometry $name] thick }
# One badge font per panel, created on demand and named after the
# panel. Named and not indexed: a rebuild renumbers the widgets, and a
# font that changed meaning between two builds would letter a badge
# from somebody else's icon size.
proc panel-badge-font {name} {
    set f "PanelBadge-$name"
    if {$f ni [font names]} { font create $f -weight bold }
    return $f
}
# Every panel, from nothing: the live strips come down and are put
# back up in declaration order. Wholesale and not per panel, because a
# band is carved out of what the bands before it left — a strip that
# grew moves every strip declared after it, and rebuilding just the one
# whose knob moved would leave the rest overlapping it.
#
# The widget path is the panel's INDEX and not its name: a name comes
# from the config and may be anything the user typed (Cyrillic, a dot,
# a leading capital — all illegal or ambiguous in a Tk path), while an
# index is always a legal component. The mapping is remembered in
# ::panel_win, which is what every later poke goes through.
proc panels-build {} {
    array unset ::panel_geo    ;# fonts, RandR and the config all land here
    foreach name [array names ::panel_win] {
        destroy $::panel_win($name)
        unset ::panel_win($name)
    }
    array unset ::panel_zone
    # a font outlives the panel that asked for it (a reload can drop a
    # panel entirely); collect the orphans rather than leak one per name
    foreach f [font names] {
        if {[string match "PanelBadge-*" $f]
            && ![dict exists $::panels [string range $f 11 end]]} {
            font delete $f
        }
    }
    set idx 0
    dict for {name p} $::panels {
        incr idx
        if {[llength [dict get $p buttons]]} { panel-build $name $idx }
    }
    tray-layout      ;# a panel's thickness is the tray's too — it follows
    fullscreen-on-top ;# ...and the strips just lifted themselves over the desk
    publish-workarea ;# they just took a bite out of the screen
}
proc panel-build {name idx} {
    set g [panel-geometry $name]
    set faces [dict get $g faces]
    set iconic [dict get $g iconic]
    set itemh [dict get $g itemh]
    set thick [dict get $g thick]
    set zone [dict get $g zone]
    set aw [dict get $g aw]
    set vert [dict get $g vert]
    set preset [dict get $g preset]
    set isz [dict get $g icon_size]
    set bfont [dict get $g badge_font]
    set side [panel-cfg $name side]
    set buttons [panel-cfg $name buttons]
    set ::panel_zone($name) $zone
    set er [expr {8 + $zone}]   ;# the face's east inner pad
    set P .panel$idx
    set ::panel_win($name) $P
    # A VERTICAL strip is one column, and a column wants one width: the
    # faces are stretched to the widest button's content so their edges
    # line up instead of every face hugging its own label (owner's
    # report, 2026-07-29 — "ничего не выровнено друг с другом"). The
    # face is a UNION element and treectrl ignores -iexpand on those
    # (the badge square met the same wall), so the minimum goes on a
    # MEMBER: the label cell, which every style has. The arithmetic is
    # panel-geometry's, backwards — the strip is content + 20 + zone
    # wide, so the content cell is the strip less its own paddings.
    set memw [expr {max(1, $thick - 2 - 4 - 8 - $er)}]
    # The face is PINNED by its own vertical padding instead of being
    # left to float in the item's slack: the two presets distributed
    # that slack differently (a row centres its content, a stack lets
    # it sit at the top), so the face's lower edge — where the live
    # indicator has to land — was in a different place in each. With
    # the pad, the item is exactly face + 2*fgap and the edge is one
    # number in both.
    set fgap [dict get $g fgap]
    toplevel $P -background $::OUTLINE
    wm overrideredirect $P 1
    set T [treectrl $P.t -showheader no -showroot no -showbuttons no \
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
    $T element create ePTxt text -fill white -lines 1 -font $bfont
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
        -padx 2 -pady $fgap -expand ns
    $T style layout sBtn eBTxt -expand ns
    if {$iconic && $preset eq "stack"} {
        $T style create sBtnI -orient vertical
        $T style elements sBtnI {eFace eBIcon eBTxt}
        $T style layout sBtnI eFace -union {eBIcon eBTxt} \
            -ipadx [list 8 $er] -ipady 3 -padx 2 -pady $fgap -expand wens
        $T style layout sBtnI eBIcon -expand we -pady {0 2}
        $T style layout sBtnI eBTxt -expand we
        $T style create sBtnB -orient vertical
        $T style elements sBtnB {eFace ePRect ePTxt eBTxt}
        $T style layout sBtnB eFace -union {ePRect eBTxt} \
            -ipadx [list 8 $er] -ipady 3 -padx 2 -pady $fgap -expand wens
        # The pad goes on the LETTERING, not on the rect around it: a
        # union element is not in the flow, and padding it grows the
        # union instead of spacing the flow (measured — the badge
        # button's content came out 4px taller than an icon button's,
        # so its whole stack sat lower and the label came down onto its
        # own indicator; owner's report, 2026-07-29).
        $T style layout sBtnB ePRect -union ePTxt -expand we
        # -expand we and not wens, exactly as the icon above it: with a
        # vertical slack to grab, the lettering grabs it, and the badge
        # button's whole stack slides down onto its own indicator.
        $T style layout sBtnB ePTxt -minwidth $isz -minheight $isz \
            -expand we -pady {0 2}
        $T style layout sBtnB eBTxt -expand we
    } elseif {$iconic} {
        $T style create sBtnI
        $T style elements sBtnI {eFace eBIcon eBTxt}
        $T style layout sBtnI eFace -union {eBIcon eBTxt} \
            -ipadx [list 8 $er] -ipady 3 -padx 2 -pady $fgap -expand wens
        $T style layout sBtnI eBIcon -expand ns -padx {0 4}
        $T style layout sBtnI eBTxt -expand ns
        $T style create sBtnB
        $T style elements sBtnB {eFace ePRect ePTxt eBTxt}
        $T style layout sBtnB eFace -union {ePRect eBTxt} \
            -ipadx [list 8 $er] -ipady 3 -padx 2 -pady $fgap -expand wens
        # ...and the same in the row preset, where the mis-placed pad
        # made the badge button WIDER than the rest and pushed its
        # right border out of line.
        $T style layout sBtnB ePRect -union ePTxt -expand ns
        # -expand ns, as the icon: the horizontal slack is not the
        # badge's to take — taking it is what pushed this button's
        # right border out of the column.
        $T style layout sBtnB ePTxt -minwidth $isz -minheight $isz \
            -expand ns -padx {0 4}
        $T style layout sBtnB eBTxt -expand ns
    }
    # One column, one width: every label cell is min-sized to the
    # widest button's content, so the faces around them come out the
    # same and their edges line up. (Horizontally there is nothing to
    # line up — each button is as wide as it needs and they sit in a
    # row.) eBTxt is in every style's union, which is what makes one
    # line reach all three.
    if {$vert} {
        foreach s [$T style names] {
            # In a STACK the label cell is the whole content width (the
            # icon sits above it); in a ROW the icon shares the line, so
            # the label gets what is left of it. Get this wrong and the
            # face is wider than the strip, which treectrl answers by
            # pushing the label against the far edge.
            set mw $memw
            if {$preset ne "stack" && $s in {sBtnI sBtnB}} {
                set mw [expr {max(1, $memw - $isz - 4)}]
            }
            if {$preset eq "stack" && $s in {sBtnI sBtnB}} {
                # under the icon, centred on it
                $T style layout $s eBTxt -minwidth $mw
            } else {
                # Beside the icon (or alone): the label sticks to the
                # WEST of its (now wider) cell, so a column of labels of
                # different lengths shares one left edge instead of each
                # floating in the middle of its own button (owner,
                # 2026-07-29). -sticky and not -expand: expand moves the
                # cell inside the style, sticky moves the element inside
                # the cell, and it is the cell that was widened here.
                $T style layout $s eBTxt -minwidth $mw -sticky w
            }
        }
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
        if {$vert} {
            # In a column the item's bottom edge is the NEXT button's
            # doorstep, and a full-width bar drawn there reads as that
            # button's top border — the indicator pointed at the wrong
            # face (owner's report, 2026-07-29). It belongs ON the face:
            # the content is top-aligned in the item, so the face's own
            # lower edge is 2*fgap up from the item's bottom, and -padx
            # 2 (the face's own) gives the bar exactly the face's width.
            # Drawn last, it takes over the bottom stretch of the face's
            # outline — an indicator that is part of the button rather
            # than a stripe near it.
            $T style layout $s eLive -detach yes -iexpand x -expand n \
                -padx 2 -pady [list 0 $fgap]
        } else {
            $T style layout $s eLive -detach yes -iexpand x -expand n
        }
        if {$zone} {
            $T style layout $s eSep -detach yes -expand wns \
                -padx [list 0 [expr {2 + $zone}]] -visible {yes multi no {}}
            $T style layout $s eArrow -detach yes -expand wns \
                -padx [list 0 [expr {2 + ($zone - $aw) / 2}]] \
                -visible {yes multi no {}}
        }
    }
    foreach b $buttons f $faces {
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
    bind $T <ButtonPress-1> [list panel-click $name %x %y]
    # WHERE the strip goes is not this proc's arithmetic any more: it
    # asks for its band (carved in declaration order out of what the
    # panels before it left) and takes the edge-hugging part of it that
    # is its own thickness — a band widened by a fat tray is not the
    # panel's to fill.
    #
    # The tray strip sits at the FAR end of this same band, in its own
    # top-level above ours: the button row stops short of it so a
    # button can never end up hidden under an icon.
    set band [strip-band $name]
    if {$band eq ""} { set band [list 0 0 {*}[screen-size]] }
    lassign [band-strip $band $side $thick] X Y W H
    set geo ${W}x${H}+${X}+${Y}
    set tray [expr {[tray-panel] eq $name ? [tray-extent] : 0}]
    if {$vert} {
        place $T -x 1 -y 1 -width [expr {$W - 2}] \
            -height [expr {$H - 2 - $tray}]
    } else {
        place $T -x 1 -y 1 -width [expr {$W - 2 - $tray}] \
            -height [expr {$H - 2}]
    }
    wm geometry $P $geo
    raise $P
    panel-reeval     ;# a rebuild starts stateless — judge the matches now
    puts "WM: panel $name up ([llength $buttons] buttons, $thick px,\
 $side/$preset, $geo)"
}
proc panel-fire {name i} {
    lassign [lindex [panel-cfg $name buttons] $i] label settings
    set hit [lindex [panel-matches $label $settings] 0]
    if {$hit ne ""} {
        puts "WM: panel $label: found 0x[format %x $hit]"
        panel-flash $name $i found
        if {[info exists ::iconic($hit)]} {
            deiconify-client $hit   ;# raises and focuses on its own
            return
        }
        raise-group $hit
        focus-to $hit
    } elseif {[dict exists $settings launch]} {
        puts "WM: panel $label: launch"
        panel-flash $name $i firing
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
proc panel-arrow {name i} {
    lassign [lindex [panel-cfg $name buttons] $i] label settings
    set wins [panel-matches $label $settings]
    if {[llength $wins] < 2} { panel-fire $name $i; return }
    puts "WM: panel $label: arrow — [llength $wins] matches"
    winlist-open $wins [list panel $name $i]
}
proc panel-flash {name i state} {
    # items are created in declaration order: button i = item i+1
    set item [expr {$i + 1}]
    set T [panel-tree $name]
    if {$T eq ""} return
    soft "panel flash" {
        $T item state set $item $state
        # the un-flash fires 600 ms later, by which time the panel may
        # have been rebuilt out from under this item — soft, like the rest
        after 600 [list soft "panel unflash" \
            [list $T item state set $item !$state]]
    }
}
proc panel-click {name x y} {
    set T [panel-tree $name]
    if {$T eq ""} return
    if {[catch {$T identify -array A $x $y}] || $A(where) ne "item"} return
    set i [expr {$A(item) - 1}]
    # the whole reserved east strip is the arrow's click target, not
    # the glyph — but only while the arrow is armed (multi)
    set zone [expr {[info exists ::panel_zone($name)] ? $::panel_zone($name) : 0}]
    if {$zone > 0 && "multi" in [$T item state get $A(item)]} {
        lassign [$T item bbox $A(item)] _x _y x2 _y2
        if {$x >= $x2 - 2 - $zone} { panel-arrow $name $i; return }
    }
    panel-fire $name $i
}
proc panel-on-top {} {
    foreach name [panel-names] {
        set P [panel-window $name]
        if {$P ne ""} { raise $P }
    }
    if {[winfo exists .traybg]} { raise .traybg }   ;# under the strip...
    if {[winfo exists .tray]} { raise .tray }       ;# ...and over the desk
    fullscreen-on-top   ;# ...and under a fullscreen window, always
}

# ---- the system tray strip ----
# Where docked icons live: a strip of square cells at the FAR end of
# its panel's band (the right end of a horizontal one, the bottom end
# of a vertical one), in its own override-redirect top-level so a panel
# rebuild — which destroys the strip outright — cannot take somebody's
# icon down with it.
#
# WHICH panel is a knob (set-tray-panel, default `default`): with more
# than one panel on the desk the tray has to be told whose bar it is
# part of, and the answer decides its edge, its orientation and the
# band it shares. A tray on a panel with no buttons is the panel-less
# case of old — the band is then the tray's alone.
#
# Off by default, like the panel: `set-tray on` in the config claims
# _NET_SYSTEM_TRAY_S<screen> (the substrate does the protocol; a
# display that already has a tray keeps it and we stay off). The
# cells are plain frames — an icon is a foreign X window reparented
# into one, and the cell's BACKGROUND is what shows through the
# transparent parts of it. That is the whole "why is my icon on a
# black square" story: we hand it the strip's own color, not black.
#
# The strip carves the workarea exactly as the panel does (the two
# share an edge, so the carve is the thicker of them), and the panel
# shortens its button row by the strip's length so the two never
# overlap.
keep tray_on 0
keep tray_icon_size 24    ;# the freedesktop-conventional cell
keep tray_gap 4           ;# between cells
keep tray_pad 3           ;# around the row
keep tray_bg #2e3436      ;# what shows through a transparent icon
keep tray_sid 0
keep tray_order {}        ;# icon windows, in dock order
keep tray_seen_extent 0   ;# the length the panel last reserved for us
keep tray_geo ""          ;# the strip geometry we last asked for
keep tray_argb 0          ;# the ARGB experiment — see set-tray-argb
keep tray_strip_argb 0    ;# ...and what the LIVE strip was built with
keep tray_laid_size 0     ;# the cell size the live cells were laid out at
keep tray_panel default   ;# whose bar the tray is part of
proc set-tray {on} {
    set ::tray_on [expr {$on ? 1 : 0}]
    tray-reconcile-soon
}
proc set-tray-panel {name} {
    set ::tray_panel $name
    panel-rebuild-soon   ;# both bands moved: the old owner's and the new
}
# The panel the tray rides on. Not resolved against the declared ones:
# a name nobody declared is still a band of its own here (that is the
# tray-and-no-buttons case, and panel-cfg answers for the edge), so the
# tray never loses its strip to a config that only forgot a button.
proc tray-panel {} { return $::tray_panel }
proc tray-side {} { panel-cfg [tray-panel] side }
# One reconcile per config's worth of knob twiddles — the same shape as
# panel-rebuild-soon, and for a sharper reason than saving work.
#
# A reload puts every wish back to the code's default and then lets the
# config speak, so WHILE THE CONFIG IS SPEAKING the wish set is
# half-built, and neither half is the truth yet. At `set-tray-argb on`
# the tray is not asked for at all (::tray_on is still the reset 0); at
# `set-tray on` the ARGB wish may still be the reset 0 under a strip
# that is 32-bit. Reconciling at either of those moments reads the
# half-built wish as a real one — and both readings say "tear the strip
# down", one as "no tray wanted", the other as "the visual moved".
# Which is somebody else's window un-embedded: the Tk client re-docks
# with a NEW window, the GTK one dies outright (measured,
# run-trayargb-test.sh) and so does nm-applet (owner's report,
# 2026-07-29). Deferred to the idle AFTER the config has finished, the
# knobs are seen together, the live-and-still-wanted case does nothing,
# and the order the config writes them in stops mattering for real.
proc tray-reconcile-soon {} {
    if {![info exists ::tray_pending]} {
        set ::tray_pending 1
        after idle {unset ::tray_pending; tray-reconcile}
    }
}
# The wish (::tray_on, ::tray_argb) and the LIVE state (a claimed
# selection, a built strip) are two different things, and this is the
# one place that brings them together. Everything else just says what
# it wants and calls here.
#
# Written this way because of a config RELOAD. The reset puts the wish
# back to "no tray" and the config then asks for one again — and if
# that were carried out literally, every reload would tear the tray
# down and build it again. A tray icon is somebody else's window: GTK
# answers being un-embedded by DESTROYING its icon window and making a
# new one (measured), and nm-applet does not survive the trip at all —
# it takes an X error on a window that went out from under it (owner's
# report, 2026-07-29). So: if the tray is live and still wanted, this
# does NOTHING, and the icons never notice a reload happened.
proc tray-reconcile {} {
    set live [expr {$::tray_owner != 0 && [winfo exists .tray]}]
    # A window's visual is fixed when it is created, so a change of
    # mind about ARGB is the one wish that needs the strip rebuilt.
    set rebuild [expr {$live && $::tray_on && $::tray_strip_argb != $::tray_argb}]
    if {$live && (!$::tray_on || $rebuild)} {
        tray-stop [expr {$rebuild ? {the tray visual changed}
                                  : {the config no longer asks for a tray}}]
        destroy .tray
        if {[winfo exists .traybg]} { destroy .traybg }
        set ::tray_geo ""
        set ::tray_seen_extent 0
        set live 0
    }
    if {$::tray_on && !$live} {
        # The strip is built FIRST: its visual is what the claim
        # advertises, and a client may dock the instant it hears the
        # announcement.
        tray-ensure
        set vis 0
        if {$::tray_argb} { scan [winfo visualid .tray] %x vis }
        # a vertical panel gets a vertical tray — the orientation is
        # published for the icons, which size themselves by it
        set ::tray_on [tray-start [expr {[tray-side] in {left right}
            ? "vertical" : "horizontal"}] $vis]
        if {$::tray_on} {
            set ::tray_strip_argb $::tray_argb
            tray-adopt-orphans   ;# ours from before, if any are waiting
        } else {
            destroy .tray
        }
    }
    tray-layout
}
# The ARGB experiment, off by default and deliberately so.
#
# On, the strip becomes a 32-bit top-level and we ADVERTISE that visual
# (_NET_SYSTEM_TRAY_VISUAL): a toolkit that sees the offer makes its
# icon in the same visual and paints it with alpha. Two things then
# have to hold, and both are ours to arrange: the cell must be the same
# depth (only then is ParentRelative legal, and only then does the
# icon's transparency show OUR color rather than black), and a
# compositor must be running to blend the strip — the server never
# blends a child window's alpha by itself.
#
# The catch that makes this more than a flag: Tk computes a color's
# pixel from the visual's masks, and a TrueColor visual has no mask
# over the alpha bits — so every Tk color in a 32-bit visual comes out
# with alpha ZERO, which a compositor draws as "not there". The strip
# would be an invisible bar with icons floating over the wallpaper. So
# the background pixel is set from outside Tk, alpha byte and all (see
# tray-paint-opaque) — that is what the shim's `window background`
# primitive is for.
#
# Chrome ignores the negotiation and makes an ARGB icon whether or not
# we advertise (measured 2026-07-29), so with the offer OFF it is the
# one client that looks wrong, and with it ON it is the one client that
# looks right. Hence a knob and not a default.
proc set-tray-argb {on} {
    set want [expr {$on ? 1 : 0}]
    if {$want && [tray-argb-visual] eq ""} {
        puts "WM: tray: no 32-bit TrueColor visual on this screen — ARGB refused"
        return
    }
    set ::tray_argb $want
    tray-reconcile-soon   ;# a live strip is rebuilt only if the visual moved
}
# "truecolor 32" as [winfo visualsavailable] spells it, or "" when the
# screen has none (a plain 24-bit server: then there is no ARGB to be
# had and the knob says so instead of building a broken strip).
proc tray-argb-visual {} {
    foreach v [winfo visualsavailable .] {
        if {$v eq "truecolor 32"} { return $v }
    }
    return ""
}
# The backdrop, and why the ARGB strip needs one — measured, not
# reasoned (run-trayargb-test.sh, 2026-07-29).
#
# With the ARGB offer taken, an icon's see-through parts are alpha ZERO
# in the top-level's composite pixmap, and the compositor duly shows
# whatever is BEHIND the strip: the wallpaper, through a hole the size
# of the icon. ParentRelative does not save it — the toolkit sets its
# own transparent background in ARGB mode and paints over ours. Nor
# does painting the strip opaque: the icon's own window covers the
# cell, and a child's pixels replace the parent's in that pixmap.
#
# So what is behind the strip has to be OURS: a plain, opaque
# 24-bit top-level of exactly the strip's geometry, stacked directly
# under it. The holes then show the tray's own color, the icon's
# antialiased edge blends against it, and nothing of the desk shows
# through. Only in ARGB mode — the default strip is opaque by itself.
proc tray-backdrop {geo} {
    if {!$::tray_argb} {
        if {[winfo exists .traybg]} { destroy .traybg }
        return
    }
    if {![winfo exists .traybg]} {
        toplevel .traybg -background $::tray_bg
        wm overrideredirect .traybg 1
        wm withdraw .traybg
    }
    if {$geo eq ""} { wm withdraw .traybg; return }
    wm geometry .traybg $geo
    wm deiconify .traybg
    raise .traybg        ;# ...and tray-layout raises .tray over it
}
proc set-tray-icon-size {px} {
    set ::tray_icon_size $px
    tray-layout
}
# The cells follow the size knob; so must the foreign windows sitting
# in them, or a reload that changes the size leaves every icon drawn at
# the old one. The refit is the substrate's — it owns what an icon is
# held at — and costs nothing when the size did not move.
proc tray-refit-cells {} {
    if {$::tray_laid_size == $::tray_icon_size} return
    set ::tray_laid_size $::tray_icon_size
    foreach w $::tray_order {
        $::tray_slot($w) configure \
            -width $::tray_icon_size -height $::tray_icon_size
    }
    tray-refit $::tray_icon_size
}
proc set-tray-background {color} {
    set ::tray_bg $color
    if {[winfo exists .traybg]} { .traybg configure -background $color }
    if {[winfo exists .tray]} {
        .tray configure -background $color
        foreach w $::tray_order { $::tray_slot($w) configure -background $color }
    }
}
proc tray-ensure {} {
    if {[winfo exists .tray]} return
    if {$::tray_argb && [set v [tray-argb-visual]] ne ""} {
        toplevel .tray -background $::tray_bg -visual $v -colormap new
    } else {
        toplevel .tray -background $::tray_bg
    }
    wm overrideredirect .tray 1   ;# our own furniture, not a client
    wm withdraw .tray             ;# shown by tray-layout once it holds a cell
}
# The substrate's hooks. The Tk round trip before the return is the
# same guarantee policy-attach gives for a frame slot: the window
# exists server-side before anything is reparented into it.
proc policy-tray-attach {w} {
    if {!$::tray_on} { return {0 0} }
    tray-ensure
    set f .tray.i[incr ::tray_sid]
    # The cell inherits the strip's visual (a child of a 32-bit
    # top-level is 32-bit unless told otherwise) — which is what makes
    # ParentRelative legal for an ARGB icon.
    frame $f -width $::tray_icon_size -height $::tray_icon_size \
        -background $::tray_bg
    set ::tray_slot($w) $f
    lappend ::tray_order $w
    tray-layout
    update idletasks
    winfo pointerxy $f
    puts "WM: tray cell $f for 0x[format %x $w]"
    return [list [winfo id $f] $::tray_icon_size]
}
proc policy-tray-detach {w} {
    if {![info exists ::tray_slot($w)]} return
    destroy $::tray_slot($w)
    unset ::tray_slot($w)
    set ::tray_order [lsearch -exact -all -inline -not $::tray_order $w]
    tray-layout
}
proc policy-tray-origin {w} {
    if {![info exists ::tray_slot($w)]} { return {0 0} }
    set f $::tray_slot($w)
    list [winfo rootx $f] [winfo rooty $f]
}
# The strip's measures: extent along its panel's edge, thickness across
# it — zero when the tray is off or empty, so neither the workarea nor
# the panel reserves anything for a strip that is not there. The
# thickness matches its panel's when that panel has buttons, so the two
# read as a single bar.
proc tray-extent {} {
    set n [llength $::tray_order]
    if {!$::tray_on || $n == 0} { return 0 }
    expr {2*$::tray_pad + $n*$::tray_icon_size + ($n - 1)*$::tray_gap}
}
proc tray-thickness {} {
    if {[tray-extent] == 0} { return 0 }
    expr {max(2*$::tray_pad + $::tray_icon_size, [panel-thickness [tray-panel]])}
}
proc tray-layout {} {
    if {![winfo exists .tray]} return
    set len [tray-extent]
    if {$len == 0} {
        wm withdraw .tray
        set ::tray_geo ""
        tray-backdrop ""
        tray-tell-panel
        return
    }
    tray-refit-cells        ;# the size knob may have moved under them
    set thick [tray-thickness]
    set sz $::tray_icon_size
    set cross [expr {($thick - $sz) / 2}]   ;# centered across the strip
    set side [tray-side]
    set vert [expr {$side in {left right}}]
    set i 0
    foreach w $::tray_order {
        set off [expr {$::tray_pad + $i*($sz + $::tray_gap)}]
        if {$vert} {
            place $::tray_slot($w) -x $cross -y $off -width $sz -height $sz
        } else {
            place $::tray_slot($w) -x $off -y $cross -width $sz -height $sz
        }
        incr i
    }
    # The FAR end of our panel's band: the end with the larger
    # coordinate along the band's long axis — the right end of a
    # horizontal bar, the bottom end of a vertical one. Taken from the
    # band and not from the screen, so a tray on the second panel
    # declared lands inside what the first one left.
    set band [strip-band [tray-panel]]
    if {$band eq ""} { set band [list 0 0 {*}[screen-size]] }
    lassign [band-strip $band $side $thick] bx by bw bh
    if {$vert} {
        set geo ${thick}x${len}+${bx}+[expr {$by + $bh - $len}]
    } else {
        set geo ${len}x${thick}+[expr {$bx + $bw - $len}]+${by}
    }
    wm geometry .tray $geo
    tray-backdrop $geo       ;# the opaque floor under an ARGB strip
    wm deiconify .tray
    raise .tray
    fullscreen-on-top        ;# ...but never over a fullscreen window
    # The COMPUTED string, not [wm geometry .tray]: that answers with
    # the geometry Tk has processed so far, which right after the
    # request is still the previous one — and a re-layout runs twice per
    # change (the attach, then the panel rebuild it kicks), so the log
    # would show every size one step late. Logged only when it moves.
    if {$geo ne $::tray_geo} {
        set ::tray_geo $geo
        puts "WM: tray strip $geo ([llength $::tray_order] icons)"
        publish-workarea   ;# a strip that grew took more of the screen
    }
    tray-tell-panel
}
# The panel shortens its row by our length — but only a CHANGED length
# is worth a rebuild: panels-build calls tray-layout at its end, so an
# unconditional kick would be an idle loop between the two.
proc tray-tell-panel {} {
    if {$::tray_seen_extent == [tray-extent]} return
    set ::tray_seen_extent [tray-extent]
    panel-rebuild-soon
}

# The screen changed size under us (RandR: a resized Xephyr window, a
# mode switch): the panel is glued to the bottom edge, so re-place it.
# Debounced — an interactive Xephyr resize streams a notify per step,
# and rebuilding the strip on each would thrash.
keep panel_resize_pending ""
proc policy-screen-changed {} {
    after cancel $::panel_resize_pending
    # the tray is glued to a corner of the same band; panels-build ends
    # by re-laying it out, and tray-layout covers the panel-less case
    set ::panel_resize_pending \
        [after 200 {panels-build; fullscreen-refit}]
}
# A fullscreen window is glued to the screen the same way the strips
# are glued to its edge, so the same notify has to re-fit it — a screen
# that grew would otherwise leave the window at the old size with a
# band of desk around it, and one that shrank would leave it hanging
# off the edge.
proc fullscreen-refit {} {
    lassign [screen-size] sw sh
    foreach w [array names ::fullscreen] {
        if {![info exists ::frameof($w)]} continue
        frame-layout $::frameof($w) $sw $sh
        wm-resize-client $w $sw $sh
        send-synthetic-configure $w
    }
}

# ---- the workarea moved: the windows follow it ----
#
# The panel changes side on a reload, or grows a row, or a tray icon
# widens the band, or the screen resizes under everything — and the
# windows that were arranged AGAINST the old workarea are suddenly
# arranged against nothing. A maximized window keeps the old
# maximization's size in the new geometry; a window flush against the
# bottom strip now floats above where the strip used to be. Nothing
# moved them before this (owner's wish, 2026-07-30).
#
# ONE RULE, applied to each axis on its own, and everything else falls
# out of it. In an axis a window either
#
#   SPANS the workarea — it sits at the origin and is exactly as long as
#     maximize would have made it there — and then it spans the new one;
#   is flush at the NEAR edge, and stays flush at the new near edge;
#   is flush at the FAR edge, and stays flush at the new far one;
#   is flush at neither, and does not move in this axis at all.
#
# Both of the owner's asks are that rule: "what arithmetically looks
# maximized goes to the new maximization" is spanning in BOTH axes, and
# "what was stuck to the old border sticks to the new one" is the two
# flush cases. It also answers what he did not ask about and would have
# had to: a full-height column down the left side spans one axis and
# hugs one edge, and comes out re-fitted in the axis it filled and
# re-stuck in the other, which is the only reading that keeps it a
# column.
#
# Spanning is measured with maximize-fit and not with the raw extent,
# which is the whole reason that proc exists. An xterm maximized on an
# 800x562 workarea is not 562 tall — it is a whole number of cells and
# leaves slack at the edge — and a test that wanted the extent exactly
# would call the most obviously maximized window on the desk "flush at
# the near edge, nothing more" and never re-fit it.
#
# What the reflow does NOT do:
#
#   - it does not touch the maximized MARK, in either direction. This is
#     the WM moving furniture, not a hand on the window: `drop` sheds the
#     mark in resize-by-edge and only there, so a re-fitted maximized
#     window stays maximized. And a window that merely LOOKS maximized
#     is not marked as such by being re-fitted — it has no saved
#     geometry, and inventing one would lie to the toggle exactly the way
#     a size-yielding `place max` would (see the place grammar).
#   - it does not clamp anything back onto the screen. A window parked
#     half off the edge on purpose has a relation to no edge of ours,
#     and hauling it back would be a policy nobody asked for; a window
#     that sits UNDER the panel because it claimed that corner keeps
#     sitting there for the same reason (see clamp-to-screen).
#   - it leaves alone whatever a hand is holding — see geometry-held-p.
#
#   off    nothing follows: the workarea changes and the windows sit
#          where they were, which is what every version before this did.
#   max    only what looks maximized (spanning BOTH axes) follows.
#   stick  the whole rule above. The default.
keep workarea_follow stick
proc set-workarea-follow {mode} {
    if {$mode ni {off max stick}} {
        error "set-workarea-follow: off, max or stick"
    }
    set ::workarea_follow $mode
}
proc policy-workarea-changed {old new} {
    if {$::workarea_follow eq "off"} return
    foreach w [array names ::frameof] {
        # Fullscreen is the screen's business and has its own refit; a
        # window under a gesture is somebody's business right now.
        if {[info exists ::fullscreen($w)] || [geometry-held-p $w]} continue
        reflow-client $w $old $new
    }
}
# A hand is on this window's geometry at this moment: a title carry, a
# border or modifier-drag resize, a keyboard move/resize mode. The
# reflow leaves it be — it would be writing over the numbers the gesture
# is negotiating, and the keyboard mode's Escape remembers a geometry
# from before, which it would then restore to a workarea that no longer
# exists.
proc geometry-held-p {w} {
    if {[kbmr-owns $w]} { return 1 }
    if {[info exists ::drag($::frameof($w))]} { return 1 }
    if {[info exists ::mdrag] && [lindex $::mdrag 2] == $w} { return 1 }
    if {[info exists ::rz] && [lindex $::rz 7] == $w} { return 1 }
    return 0
}
# One axis. o0/o and n0/n are that axis of the old and the new workarea,
# p/s where the frame sits and how long it is, om/nm the length a
# maximized frame would have in each. Returns {position length how}.
proc reflow-axis {o0 o n0 n p s om nm} {
    if {$p == $o0 && $s == $om}  { return [list $n0 $nm span] }
    if {$p == $o0}               { return [list $n0 $s near] }
    if {$p + $s == $o0 + $o} {
        # The near edge wins a window too long to fit, the same way
        # clamp-to-rect decides it: better to lose the far edge than the
        # one with the title bar on it.
        return [list [expr {max($n0, $n0 + $n - $s)}] $s far]
    }
    return [list $p $s stay]
}
proc reflow-client {w old new} {
    set t $::frameof($w)
    lassign [frame-chrome $t] B top
    # Frame lengths throughout — the client's own size plus what the
    # decoration adds — because it is the FRAME that is flush with an
    # edge or fills the workarea, and the client size is what has to be
    # asked for at the end.
    set cw [$t.slot cget -width]; set ch [$t.slot cget -height]
    set fw [expr {$cw + 2*$B}];   set fh [expr {$ch + $top + $B}]
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> X Y
    lassign [maximize-fit $w $old] omw omh
    lassign [maximize-fit $w $new] nmw nmh
    lassign [reflow-axis [lindex $old 0] [lindex $old 2] \
                         [lindex $new 0] [lindex $new 2] $X $fw \
                         [expr {$omw + 2*$B}] [expr {$nmw + 2*$B}]] nX nfw hx
    lassign [reflow-axis [lindex $old 1] [lindex $old 3] \
                         [lindex $new 1] [lindex $new 3] $Y $fh \
                         [expr {$omh + $top + $B}] [expr {$nmh + $top + $B}]] nY nfh hy
    # `max` means what it says: a window that does not look maximized —
    # spanning BOTH axes — is not touched at all, not even in the axis it
    # happens to fill.
    if {$::workarea_follow eq "max" && ($hx ne "span" || $hy ne "span")} return
    if {$nX == $X && $nY == $Y && $nfw == $fw && $nfh == $fh} return
    wm geometry $t +$nX+$nY
    wm-resize-client $w [expr {$nfw - 2*$B}] [expr {$nfh - $top - $B}]
    puts "WM: reflow 0x[format %x $w] $hx/$hy ->\
 [expr {$nfw - 2*$B}]x[expr {$nfh - $top - $B}]+$nX+$nY"
    maximize-settle $w    ;# the frame moved even where the size did not
    # The way back travels with the window. ::maxsaved is a rect in the
    # workarea that just moved, so the same rule says where it belongs
    # now: a window maximized on a desk whose panel then moved to the top
    # must not un-maximize to a place under the panel.
    if {![info exists ::maxsaved($w)]} return
    lassign $::maxsaved($w) scw sch sX sY
    lassign [reflow-axis [lindex $old 0] [lindex $old 2] \
                         [lindex $new 0] [lindex $new 2] $sX [expr {$scw + 2*$B}] \
                         [expr {$omw + 2*$B}] [expr {$nmw + 2*$B}]] sX sfw -
    lassign [reflow-axis [lindex $old 1] [lindex $old 3] \
                         [lindex $new 1] [lindex $new 3] $sY [expr {$sch + $top + $B}] \
                         [expr {$omh + $top + $B}] [expr {$nmh + $top + $B}]] sY sfh -
    set ::maxsaved($w) \
        [list [expr {$sfw - 2*$B}] [expr {$sfh - $top - $B}] $sX $sY]
}

# ---- default key bindings ----
# The defaults live IN CODE — the config is an override layer, not a
# preset carrier. The window OPS menu (actions on the focused window)
# answers both the one-chord Alt+Space and the stumpwm-style sequence
# Super+t w m; the window LIST sits on Alt+Tab — where the held Alt
# turns it into the fvwm cycle — and on Super+t w w as a plain static
# menu (the sequence ends with everything released).
#
# They live in a PROC because a config reload has to put them back: the
# reset drops every grab this WM holds (a config is free to bind over a
# default, and an override cannot be un-bound piecemeal), and then the
# in-code defaults are laid down again as a fresh floor.
proc policy-default-bindings {} {
    wm-bind {<Alt>space} winops
    wm-bind {<Super>t w m} winops
    wm-bind {<Alt>Tab} winlist
    wm-bind {<Super>t w w} winlist
    # Re-read the config in place. Deliberately a default: the whole
    # point of the reload is to try a config without restarting, and
    # having to configure the way to reload the config first would be a
    # poor joke. Bind over it like any other default.
    wm-bind {<Super>t w r} Reload
    # The way out, and a default for the same reason: a desk you can
    # only leave by finding another terminal and killing yourself is
    # the "how do I exit vim" joke with a whole login in it. It sits in
    # the Super+t family with the rest, one letter under a prefix — far
    # enough that nobody arrives by accident, and guessable from the
    # others rather than needing to be looked up (owner, 2026-07-29).
    wm-bind {<Super>t q} Quit
}
policy-default-bindings

# ---- the config layer: defaults, reset, apply ----
# A reload is "put everything back the way the CODE has it, then let the
# config speak again on that clean floor" — the owner's own contract for
# it. What that costs the config is one rule: it must be DECLARATIVE.
# Calling the set-* knobs, declaring panel buttons, style rules and key
# binds is all undoable, because the reset knows where that state
# lives. Redefining a policy or substrate proc is not: a reset has no
# way to remember what the proc used to be, and the next reload would
# be building on the patch. (Procs the config defines FOR ITSELF —
# predicates, launchers — are fine; they are just names, and the config
# redefines them on every load.)
#
# The defaults are not written down twice. They are SNAPSHOTTED from
# the code's own values the moment before the config is first sourced,
# so a default and its copy cannot drift apart: there is no copy.
set config_vars {
    border gripz OUTLINE titlejust winlist_cycle_opt icon_path
    style_rules minimize maximize workarea_follow panels panel_target
    panel_live_bar panel_live_face drag_mods drag_slop edge_resist root_cursor
    key_echo key_echo_place titlebar_buttons titlebar_gestures fade
    tray_on tray_icon_size tray_gap tray_pad tray_bg tray_argb tray_panel
}
proc policy-snapshot-defaults {} {
    foreach v $::config_vars { set ::config_default($v) [set ::$v] }
    set ::config_default(TitleFont) [font actual TitleFont]
}
proc policy-reset {} {
    # The tray is deliberately NOT torn down here, only WISHED away:
    # ::tray_on goes back to 0 with the other variables and the live
    # strip is left standing until policy-apply reconciles it with what
    # the new config asked for. A reload that keeps the tray therefore
    # does not disturb a single icon — and an icon is somebody else's
    # window, which does not always survive being un-embedded (see
    # tray-reconcile).
    foreach v $::config_vars { set ::$v $::config_default($v) }
    font configure TitleFont {*}$::config_default(TitleFont)
    title-metrics
    # Caches that a config decides the contents of: per-client style
    # verdicts (the rules are gone) and resolved icons (the path may
    # move under them).
    array unset ::styleof
    foreach {k img} [array get ::resolvedicon] {
        if {$img ne ""} { soft "drop a cached icon" [list image delete $img] }
    }
    array unset ::resolvedicon
    # Every chord, ours and the config's alike, and then our own floor
    # back down. keys-reset is the substrate's: the grabs are its.
    keys-reset
    policy-default-bindings
}
proc policy-apply {} {
    panels-build        ;# no buttons declared -> the strip goes away
    tray-reconcile      ;# start, stop or leave the tray exactly alone
    retitle-frames      ;# live frames follow the metrics and the font
    root-cursor-apply   ;# ...and the desk stops wearing the server's X
    publish-workarea
    panel-match-kick
    puts "WM: config applied ([llength [panel-all-buttons]] buttons on\
 [llength [panel-names]] panel(s), [llength $::style_rules] style rules,\
 tray [expr {$::tray_on ? {on} : {off}}])"
}

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
proc set-drag-slop {px} {
    if {![string is integer -strict $px] || $px < 0} {
        error "set-drag-slop: a pixel count, 0 to carry from the first pixel"
    }
    set ::drag_slop $px
}

# Edge resistance: a carried window STICKS to an edge of the workarea —
# within the resistance the frame sits exactly on it, and it takes that
# much more pointer travel to get past. Flush against a strip is the
# position one is usually aiming for, and hitting it by hand to the
# pixel is aiming nobody should have to do (fvwm's EdgeResistance,
# which the owner missed here). Both edges of both axes, and the
# WORKAREA's rather than the screen's: the edge worth being flush with
# is the one the panel leaves free. 0 switches it off.
keep edge_resist 12
proc set-edge-resist {px} {
    if {![string is integer -strict $px] || $px < 0} {
        error "set-edge-resist: a pixel count, 0 to switch it off"
    }
    set ::edge_resist $px
}
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
    lassign [workarea] wax way ww wh
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
    set ::drag_mods [parse-mods $spec]
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
    set ::root_cursor $name
    root-cursor-apply
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
    if {$button == 1} {
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
