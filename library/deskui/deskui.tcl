# deskui — the desk's ui toolkit as a package: the style bridge, the
# mnemonics and accelerators, the focus ring, the field megawidget,
# the ask and pick dialogs, the tree render and its cell editors.
#
# Everything here is GENERIC: it knows nothing of applets, of layers,
# or of window management, and a program that requires it gets the
# desk's look and the desk's widgets WITHOUT becoming a window manager
# — which `package require tk9wm` would make it, redirect and all (see
# ../pkgIndex.tcl). That distinction is the whole reason this file was
# cut out of library/ui/host.tcl.
#
# It lives in tk9wm's tree because that is where it grew and where its
# consumers are; its own repo is the endgame, not the start, so the
# code sits in a directory of its own — the move, when it comes, is a
# move and not a picking-over.
#
# WHAT A CONSUMER MUST DO IS deskui-init. The toolkit talks to whoever
# hosts it over Tk send, and it cannot guess that name: the WM knows
# what it is called and tells its host on argv. `-` means nobody is
# behind us — the standalone answers below stand in for the desk, and
# that mode is a REQUIREMENT here, not a courtesy: anything that
# cannot answer for itself with no desk behind it does not belong in
# this file.
#
# The procedure names are deliberately global and un-prefixed (ui-*),
# the same choice the tk9wm package makes for the same reason: the
# files that call them — applet files, config files — are written at
# the global level, and a namespace would buy nothing here but a
# rename across every consumer.
package require Tk
package require treectrl   ;# the desk's own widget of choice
package require treesync   ;# what ui-tree-render reconciles against

# deskui-init PEER — PEER is the send name of whoever hosts us, or `-`
# when nobody does. Said once, before anything else here is called.
set ui_wmapp -
proc deskui-init {peer} { set ::ui_wmapp $peer }

