# tk9wm-ui — the applet host: ONE process, one Tk, every applet a
# toplevel of its own. Run by the WM (see `applet` in policy.tcl) with
#
#     <interpreter> host.tcl WMAPP ?APPLET?
#
# where the interpreter is what reexec-head knows the desk runs on —
# the self-exec machinery's answer, reused: whatever whale carries the
# WM certainly carries the ui.
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

lassign $argv ui_wmapp ui_first
set ui_library [file dirname [file normalize [info script]]]

# Claim the name; a LIVE host already holding it means we are the
# loser of a race — hand it the request and leave.
if {[tk appname tk9wm-ui] ne "tk9wm-ui"} {
    if {$ui_first ne ""} {
        catch {send -- tk9wm-ui [list ui-open $ui_first]}
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
    bind [winfo toplevel $btn] <Alt-Key-$ch> [list $btn invoke]
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

if {$ui_first ne ""} { after idle [list ui-open $ui_first] }
