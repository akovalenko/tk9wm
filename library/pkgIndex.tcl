# The window manager as a Tcl package. Requiring it LOADS a working WM
# into the interpreter — substrate.tcl requires Tk, loads the tkwmx
# shim, installs the X error sink and takes SubstructureRedirect on the
# root window, so the require fails (loudly, and correctly) if another
# window manager already owns the display. What it does NOT do is start
# dispatching: that is tk9wm-main, so a caller gets a chance to poke at
# the loaded WM first.
#
# Sourced at global level, which is what `package ifneeded` scripts get
# — and what these two layers need: their procs and state are global by
# design (the user's config file calls set-* knobs at global level), so
# an ::apply wrapper would quietly make every `set` at their top level
# a local variable.
set _tk9wm_load [list source -encoding utf-8 [file join $dir substrate.tcl]]
foreach _f {policy.tcl main.tcl} {
    append _tk9wm_load \n \
	[list source -encoding utf-8 [file join $dir $_f]]
}
append _tk9wm_load \n [list package provide tk9wm 0.1]
package ifneeded tk9wm 0.1 $_tk9wm_load
unset _tk9wm_load _f
