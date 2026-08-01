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
proc wm-call {script} { send -- $::ui_wmapp $script }

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
    set ::ui_palette $st
    foreach {name key} {DeskFont deskfont TitleFont titlefont} {
        if {[lsearch -exact [font names] $name] < 0} { font create $name }
        font configure $name {*}[dict get $st $key]
    }
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
        bg     TFrame  -background
        fg     TLabel  -foreground
        field  TEntry  -fieldbackground
        select TEntry  -selectbackground
        trough TScrollbar -troughcolor
    } {
        if {![catch {ttk::style lookup $style $opt} v] && $v ne ""} {
            dict set ::ui_palette $key $v
        }
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
}
proc ui-color {key} {
    expr {[dict exists $::ui_palette $key]
          ? [dict get $::ui_palette $key] : "#888888"}
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
proc ui-field {path args} {
    set o [dict merge {-height 1 -font DeskFont} $args]
    ui-ring-box $path
    text $path.t -height [dict get $o -height] -width 1 -wrap none \
        -font [dict get $o -font] -undo 1 -borderwidth 0 \
        -highlightthickness 0 -padx 3 -pady 1 \
        -background [ui-color field] -foreground [ui-color fg] \
        -insertbackground [ui-color fg]
    grid $path.t -row 0 -column 0 -sticky nsew
    grid rowconfigure $path 0 -weight 1
    grid columnconfigure $path 0 -weight 1
    return $path
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
