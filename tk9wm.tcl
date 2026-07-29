# tk9wm — the entry point: find the packages, load the WM, run it.
#
#   whale tk9wm.tcl            from a checkout
#   whale tk9wm.tcl demo       the timed self-test tests/run-demo.sh drives
#
# Everything of substance is in the tk9wm package (library/): the
# substrate (mechanism), the policy (look and feel) and the config
# layer. This file only arranges for `package require` to find them,
# which differs by where tk9wm was installed from:
#
#  - a checkout — library/ sits next to this script and is on nobody's
#    auto_path yet, so add the checkout itself: Tcl scans a directory's
#    CHILDREN for package indexes, which picks up library/ and, once
#    ./configure && make has run, the shim's pkgIndex.tcl here at the
#    root as well;
#  - an installed package directory, or a whale carrying tk9wm as a
#    baked-in battery — this script sits next to its own library files
#    with the index already in auto_path's reach, and the branch below
#    correctly does nothing.
#
# The checkout goes to the FRONT, and that is load-bearing rather than
# tidy. On a host that also has the shim compiled in, appending loses:
# `package require` walks auto_path in order and stops at the first
# directory that supplies the package, so the built-in copy answers and
# the libtkwmx.so you just built is silently ignored — you edit
# generic/tkwmx.c, rebuild, and nothing changes. Measured, not
# reasoned. Prepending costs nothing: this directory offers exactly two
# packages, so there is nothing else it could shadow.
set here [file dirname [file normalize [info script]]]
if {[file exists [file join $here library pkgIndex.tcl]]} {
    set ::auto_path [linsert $::auto_path 0 $here]
}

package require tk9wm
tk9wm-main {*}$argv
