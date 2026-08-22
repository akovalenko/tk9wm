# tk9wm on a whale — the wrapper that KNOWS (the kit wrapper's rule:
# an entry point that can say how to become us again must not leave
# reexec-head guessing). One file, two seats:
#
#   //zipfs:/app/apps/tk9wm.tcl   the BATTERY stub, `whale -app tk9wm`
#                                 (put there by the whalebuild recipe's
#                                 `app` field; a full //zipfs: path on
#                                 the command line lands here too)
#   //zipfs:/app/main.tcl         the DEDICATED whale, `build -app` /
#                                 `-forge pack` with this file as the
#                                 app dir's main.tcl
#
# The seat decides what execv needs. A dedicated whale re-runs its
# baked main.tcl off the bare executable — name nothing. A battery
# whale re-run bare is a tclsh: the guess in reexec-head reads a zipfs
# argv0 as "the executable alone re-runs it" and is WRONG exactly
# here, which is why this wrapper exists — the flag route back to this
# stub has to be said. The app name is read off this file's own name
# in the registry, so a renamed registry entry keeps working.
set exe [info nameofexecutable]
if {[info script] eq "//zipfs:/app/main.tcl"} {
    set ::tk9wm_reexec [list $exe]
    set ::tk9wm_uiexec [list $exe -ui-host]
} else {
    set app [file rootname [file tail [info script]]]
    set ::tk9wm_reexec [list $exe -app $app]
    set ::tk9wm_uiexec [list $exe -app $app -ui-host]
}

# THE WRAPPER IS THE HOST'S INTERPRETER TOO (-ui-host SCRIPT ARG...).
# The applet host is a separate process, and a whale is not
# wish-shaped: Tcl_Main exits when a script ends, so host.tcl handed
# to the bare interpreter would die before its first applet — the
# vwait must come from a wrapper (the kit's -ui-host pattern, same
# reasoning verbatim). The host script's path leads through the
# IMAGE, which the child whale mounts at the same //zipfs:/app by
# itself — nothing to arrange.
if {[lindex $argv 0] eq "-ui-host"} {
    set argv [lassign [lrange $argv 1 end] tk9wm_uiscript]
    set argc [llength $argv]
    source $tk9wm_uiscript
    vwait ::forever
}

# The desk's name on the send registry is the wrapper's to claim (the
# kit's rule): left to the boot script's accidents this desk would
# introduce itself as «tk9wm.tcl» or «main.tcl», which nobody would
# think to call. Tk is compiled in but lazy — the require is what
# brings it up.
package require Tk
tk appname tk9wm
package require tk9wm
tk9wm-main {*}$argv
