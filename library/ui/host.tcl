# tk9wm-ui — the applet host: ONE process, one Tk, every applet a
# toplevel of its own. Run by the WM (see `applet` in policy.tcl) with
#
#     <interpreter> host.tcl WMAPP ?APPLET ...?
#
# where the interpreter is what reexec-head knows the desk runs on —
# the self-exec machinery's answer, reused: whatever whale carries the
# WM certainly carries the ui. The WM asks for one applet; several
# arrive when a stale predecessor hands over everything it had open
# (see ui-freshen below).
#
# THE HOST IS A DISPOSABLE RESIDENT. Disposable: nothing durable lives
# here — applet state of consequence belongs to the WM and the custom
# file, and a host that dies is respawned by the next `applet` press.
# Resident: it deliberately SURVIVES a WM restart (execv keeps
# children; our X connection is our own), so an open applet rides
# across the dev loop's restarts — and it stays correct doing so,
# because applets render what the LIVE WM answers over the send door
# (knob-table and kin), not what was true when the host started.
#
# An applet is a proc building into a GIVEN toplevel — never `.` (the
# host owns `.`, withdrawn). Its window is named for the match:
# toplevel .tk9wm-NAME wears WM_CLASS {tk9wm-NAME Tk9wmUi}, which is
# what makes `applet NAME` idempotent on the WM side and the window
# manageable by any panel button.
package require Tk
package require treectrl   ;# the desk's own widget of choice, and the
                            # configurator's tree; whale carries it
wm withdraw .

set ui_wmapp [lindex $argv 0]
set ui_first [lrange $argv 1 end]
set ui_library [file dirname [file normalize [info script]]]
# treesync lives one storey up, beside fut.tcl: the host loads no
# tk9wm package, so the shared engine is sourced straight out of the
# library both worlds read — the configurator reconciles its tree
# through the same treesync the WM's strip does.
source [file join [file dirname $ui_library] treesync.tcl]

# Claim the name; a LIVE host already holding it means we are the
# loser of a race — hand it the requests and leave.
if {[tk appname tk9wm-ui] ne "tk9wm-ui"} {
    foreach ui_a $ui_first {
        catch {send -- tk9wm-ui [list ui-open $ui_a]}
    }
    exit 0
}
chan configure stdout -buffering line

