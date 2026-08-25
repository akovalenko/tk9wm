# tk9wm — the assembly on top of the two layers: the customization
# layer (one Tcl config file, re-readable on a live desk) and the entry
# point that starts dispatching.
#
# Sourced THIRD, by pkgIndex.tcl, after substrate.tcl and the policy
# parts (library/policy/, numbered — the names carry the load order):
# the snapshot below has to happen with both layers in and before the
# config has said a word. Sourcing order matters for a plainer reason
# than it used to (the error handler no longer has to beat Tk to the
# display): the substrate takes the redirect and defines the transport
# the policy is written against, so it comes first — and it is what
# requires Tk. Nothing is dispatched until tk9wm-main.

# Where our own files live — the config fallback below reads
# default-config.tcl out of it. Taken from this script's own path, so
# it is right in a checkout, in an installed package directory and in a
# whale's image alike.
set ::tk9wm_library [file dirname [file normalize [info script]]]

# The defaults a reload puts back are taken FROM THE CODE, right here —
# after both layers are in and before the config has said a word. So
# they cannot drift from what the code actually does: nothing is
# written down twice (see policy/85-config.tcl, the config layer).
# The one setup step in this file, and it must not run twice: the
# snapshot is taken from the CODE's own values a moment before a config
# is first read, and a second one — taken on a live desk — would freeze
# the config's own values as the defaults it is reset to, which is a
# reload that can no longer undo anything.
# Unconditional: the snapshot is incremental (each missing entry taken
# when first seen), so a re-source fills in defaults for config_vars a
# newer library brought — without it, the first Reload after such a
# Reread died on the missing entry.
policy-snapshot-defaults

# The customization layer: ONE Tcl file, sourced after both layers are
# in and before the first window is managed — the user's
# ~/.config/tk9wm.tcl (XDG_CONFIG_HOME honored) when it exists, else
# the project's default-config.tcl. The project file is a commented
# example, deliberately NOT load-bearing: every default lives in code,
# so a two-line user config ("bold titles, that's all") starts from
# exactly the stock behavior — it overrides, it does not re-build. A
# broken config is logged and skipped: a WM that dies on a typo in its
# config locks the user out of the session that would let them fix it.
#
# Resolved AT EVERY LOAD, not once: a config written after the WM
# started should be found by the next reload, without a restart.
proc config-dir {} {
    expr {[info exists ::env(XDG_CONFIG_HOME)]
        && $::env(XDG_CONFIG_HOME) ne ""
        ? $::env(XDG_CONFIG_HOME) : [file join $::env(HOME) .config]}
}
proc config-path {} {
    set conf [file join [config-dir] tk9wm.tcl]
    if {![file exists $conf]} {
        # FIRST RUN MATERIALIZES THE SAMPLE (the owner, 2026-08-06).
        # The annotated default-config is every knob's documentation,
        # and read in place from the library it left the user nothing
        # to edit: the natural next move — open ~/.config/tk9wm.tcl
        # and uncomment something — found no file there. The copy
        # changes no behavior at all (the sample is all comment, a
        # deliberate no-op), it only puts the crib where the editing
        # will happen. A desk that cannot write there keeps the old
        # fallback and reads the library's copy in place.
        set sample [file join $::tk9wm_library default-config.tcl]
        if {[catch {
            file mkdir [config-dir]
            file copy $sample $conf
        }]} {
            return $sample
        }
        puts "WM: config: first run — $conf written from the sample"
    }
    return $conf
}
# The customization layer's file — MACHINE-OWNED: the configurator and
# the desk's own buttons (the welcome widget's "hide forever") write
# it whole; nobody edits it by hand. It loads AFTER the config, so a
# word said by click is the later word of the same user and wins —
# and the loader says out loud which config knobs it overrode, so the
# shadowing is lawful rather than mysterious (the owner's design,
# 2026-07-31).
proc custom-path {} {
    file join [config-dir] tk9wm.custom.tcl
}
proc load-config {} {
    set ::layer_knobs {}   ;# a fresh load cycle starts here
    set ::layer_where {}   ;# ...and so does what it knows about lines
    set conf [config-path]
    lassign [layer-source config $conf] code err info
    if {$code} {
        puts "WM: config $conf FAILED: $err — running on what it managed to set"
        layer-blame $conf $info
        return 0
    }
    puts "WM: config $conf"
    return 1
}
# The one sentence above names WHAT died; this is the WHERE — the
# error's own stack, which carries the failing statement and the
# file and line it sits on (the owner's ask, 2026-07-31: the
# sentence alone sent him hunting inside `action Claude` — the last
# casualty of the dead tail — when the corpse was a style two
# actions up, and only a line number says so). The stack is printed
# down to the LOADER'S OWN FRAME and no further: everything from
# `source $path` on is this file's plumbing, the same in every
# error, and noise under a blame that ends, as it should, on the
# config's own line.
proc layer-blame {path info} {
    set lines [split [string trimright $info] \n]
    set i [lsearch -exact [lmap l $lines {string trim $l}] "\"source $path\""]
    if {$i >= 2} { set lines [lrange $lines 0 [expr {$i - 2}]] }
    foreach line $lines { puts "WM:   $line" }
}
proc load-custom {} {
    set path [custom-path]
    if {![file exists $path]} { return 1 }
    lassign [layer-source custom $path] code err info
    if {$code} {
        puts "WM: custom $path FAILED: $err — running on what it managed to set"
        layer-blame $path $info
        return 0
    }
    puts "WM: custom $path"
    foreach key [layer-overlaps] {
        puts "WM: custom overrides the config: $key"
    }
    return 1
}

