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
# The order is the dependency order and it is not alphabetical: the
# substrate first (the policy calls into it AT LOAD), then the policy,
# then the widget frame, then each widget — a widget declares fonts and
# a type, both of which the frame and the policy must already offer —
# and main.tcl last, since it calls into all of them. reread-layers
# walks the same order for the same reason.
set _tk9wm_load [list source -encoding utf-8 [file join $dir fut.tcl]]
append _tk9wm_load \n \
    [list source -encoding utf-8 [file join $dir elisp.tcl]]
append _tk9wm_load \n \
    [list source -encoding utf-8 [file join $dir treesync.tcl]]
append _tk9wm_load \n \
    [list source -encoding utf-8 [file join $dir substrate.tcl]]
set _tk9wm_files [list policy.tcl widget.tcl]
foreach _w [lsort [glob -nocomplain -tails -directory [file join $dir widgets] *.tcl]] {
    lappend _tk9wm_files [file join widgets $_w]
}
lappend _tk9wm_files main.tcl
foreach _f $_tk9wm_files {
    append _tk9wm_load \n \
	[list source -encoding utf-8 [file join $dir $_f]]
}
append _tk9wm_load \n [list package provide tk9wm 0.1]
package ifneeded tk9wm 0.1 $_tk9wm_load
unset _tk9wm_load _f _tk9wm_files
catch {unset _w}

# tcllib's json rides THIS index rather than its own: the package
# unknown handler reads an auto_path directory's children for
# pkgIndex.tcl files and no deeper, and json/ sits a level below
# wherever this library lands — checkout, installed tree and kit
# alike. Vendored unmodified from tcllib 2.0 (see json/README.md);
# pure Tcl, with json.tcl quietly picking up the tcllibc accelerator
# when the interpreter carries one (a whale does).
package ifneeded json 1.3.6 \
    [list source -encoding utf-8 [file join $dir json json.tcl]]
