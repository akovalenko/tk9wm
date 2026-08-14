# ---- the desk's typography: one font, and what descends from it ----
#
# DESKFONT is the font this window manager is set in. It starts as a
# copy of TkDefaultFont, TK9WM_TITLE_FONT overrides it at startup (any
# Tk font spec, e.g. "DejaVu Sans 12"), and set-desk-font re-points it
# live. Every vertical measure of the decoration derives from its
# metrics — a 22px strip that was roomy at 96 dpi was visibly too tight
# for the same font at Xft.dpi 144 (live report, 2026-07-27).
#
# Everything else is a DERIVATION: a base plus a delta, in
# `wm-font NAME ?-from BASE? ?option value ...?`. The delta is ordinary
# font options, with one addition Tk has no notion of — a size may be a
# FACTOR of the base's:
#
#   wm-font PanelFont  -size 11 -weight normal      ;# the owner's example
#   wm-font ClockFont  -size 1.8x -weight bold      ;# ...and the one Tk cannot
#   wm-font DateFont   -size 0.8x
#
# Tk named fonts do not inherit — a named font is a fixed spec — so the
# whole family is RE-DERIVED whenever a base moves (set-desk-font, a
# config reload, a theme change). That is the point of holding the
# relation rather than the result: "the panel is the desk font at 85%"
# stays true after the desk font changes, which is exactly what a
# hard-coded 11 does not.
#
# WHY FACTORS AND NOT DELTAS (+2, -1), which one might expect next to
# them: Tk's size is signed, and the sign is the UNIT — a positive size
# is points, a negative one is pixels. A factor multiplies and keeps
# the unit whatever it is; "+2" would have to mean "two points bigger"
# on one desk and "two pixels smaller" on another, and a rule that
# reads backwards half the time is worse than no rule. An absolute
# number is always allowed, and means what Tk means by it.
#
# The order of declaration is the order of derivation: a font's base
# must be declared before it. A chain works (Clock from Panel from
# Desk); a cycle is refused at declaration.
unless-already {[lsearch -exact [font names] DeskFont] >= 0} {
    font create DeskFont {*}[font actual TkDefaultFont]
    # The launcher's word applies ONCE, with the creation: re-applied
    # on every re-source it would stomp whatever set-desk-font wrote
    # since — the same disease the stock kin declarations below had.
    if {[info exists ::env(TK9WM_TITLE_FONT)] && $::env(TK9WM_TITLE_FONT) ne ""} {
        if {[catch {font configure DeskFont {*}[font actual $::env(TK9WM_TITLE_FONT)]} err]} {
            puts "WM: TK9WM_TITLE_FONT «$::env(TK9WM_TITLE_FONT)» rejected: $err"
        }
    }
}
keep font_kin {}   ;# NAME -> {from BASE opts {...}}, in declaration order

