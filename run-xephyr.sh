#!/bin/sh
# Live playground: tk9wm inside a Xephyr window on a real desktop.
# Usage: run-xephyr.sh [display] [WxH]    (default :7 1280x800)
#        WHALE=/path/to/whale overrides the binary
# No demo timers in this mode — the WM runs until Xephyr closes or Ctrl-C.
#
# Set the screen size HERE and do not resize the window afterwards: after
# an interactive resize Xephyr's XTEST coordinates stop matching the
# screen (measured: a synthetic pointer either clamps to the original box
# or comes out scaled), which makes every headless driver silently lie.
HERE="$(cd "$(dirname "$0")" && pwd)"
WHALE="${WHALE:-$HERE/../whalebuild/work/linux/whale}"
DPY="${1:-:7}"
SIZE="${2:-1280x800}"

Xephyr "$DPY" -screen "$SIZE" -title "tk9wm playground" &
XEPHYR=$!
trap 'kill $XEPHYR 2>/dev/null' EXIT INT TERM
sleep 1

# Paint the root with hsetroot, NOT xsetroot: a compositor (compton and
# friends) composites the root PIXMAP published in _XROOTPMAP_ID and never
# looks at the background pixel xsetroot sets — with no such property it
# paints its own 50% grey instead. On Xephyr xsetroot fails to paint even
# without a compositor.
if command -v hsetroot >/dev/null; then
    DISPLAY="$DPY" hsetroot -solid '#20303c'
fi

DISPLAY="$DPY" "$WHALE" "$HERE/wm.tcl" &
echo "tk9wm live on $DPY ($SIZE) — drag titles, click X, resize from inside clients"

# a couple of guinea pigs, when available
command -v xterm  >/dev/null && DISPLAY="$DPY" xterm  -geometry 80x24+20+20 &
command -v xclock >/dev/null && DISPLAY="$DPY" xclock -geometry 150x150+60+60 &

wait $XEPHYR