# The transport, host side: eval in the WM, get the answer. The WM's
# send name rode in on argv — the WM knows what it is called, the
# host should not guess.
#
# ...AND WITH NO DESK BEHIND IT (config-tree, step 4: an applet has to
# work standalone as well as wired to a WM — the requirement on
# anything that leaves for a library). Started with `-` for the WM's
# name, the host answers the calls it can answer by itself and refuses
# the rest OUT LOUD: an applet that needs the desk says so in a
# sentence instead of hanging on a send to nobody.
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
    set st $::ui_palette
    foreach {opt key} {
        background bg foreground fg activeBackground select
        selectBackground select highlightBackground bg
        troughColor trough insertBackground fg
    } {
        option add *$opt [dict get $st $key] widgetDefault
    }
    option add *font DeskFont widgetDefault
    option add *Entry.background [dict get $st field] widgetDefault
    option add *Text.background [dict get $st field] widgetDefault
    option add *Listbox.background [dict get $st field] widgetDefault
    ui-style-announce
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
# this bridge has, and no applet is obliged to be restyleable.
proc ui-style-announce {} {
    foreach name [dict keys $::ui_applets] {
        set top .tk9wm-$name
        if {![winfo exists $top]} continue
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
    ttk::frame $path -style UiRing.TFrame -borderwidth 2 -relief solid {*}$args
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

# ---- A PICKER: choose one, name one (config-tree, step 4) --------
# Pick from a list, type a name, commit — the shape every «make a new
# one» dialog in this desk has. It was the configurator's; nothing
# about it ever was, so it lives here with the rest of the layer the
# next applet gets for free.
proc ui-pick-dialog {w parent wtitle title choices entrylabel commit} {
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
    listbox $w.list -font DeskFont -height [expr {max(3, min(10,
        [llength $choices]))}] -exportselection 0 \
        -background [ui-color field] -foreground [ui-color fg] \
        -selectbackground [ui-color select]
    ui-focusable $w.list
    foreach c $choices { $w.list insert end $c }
    label $w.el -takefocus 0 -anchor w -text $entrylabel
    entry $w.e -font DeskFont -background [ui-color field] \
        -foreground [ui-color fg] -insertbackground [ui-color fg]
    ui-focusable $w.e
    frame $w.b -takefocus 0
    ttk::button $w.b.ok -text OK -underline 0 \
        -command [list ui-pick-commit $w $commit]
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
    bind $w.list <Double-ButtonPress-1> [list ui-pick-commit $w $commit]
    bind $w.list <Return> [list ui-pick-commit $w $commit]
    bind $w.e <Return> [list ui-pick-commit $w $commit]
    focus [expr {[llength $choices] ? "$w.list" : "$w.e"}]
}
proc ui-pick-commit {w commit} {
    set choice ""
    if {[llength [$w.list curselection]]} {
        set choice [$w.list get [lindex [$w.list curselection] 0]]
    }
    set typed [string trim [$w.e get]]
    destroy $w
    # BOTH answers go to whoever asked — which of them wins is the
    # caller's question, and a dialog that decided it for them would
    # be carrying one applet's habits into the library.
    {*}$commit $choice $typed
}
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
proc ui-cell-choice {T item column addr vals opts} {
    catch {destroy $T.pop}
    menu $T.pop -tearoff 0 -font DeskFont
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
    set lines [llength [split $val \n]]
    ui-field $T.edit -height [expr {max(1, min(6, $lines))}] \
        -onleave [list ui-cell-leave $T]
    ui-field-set $T.edit $val
    ui-field-select-all $T.edit
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
        grid $T.edit.pick -row 0 -column 1 -sticky ns
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
        lassign [$T item bbox $item $column [dict get $o element]] etx ety
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
# around it, never smaller than the cell it stands on.
proc ui-cell-grow {T y1 y2} {
    if {![winfo exists $T.edit.t]} return
    set want [expr {max(1, min(6, [llength [split [ui-field-get $T.edit] \n]]))}]
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

# ---- THE DESK SAYS WHEN A LAYER MOVED UNDER US --------------------
# An applet renders what the live desk answers, which is right until
# the desk changes something WITHOUT being asked by this window: the
# welcome mat retiring itself writes `set-welcome off` into the custom
# layer, and an open configurator went on showing `on` (the owner,
# 2026-08-02). The writer is shared already — there is one custom-write
# and both sides call it — so what was missing was only the word that
# it happened.
#
# An applet that cares declares `changed CMD` in its meta and is
# called with the layer and the key. A withdrawn one is skipped: it
# will be built or re-read when it comes back.
proc ui-layer-changed {layer key {by desk}} {
    dict for {name meta} $::ui_applets {
        if {![dict exists $meta changed]} continue
        set top .tk9wm-$name
        if {![winfo exists $top] || [wm state $top] eq "withdrawn"} continue
        if {[catch {uplevel #0 [list {*}[dict get $meta changed] $layer $key $by]} err]} {
            puts "UI: applet $name: told of $layer $key and threw: $err"
        }
    }
}
proc ui-applet {name meta} { dict set ::ui_applets $name $meta }
set ui_applets {}
# The applet files, and WHEN they are read again: normally never — a
# reopen must not pay for a re-source — but a Reread on the WM bumps
# ui_generation (it rides in on ui-style), and the mismatch here is
# the dev loop's "close and reopen picks up the new code".
set ui_loaded_gen ""
proc ui-load-applets {} {
    foreach f [lsort [glob -nocomplain \
            [file join $::ui_library applets *.tcl]]] {
        # at the GLOBAL level: an applet file's top-level `set`s are
        # its state variables, and a plain source inside this proc
        # made them locals that died with the call (measured: the
        # first build crashed on a variable the file had just set)
        if {[catch {uplevel #0 [list source $f]} err]} {
            puts "UI: applet file [file tail $f] FAILED: $err"
        }
    }
    set ::ui_loaded_gen [expr {[dict exists $::ui_palette generation]
                               ? [dict get $::ui_palette generation] : ""}]
}
# Is this host's CODE — its own included — still the code on disk?
# The generation is an mtime fingerprint of library/ui, riding in on
# ui-style. A stale host answers so and LEAVES; the WM respawns a
# fresh one and retries. The reply must go out before the death — a
# send whose target dies mid-conversation never returns (the
# restart-wm lesson).
proc ui-stale? {} {
    expr {[dict exists $::ui_palette generation]
          && [dict get $::ui_palette generation] ne $::ui_loaded_gen}
}
ui-style-sync    ;# know the generation before the first load...
ui-load-applets  ;# ...so an unchanged desk never re-sources on open

# ui-open NAME — the send-facing verb: build the applet's toplevel,
# or show the one it already has. The WM prefers finding the WINDOW
# itself (its own idempotent match) and calls here only when no
# window lives.
proc ui-open {name} {
    if {![dict exists $::ui_applets $name]} {
        puts "UI: no applet named $name ([dict keys $::ui_applets])"
        return
    }
    ui-style-sync
    if {[ui-stale?]} {
        # Take the well-known name off FIRST, then ask the WM for a
        # successor: by the time it looks, the registry no longer
        # offers this host and the request lands on a spawn. Nobody
        # waits for anybody — the WM's call was async, and this one is
        # too.
        puts "UI: stale — the ui files changed; leaving for a fresh host"
        catch {tk appname tk9wm-ui-retired}
        catch {send -async -- $::ui_wmapp [list applet $name]}
        after idle exit
        return stale
    }
    set top .tk9wm-$name
    if {[winfo exists $top]} {
        wm deiconify $top
        raise $top
        return
    }
    set meta [dict get $::ui_applets $name]
    toplevel $top -class Tk9wmUi
    # BUILT OUT OF SIGHT. A toplevel is on the screen from the moment
    # it exists, so an applet that measures and sizes itself while
    # building does all of that in public: the configurator showed a
    # starting size, then jumped to its real one (the owner,
    # 2026-08-02). Withdrawn, it builds, fills and fits with nobody
    # watching, and the first thing seen is the finished window.
    wm withdraw $top
    wm title $top [expr {[dict exists $meta title]
                         ? [dict get $meta title] : "tk9wm: $name"}]
    # CLOSING WITHDRAWS, it does not destroy: an applet holds no
    # durable state, but rebuilding one costs a visible pause, and
    # the second open should be instant (the owner's rule for
    # applets in general — anything else needs a reason). The window
    # comes back with everything it had; ui-open re-syncs the style
    # around it.
    wm protocol $top WM_DELETE_WINDOW [list wm withdraw $top]
    if {[catch {[dict get $meta build] $top} err]} {
        puts "UI: applet $name build FAILED: $err"
        catch {destroy $top}
        return
    }
    update idletasks     ;# let the build's own sizing settle first...
    wm deiconify $top    ;# ...and only then is there anything to see
    puts "UI: applet $name up"
}

# ui-freshen — the PUSH half of the stale check. The pull half
# (ui-open) can only help the NEXT open: an applet already on the
# screen rides a Reread or a WM restart with the code it was born
# with, against a desk whose dictionary may have moved — the owner's
# Alt-Up case (2026-07-31), cured that day by destroying the window
# by hand. So the desk nudges the resident host to LOOK (see
# ui-freshen-push in policy.tcl); a current host shrugs it off, a
# stale one restarts itself: it retires the name, execs a successor
# carrying every applet that stands open (they ride argv into
# ui-open, and the claim is clean because the name is already free),
# and leaves — its windows die with it and come back fresh. The
# blink of the reopening windows is the accepted price (the owner's
# go, 2026-07-31). A closed (withdrawn) applet is NOT handed over:
# closed means closed, and the next open builds it anew anyway.
proc ui-freshen {} {
    # the guard against a nudge arriving inside a nudge: the wm-calls
    # below spin the event loop, and one successor is enough
    if {[info exists ::ui_leaving]} return
    ui-style-sync
    if {![ui-stale?] || [info exists ::ui_leaving]} return
    set ::ui_leaving 1
    set open {}
    foreach w [winfo children .] {
        if {[string match .tk9wm-* $w] && [wm state $w] ne "withdrawn"} {
            lappend open [string range $w 7 end]
        }
    }
    puts "UI: stale after the desk's nudge — a successor takes over ($open)"
    catch {tk appname tk9wm-ui-retired}
    if {[catch {
        set head [wm-call ui-exec-head]
        if {![llength $head]} { error "this image gave no ui-exec head" }
        exec {*}$head [file join $::ui_library host.tcl] \
            $::ui_wmapp {*}$open &
    } err]} {
        # no successor is still a working desk: the next applet press
        # spawns a fresh host — only the standing windows are lost
        puts "UI: could not exec a successor ($err) — just leaving"
    }
    # the reply must go out before the death (the restart-wm lesson)
    after idle exit
}

foreach ui_a $ui_first { after idle [list ui-open $ui_a] }
