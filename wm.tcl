# tk9wm — thin assembly of the two layers:
#
#  substrate.tcl — the mechanism a WM cannot exist without: the tkwmx
#    shim on TK'S OWN connection (redirect, X error sink, events
#    dispatched by Tk itself), reparent / save-set surgery, adoption,
#    focus core with PointerRoot repair, close machinery, synthetic
#    ConfigureNotify, EWMH minimum. Drives policy-*.
#  policy.tcl — our local decisions: Tk-widget decorations (titlebar/✕/
#    slot), cascade placement, title drag, click-to-focus. Implements the
#    policy-* hooks (contract — substrate.tcl header; discussion — the
#    idea file, step 9).
#
# Sourcing order still matters, though for a plainer reason than it used
# to (the error handler no longer has to beat Tk to the display): the
# substrate takes the redirect and defines the transport the policy is
# written against, so it comes first — and it is what requires Tk.
# Nothing is dispatched until substrate-start below; events that arrive
# while the policy is loading wait in a queue.

set here [file dirname [file normalize [info script]]]
source [file join $here substrate.tcl]
source [file join $here policy.tcl]

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
    if {![file exists $conf]} { set conf [file join $::here default-config.tcl] }
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
# Reached by the TK9WM_RELOAD ClientMessage (send-reload.tcl) and by
# the default chord Super+t w r.
proc reload-config {} {
    puts "WM: config reload requested"
    policy-reset
    load-config
    policy-apply
}

load-config
substrate-start

# Demo mode (argv "demo"): timed self-test used by run-demo.sh. Without it
# the WM runs indefinitely — that is the live/Xephyr mode.
if {[lindex $argv 0] eq "demo"} {
    # exercise the close path on whatever has focus (client B by then)
    after 5800 {
        if {$focused != 0} {
            puts "WM: demo: pressing close on focused 0x[format %x $focused]"
            close-client $focused
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
