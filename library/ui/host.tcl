# tk9wm-ui — the applet host: ONE process, one Tk, every applet a
# toplevel of its own. Run by the WM (see `applet` in policy/80-custom.tcl) with
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
#
# WHAT IS LEFT IN THIS FILE is the half that is tk9wm's own: the name
# it claims, the applet registry, the staleness check and the handover
# to a successor. The widgets and the style bridge went to the deskui
# package next door — a consumer that is not a window manager (tk9fm)
# requires that and none of this.
set ui_library [file dirname [file normalize [info script]]]
# We run as a SCRIPT, not out of a package, so the library the desk
# ships is put on the path by hand — right in a checkout, in an
# installed tree and in a whale's image alike, the same way main.tcl
# finds its own.
lappend auto_path [file dirname $ui_library]
package require deskui

set ui_wmapp [lindex $argv 0]
set ui_first [lrange $argv 1 end]
deskui-init $ui_wmapp    ;# the toolkit cannot guess the desk's name

wm withdraw .

# Claim the name; a LIVE host already holding it means we are the
# loser of a race — hand it the requests and leave.
if {[tk appname tk9wm-ui] ne "tk9wm-ui"} {
    foreach ui_a $ui_first {
        catch {send -- tk9wm-ui [list ui-open $ui_a]}
    }
    exit 0
}
chan configure stdout -buffering line


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
# ui-freshen-push in policy/80-custom.tcl); a current host shrugs it off, a
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
