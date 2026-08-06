# library/json — tcllib's json, vendored

`json.tcl` and `json_tcl.tcl` are byte-identical copies from tcllib
release 2.0 (`modules/json/`, package `json 1.3.6`, BSD license as
tcllib's `license.terms`); keep them unmodified so a future refresh
is a plain diff against upstream.

Why vendored: the config layer parses JSON (the claude-projects menu
is the model task), and neither a stock tclkit nor whalebuild's
install tree carries tcllib — the kit and the checkout both need the
module to travel with the library. Only the pure-Tcl leg is taken:
`jsonc.tcl` is critcl source compiled into tcllibc, never sourced at
run time, and `json.tcl` finds that accelerator by itself when the
interpreter carries one (a whale does).

Why no pkgIndex.tcl here: the package unknown handler scans an
auto_path directory's children for indexes and no deeper, and this
directory sits a level below wherever the library lands — checkout,
installed tree, kit alike. The `package ifneeded json` line lives in
`library/pkgIndex.tcl`, which every one of those places already
finds.
