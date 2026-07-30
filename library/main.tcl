# tk9wm — the assembly on top of the two layers: the customization
# layer (one Tcl config file, re-readable on a live desk) and the entry
# point that starts dispatching.
#
# Sourced THIRD, by pkgIndex.tcl, after substrate.tcl and policy.tcl:
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
# written down twice (see policy.tcl, the config layer).
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
proc config-path {} {
    set xdg [expr {[info exists ::env(XDG_CONFIG_HOME)]
        && $::env(XDG_CONFIG_HOME) ne ""
        ? $::env(XDG_CONFIG_HOME) : [file join $::env(HOME) .config]}]
    set conf [file join $xdg tk9wm.tcl]
    if {![file exists $conf]} {
        set conf [file join $::tk9wm_library default-config.tcl]
    }
    return $conf
}
proc load-config {} {
    set conf [config-path]
    if {[catch {uplevel #0 [list source $conf]} err]} {
        puts "WM: config $conf FAILED: $err — running on what it managed to set"
        return 0
    }
    puts "WM: config $conf"
    return 1
}

# Re-read the config in place: no restart, no clients disturbed. The
# contract is the owner's own — everything configurable goes back to
# the CODE's defaults (empty panel and all), and the config then draws
# on that clean floor, exactly as it does at startup. What makes it
# sound is that the config is declarative; the reset knows where every
# knob's state lives, and cannot know about a monkey-patched proc (see
# policy.tcl, the config layer).
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
    policy-reset
    load-config
    policy-apply
}

# Reload is the config; this is the CODE. Both layers sourced again on
# the running desk, which redefines every proc and leaves the desk
# itself alone (see the head of substrate.tcl for the three kinds of
# statement that makes possible, and for the honest edge of it).
#
# It exists as a command rather than as a line in everyone's config
# because the two things that are easy to get wrong belong in one
# place: the ORDER (the substrate first — the policy calls into it at
# load, not only at run time) and the CATCH (a typo halfway through
# would otherwise take the desk down with it, and a desk that dies of
# a typo is no use for the loop this is for).
#
# A half-sourced file leaves a half-defined layer, and this cannot
# undo that. It says so out loud and leaves the desk running, which is
# the difference between an error one fixes and an error one reboots.
proc reread-layers {} {
    puts "WM: re-sourcing both layers"
    foreach f {substrate.tcl policy.tcl} {
        set path [file join $::tk9wm_library $f]
        if {[catch {uplevel #0 [list source $path]} err]} {
            puts "WM: re-source $f FAILED: $err"
            puts "WM: the desk is running on a HALF-LOADED layer — fix and re-source again"
            return 0
        }
    }
    puts "WM: re-sourced (procs replaced; state, grabs and clients untouched)"
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
    load-config
    substrate-start

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