# Re-read the config in place: no restart, no clients disturbed. The
# contract is the owner's own — everything configurable goes back to
# the CODE's defaults (empty panel and all), and the config then draws
# on that clean floor, exactly as it does at startup. What makes it
# sound is that the config is declarative; the reset knows where every
# knob's state lives, and cannot know about a monkey-patched proc (see
# policy/85-config.tcl, the config layer).
#
# A broken config leaves the desk on defaults plus whatever it managed
# to set before it threw — the same rule as at startup, and the reason
# the reset happens FIRST: a config that fails must not be able to
# leave the previous one's settings half-standing.
#
# Reached by the TK9WM_RELOAD ClientMessage (tools/send-reload.tcl) and
# by the default chord Super+t w r.
proc reload-config {} {
    puts "WM: config reload requested"
    # Anybody parked on a popup is waiting for an answer about a desk
    # that is about to stop existing — the deed they asked about may not
    # survive the replay. Cancelled OUT LOUD, not dismissed: nobody
    # declined anything here, the ground moved.
    popup-yank "the config is being reloaded"
    ask-yank "the config is being reloaded"
    # One transition, not the flapping a rebuild makes on the way — see
    # workarea-held. The clients hear about the workarea once, when the
    # config has finished saying what it is — and the STRIPS rebuild
    # once too (panels-held): the standing panels ride the load as
    # they are, and the release builds them from the final word.
    workarea-held {
        panels-held {
            policy-reset
            load-config
            # the floor the layers below leave — the only moment the
            # state without the custom layer actually exists, and so
            # the only honest place to judge what that layer DOES
            # (custom-effect-judge, the pins audit)
            custom-floor-snapshot
            load-custom
            custom-homes
            custom-effect-judge
            tray-argb-default
            policy-apply
        }
        # The chrome transition the titles settler deferred under the
        # hold (a reload that moved set-title-air or set-border): the
        # strips have rebuilt, the frames wear their new lengths, and
        # the hold has not released yet — so the reflow the release
        # runs judges every window from edges this has already
        # re-glued. See rechrome-settle for why the order carries the
        # whole design.
        rechrome-settle
    }
}

