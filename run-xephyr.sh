#!/bin/sh
# Live playground: tk9wm inside a Xephyr window on a real desktop.
# Usage: run-xephyr.sh [display] [WxH]    (default :7 1280x800)
#        WHALE=/path/to/whale   overrides the binary
#        TK9WM_QUIRKS=1         enables the WM's client workarounds
#                               (off here on purpose — see below)
# No demo timers in this mode — the WM runs until Xephyr closes or Ctrl-C.
#
# Order matters: server, then resources, then the WM, then clients — an
# xterm started last picks its settings (DPI included) out of the X
# resource database this script merges below.
HERE="$(cd "$(dirname "$0")" && pwd)"
WHALE="${WHALE:-$HERE/../whalebuild/work/linux/whale}"
DPY="${1:-:7}"
SIZE="${2:-1280x800}"

# -noreset: the server keeps its state (and the merged resources) when the
# last client happens to exit, instead of resetting the session under us.
#
# Set the screen size HERE and do not resize the window afterwards: after
# an interactive resize Xephyr's XTEST coordinates stop matching the
# screen (measured: a synthetic pointer either clamps to the original box
# or comes out scaled), which makes every headless driver silently lie.
Xephyr "$DPY" -noreset -screen "$SIZE" -title "tk9wm playground" &
XEPHYR=$!
trap 'kill $XEPHYR 2>/dev/null' EXIT INT TERM
sleep 1

# X resources before any client starts, so clients read them at startup.
[ -f "$HOME/.Xresources" ] && DISPLAY="$DPY" xrdb -merge "$HOME/.Xresources"

# Paint the root with hsetroot, NOT xsetroot: a compositor (compton and
# friends) composites the root PIXMAP published in _XROOTPMAP_ID and never
# looks at the background pixel xsetroot sets — with no such property it
# paints its own 50% grey instead. On Xephyr xsetroot fails to paint even
# without a compositor.
if command -v hsetroot >/dev/null; then
    DISPLAY="$DPY" hsetroot -solid '#20303c'
fi

# The WM runs WITHOUT quirks unless the caller asked for them: the timed
# repeats of the synthetic ConfigureNotify are a workaround, and leaving
# them on by default would hide whether the event-driven moments (manage,
# the client's MapNotify) are enough on their own.
DISPLAY="$DPY" "$WHALE" "$HERE/wm.tcl" &
echo "tk9wm live on $DPY ($SIZE), quirks=${TK9WM_QUIRKS:-off} — drag titles, click X"

# guinea pigs last, so they inherit the resources merged above
command -v xterm  >/dev/null && DISPLAY="$DPY" xterm  -geometry 80x24+20+20 &
command -v xclock >/dev/null && DISPLAY="$DPY" xclock -geometry 150x150+60+60 &

wait $XEPHYR