# THE OTHER NATURAL FORM (the owner, 2026-08-01): «DejaVu Sans 10
# bold» — Tk's own font spec, and the one a person who does not write
# Tcl reaches for. Both forms are legal wherever this desk takes a
# font, and the spec is read into the SAME options, naming only the
# parts it mentions: «DejaVu Sans» sets a family and leaves the size
# where it was, which is what makes it usable as a delta on a derived
# font just like -family is.
#
# The grammar Tk uses and this follows: family, then an optional
# SIZE, then any number of style words. Read from the right — styles
# first, then a numeric size — because a family may be several words
# and cannot be told from the rest by position alone.
proc font-spec-opts {spec} {
    set weight ""; set slant ""; set under ""; set over ""; set size ""
    set words $spec
    while {[llength $words] > 1} {
        set w [string tolower [lindex $words end]]
        switch -- $w {
            normal - bold        { set weight $w }
            roman - italic       { set slant $w }
            underline            { set under 1 }
            overstrike           { set over 1 }
            default { break }
        }
        set words [lrange $words 0 end-1]
    }
    if {[llength $words] > 1 && [string is integer -strict [lindex $words end]]} {
        set size [lindex $words end]
        set words [lrange $words 0 end-1]
    }
    if {![llength $words]} {
        error "a font is «FAMILY ?SIZE? ?STYLES?» — «$spec» names no family"
    }
    set opts [dict create -family [join $words " "]]
    if {$size ne ""}   { dict set opts -size $size }
    if {$weight ne ""} { dict set opts -weight $weight }
    if {$slant ne ""}  { dict set opts -slant $slant }
    if {$under ne ""}  { dict set opts -underline $under }
    if {$over ne ""}   { dict set opts -overstrike $over }
    return $opts
}
# Either form in, options out. The dash is the tell: a first word
# that starts with one is the option form, anything else is a spec —
# given as one argument («{DejaVu Sans 10 bold}») or as several,
# because both are how one naturally types it.
proc font-args {who args} {
    if {![llength $args]} { return {} }
    # ONE WORD MAY BE THE WHOLE THING, either shape. The spec form
    # already worked that way (`set-desk-font {DejaVu Sans 13}`), and
    # the option form did not: braced into a single word it was read as
    # one odd option and refused, so a script holding its options in a
    # variable had to remember to expand them and nothing said why (the
    # owner, 2026-08-04: "font-args для скриптера неинтуитивно
    # устроен"). A lone word that looks like options and pairs up IS
    # the options.
    if {[llength $args] == 1 && [llength [lindex $args 0]] > 1
            && [string index [lindex [lindex $args 0] 0] 0] eq "-"
            && [llength [lindex $args 0]] % 2 == 0} {
        set args [lindex $args 0]
    }
    if {[string index [lindex $args 0] 0] eq "-"} {
        if {[llength $args] % 2} { error "$who: options come in pairs" }
        return $args
    }
    set spec [expr {[llength $args] == 1 ? [lindex $args 0] : $args}]
    if {[catch {font-spec-opts $spec} opts]} { error "$who: $opts" }
    return $opts
}
proc wm-font {name args} {
    set args [font-args "wm-font $name" {*}$args]
    set from DeskFont
    set opts {}
    foreach {o v} $args {
        if {$o eq "-from"} { set from $v } else { lappend opts $o $v }
    }
    # A base that is not DeskFont must itself be a declared derivation
    # (or DeskFont), and it must already exist — that is what makes
    # "declaration order is derivation order" true rather than hoped.
    if {$from ne "DeskFont" && ![dict exists $::font_kin $from]} {
        error "wm-font $name: -from «$from» is not a font this desk derives"
    }
    if {$name eq $from} { error "wm-font $name: a font cannot descend from itself" }
    dict set ::font_kin $name [dict create from $from opts $opts]
    fonts-derive
}
# A size that is a factor of the base's — "0.85x" — or a plain number,
# which Tk reads its own way (positive points, negative pixels). The
# factor keeps the base's sign, so it keeps the base's unit, and never
# rounds a font away to nothing.
proc font-size-of {from v} {
    if {[regexp {^([0-9]*\.?[0-9]+)[xX]$} $v -> f]} {
        set base [font configure $from -size]
        set n [expr {int(round($base * $f))}]
        return [expr {$base < 0 ? min($n, -1) : max($n, 1)}]
    }
    if {![string is integer -strict $v]} {
        error "wm-font -size: a number, or a factor of the base like 0.85x"
    }
    return $v
}
proc fonts-derive {} {
    dict for {name spec} $::font_kin {
        set from [dict get $spec from]
        set out [font actual $from]
        foreach {o v} [dict get $spec opts] {
            if {$o eq "-size"} { set v [font-size-of $from $v] }
            dict set out $o $v
        }
        if {[lsearch -exact [font names] $name] < 0} { font create $name }
        font configure $name {*}$out
    }
}
# The two the WM itself is written in. TitleFont is the desk font
# unchanged — it has its own name because the titlebar is the one piece
# a desk most often wants to style on its own, and because thirty-odd
# places already say TitleFont and mean "the text on our furniture".
# Declared KEEP-fashion: font_kin is state a config writes into
# (set-title-font -weight bold is an ENTRY here), and a bare wm-font
# on re-source overwrote that entry with the stock emptiness — the
# owner's titlebars were measured going un-bold on every Reread while
# every Reload and Restart bolded them back, a pattern with no visible
# rule until it had one.
unless-already {[dict exists $::font_kin TitleFont]} { wm-font TitleFont }
unless-already {[dict exists $::font_kin PanelFont]} { wm-font PanelFont }
proc set-desk-font {args} {
    # The font OBJECT is where this wish lives — there is no variable
    # to write — so configuring it IS the wish, and the deeds it owes
    # (the derived faces, then every live frame) are asked for.
    font configure DeskFont {*}[font-args set-desk-font {*}$args]
    settle-soon fonts
    settle-soon titles
}
# The pseudo-icon lettering (see winlist-icon): TitleFont's family, but
# bold and sized in PIXELS to the badge, not the text line — configured
# at each winlist open, when the badge size is known. Every panel keeps
# its OWN instance (panel-badge-font): a badge size is per panel — a
# dock of 48px icons beside a taskbar of 24px ones is the ordinary
# case — and panels sharing one font would each be lettered for
# whichever was built last.
unless-already {[lsearch -exact [font names] IconFont] >= 0} {font create IconFont -weight bold}
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
    # ...and the air inside one. A CONSTANT three pixels was right at
    # the size this desk is usually run at and wrong everywhere else:
    # at a 32-point title the glyph filled its box to the outline and
    # the row of boxes read as one band (the owner, 2026-07-30 — "big
    # font = big buttons, and big glyphs IN them"). A share of the
    # button keeps the proportions instead, and at the stock size it is
    # the same three pixels it always was.
    set ::btnpad [expr {max(3, $::btnw / 7)}]
    btn-images
    puts "WM: titlebar h=$::titleh top=$::decotop btn=$::btnw\
 font=[font actual TitleFont -family]/[font actual TitleFont -size]"
}

