#!/bin/sh
# The welcome mat FITS — the desk's first impression is the one piece
# of furniture whose height nobody declares: it is however deep the
# text wraps to, and the desk has to reserve that much before it knows
# it (the owner, 2026-08-03: the mat ran off the bottom of the screen,
# its last lines behind the panel, and a modest clipped square with the
# desk window off).
#
# The trap is that a widget is MEASURED in a window nobody maps. Asked
# for its wrapped height there, a text widget that was never given a
# width answers in the hundreds, and a re-fit that waits for a mapping
# never runs at all — either way the reserved size and the built size
# disagree, and it is the built one that shows.
#
# So both readings are demanded to agree, in both worlds the mat can
# live in: inside the desk window (a frame in it) and, with the desk
# window off, in a toplevel of its own. And the whole of it inside the
# workarea, which is what "not behind the panel" means.
. "$(dirname "$0")/common.sh"
export DISPLAY=:95
rm -f /tmp/.X95-lock /tmp/.X11-unix/X95
Xvfb :95 -screen 0 1280x1024x24 >/dev/null 2>&1 &
XVFB=$!
sleep 1

CONF="$HERE/welcome-config"
rm -rf "$CONF"; mkdir -p "$CONF"
trap 'kill $XVFB 2>/dev/null' EXIT
cat > "$CONF/tk9wm.tcl" <<'EOF'
# a panel at the bottom for the mat to be measured against — and to
# hide behind, which is the failure this test is about
action проба {type terminal}
panel-button проба
EOF

LOG="$HERE/wm-welcome.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 2

qf() { printf '%s\n' "$1" > "$CONF/q.tcl"
       "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl"; }

# What the mat is, wherever it lives: the reserved size, the size it
# actually asks for, its rectangle in root coordinates, and whether
# every wrapped line of it is on screen.
STATE='set c $::widget_win(__welcome)
set t $c.t
list reserved [list [winfo reqwidth $c] [winfo reqheight $c]] \
     measured $::widget_size(__welcome) \
     lines [list [$t cget -height] [expr {[$t count -displaylines 1.0 end] + 1}]] \
     rect [list [winfo rootx $c] [winfo rooty $c] \
                [winfo width $c] [winfo height $c]] \
     workarea [workarea]'

ON=$(qf "$STATE")
echo "--- desk window on:  $ON"
qf 'set-desk-window off' >/dev/null
sleep 1
OFF=$(qf "$STATE")
OFFTOP=$(qf 'list [wm geometry $::widget_top(area1)] \
                  [winfo reqheight $::widget_win(__welcome)]')
echo "--- desk window off: $OFF"
echo "--- its own toplevel: $OFFTOP"

kill $WM 2>/dev/null

# fits STATE-STRING — the two readings agree and the whole mat is
# inside the workarea.
fits() {
    echo "$1" | tr -d '{}' | awk '
        { for (i = 1; i < NF; i++) f[$i] = i }
        END {
            rh = $(f["reserved"] + 2); mh = $(f["measured"] + 2)
            sh = $(f["lines"] + 1);    dl = $(f["lines"] + 2)
            y  = $(f["rect"] + 2);     h  = $(f["rect"] + 4)
            wy = $(f["workarea"] + 2); wh = $(f["workarea"] + 4)
            if (mh != rh)     { print "reserved " mh " for a mat " rh " deep"; exit }
            if (sh != dl)     { print "shows " sh " lines of " dl }
            if (y < wy)       { print "top at " y ", above the workarea " wy; exit }
            if (y + h > wy + wh) { print "bottom at " y + h ", past the workarea " wy + wh }
        }'
}

echo "--- verdict"
FAIL=0
BAD=$(fits "$ON")
if [ -z "$BAD" ]; then
    echo "OK: inside the desk window the mat is reserved at its real depth\
 and fits the workarea"
else
    echo "FAIL: with the desk window on, the mat $BAD"; FAIL=1
fi
BAD=$(fits "$OFF")
if [ -z "$BAD" ]; then
    echo "OK: ...and the same in a toplevel of its own, with the desk window off"
else
    echo "FAIL: with the desk window off, the mat $BAD"; FAIL=1
fi
# The fallback toplevel is sized from the measurement, so a mat deeper
# than the measurement is a mat with its tail cut off — the clipped
# square of the report.
TOPH=$(echo "$OFFTOP" | sed -n 's/^[0-9]*x\([0-9]*\)+.*/\1/p')
WANTH=$(echo "$OFFTOP" | awk '{print $2}')
if [ -n "$TOPH" ] && [ "$TOPH" -ge "$WANTH" ]; then
    echo "OK: the toplevel it falls back to holds the whole mat ($TOPH >= $WANTH)"
else
    echo "FAIL: the fallback toplevel is $TOPH deep for a $WANTH mat"; FAIL=1
fi
check_invariants "$LOG" || FAIL=1
if grep -q 'handler error' "$LOG"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$LOG"
    FAIL=1
fi
exit $FAIL
