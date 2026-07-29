# Shared preamble for the tk9wm regressions — sourced, not run:
#
#     . "$(dirname "$0")/common.sh"
#
# Every run-*.sh raises its own X server and drives a whole session in
# ONE shell call (the sandbox gives each call its own namespaces, so a
# server started in another call is not reachable from this one). What
# they all need first is the same four paths, which is all this file
# is.
#
# HERE   this directory — where fixtures (client*.tcl) live and where
#        every artifact (logs, screenshots, throwaway config dirs) is
#        written; all of it gitignored.
# ROOT   the checkout.
# TOOLS  live-display diagnostics and pokers (probe-*, send-*, set-*).
# WMTCL  the window manager's entry script. Not WM: several tests use
#        that name for the WM's pid.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TOOLS="$ROOT/tools"
WMTCL="${WMTCL:-$ROOT/tk9wm.tcl}"

# The interpreter. Any Tcl/Tk 9 with treectrl will do — what it does
# NOT need any more is the shim compiled in: tk9wm.tcl puts the
# checkout on auto_path, so the libtkwmx.so built here (./configure &&
# make) is found and loaded. A whale carrying tk9wm as a baked-in
# battery works too, and needs no build at all.
#
# The sibling whalebuild checkout is only the default; point LINUX (or
# WHALE / WHALE_CLI individually) anywhere else — a stock tclkit, a
# system wish — to run the suite on another host.
LINUX="${LINUX:-$ROOT/../whalebuild/work/linux}"
WHALE="${WHALE:-$LINUX/whale}"
WHALE_CLI="${WHALE_CLI:-$LINUX/whale-cli}"

# Wine, for the three probes that drive a real Windows client through
# it (the sandbox wrapper in the thoughts tree).
WINESH="${WINESH:-$ROOT/../../../tools/sandbox/wine.sh}"

# The WM checks its own modal invariants — a mode left standing with no
# router, a compass with no mode, a frame still wearing the modal amber,
# the keyboard grabbed for nobody — and says so in the log. That makes
# the check FREE for every scenario the suite drives, whatever the
# scenario was written for: one line at the end of a test turns it into
# an interleaving test as well. Add it to yours.
check_invariants() {
    if grep -q 'WM: INVARIANT' "$1"; then
        echo "FAIL: the WM broke its own modal invariants:"
        grep 'WM: INVARIANT' "$1" | sed 's/^/    /'
    else
        echo "OK: no modal invariant was broken"
    fi
}
