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

# The customization layer: ONE Tcl file, sourced after both layers are
# in and before the first window is managed — the user's
# ~/.config/tk9wm.tcl (XDG_CONFIG_HOME honored) when it exists, else
# the project's default-config.tcl. The project file is a commented
# example, deliberately NOT load-bearing: every default lives in code,
# so a two-line user config ("bold titles, that's all") starts from
# exactly the stock behavior — it overrides, it does not re-build. A
# broken config is logged and skipped: a WM that dies on a typo in its
# config locks the user out of the session that would let them fix it.
set xdg [expr {[info exists env(XDG_CONFIG_HOME)] && $env(XDG_CONFIG_HOME) ne ""
    ? $env(XDG_CONFIG_HOME) : [file join $env(HOME) .config]}]
set conf [file join $xdg tk9wm.tcl]
if {![file exists $conf]} { set conf [file join $here default-config.tcl] }
if {[catch {source $conf} err]} {
    puts "WM: config $conf FAILED: $err — running on defaults"
} else {
    puts "WM: config $conf"
}

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