# Reload is the config; this is the CODE. All THREE files sourced again
# on the running desk, which redefines every proc and leaves the desk
# itself alone (see the head of substrate.tcl for the kinds of
# statement that makes possible, and for the honest edge of it).
#
# This file is in the list, and learning that it had to be cost a
# measurement: a fix to reload-config — which lives HERE — was
# re-sourced onto the owner's live desk and changed nothing, because
# only the two layers were being re-read (2026-07-30). A `Reread` that
# quietly skips a third of the code is worse than none.
#
# It exists as a command rather than as a line in everyone's config
# because the two things that are easy to get wrong belong in one
# place: the ORDER (the substrate first — the policy calls into it at
# load, not only at run time; this file last, since it calls into
# both) and the CATCH (a typo halfway through would otherwise take the
# desk down with it, and a desk that dies of a typo is no use for the
# loop this is for).
#
# A half-sourced file leaves a half-defined layer, and this cannot
# undo that. It says so out loud and leaves the desk running, which is
# the difference between an error one fixes and an error one reboots.
# Every file of the library, in load order — pkgIndex.tcl builds the
# same list the same way, and the order is explained there.
proc library-files {} {
    set l {}
    foreach f {fut.tcl elisp.tcl treesync.tcl substrate.tcl} {
        lappend l [file join $::tk9wm_library $f]
    }
    foreach p [lsort [glob -nocomplain [file join $::tk9wm_library policy *.tcl]]] {
        lappend l $p
    }
    lappend l [file join $::tk9wm_library widget.tcl]
    foreach w [lsort [glob -nocomplain [file join $::tk9wm_library widgets *.tcl]]] {
        lappend l $w
    }
    lappend l [file join $::tk9wm_library main.tcl]
    return $l
}
proc reread-layers {} {
    puts "WM: re-sourcing the library"
    foreach path [library-files] {
        set f [file tail $path]
        if {[catch {uplevel #0 [list source $path]} err opts]} {
            puts "WM: re-source $f FAILED: $err"
            layer-blame $path [dict get $opts -errorinfo]
            puts "WM: the desk is running on a HALF-LOADED layer — fix and re-source again"
            return 0
        }
    }
    puts "WM: re-sourced (procs replaced; state, grabs and clients untouched)"
    # The honest edge of "state untouched": state written by OLDER
    # procs may predate a shape the new ones insist on. The one such
    # split so far: a maximized mark written before the mark went
    # per-axis is a whole one (::maxsaved with no ::maxaxes) — say the
    # axes for it, or the first resize after this Reread throws.
    foreach w [array names ::maxsaved] {
        if {![info exists ::maxaxes($w)]} { set ::maxaxes($w) {h v} }
    }
    # ...and the resident ui host gets a nudge: the edit that asked
    # for this Reread may have moved the ui code too, and an OPEN
    # applet never passes the ui-open stale check. A current host
    # shrugs it off (ui-freshen in the host).
    ui-freshen-push
    return 1
}

# Read the config, arm the dispatcher, and run. Everything above is
# definition only, so `package require tk9wm` leaves a loaded but idle
# WM — this is the call that starts managing the desk, and it does not
# return.
#
# Demo mode (argument "demo"): the timed self-test tests/run-demo.sh
# drives. Without it the WM runs indefinitely — the live/Xephyr mode.
proc tk9wm-main {args} {
    # -replace was read (and acted on) by the substrate when the package
    # was required — the desk is taken before anything here runs. Drop
    # it so it cannot be mistaken for a mode below.
    set args [lsearch -all -inline -not -exact $args -replace]
    # Held for the same reason a reload is (see workarea-held): a config
    # line that touches live frames rebuilds the panels before the rest
    # of the file has declared its buttons, so the workarea moves twice
    # on the way up. Nothing is managed yet, so nothing is hurt — but
    # one publication is the truth and two are noise, and the startup
    # log is where one looks to learn what the shape of a load is.
    # every verb puts its guard on before a layer is read: a word that
    # throws is recorded and the file goes on (config-instrument)
    puts "WM: config vocabulary: [config-instrument-vocabulary] words guarded"
    # ...and the wishes those words write: declared against restored,
    # said once and out loud (see knob-var-audit).
    knob-var-audit
    # ...and the loader directive itself: a bad include must cost its
    # own line, not the rest of the file (the badword lesson)
    config-instrument custom-include
    workarea-held { panels-held {
        load-config
        custom-floor-snapshot        ;# see reload-config: the pins audit
        load-custom
        custom-homes
        custom-effect-judge
        tray-argb-default
        welcome-inject
    } }
    substrate-start
    # the resident ui host SURVIVED any restart on purpose — and the
    # restart may have brought new code under it (the dev loop pulls
    # a commit and restarts the desk). Same nudge as a Reread's; on a
    # cold start there is nobody to nudge and the push says nothing.
    after idle ui-freshen-push

    if {[lindex $args 0] eq "demo"} {
        # exercise the close path on whatever has focus (client B by then)
        after 5800 {
            if {$::focused != 0} {
                puts "WM: demo: pressing close on focused 0x[format %x $::focused]"
                close-client $::focused
            }
        }
        # survival demo: provoke a BadWindow on purpose; without the error
        # handler Xlib's default would have exited the whole process here
        after 6000 {
            puts "WM: injecting BadWindow on purpose (mapping a bogus id)"
            x-map 0x666666
            x-sync 0
        }
        after 12000 {xerror-flush; puts "WM: bye"; exit 0}
    }
    vwait ::forever
}