# Titlebar buttons, fvwm-style (the owner's frame as the model): a thin
# white outlined square holding a thin white glyph, drawn flat on the
# titlebar color. The glyphs are svg — re-rendered crisp at whatever
# size the font dictates, never scaled bitmaps.
# ---- the desk's colours: a THEME, and what is derived from it -------
#
# «I want a light theme» IN ONE WORD (the owner, 2026-08-02), and the
# shape follows the fonts: the theme is the SOURCE, a colour knob is an
# OVERRIDE, and the configurator says which of the two a row is looking
# at. Colours are the easier half of that pattern, as he said when he
# asked for it — a colour is either overridden whole or inherited, with
# no third thing. So where a font holds a RELATION to its base (a
# factor, a delta) and is re-derived, a colour is a LOOKUP: the theme
# names roles, and a role answers with a colour.
#
# THE ROLES ARE THE INTERFACE, not the colours. Nothing in the desk
# says #2e3436 any more; it says `ground` and gets whatever this theme
# paints furniture with. That is what makes a second theme a table
# entry rather than a grep, and it is also why several roles that
# happen to share a colour today are still separate roles — `ground`
# and `edge` are both #2e3436 in the dark theme and must not be in a
# light one. That split earned itself immediately: `edge` and `rule`
# were one role for about ten minutes, and collapsing them painted the
# panel's button outlines in the ground's own colour — invisible. They
# are a BORDER and a HAIRLINE and only looked alike.
#
# `edge` is the one role that is the same in both themes, and says why:
# it is the constant dark outline that keeps two touching frames from
# fusing into one grey field, and the titlebars it separates are dark
# in both themes. A light `edge` would have to differ from `unfocus`
# to do its job, and there is no light grey that does.
#
# `curb` is the line a strip draws against the clients it borders, and
# it is edge's job done the other way around: whichever way the theme
# goes, the browser beside the panel is the same near-ground field —
# the light one fused with the light strip, the dark one with the dark
# (the owner, 2026-08-05, both at once) — so where edge could stay
# dark forever, the curb must step AWAY from ground in each theme:
# dark on the light desk, pale on the dark one.
#
# The light `select` is deliberately not the palest blue that still
# reads as blue. It was, and against the furniture it sits on the band
# barely showed at all (the owner, 2026-08-02) — a selection has to be
# findable at a glance, and on a light ground that means going darker
# rather than more saturated. It stops where the ordinary dark ink is
# still comfortable on it, because a menu row draws its text in that
# ink whether it is selected or not.
#
# What ISN'T here: a hierarchy of colours ("this one, only 10% greener"
# — the owner's next step, deliberately left out). Every role is stated
# outright, twenty lines a theme, and a table one can read is worth
# more than a derivation one has to run.
keep theme dark
keep theme_palette {
    dark {
        ground  #2e3436   raised  #555753   ink     #eeeeec   dim     #babdb6
        edge    #2e3436   rule    #888a85   desk    #14181b   slot    #202020
        focus   #3465a4   unfocus #888a85   modal   #c17d11   alert   #cc4444
        found   #4e9a06   firing  #ce5c00   live    #5d6e59   livebar #8ae234
        bad     #a40000   curb    #888a85
        field   #22272a   link    #8ab4f8   select  #204a87   trough  #3a4144
    }
    light {
        ground  #f2f1ef   raised  #e4e2de   ink     #1c1c1c   dim     #555753
        edge    #2e3436   rule    #babdb6   desk    #d3d7cf   slot    #c8ccc4
        focus   #3465a4   unfocus #6b7278   modal   #c17d11   alert   #cc4444
        found   #4e9a06   firing  #ce5c00   live    #b8d39a   livebar #4e9a06
        bad     #a40000   curb    #2e3436
        field   #ffffff   link    #1a4a8a   select  #a3c4ea   trough  #e4e2de
    }
}
# The titlebars stay DARK in both themes — the focus blue and a grey
# beside it — and that is not laziness. The titlebar glyphs are white
# svg rendered once per size (btn-images), not once per ground, so a
# pale titlebar would need the ink to follow it and the whole glyph
# cache to be per-colour. A light desk with accent titlebars is also
# what most light schemes actually look like.
proc themed {role} {
    set p [dict get $::theme_palette $::theme]
    if {[dict exists $p $role]} { return [dict get $p $role] }
    error "themed: no such colour role: $role"
}
proc set-theme {name} {
    if {![dict exists $::theme_palette $name]} {
        error "set-theme: no such theme «$name» — [join [dict keys $::theme_palette] { or }]"
    }
    set ::theme $name
    # The derived variables move IN THE SAME BREATH as the word, not
    # at settle time. ::theme moves synchronously — `themed` answers
    # the new palette at once — so a panel or widget rebuild already
    # sitting in the idle queue would otherwise build against a MIXED
    # world: the new theme's raised behind faces still tinted with the
    # old theme's live. That was the owner's half-applied preview
    # (2026-08-04): a light strip wearing the dark theme's green under
    # its matched buttons — sometimes, exactly as often as a rebuild
    # got into the queue ahead of the settler. Deriving is writing
    # wishes, not acting on the world, so the word may do it; the
    # REPAINT stays with the settler.
    theme-derive
    settle-soon theme
}
# The variables a role STANDS BEHIND, unless somebody said their own
# word. Roles with no knob simply follow.
proc theme-derive {} {
    set ::OUTLINE [themed edge]
    set ::KBMR_BG [themed modal]
    set ::KEY_ECHO_BAD [themed bad]
    set ::panel_live_face [themed live]
    set ::panel_live_bar [themed livebar]
    theme-derive-said
}
# LIVE, like every knob that touches something one can see — and here
# that means nearly everything, so it is nearly everything that gets
# rebuilt. Cheap by construction: the panels, the widgets and the desk
# window are all things this desk already destroys and remakes on a
# reload, and the frames are re-dressed the way a focus change dresses
# them. The applets are told over the same door a font change uses.
proc theme-apply {} {
    # Derived here TOO, not only in the word: a reload's policy-reset
    # puts the code defaults back under whatever theme the layers
    # re-say, and this settler is where the two meet again.
    theme-derive
    # Through the DEFERRED builders, not the direct ones: set-theme is a
    # config line as often as it is a click, and a strip rebuilt in the
    # middle of a load lays itself out against half a config (the
    # lesson panels-held already records). Idle is also where five
    # knobs turned in one config collapse into one build.
    if {[llength [info commands panel-rebuild-soon]]} { panel-rebuild-soon }
    if {[llength [info commands widgets-rebuild-soon]]} {
        desk-window-build
        widgets-rebuild-soon
    }
    if {[llength [info commands tray-recolor]]} { tray-recolor }
    foreach {ww tt} [array get ::frameof] {
        frame-recolor $tt [frame-focus-color $ww]
    }
    after idle ui-restyle
}
# The two colours that DO have a knob: the variable holds what the
# theme gives, and the parallel `_said` one holds the word a layer
# spoke, which is what the configurator reads. Empty there is what
# makes the row say «worked out, not written» — the same shape the
# terminal's answer has, and the reason none of that had to be built
# again for this.
proc theme-derive-said {} {
    if {$::desk_background_said eq ""} { set ::desk_background [themed desk] }
    if {$::tray_bg_said eq ""} { set ::tray_bg [themed ground] }
}
# Frame colors: the focus highlight pair, the modal amber a keyboard
# move/resize wears, the matching lighter shade for each one's corner
# grips, and the constant dark outline that keeps two touching frames
# readable as two windows (before it, several inactive titlebars fused
# into one gray field).
keep OUTLINE #2e3436
set KBMR_BG #c17d11
array set gripof {#3465a4 #6b93c0 #888a85 #a5a7a1 #c17d11 #e0a94a
                  #6b7278 #8d949a}

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
# titlebar-button NAME -glyph SVG ?-side left|right? ?-needs CMDS?
#                                                    ?-when PRED?
# Order within a side is declaration order, left to right. The name
# becomes a treectrl column tag and an image name, so it is kept to
# lowercase letters.
#
# PRESENCE is two conditions, judged where the set is (client-buttons,
# at frame build and again on retitle): `-needs` gates on the machine
# — commands in PATH, the actions' own word — and `-when` on the
# WINDOW, a predicate exactly as wm-style takes them. The minimize
# button refusing to appear on a client whose style refuses
# minimization used to be a name check hard-coded in client-buttons;
# it is now the stock declaration's own -when, the first consumer of
# the general word.
keep titlebar_buttons {}
proc titlebar-button {name args} {
    if {![regexp {^[a-z][a-z0-9]*$} $name]} {
        error "titlebar-button: «$name» — lowercase letters and digits,\
 it becomes a column tag"
    }
    set side right
    set glyph ""
    set spec {}
    foreach {opt val} $args {
        switch -- $opt {
            -side {
                if {$val ni {left right}} {
                    error "titlebar-button $name: -side is left or right"
                }
                set side $val
            }
            -glyph { set glyph $val }
            -needs { dict set spec needs $val }
            -when  { dict set spec when $val }
            default { error "titlebar-button $name: unknown option $opt" }
        }
    }
    if {$glyph eq ""} {
        error "titlebar-button $name: -glyph is required —\
 svg markup, or a character or two"
    }
    if {![string match <* [string trim $glyph]]
            && [string length $glyph] > 2} {
        error "titlebar-button $name: a text glyph is a character or\
 two, not «$glyph» — anything longer wants svg"
    }
    dict set ::titlebar_buttons $name \
        [dict merge [dict create side $side glyph $glyph] $spec]
}
# Which of the two a glyph IS: svg markup renders to a photo
# (btn-images), a bare character draws as text in the strip's own
# font and ink — `titlebar-button ask -glyph ?` is the whole
# declaration (the owner, 2026-08-05).
proc titlebar-glyph-text {name} {
    set g [dict get $::titlebar_buttons $name glyph]
    if {[string match <* [string trim $g]]} { return "" }
    return $g
}
proc titlebar-side  {name} { dict get $::titlebar_buttons $name side }
proc titlebar-image {name} { return imgBtn-$name }
proc btn-images {} {
    # re-creating a photo under the same name updates every user of it;
    # the union box is glyph + 2*3px ipad (the 1px outline draws inside),
    # so this glyph height makes the box exactly btnw square — the full
    # button cell, no inset
    set g [expr {max($::btnw - 2 * $::btnpad, 7)}]
    # ...and the TEXT glyphs get a font fitted to the same square the
    # svg renders into: a font asks for its linespace, and a glyph
    # taller than the cell hung below the row — a П-shaped button rank
    # (the owner, 2026-08-05). The badge trick, again: a PIXEL size
    # walked down until the line fits, so a text button is the same
    # btnw square its svg neighbours are.
    if {"BtnGlyphFont" ni [font names]} { font create BtnGlyphFont }
    for {set s $g} {$s > 7} {incr s -1} {
        font configure BtnGlyphFont \
            -family [font actual TitleFont -family] -size -$s -weight bold
        if {[font metrics BtnGlyphFont -linespace] <= $g} break
    }
    dict for {name spec} $::titlebar_buttons {
        if {[titlebar-glyph-text $name] ne ""} continue   ;# drawn as text
        image create photo [titlebar-image $name] \
            -format [list svg -scaletoheight $g] -data [dict get $spec glyph]
    }
}
# The stock right-side trio keeps the OUTER edge: a config's buttons
# land INSIDE — right of the menu, left of minimize — in declaration
# order (the owner, 2026-08-05). The hand knows close and its
# neighbours by position, and a custom button outside them would move
# what must not move.
proc titlebar-order {names} {
    set out {}
    set tail {}
    foreach n $names {
        if {$n in {minimize maximize close}} {
            lappend tail $n
        } else {
            lappend out $n
        }
    }
    concat $out $tail
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
proc minimize-allowed {w} { expr {[minimize-mode $w] ne "refuse"} }
titlebar-button menu     -side left  -glyph $SVG_MENU
titlebar-button minimize -side right -glyph $SVG_MIN -when minimize-allowed
titlebar-button maximize -side right -glyph $SVG_MAX
titlebar-button close    -side right -glyph $SVG_CLOSE

titlebar-bind menu     <1> winops
titlebar-bind minimize <1> Minimize
titlebar-bind maximize <1> Maximize
# The pair every classic desktop hides on this button (Metacity, KWin):
# the middle button makes the window tall, the right one wide — each
# axis a toggle of its own.
titlebar-bind maximize <2> Maximize-V
titlebar-bind maximize <3> Maximize-H
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
    wm-font TitleFont {*}$args
    settle-soon titles
}
# ...and the same for the strip's lettering, which had the FONT all
# along (PanelFont is one of the two the WM is written in) and no way
# to say so: a desk that wanted smaller buttons had to move the desk
# font and take the titlebars with it (the owner, 2026-08-02). A delta
# on the base, exactly like the titlebar's — `set-panel-font -size
# 0.85x` is the whole idiom, and the strip re-measures because its
# geometry memo goes with the rebuild.
proc set-panel-font {args} {
    wm-font PanelFont {*}$args
    panel-rebuild-soon
}
proc retitle-frames {} {
    title-metrics
    after idle ui-restyle   ;# the applets are set in this desk's fonts
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
        # A rebuild is needed for a changed button SET — the columns,
        # elements and styles are per widget — and for a changed BUTTON
        # SIZE, which is the same thing one level down: the box is the
        # glyph plus the padding, both baked into the style at build
        # time, and re-creating the photo under its old name does not
        # make treectrl re-measure the element that draws it. Without
        # this a live font change grew the strip and the columns and
        # left four twenty-pixel buttons stranded at the top of a tall
        # titlebar (the owner, 2026-07-30).
        set want [client-buttons $w]
        if {$want ne [frame-buttons $t]
                || ![info exists ::btnwof($t)] || $::btnwof($t) != $::btnw} {
            unset -nocomplain ::btn($t)
            destroy $t.title
            titlebar-build $t $w $want [title-or-id $w \
                [expr {[info exists ::titleof($w)] ? $::titleof($w) : ""}]]
        }
        frame-layout $t [$t.slot cget -width] [$t.slot cget -height]
    }
    update idletasks
    foreach {w t} [array get ::frameof] {
        # A TALLER TITLEBAR IS A TALLER FRAME, and this growth is
        # OURS: no client asked for it, so the resize path's clamp
        # never sees it, and a window standing at the bottom edge
        # ends up four pixels under the panel (measured, after the
        # desk font grew by one). The origin follows the same rule as
        # everywhere else: move it in, never shrink it, and leave a
        # window that state owns — fullscreen — alone.
        # ...but NOT in the middle of a reload (wa_hold): the workarea
        # is mid-transition then — half the config spoken, or none —
        # and a clamp against it moves windows the release's REFLOW
        # was about to judge from their held positions. The clamp
        # jumping first is what broke the corner window's re-stick
        # and moved a column under follow-off (measured, the reflow
        # suite); held, the one transition at release owns ALL the
        # moving, which is the reflow's whole design.
        if {!$::wa_hold && ![info exists ::fullscreen($w)]
                && [regexp {^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$} \
                        [wm geometry $t] -> fw fh fx fy]} {
            lassign [clamp-to-rect [workarea-at [list $fx $fy $fw $fh]] \
                         $fx $fy $fw $fh] nx ny
            if {$nx != $fx || $ny != $fy} { wm geometry $t +$nx+$ny }
        }
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
# integral columns) in the FREE resize only: a maximized axis and a
# %-sized place fill to the pixel regardless (the mutter rule — see
# apply-size-hints), so `ignore` is for taste, not for even edges.
# icon (anything resolve-icon takes: a Tk image name, a file path, a
# bare NAME searched as NAME.png through icon-path) — shown for the
# window in the window list, overriding the client's own _NET_WM_ICON.
# minimize (iconify|refuse) — this client's answer to an iconify
# request, overriding the desk-wide set-minimize.
# decor (full|border|none|hint) — how much frame this client wears;
# see chrome-of, and hinted-decor for what the window itself asked for
# (a named step OVERRULES that; `hint` hands the question back to the
# window). decor-floor (border|full) — the least frame a window that
# ASKED for none still wears: promotes only the Motif-said none (the
# CSD shape — firefox, GTK4), so the furniture types (dock, splash,
# tooltip...) stay bare and `wm-style always {decor-floor border}` is
# safe desk-wide; an explicit `decor none` rule outranks the floor.
# place (a term list) — the geometry it is
# born with; see parse-place.
# desk (a number, or sticky) — which desk it is born on; sticky means
# every desk. See the virtual desks block in the substrate.
# layer (a number 0..12, or below|normal|above|dock|top) — where in the
# stack it lives; see the LAYERS block. The number is what lets a config
# say the thing no state can: «over the panel AND over a fullscreen
# window» is layer 10 or more, and nothing else on the desk has to know
# about it.
# opacity (0 < N <= 1) — the translucency the frame rests at (needs a
# compositor); see rest-opacity.
# start (iconic|fullscreen|normal) — the state it is born in, the
# config's word for what a client asks with WM_HINTS initial_state or a
# pre-map _NET_WM_STATE; see policy-start-state.
keep style_rules {}
proc always {w} { return 1 }
proc wm-style {pred settings} {
    # A malformed rule must die HERE, at its own line of the config —
    # accepted, it detonates later inside style-of on every window the
    # predicate matches, and what that looks like from the desk is
    # nothing like a config error: an empty 200x200 husk where the
    # window list should be, new frames half-managed (the owner's
    # desk, 2026-07-31, from `place max force` — three words where
    # `place {max force}` was meant: a value with spaces needs its
    # own braces).
    if {[llength $settings] % 2} {
        error "wm-style: settings is not a dict (odd length): «$settings» —\
 a value with spaces needs its own braces: place {max force}"
    }
    lappend ::style_rules [list $pred $settings]
}
proc style-of {w} {
    if {[info exists ::styleof($w)]} { return $::styleof($w) }
    # The seed's decor is the WORD `hint` — "whatever the window asked
    # for", resolved after the rules have spoken. A `decor` named in
    # the config beats the window's hint by the same mechanism that
    # makes a later rule beat an earlier one (the order the owner asked
    # for, 2026-08-02: what a hint decides, a config line must be able
    # to overrule), a later `decor hint` hands the question back to the
    # window — and the floor below can tell a hint-derived none from a
    # config-spoken one, which no post-merge reading of a concrete
    # value could.
    set st [dict create increments respect decor hint]
    foreach rule $::style_rules {
        lassign $rule pred settings
        if {[catch {uplevel #0 [list {*}$pred $w]} match]} {
            puts "WM: style predicate error on 0x[format %x $w]: $match"
        } elseif {$match} {
            set st [dict merge $st $settings]
        }
    }
    if {[dict get $st decor] eq "hint"} {
        set d [hinted-decor $w]
        # decor-floor: the least frame a window that ASKED for none
        # still wears — the CSD shape (firefox, every GTK4 window)
        # made resizable and focus-ringed desk-wide in one always-rule
        # (the owner, 2026-08-14). Only the MOTIF-said none is
        # promoted: a none that came from the furniture types (dock,
        # splash, tooltip...) stays bare — `always {decor-floor
        # border}` must not dress the panel's neighbours. And only a
        # HINT-derived none: an explicit `decor none` rule was just
        # honored above by not entering this branch, so a config can
        # still pin a window bare under a desk-wide floor.
        if {$d eq "none" && [dict exists $st decor-floor]} {
            set floor [dict get $st decor-floor]
            if {$floor ni {none border full}} {
                puts "WM: decor-floor «$floor»: none, border or full —\
 ignored"
            } elseif {[client-motif-decor $w] eq "0"} {
                set d $floor
            }
        }
        dict set st decor $d
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

# ---- what the CLIENT asked for, before any rule speaks ----
# The default `decor` is not a constant. A window that draws its own
# titlebar inside itself asks for no frame, and honoring that is not a
# courtesy: a GTK4 window given ours wears TWO titlebars, one of them
# useless. So the style's starting point is what the WINDOW said, and
# `full` is merely what a window that said nothing gets.
#
# The Motif mask maps onto our three steps almost by itself, because
# the three steps ARE the distinctions Motif drew: no bits at all is
# `none`; a mask carrying MWM_DECOR_TITLE is `full`; anything left —
# a border, resize handles, no title strip — is exactly `border`.
#
# The EWMH types answer only when Motif said nothing, and follow the
# spec's own reading: the furniture of the desk (a desktop, a dock, a
# splash, the popup kinds that arrive override-redirect anyway) carries
# no frame; a torn-off toolbar or menu is decorated small, which is
# what `border` is for; a dialog or a utility window is an ordinary
# decorated window and says so by not being anything else.
proc hinted-decor {w} {
    set d [client-motif-decor $w]
    if {$d ne ""} {
        if {$d == 0} { return none }
        if {$d & 8}  { return full }        ;# MWM_DECOR_TITLE
        return border
    }
    foreach type [client-window-types $w] {
        switch -- $type {
            desktop - dock - splash - notification - tooltip -
            dropdown_menu - popup_menu - combo - dnd { return none }
            toolbar - menu { return border }
            normal - dialog - utility { return full }
        }
    }
    return full
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
# which is also when a config may have changed the catalogue itself —
# and that is the moment -needs and -when are judged, not
# continuously. A predicate that throws costs its button and a log
# line, never the frame (the panel-matches rule).
proc client-buttons {w} {
    set names {}
    dict for {name spec} $::titlebar_buttons {
        if {[dict exists $spec needs]
                && ![needs-met [dict get $spec needs]]} continue
        if {[dict exists $spec when]} {
            if {[catch {uplevel #0 \
                    [list {*}[dict get $spec when] $w]} m]} {
                puts "WM: titlebar button $name: when predicate error: $m"
                continue
            }
            if {!$m} continue
        }
        lappend names $name
    }
    return $names
}
# Commands in PATH, all of them — the actions' waiting gate, factored:
# the cached MISS is busted first, so software that arrived since is
# noticed (the needs lesson).
proc needs-met {cmds} {
    foreach c $cmds {
        array unset ::auto_execs $c
        if {[auto_execok $c] eq ""} { return 0 }
    }
    return 1
}
proc frame-buttons {t} {
    if {[info exists ::btncols($t)]} { return $::btncols($t) }
    dict keys $::titlebar_buttons
}

