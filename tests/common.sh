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

# ---- an X server of our own, on a display NOBODY chose ----
# 106 runners used to write their display numbers by hand and shared
# 61 of them; on a machine with another user's servers, more than
# half could not start at all — a foreign lock under sticky /tmp is
# not ours to rm. Nobody picks numbers any more: -displayfd hands the
# choosing to the server, and it answers with the display it took
# only once it is ready to serve — which is also why there is nothing
# to sleep for afterwards. A machine that cannot raise a server at
# all says SKIP and exits 77 (automake's word for «no environment»),
# so an infrastructure hole stops reading as a red battery.
#
# Cleanup is ONE accumulated trap: every server raised through here
# is killed AND REAPED on exit. The wait is the load-bearing half: a
# TERM'd server unlinks its lock and socket on the way down, but a
# suite that exits without waiting races that death against the
# shell call's teardown and can leave the lock standing — the owner
# swept a few such locks by hand (2026-08-07) before the wait was
# here. A suite that sets an EXIT trap of its own replaces this one —
# a shell has one trap per signal — so it must put `stop_xservers`
# in the replacement, as every such suite here does.
XSERVERS=""
stop_xservers() {
    kill $XSERVERS 2>/dev/null
    wait $XSERVERS 2>/dev/null
}
start_xserver() {   # start_xserver CMD [ARGS...] — sets XSERVER, DISPLAY
    _fd=$(mktemp)
    "$@" -displayfd 3 3>"$_fd" >/dev/null 2>&1 &
    XSERVER=$!
    XSERVERS="$XSERVERS $XSERVER"
    trap stop_xservers EXIT
    _n="" _i=0
    while [ $_i -lt 100 ]; do
        _n=$(cat "$_fd"); [ -n "$_n" ] && break
        sleep 0.05; _i=$((_i+1))
    done
    rm -f "$_fd"
    [ -n "$_n" ] || { echo "SKIP: no $1 could be started"; exit 77; }
    export DISPLAY=":$_n"
}
start_xvfb() {      # start_xvfb [GEOMETRY [EXTRA...]] — sets XVFB too
    _geom="${1:-800x600x24}"
    [ $# -gt 0 ] && shift
    start_xserver Xvfb -screen 0 "$_geom" "$@"
    XVFB=$XSERVER
}

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