# The transport, our side: eval in the desk, get the answer. The name
# is never guessed — it is said once to deskui-init, because only the
# consumer knows it (the WM tells its host on argv).
#
# ...AND WITH NO DESK BEHIND IT (config-tree, step 4: an applet has to
# work standalone as well as wired to a WM — the requirement on
# anything that leaves for a library, and now the requirement on
# everything IN one). Initialized with `-`, we answer the calls we can
# answer by ourselves and refuse the rest OUT LOUD: a consumer that
# needs the desk says so in a sentence instead of hanging on a send to
# nobody.
#
# The four verbs below are therefore the CONTRACT a peer must speak:
# ui-style, workarea, chrome, and the problems pair. A peer that is not
# a tk9wm answers them itself; tk9wm answers them already.
proc wm-call {script} {
    if {$::ui_wmapp ne "-"} { return [send -- $::ui_wmapp $script] }
    return [ui-standalone $script]
}
proc ui-standalone? {} { expr {$::ui_wmapp eq "-"} }
proc ui-standalone {script} {
    switch -- [lindex $script 0] {
        ui-style {
            # the theme the toolkit itself has, which is the honest
            # answer when no desk has an opinion
            set f [font actual TkDefaultFont]
            return [dict create scheme light \
                deskfont [list -family [dict get $f -family] -size 10] \
                titlefont [list -family [dict get $f -family] -size 10 \
                                -weight bold] \
                bg #d6d6d6 fg #202020 field #ffffff select #b0c4de \
                trough #c0c0c0 link #204a87]
        }
        problems  { return {} }
        problem-record { puts "UI: $script" ; return }
        workarea  { return [list 0 0 [winfo screenwidth .] [winfo screenheight .]] }
        chrome    { return {} }
    }
    error "«[lindex $script 0]» needs the desk, and this host was\
 started without one"
}

# The style bridge, host side: fetch the desk's fonts and palette
# (ui-style in the WM) and wear them. Named fonts re-CONFIGURE, so a
# sync restyles windows already up; the option database covers the
# widgets built after it; and the palette itself is kept for applet
# builders that color by hand ([ui-color KEY]). Synced at every
# ui-open — the desk may have changed its type since, and an applet
# should arrive dressed for today.
set ui_palette {}
proc ui-style-sync {} {
    if {[catch {wm-call ui-style} st]} {
        puts "UI: style sync failed: $st"
        return
    }
    if {![dict exists $st scheme]} { return }
    set ::ui_palette $st
    foreach {name key} {DeskFont deskfont TitleFont titlefont} {
        if {[lsearch -exact [font names] $name] < 0} { font create $name }
        font configure $name {*}[dict get $st $key]
    }
    # ...AND A FONT FOR WHAT ONE CLICKS. A hyperlink says so by being
    # underlined, and an applet spelling that out per widget gets it
    # subtly wrong in three places — so the bridge keeps one, dressed
    # from the same desk font it follows.
    if {[lsearch -exact [font names] LinkFont] < 0} { font create LinkFont }
    font configure LinkFont {*}[dict get $st deskfont] -underline 1
    # THE TTK THEME IS PART OF THE BRIDGE (the owner: the font dialog
    # was a mess of two palettes). Tk's own dialogs — fontchooser
    # first among them — are ttk widgets, so a desk that dresses its
    # applets must dress ttk too, matched at least light-to-light and
    # dark-to-dark. awthemes carries awdark/awlight and rides in
    # whale; without it, clam is the fallback that at least honors
    # colors.
    set scheme [dict get $st scheme]
    set theme [expr {$scheme eq "light" ? "awlight" : "awdark"}]
    if {[catch {package require $theme}] || [catch {ttk::style theme use $theme}]} {
        catch {ttk::style theme use clam}
        set theme clam
    }
    catch {ttk::style configure . -font DeskFont}
    # ...and the palette THE THEME actually uses becomes ours, so the
    # plain-Tk half (treectrl, text, listbox) agrees with the ttk half
    # instead of arguing with it. The WM's own colors stay the
    # fallback for anything a theme does not name.
    foreach {key style opt} {
        bg       TFrame  -background
        fg       TLabel  -foreground
        field    TEntry  -fieldbackground
        select   TEntry  -selectbackground
        selectfg TEntry  -selectforeground
        trough   TScrollbar -troughcolor
    } {
        if {![catch {ttk::style lookup $style $opt} v] && $v ne ""} {
            dict set ::ui_palette $key $v
        }
    }
    # SELECTED TEXT IS ITS OWN COLOUR, and forgetting that is how a
    # selection swallows the row it is meant to point at: awlight's
    # selection band is a DARK blue, so the ordinary black ink went
    # invisible on it (the owner, 2026-08-02 — "the idea was white
    # letters on that selection; treectrl draws them black"). ttk
    # names the pair and we now take both; where a theme names only
    # the band, the ink is worked out from it by luminance, which is
    # never wrong even when it is not what the theme would have said.
    if {![dict exists $::ui_palette selectfg]
            || [dict get $::ui_palette selectfg] eq ""} {
        dict set ::ui_palette selectfg \
            [ui-readable [dict get $::ui_palette select]]
    }
    # POINTED AT IS NOT PICKED. The selection band is a ground with an
    # ink of its own; a header or a row merely UNDER THE POINTER keeps
    # the ordinary ink, so it cannot wear that band — awlight's dark
    # blue behind unchanged black letters is a heading that goes blank
    # as you reach for it (the owner, 2026-08-02). So the hover ground
    # is the header's own, tinted a little toward the selection: the
    # same hue says the same thing, and the ordinary ink stays on it.
    dict set ::ui_palette hover \
        [ui-tint [dict get $::ui_palette trough] \
                 [dict get $::ui_palette select] 0.22]
    set st $::ui_palette
    # ...and the PAIR goes into the option database. selectForeground
    # was not written here, so every plain entry and listbox that had
    # not dressed it by hand fell back on Tk's own black — dark
    # letters on the dark selection band, in both themes (the owner,
    # 2026-08-10, in the examples dialog's entry).
    foreach {opt key} {
        background bg foreground fg activeBackground select
        activeForeground selectfg
        selectBackground select selectForeground selectfg
        highlightBackground bg
        troughColor trough insertBackground fg
    } {
        option add *$opt [dict get $st $key] widgetDefault
    }
    option add *font DeskFont widgetDefault
    option add *Entry.background [dict get $st field] widgetDefault
    option add *Text.background [dict get $st field] widgetDefault
    option add *Listbox.background [dict get $st field] widgetDefault
    ui-redress-tk-dialogs
    ui-style-announce
}
# ---- Tk's own dialogs, told the palette by hand ----
# The fontchooser is ttk down to its lists — and the lists are plain
# listboxes, dressed once at birth from whatever the option database
# said that day. The ttk half follows a live theme flip; the plain
# half kept its birth colours on the owner's desk (light→dark→light
# left the lists dark, 2026-08-10). The database cannot reach a
# widget that already exists, so the standing dialogs are walked and
# re-dressed by name — the same move cfg-restyle makes for the tree,
# for the same reason. Every TkFontDialog wherever it hangs (the
# chooser builds under its -parent, not under the root), and only the
# plain widgets in it: ttk needs nothing here.
proc ui-redress-tk-dialogs {{root .}} {
    foreach w [winfo children $root] {
        if {[winfo class $w] eq "TkFontDialog"} {
            catch {$w configure -background [ui-color bg]}
            ui-redress-plain $w
        } else {
            ui-redress-tk-dialogs $w
        }
    }
}
proc ui-redress-plain {w} {
    switch -- [winfo class $w] {
        Listbox - Entry - Text - Spinbox {
            catch {$w configure -background [ui-color field] \
                       -foreground [ui-color fg] \
                       -selectbackground [ui-color select] \
                       -selectforeground [ui-color selectfg]}
            catch {$w configure -insertbackground [ui-color fg]}
        }
    }
    foreach c [winfo children $w] { ui-redress-plain $c }
}
# ...AND THE APPLETS ALREADY ON THE SCREEN, which is the other half
# and was missing. `option add` dresses what is created NEXT and
# nothing that exists, so a live theme change left every open applet
# wearing the theme it was born in (the owner, 2026-08-02: "the
# configurator does not repaint on the fly; I would like all of ours
# to understand an analog of <<ThemeChanged>>"). This is that analog,
# and it is deliberately the same shape Tk's own is: a virtual event
# on the toplevel, which whoever cares binds. An applet that binds
# nothing simply keeps its colours — the same soft edge the rest of
# this bridge has, and no window is obliged to be restyleable.
#
# WHO GETS TOLD is every toplevel this program owns, not the applet
# registry it used to walk: the registry is the host's private word and
# has no business in a library. Strictly more windows hear it now (a
# standing .ask, a dialog) and that costs nothing — an event nobody
# binds is an event nobody notices.
proc ui-style-announce {} {
    foreach top [concat . [winfo children .]] {
        if {![winfo exists $top] || [winfo toplevel $top] ne $top} continue
        catch {event generate $top <<DeskStyle>> -when tail}
    }
}
proc ui-color {key} {
    expr {[dict exists $::ui_palette $key]
          ? [dict get $::ui_palette $key] : "#888888"}
}
# Ink a given ground can carry — the WM's own contrast-fg, on this
# side of the door. Two-way and no more: light ink on a dark ground,
# dark ink on a light one.
proc ui-readable {bg} {
    if {[catch {winfo rgb . $bg} c]} { return #eeeeec }
    lassign $c r g b
    expr {(0.2126*$r + 0.7152*$g + 0.0722*$b) / 65535.0 > 0.5
          ? "#1c1c1c" : "#eeeeec"}
}
# A colour a LITTLE way toward another one — the one derivation this
# bridge allows itself, and only because the palette it derives from
# is not ours to extend: the ttk theme names the roles it names, and
# «the same ground, a hint of the accent in it» is not one of them.
# Both ends of the mix are palette colours, so a theme change moves
# the result with them.
proc ui-tint {base accent frac} {
    if {[catch {winfo rgb . $base} b] || [catch {winfo rgb . $accent} a]} {
        return $base
    }
    set out {}
    foreach x $b y $a {
        lappend out [expr {round($x * (1.0 - $frac) + $y * $frac) / 256}]
    }
    format "#%02x%02x%02x" {*}$out
}
# The desk's usable rectangle {x y w h} and what a frame costs around
# a client {border decotop} — an applet that sizes itself must fit
# INSIDE the workarea, decoration included, or it is born with its
# bottom edge under the panel (the owner's report). Screen dimensions
# are the wrong measure and the WM is the only honest source.
proc ui-workarea {} {
    expr {[dict exists $::ui_palette workarea]
          ? [dict get $::ui_palette workarea]
          : [list 0 0 [winfo screenwidth .] [winfo screenheight .]]}
}
proc ui-chrome {} {
    expr {[dict exists $::ui_palette chrome]
          ? [dict get $::ui_palette chrome] : {2 28}}
}

# MNEMONICS, marked in the text itself: "&Knobs" shows Knobs with the
# K underlined and answers to Alt+k. One notation for every applet —
# a keyboard-first desk cannot have each of them inventing its own —
# and it works for the things that are NOT buttons too: a label can
# lead to the widget it names, which is the only way a tree or a
# list gets a hotkey of its own (the owner's ask, made general).
proc ui-mnemonic {text} {
    set i [string first & $text]
    if {$i < 0} { return [list $text -1] }
    return [list [string replace $text $i $i] $i]
}
# ui-label PATH TEXT ?TARGET? ?options...? — the label, and the
# promise its underline makes: Alt+letter puts the focus where the
# label points.
proc ui-label {path text {target ""} args} {
    lassign [ui-mnemonic $text] shown idx
    label $path -text $shown -underline $idx -takefocus 0 -anchor w {*}$args
    if {$idx >= 0 && $target ne ""} {
        set ch [string tolower [string index $shown $idx]]
        bind [winfo toplevel $path] <Alt-Key-$ch> [list ui-focus-target $target]
    }
    return $path
}
# ...and the focus lands VISIBLY: a target that was never given a
# ring would take the focus and say nothing about it.
proc ui-focus-target {w} {
    if {![winfo exists $w]} return
    focus $w
}
# Generic Alt-accelerator support (the owner's pick over hand-rolled
# bindings): a button declaring -underline N gets Alt+<that letter>
# bound on its toplevel to its own invoke. Call it once per button;
# the underline is already the visible promise, this makes it true.
# A button whose TEXT carries an & is marked up first, so both
# notations are available and only one has to be remembered.
proc ui-accel {btn} {
    lassign [ui-mnemonic [$btn cget -text]] shown idx
    if {$idx >= 0} { $btn configure -text $shown -underline $idx }
    set u [$btn cget -underline]
    # modern Tk defaults -underline to the EMPTY STRING, not -1 (the
    # owner has been bitten before) — treat anything non-numeric as
    # "no underline declared"
    if {![string is integer -strict $u] || $u < 0} return
    set ch [string tolower [string index [$btn cget -text] $u]]
    set top [winfo toplevel $btn]
    # TWO BUTTONS, ONE LETTER: only the first can answer, and the
    # second was still SHOWING its underline — promising a key that
    # belongs to somebody else (the owner found Close and Clear both
    # wearing C, 2026-08-01). The first keeps the letter; the loser
    # loses its underline, so what is on the screen is what works,
    # and the desk is told, because a promise the ui could not keep
    # is a defect and not a detail.
    if {[info exists ::ui_accel($top,$ch)] && $::ui_accel($top,$ch) ne $btn} {
        $btn configure -underline -1
        set held $::ui_accel($top,$ch)
        lappend ::ui_accel_clash [list $top $ch $held $btn]
        puts "UI: accelerator clash on Alt+$ch in [winfo class $top]:\
 «[$held cget -text]» holds it, «[$btn cget -text]» shows it no more"
        catch {
            wm-call [list problem-record "ui accelerator" \
                "Alt+$ch is asked for twice in this window —\
 «[$held cget -text]» answers it, «[$btn cget -text]» stopped\
 promising it"]
        }
        return
    }
    set ::ui_accel($top,$ch) $btn
    bind $top <Destroy> +[list ui-accel-forget $top %W]
    bind $top <Alt-Key-$ch> [list ui-accel-fire $btn]
}
# ---- a button struck by its letter shows itself struck ----
# Tk does this in some places and not others (the owner, and he wants
# it everywhere): a key that fires a button somewhere across the
# window says nothing about WHICH button answered unless the button
# says it. So it presses, paints, acts, and lets go a moment later.
#
# It acts BEFORE it lets go, not after: the press is then visible for
# exactly as long as the work takes plus the tail, and a caller — a
# test, a script — sees the same timing it always did rather than a
# command delayed for the sake of a wink.
proc ui-accel-fire {btn} {
    if {![winfo exists $btn]} return
    set undo [ui-press $btn]
    update idletasks
    $btn invoke
    after 90 [list ui-unpress $btn $undo]
}
proc ui-press {btn} {
    # ttk widgets have a state machine; classic ones have a relief
    if {![catch {$btn instate pressed}]} {
        $btn state pressed
        return ttk
    }
    set old [$btn cget -relief]
    catch {$btn configure -relief sunken}
    return $old
}
proc ui-unpress {btn undo} {
    if {![winfo exists $btn]} return
    if {$undo eq "ttk"} {
        catch {$btn state {!pressed}}
    } else {
        catch {$btn configure -relief $undo}
    }
}
# ...and a window that goes takes its letters with it, or the next
# window of the same name would inherit a clash that is not there.
proc ui-accel-forget {top w} {
    if {$w ne $top} return
    array unset ::ui_accel "$top,*"
}
# What a TEST asks: every clash this session has seen, so a suite can
# insist there were none instead of somebody noticing by hand.
proc ui-accel-clashes {} {
    if {![info exists ::ui_accel_clash]} { return {} }
    return $::ui_accel_clash
}
# ---- a ring that belongs to the BOX, not to the widget in it ----
# The owner's taste, and it is the right one (2026-08-01): a scrolled
# tree with its scrollbar is ONE thing on the screen, so the focus
# ring goes round the pair — and while a value is being edited INSIDE
# that box, the box has not stopped being where the focus is. A ring
# drawn by the widget itself blinks off the moment an editor opens
# over it, which says «you left» when nobody left.
#
# So: a ttk::frame with a style of its own, and the ring follows the
# focus anywhere in its subtree. Reusable on purpose — the next
# applet gets a scrolled thing too.
proc ui-ring-box {path args} {
    # OUT OF THE FOCUS CYCLE ITSELF: the box decorates, the widget in
    # it focuses. Left to Tk's heuristic the frame was a Tab stop of
    # its own — the ring lit with nothing focused in it, an empty
    # stop right before the real one (the owner, 2026-08-02).
    ttk::frame $path -style UiRing.TFrame -borderwidth 2 -relief solid \
        -takefocus 0 {*}$args
    catch {ttk::style configure UiRing.TFrame -bordercolor [ui-color bg]}
    catch {ttk::style configure UiRingOn.TFrame -bordercolor [ui-color link]}
    bind $path <FocusIn>  +[list ui-ring-follow $path %W]
    bind $path <FocusOut> +[list ui-ring-follow $path %W]
    return $path
}
# Tk sends FocusIn/FocusOut for every widget in the subtree; what the
# box wants to know is whether the focus is STILL somewhere inside
# it, which is one question about the focus widget's ancestry.
proc ui-ring-follow {box w} {
    after idle [list ui-ring-paint $box]
}
proc ui-ring-paint {box} {
    if {![winfo exists $box]} return
    set f [focus]
    set inside [expr {$f ne "" && ($f eq $box || [string match "$box.*" $f])}]
    $box configure -style [expr {$inside ? "UiRingOn.TFrame" : "UiRing.TFrame"}]
}

# ---- a field one can actually type in ----
# A decorated `text` rather than an `entry`, even for one-liners (the
# owner's preference, same day, and he is right): it has undo, it can
# grow to three lines when the value is three lines, and it takes the
# same dress as everything else. Borderless inside a ring box, so the
# BOX draws the focus and the text draws only text.
#
#   ui-field PATH ?-height N? ?-font F?   -> the box; $box.t is the text
# TAB LEAVES THE FIELD. A text widget's own Tab inserts a tab
# character, which is right for a text editor and wrong for a field
# standing in for an entry — the owner wants the focus to move, here
# and everywhere else (2026-08-02; tabs-as-spaces for the multi-line
# case is a separate wish for later).
#
#   -onleave CMD   run before the focus goes; answering 0 keeps it
#                  (the tree's editor commits there, and a refused
#                  value stays under the hand that typed it)
proc ui-field {path args} {
    set o [dict merge {-height 1 -font DeskFont -onleave {}} $args]
    set ::ui_field_leave($path) [dict get $o -onleave]
    ui-ring-box $path
    text $path.t -height [dict get $o -height] -width 1 -wrap none \
        -font [dict get $o -font] -undo 1 -borderwidth 0 \
        -highlightthickness 0 -padx 3 -pady 1 \
        -background [ui-color field] -foreground [ui-color fg] \
        -insertbackground [ui-color fg]
    grid $path.t -row 0 -column 0 -sticky nsew
    grid rowconfigure $path 0 -weight 1
    grid columnconfigure $path 0 -weight 1
    bind $path.t <Tab>           [list ui-field-leave $path next]
    bind $path.t <Shift-Tab>     [list ui-field-leave $path prev]
    # X sends this one for shift+tab, and a form that ignores it has
    # a backwards tab that silently does nothing
    bind $path.t <ISO_Left_Tab>  [list ui-field-leave $path prev]
    bind $path <Destroy> +[list ui-field-forget $path %W]
    return $path
}
proc ui-field-forget {path w} {
    if {$w eq $path} { array unset ::ui_field_leave $path }
}
# THE SIXTH WALL STANDS, AND THE LINES KEEP COMING: past the tallest
# a field opens at, a scrollbar joins the text inside the same ring —
# the pair is one thing on the screen, exactly like the tree and its
# scrollbar (the owner, 2026-08-02) — and leaves when the lines do.
# Out of the focus cycle for the same reason the tree's is: a stop
# with nothing to show for it is worse than no stop.
proc ui-field-scroll {path on} {
    if {$on && ![winfo exists $path.sb]} {
        ttk::scrollbar $path.sb -orient vertical -takefocus 0 \
            -command [list $path.t yview]
        $path.t configure -yscrollcommand [list $path.sb set]
        grid $path.sb -row 0 -column 1 -sticky ns
    } elseif {!$on && [winfo exists $path.sb]} {
        destroy $path.sb
        $path.t configure -yscrollcommand {}
    }
}
proc ui-field-leave {path which} {
    if {[info exists ::ui_field_leave($path)]
            && [llength $::ui_field_leave($path)]} {
        if {![uplevel #0 $::ui_field_leave($path)]} { return -code break }
    }
    if {[winfo exists $path.t]} {
        focus [expr {$which eq "next" ? [tk_focusNext $path.t]
                                      : [tk_focusPrev $path.t]}]
    }
    return -code break
}
# WHERE THE FIRST LETTER SITS inside the field, {dx dy} from the box's
# own corner: the ring's border plus the text's padding. A caller that
# wants the letters to land on somebody else's letters places the box
# by this, instead of guessing at the arithmetic.
proc ui-field-inset {path} {
    set b [expr {[$path cget -borderwidth] + 0}]
    lassign [$path.t bbox 1.0] bx by
    if {$bx eq ""} {
        return [list [expr {$b + [$path.t cget -padx]}] \
                     [expr {$b + [$path.t cget -pady]}]]
    }
    return [list [expr {$b + $bx}] [expr {$b + $by}]]
}
proc ui-field-get {path} { string trimright [$path.t get 1.0 end] \n }
# HOW MANY LINES ARE THERE TO SEE — which is not how many lines the
# VALUE has. ui-field-get trims the trailing newlines, rightly (the
# one Tk keeps at the end is nobody's), and a caller who sized a field
# by that count left the last empty line homeless: Return at the end
# of a one-line field put the cursor on a second line the field had no
# room for, and the room only arrived once a letter was typed on it
# (the owner, 2026-08-03). The widget's own end knows better.
proc ui-field-lines {path} {
    lindex [split [$path.t index end-1c] .] 0
}
proc ui-field-set {path text} {
    $path.t delete 1.0 end
    $path.t insert 1.0 $text
    $path.t edit reset          ;# the value it was given is not an edit
    $path.t edit modified 0
}
proc ui-field-dirty? {path} { $path.t edit modified }
proc ui-field-select-all {path} {
    $path.t tag add sel 1.0 end-1c
    $path.t mark set insert 1.0
}

# ...and the keyboard-first dress code: the focus must be VISIBLE.
# Applied by builders to their focusable widgets.
proc ui-focusable {w} {
    # plain Tk: the highlight ring is an option
    if {![catch {$w configure -highlightthickness 2 \
            -highlightcolor [ui-color link] \
            -highlightbackground [ui-color bg]}]} return
    # ttk: no such option — the theme draws its own focus, and not
    # loudly enough for a keyboard-first desk, so the widget swaps to
    # a ringed variant of its own style while it holds the focus
    set base [$w cget -style]
    if {$base eq ""} { set base [winfo class $w] }
    set ring Focus.$base
    catch {ttk::style configure $ring -bordercolor [ui-color link] \
        -lightcolor [ui-color link] -darkcolor [ui-color link] \
        -focuscolor [ui-color link]}
    bind $w <FocusIn>  [list $w configure -style $ring]
    bind $w <FocusOut> [list $w configure -style $base]
}

# Background errors go to the LOG, not to a dialog. Tk's stock
# bgerror pops a window over the desk for something the user did not
# ask about and cannot act on; the desk's log is where the desk's
# accidents belong (and the applet that caused it says its own piece
# on its own status line).
proc bgerror {msg} {
    puts "UI: background error: $msg"
    if {[info exists ::errorInfo]} { puts $::errorInfo }
}

# ---- A DIALOG REFUSES IN THE DIALOG -------------------------------
# A commit that closes the window first and complains after — into
# whatever status line its applet keeps — reads as swallowed silence
# from where one sits (the owner, 2026-08-02, twice over: a bad
# chord, then a nameless widget). So a dialog with something to
# refuse says it under its own entries, in red, and keeps the floor;
# WHAT is valid and how to say it wrong is the caller's knowledge
# (the check callback below), holding the door is the dialog's job.
proc ui-dialog-say {w msg} {
    if {![winfo exists $w.say]} {
        label $w.say -takefocus 0 -anchor w -justify left \
            -foreground "#cc4040"
        pack $w.say -fill x -padx 6 -pady 2
    }
    $w.say configure -text $msg
    bell
}
# ---- A PICKER: choose one, name one (config-tree, step 4) --------
# Pick from a list, type a name, commit — the shape every «make a new
# one» dialog in this desk has. It was the configurator's; nothing
# about it ever was, so it lives here with the rest of the layer the
# next applet gets for free. The optional CHECK is the validating
# half: called with {choice typed}, it answers "" for good words or
# the sentence to refuse them with — said in the dialog, which then
# stays open on the line that needs fixing.
proc ui-pick-dialog {w parent wtitle title choices entrylabel commit {check {}}} {
    catch {destroy $w}
    toplevel $w -class Tk9wmUi
    wm title $w $wtitle
    wm transient $w $parent
    label $w.l -takefocus 0 -anchor w -text $title
    # -exportselection 0, AND IT IS NOT A DETAIL: a listbox that owns
    # the X selection loses its highlight the moment anything else
    # takes it — typing in the name field below does exactly that. The
    # dialog that asks for a pick AND a name was unusable because of
    # it: the owner found that the only way through was to type the
    # name first and then click the list, in that order (2026-08-02).
    # ...and WIDE ENOUGH TO READ: left to the toolkit's twenty
    # characters, the examples dialog showed the head of every row and
    # nothing of what made a row worth offering (the owner,
    # 2026-08-10). The list asks for its longest row, within reason —
    # a character count is an estimate under a proportional font, and
    # the cap keeps a long-winded example from opening a wall.
    set wch 20
    foreach c $choices { set wch [expr {max($wch, [string length $c])}] }
    listbox $w.list -font DeskFont -height [expr {max(3, min(10,
        [llength $choices]))}] -exportselection 0 \
        -width [expr {min($wch, 80)}] \
        -background [ui-color field] -foreground [ui-color fg] \
        -selectbackground [ui-color select] \
        -selectforeground [ui-color selectfg]
    ui-focusable $w.list
    foreach c $choices { $w.list insert end $c }
    label $w.el -takefocus 0 -anchor w -text $entrylabel
    entry $w.e -font DeskFont -background [ui-color field] \
        -foreground [ui-color fg] -insertbackground [ui-color fg]
    ui-focusable $w.e
    frame $w.b -takefocus 0
    ttk::button $w.b.ok -text OK -underline 0 \
        -command [list ui-pick-commit $w $commit $check]
    ttk::button $w.b.cancel -text Cancel -underline 0 \
        -command [list destroy $w]
    foreach b [list $w.b.ok $w.b.cancel] { ui-focusable $b; ui-accel $b }
    pack $w.b.ok $w.b.cancel -side left -padx 4 -pady 4
    pack $w.l -fill x -padx 6 -pady {6 2}
    pack $w.list -expand 1 -fill both -padx 6
    pack $w.el -fill x -padx 6 -pady {6 2}
    pack $w.e -fill x -padx 6
    pack $w.b -fill x
    bind $w <Escape> [list destroy $w]
    bind $w.list <Double-ButtonPress-1> [list ui-pick-commit $w $commit $check]
    bind $w.list <Return> [list ui-pick-commit $w $commit $check]
    bind $w.e <Return> [list ui-pick-commit $w $commit $check]
    focus [expr {[llength $choices] ? "$w.list" : "$w.e"}]
}
proc ui-pick-commit {w commit check} {
    set choice ""
    if {[llength [$w.list curselection]]} {
        set choice [$w.list get [lindex [$w.list curselection] 0]]
    }
    set typed [string trim [$w.e get]]
    # the caller's word on what valid means — refused words keep the
    # dialog standing, and the refusal is right under the entries
    if {[llength $check]} {
        set say [uplevel #0 [list {*}$check $choice $typed]]
        if {$say ne ""} { ui-dialog-say $w $say ; return }
    }
    destroy $w
    # BOTH answers go to whoever asked — which of them wins is the
    # caller's question, and a dialog that decided it for them would
    # be carrying one applet's habits into the library.
    {*}$commit $choice $typed
}
# ---- the ask box: one line of text, dressed as the desk ----------
# The WM's `Ask` lands here: an UNDECORATED box (override-redirect —
# the desk must not frame its own question) at the point the WM
# worked out from the place grammar, no buttons — Enter answers,
# Escape answers empty — and the field is ui-field, the same
# text-as-entry every configurator editor is. Deliberately spare: the
# owner wants a command line grown from this material one day
# (2026-08-05), and a command line is a prompt, a field and two keys.
#
# The answer goes back over the send bridge (ask-answer ID TEXT); a
# WM that reloaded meanwhile drops it with a line, and tells this box
# to go through ui-ask-drop.
proc ui-place-axis {origin extent size align} {
    switch -- $align {
        start  { return $origin }
        end    { return [expr {$origin + $extent - $size}] }
        center { return [expr {$origin + ($extent - $size) / 2}] }
    }
}
proc ui-ask {wmapp id prompt initial anchor warect {width ""}} {
    catch {destroy .ask}
    # A CLIENT, not an override-redirect (the first version was one,
    # and learned why not: Tk's focus -force on such a window moves
    # Tk's own notion of focus and never the SERVER's, so every
    # keystroke went on landing in whatever held the real focus).
    # Managed, the box gets the focus through the front door and
    # hands it back through the refocus history. The WM tells it
    # apart BY CLASS — Tk9wmGadget, the host's gadget mark, the ask
    # the first wearer — and its own code rule undresses it and holds
    # it above the top client layer; no window type is claimed.
    toplevel .ask -class Tk9wmGadget -background [ui-color edge]
    wm title .ask $prompt
    wm withdraw .ask
    # dressed as the KEY ECHO, which is the modal box this desk
    # already speaks through — the amber ground, white ink, the edge
    # outline — with only the field keeping its editor dress; and
    # with room to breathe (the owner, 2026-08-05). A prompt longer
    # than a word or two goes ABOVE the field, so a long question and
    # a long answer each get the full width.
    frame .ask.b -background [ui-color modal]
    pack .ask.b -padx 1 -pady 1 -fill both -expand 1
    label .ask.b.p -text $prompt -font DeskFont -anchor w \
        -background [ui-color modal] -foreground white
    ui-field .ask.b.f
    set long [expr {[string length $prompt] > 20}]
    # the width the asker said: characters go to the field (its own
    # unit), a percent is of the workarea and lands on the whole BOX
    # below, the field stretching into it; unsaid, the layout's own
    # defaults
    if {[string is integer -strict $width]} {
        .ask.b.f.t configure -width $width
    } else {
        .ask.b.f.t configure -width [expr {$long ? 56 : 40}]
    }
    ui-field-set .ask.b.f $initial
    # the priming arrives SELECTED, whole (the owner, 2026-08-17):
    # the first letter typed replaces it, keeping it is Enter, and
    # editing it starts with a cursor key — the field convention
    # every rename box in the world has taught. An empty initial
    # selects nothing and none of this shows.
    ui-field-select-all .ask.b.f
    if {$long} {
        grid .ask.b.p -row 0 -column 0 -sticky w  -padx 12 -pady {10 4}
        grid .ask.b.f -row 1 -column 0 -sticky ew -padx 12 -pady {0 12}
        grid columnconfigure .ask.b 0 -weight 1
    } else {
        grid .ask.b.p -row 0 -column 0 -sticky w  -padx {12 6} -pady 12
        grid .ask.b.f -row 0 -column 1 -sticky ew -padx {0 12} -pady 12
        grid columnconfigure .ask.b 1 -weight 1
    }
    bind .ask.b.f.t <Return>   "ui-ask-commit [list $wmapp] $id; break"
    bind .ask.b.f.t <KP_Enter> "ui-ask-commit [list $wmapp] $id; break"
    bind .ask.b.f.t <Escape>   "ui-ask-cancel [list $wmapp] $id; break"
    update idletasks
    set W [winfo reqwidth .ask]
    set H [winfo reqheight .ask]
    lassign $anchor ha va
    lassign $warect wx wy ww wh
    if {[regexp {^([0-9]+)%$} $width -> pc]} {
        set W [expr {max($ww * $pc / 100, [winfo reqwidth .ask.b.p] + 40)}]
    }
    wm geometry .ask ${W}x${H}+[ui-place-axis $wx $ww $W $ha]+[ui-place-axis \
        $wy $wh $H $va]
    wm deiconify .ask
    # the X focus is the WM's business (it manages this window and
    # focuses a newcomer); Tk's own focus goes to the field so the
    # keys the server sends this client land in it
    focus .ask.b.f.t
}
# The answer goes over SYNCHRONOUSLY, before the box is destroyed:
# destroying first races the WM's focus bookkeeping — the box's
# unmanage moves the focus, the focus-left-the-ask rule would cancel
# the wait, and the answer would arrive to nobody. Synchronous is
# safe in THIS direction: the WM never waits on the host (its sends
# are -async), so the two cannot deadlock.
proc ui-ask-commit {wmapp id} {
    set text [ui-field-get .ask.b.f]
    catch {send -- $wmapp [list ask-answer $id $text]}
    catch {destroy .ask}
}
proc ui-ask-cancel {wmapp id} {
    catch {send -- $wmapp [list ask-cancel $id]}
    catch {destroy .ask}
}
proc ui-ask-drop {id} { catch {destroy .ask} }

# ---- WHAT IS BUILT ON FIRST USE, BUILT NOW (the owner's ask) ------
# Dialogs, menus and popups appear when somebody presses the key that
# needs them — which is also when a defect in their construction
# appears, and only if somebody presses it. The accelerator clash he
# found (two buttons promising Alt+C) was exactly that: sitting in a
# window nobody opens in the suite.
#
# So a builder can be registered here, and a run can ask for all of
# them at once: each is built, torn down, and anything that threw is
# named. The registration is what makes a lazily-built thing testable
# without a hand on the keyboard.
set ui_lazy {}
proc ui-lazy {name build {teardown {}}} {
    dict set ::ui_lazy $name [list $build $teardown]
}
proc ui-build-all {} {
    set bad {}
    dict for {name pair} $::ui_lazy {
        lassign $pair build teardown
        if {[catch {uplevel #0 $build} err]} {
            lappend bad [list $name $err]
        }
        catch {uplevel #0 $teardown}
    }
    return $bad
}
# ---- A TREE FROM NODES (config-tree, step 4) ----------------------
# The walk the configurator grew is not the configurator's: any applet
# rendering a tree wants the same thing — a list of records, each with
# its children, put under a parent by treesync, with a hook to
# remember what a row turned out to be. So it lives here, in the layer
# the next applet gets for free.
#
# It asks nothing of the desk: no wm-call, no registry, no theme. A
# node needs a `key` (unique among siblings — treesync's identity) and
# may carry `children`; everything else is the view's business.
#
#   view: make/update as treesync takes them, plus an optional
#         `register {item node}` called for every row in walk order.
proc ui-tree-render {T parent nodes view} {
    # the root item is 0 to treesync, and an empty string is not
    # something a tree can describe
    if {$parent eq ""} { set parent 0 }
    set rows [lmap n $nodes { list [dict get $n key] $n }]
    set m [treesync::sync $T $view $rows $parent]
    foreach n $nodes {
        set item [dict get $m [dict get $n key]]
        if {[dict exists $view register]} {
            uplevel #0 [list {*}[dict get $view register] $item $n]
        }
        if {[dict exists $n children]} {
            ui-tree-render $T $item [dict get $n children] $view
        }
    }
    return $m
}
# ---- EDITING A CELL OF THAT TREE (config-tree, step 4) -----------
# The field that opens ON a cell, over the value it is about. It was
# the configurator's, and it is the last thing in it that every
# tree-shaped applet wants — but moving it was never a matter of
# moving code: it held on to three things that belong to the APPLET,
# and the only way to let go of them is to NAME them.
#
#   ui-cell-edit T ITEM COLUMN ADDR OPTS
#
# ADDR is whatever the applet calls this cell. The library never looks
# inside it; it hands it back with every question. OPTS carries the
# three answers:
#
#   commit {ADDR VALUE} -> 1|0  put the value, and say whether it was
#                               taken. A refusal leaves the field open
#                               on the text that was refused — the
#                               fix is then a keystroke away.
#   refuse {SENTENCE}           where the library's own sentences go:
#                               a status line, a log. How loud a
#                               refusal is (a bell?) is the applet's
#                               too — this is its place to speak.
#   may-i {WHAT} -> 1|0         may this happen while the value is
#                               still half-typed — the scroll, the
#                               erase, the focus walking off? The
#                               policy is the applet's; the mechanics
#                               below are ours.
#
# The rest of OPTS is data, not policy: `value` (what the editor opens
# on, and what a bool or a choice currently holds), `kind` (which
# gesture this cell has: `bool` toggles, `choice ...` drops a menu,
# anything else is text), `pick` (the dialog behind the ▾, called with
# ADDR — the applet's, because a color chooser knows what a color is
# and this layer does not), `element` (the text element inside the
# column, so the letters land on the letters) and `how` (`primary`,
# the everyday gesture, which prefers the dialog where there is one;
# `text`, which always opens the field).
array set ui_cell {}
proc ui-cell-defaults {opts} {
    dict merge {how primary kind text value {} element {} pick {}
                commit {} refuse {} may-i {}} $opts
}
proc ui-cell-opts {T} {
    expr {[info exists ::ui_cell($T)] ? $::ui_cell($T) : {}}
}
proc ui-cell-cb {opts key} {
    expr {[dict exists $opts $key] ? [dict get $opts $key] : {}}
}
# ACTIVATION IS EDITING, and which editing is the kind's business:
# there is no text to type in a bool (it toggles) or in a simple
# oneOf (it drops its menu), and everything else opens the field —
# straight into the dialog when the everyday gesture asked and a
# dialog is what this cell has.
proc ui-cell-edit {T item column addr opts} {
    set o [ui-cell-defaults $opts]
    set kind [dict get $o kind]
    switch -- [lindex $kind 0] {
        bool {
            # two words, and the pair is the kind's own: a bare `bool`
            # means the on/off this desk spells its switches with,
            # `bool yes no` means somebody else's pair
            lassign [lrange $kind 1 end] yes no
            if {$yes eq ""} { set yes on ; set no off }
            set v [dict get $o value]
            ui-cell-commit $T $addr [expr {$v eq $yes ? $no : $yes}] $o
            return
        }
        choice {
            ui-cell-choice $T $item $column $addr [lrange $kind 1 end] $o
            return
        }
    }
    if {[dict get $o how] eq "primary" && [llength [dict get $o pick]]} {
        ui-cell-pick $T $addr $o
        return
    }
    # after the event sequence, so nothing steals the focus back from
    # the field the moment it claims it
    after idle [list ui-cell-open $T $item $column $addr $o]
}
# A CHOICE IS A MENU AT ITS CELL, not a cycle to click blind through
# (the owner: four panel sides by repeated presses is cruel). A menu
# holds the keyboard natively, and what the cell holds now is marked.
# A POPUP MENU IS BUILT FRESH AND DRESSED BY HAND. The rest of this
# bridge dresses its widgets explicitly from ui-color; menus leaned
# on the option database — and that database is a timeline, not a
# mirror: the ttk theme package files entries of its own beside ours,
# and after a live light↔dark flip a freshly built menu came up
# wearing the OLD theme (the owner, 2026-08-02). Explicit colors read
# the palette as it stands, every time the menu is built.
proc ui-menu {path} {
    catch {destroy $path}
    # -selectcolor is the radiobutton MARKER beside the entry that
    # holds now — left to the option database it kept the OLD theme's
    # ink after a live flip (a white dot on a light menu, the owner,
    # 2026-08-04), for exactly the timeline reason above. The marker
    # is ink: black on light, white on dark, by the same word.
    menu $path -tearoff 0 -font DeskFont \
        -background [ui-color bg] -foreground [ui-color fg] \
        -activebackground [ui-color select] \
        -activeforeground [ui-color selectfg] \
        -selectcolor [ui-color fg]
    return $path
}
proc ui-cell-choice {T item column addr vals opts} {
    ui-menu $T.pop
    set ::ui_cell_choice [dict get $opts value]
    foreach v $vals {
        $T.pop add radiobutton -label $v -variable ::ui_cell_choice -value $v \
            -command [list ui-cell-commit $T $addr $v $opts]
    }
    lassign [$T item bbox $item $column] x1 y1 x2 y2
    tk_popup $T.pop [expr {[winfo rootx $T] + $x1}] \
                    [expr {[winfo rooty $T] + $y2}]
}
# The overlay itself. Its Map claims the focus: visible MEANS focused.
# Return commits, Escape drops, losing the focus is a commit attempt,
# Tab is a commit of what was touched.
proc ui-cell-open {T item column addr opts} {
    ui-cell-close $T
    lassign [$T item bbox $item $column] x1 y1 x2 y2
    if {$x1 eq ""} return
    set o [ui-cell-defaults $opts]
    dict set o addr $addr
    set ::ui_cell($T) $o
    set val [dict get $o value]
    # A THREE-LINE SCRIPT WANTS THREE LINES. The field is a text, so
    # it can have them — and it has undo, which an entry never did
    # (the owner's preference, 2026-08-01).
    ui-field $T.edit -onleave [list ui-cell-leave $T]
    ui-field-set $T.edit $val
    # ...and the count is the FIELD's, the same one growing uses later:
    # two ways of counting the same lines is how they come to disagree
    set lines [ui-field-lines $T.edit]
    $T.edit.t configure -height [expr {max(1, min(6, $lines))}]
    ui-field-select-all $T.edit
    ui-field-scroll $T.edit [expr {$lines > 6}]
    # GRID, and the button gets a column of its own: PACKED, the
    # field (with -expand) claimed the whole cavity before the button
    # was packed at all — it existed, mapped 0, 1x1 in a corner,
    # which is why the owner could find no arrow anywhere (measured
    # on his live desk through the send door).
    if {[llength [dict get $o pick]]} {
        # the combobox-like way into the dialog: the button, or Down
        # from the keyboard — a gesture that costs nothing to guess
        ttk::button $T.edit.pick -text ▾ -takefocus 0 -width 2 \
            -command [list ui-cell-pick $T $addr $o]
        grid $T.edit.pick -row 0 -column 2 -sticky ns   ;# 1 is the scrollbar's
        # Down and F4 both — the gestures a combobox has taught every
        # pair of hands (the owner names F4 by its Windows habit;
        # Down is the X one)
        bind $T.edit.t <Down> [list ui-cell-pick $T $addr $o]
        bind $T.edit.t <F4>   [list ui-cell-pick $T $addr $o]
    }
    set h [expr {max($y2 - $y1, [winfo reqheight $T.edit.t] + 6)}]
    # PIXEL-PERFECT ON THE CELL'S OWN TEXT (the owner's taste, and the
    # right one: an editor that shifts the letters by two pixels reads
    # as a different thing appearing, not as the same value becoming
    # editable). The offset is MEASURED — where the cell's text
    # element starts, less the field's own inner padding — so it stays
    # true when a font or a row height changes. A caller that names no
    # element gets the cell's own corner, which is as true as the
    # tree let it be.
    set inner [ui-field-inset $T.edit]
    set etx "" ; set ety ""
    if {[dict get $o element] ne ""} {
        lassign [$T item bbox $item $column [dict get $o element]] \
            etx ety ex2 ey2
        # AN EMPTY ELEMENT HAS NO BOX, ONLY AN ANCHOR: treectrl
        # answers with a zero-size rectangle at the anchor point —
        # the vertical MIDDLE of the cell — and an overlay placed by
        # it hung pixels below its row on every empty cell's first
        # edit (the owner, 2026-08-02). The anchor's x is still where
        # the letters will start; its y is not a top and is replaced
        # by the cell's own.
        if {$etx ne "" && ($ex2 == $etx || $ey2 == $ety)} {
            set ety [expr {$y1 + [lindex $inner 1]}]
        }
    }
    if {$etx eq ""} { set etx $x1 ; set ety $y1 }
    # ...AND NO WIDER THAN WHAT IS ACTUALLY THERE TO SEE. The field is
    # placed inside the tree, so a cell reaching past the tree's right
    # edge gives it a width that is partly outside the window: the
    # text believes it has room it does not have, so it never scrolls,
    # and the end of a long line sits in the clipped part where no
    # amount of scrolling brings it back (the owner, 2026-08-02, on a
    # long line in a script). Clipped to the visible width, the text
    # scrolls after the cursor as it should.
    set px [expr {$etx - [lindex $inner 0]}]
    set room [expr {[winfo width $T] - $px - 2}]
    place $T.edit -x $px -y [expr {$ety - [lindex $inner 1]}] \
        -width [expr {max(60, min($x2 - $x1, $room))}] -height $h
    bind $T.edit.t <Map> {focus %W}
    # RETURN COMMITS, because a field in a tree is answering a
    # question and not writing a paragraph; a newline is Shift+Return,
    # which is the habit every such field has taught.
    bind $T.edit.t <Return>       "[list ui-cell-done $T commit]; break"
    bind $T.edit.t <Shift-Return> \
        "%W insert insert \\n; [list ui-cell-grow $T $y1 $y2]; break"
    # ...and anything else that changes how many lines there are —
    # a line deleted, a paste — moves the wall too
    bind $T.edit.t <KeyRelease> +[list ui-cell-grow $T $y1 $y2]
    bind $T.edit.t <Escape>       "[list ui-cell-done $T cancel]; break"
    bind $T.edit.t <FocusOut>     [list ui-cell-focusout $T]
    focus $T.edit.t
}
# A FIELD THAT GAINS A LINE GAINS THE ROOM FOR IT. Shift+Return put a
# real newline into a one-line field and left it one line tall, with
# the new line out of sight below the bottom edge (the owner,
# 2026-08-02). The height follows what is in there — up to the same
# six lines a field opens with at most — and the overlay is re-placed
# around it, never smaller than the cell it stands on. Past the six,
# the scrollbar takes over (ui-field-scroll).
proc ui-cell-grow {T y1 y2} {
    if {![winfo exists $T.edit.t]} return
    set lines [ui-field-lines $T.edit]
    ui-field-scroll $T.edit [expr {$lines > 6}]
    set want [expr {max(1, min(6, $lines))}]
    if {[$T.edit.t cget -height] == $want} return
    $T.edit.t configure -height $want
    update idletasks
    place configure $T.edit \
        -height [expr {max($y2 - $y1, [winfo reqheight $T.edit.t] + 6)}]
}
proc ui-cell-commit {T addr value opts} {
    set cmd [ui-cell-cb $opts commit]
    if {![llength $cmd]} { return 1 }
    return [uplevel #0 [list {*}$cmd $addr $value]]
}
# The dialog behind the ▾ is the APPLET's, and while it is up the
# field must not read its lost focus as an abandonment: the two are
# one gesture.
proc ui-cell-pick {T addr opts} {
    set ::ui_cell($T,picking) 1
    try {
        uplevel #0 [list {*}[ui-cell-cb $opts pick] $addr]
    } finally {
        set ::ui_cell($T,picking) 0
    }
}
# Answers whether the edit is now SETTLED — committed or dropped — so
# a caller that must not walk over a half-typed value (a Save) can
# tell. A refusal keeps the field standing on the offending text.
proc ui-cell-done {T how} {
    if {![winfo exists $T.edit]} { return 1 }
    set o [ui-cell-opts $T]
    set v [ui-field-get $T.edit]
    if {$how eq "commit"
            && ![ui-cell-commit $T [dict get $o addr] $v $o]} { return 0 }
    ui-cell-close $T
    focus $T                      ;# ...and the tree is where one lands
    return 1
}
# The field and what is known about it go together: $T.edit exists
# exactly while ::ui_cell($T) does, and every reader below leans on it.
proc ui-cell-close {T} {
    catch {bind $T.edit.t <FocusOut> {}}
    catch {destroy $T.edit}
    unset -nocomplain ::ui_cell($T)
}
# TAB COMMITS WHAT WAS TOUCHED (the owner, 2026-08-02): a value looked
# at and left alone is not an edit, and writing it back would make a
# customization out of a glance. Return still commits whatever is
# there — typing the same thing on purpose is a legitimate way to pin
# it, and that stays.
proc ui-cell-leave {T} {
    if {![winfo exists $T.edit]} { return 1 }
    if {![ui-field-dirty? $T.edit]} {
        ui-cell-close $T
        focus $T
        return 1
    }
    return [ui-cell-done $T commit]
}
# A CLICK ELSEWHERE asks the same question a scroll asks, and the
# guard answers it: nothing typed and the field goes quietly;
# something typed and it stays, with the focus coming back to it —
# losing work to a stray click is the one outcome nobody would have
# chosen.
proc ui-cell-focusout {T} {
    if {[info exists ::ui_cell($T,picking)] && $::ui_cell($T,picking)} return
    if {![winfo exists $T.edit]} return
    if {[ui-cell-guard $T focus]} return
    after idle [list catch [list focus $T.edit.t]]
}
# ---- what may happen while a value is half-typed ----
# ONE question decides it, and it is a mechanical one: has anything
# been TYPED? A field still holding what it was given is a glance, and
# a glance costs nothing to drop — it goes, and the gesture proceeds.
# A field with a change in it is WORK, and what may be done to work in
# progress is the applet's rule, not ours: may-i answers. A yes takes
# the field WITH it — an overlay left standing over a scrolling tree
# is nobody's answer — so a yes always means the way is clear.
#
# Asked BEFORE the view moves, so it hangs off the gestures rather
# than off -yscrollcommand, which only ever reports what has already
# happened.
proc ui-cell-guard {T what} {
    if {![winfo exists $T.edit]} { return 1 }
    if {[ui-field-dirty? $T.edit] && ![ui-cell-may-i $T $what]} {
        if {$what eq "focus"} {
            ui-cell-say $T "finish this value (Return) or drop it (Escape)"
        } else {
            ui-cell-say $T "finish this value (Return) or drop it (Escape)\
 — the tree holds still while one is half-typed"
        }
        return 0
    }
    ui-cell-close $T
    return 1
}
proc ui-cell-may-i {T what} {
    set cmd [ui-cell-cb [ui-cell-opts $T] may-i]
    # NO POLICY MEANS NO: a tree walking out from under a half-typed
    # value is the outcome to default AWAY from.
    if {![llength $cmd]} { return 0 }
    return [uplevel #0 [list {*}$cmd $what]]
}
proc ui-cell-say {T sentence} {
    set cmd [ui-cell-cb [ui-cell-opts $T] refuse]
    if {![llength $cmd]} { puts "UI: $sentence" ; return }
    uplevel #0 [list {*}$cmd $sentence]
}

package provide deskui 0.1
