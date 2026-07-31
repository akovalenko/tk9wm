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
}
proc ui-color {key} {
    expr {[dict exists $::ui_palette $key]
          ? [dict get $::ui_palette $key] : "#888888"}
}

proc ui-applet {name meta} { dict set ::ui_applets $name $meta }
set ui_applets {}
foreach f [lsort [glob -nocomplain [file join $ui_library applets *.tcl]]] {
    if {[catch {source $f} err]} {
        puts "UI: applet file [file tail $f] FAILED: $err"
    }
}

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
    if {[catch {[dict get $meta build] $top} err]} {
        puts "UI: applet $name build FAILED: $err"
        catch {destroy $top}
        return
    }
    puts "UI: applet $name up"
}

if {$ui_first ne ""} { after idle [list ui-open $ui_first] }
