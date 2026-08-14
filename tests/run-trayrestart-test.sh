#!/bin/sh
# A tray icon's client must SURVIVE the tray manager going away — the
# regression behind nm-applet dying on every restart of an ARGB desk
# (owner's report, 2026-08-14).
#
# The reload was cured earlier (tray-reconcile leaves a live,
# still-wanted strip alone — run-trayargb-test.sh measures it), but a
# restart-in-place runs the whole dance: tray-stop hands every icon
# back to the root, execv, the fresh instance re-claims the selection
# and adopts recorded orphans. What made that fatal on an ARGB desk
# was one ASYNC BadMatch: a depth-32 icon wearing a ParentRelative
# background cannot be reparented under the depth-24 root, so the
# undock's hand-back silently failed, the icon died with the old
# connection, and the client took a fatal X error on a window that
# went out from under it. The cure is two-sided: the undock clears
# the background before reparenting, and the dock never puts OUR
# ParentRelative on an icon whose depth is not the root's — the
# save-set rescue after a CRASH reparents to the root too, clears
# nothing, and just fails otherwise.
#
# Four passes, all with a compositor running (the owner's desk):
#   A  plain strip (argb off), live restart — the baseline that
#      always worked;
#   B  ARGB strip, live restart — nm-applet's exact death;
#   C  ARGB strip, a LOST race: the client is SIGSTOPped around the
#      restart, so the fresh instance force-adopts the old window
#      before the client can react, then the client wakes into the
#      backlog;
#   D  ARGB strip, a CRASH (kill -9): no undock runs at all — the
#      save-set alone must save the icon, and a fresh instance must
#      bring it back to the glass.
#
# The client is GTK3's GtkStatusIcon — the same machinery nm-applet
# is made of. No GDK_SYNCHRONIZE: the owner's crash trace shows the
# async report, so the client runs the way nm-applet really runs.
. "$(dirname "$0")/common.sh"
start_xvfb 800x600x24 +extension Composite +extension RENDER
trap 'kill $COMP $GTK $WM 2>/dev/null; stop_xservers' EXIT
hsetroot -solid '#ff00ff' 2>/dev/null
compton --backend xrender --config /dev/null \
    >"$HERE/trayrestart-comp.log" 2>&1 &
COMP=$!
sleep 1

CFG="$HERE/trayrestart-config"

# one pass's worth of desk: a WM over $CFG logging to $1, a GTK client
# logging to $2, spun up and waited for. Sets WM and GTK.
raise_desk() {
    XDG_CONFIG_HOME="$CFG" "$LINUX/whale" "$WMTCL" > "$1" 2>&1 &
    WM=$!
    wait_wm "$1" $WM
    python3 "$HERE/tray-client-gtk.py" "#729fcf" > "$2" 2>&1 &
    GTK=$!
    wait_for 15 grep -q '^WM: tray: docked' "$1" \
        || echo "note: the GTK icon never docked in $1"
    sleep 1
}
drop_desk() {
    kill $GTK $WM 2>/dev/null
    wait $GTK $WM 2>/dev/null
    sleep 0.5
}
alive() { kill -0 $GTK 2>/dev/null && echo 1 || echo 0; }

# ---- pass A: a plain strip, live restart ----
rm -rf "$CFG"; mkdir -p "$CFG"
printf '%s\n' 'set-welcome off' 'set-tray-argb off' 'set-tray on' \
    > "$CFG/tk9wm.tcl"
raise_desk "$HERE/wm-trayrestart-a.log" "$HERE/trayrestart-gtk-a.log"
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" "$DISPLAY"
sleep 5
A_ALIVE=$(alive)
A_DOCKS=$(grep -c '^WM: tray: docked' "$HERE/wm-trayrestart-a.log")
drop_desk

# ---- pass B: the ARGB strip, live restart (nm-applet's death) ----
printf '%s\n' 'set-welcome off' 'set-tray-argb on' 'set-tray on' \
    > "$CFG/tk9wm.tcl"
raise_desk "$HERE/wm-trayrestart-b.log" "$HERE/trayrestart-gtk-b.log"
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" "$DISPLAY"
sleep 5
B_ALIVE=$(alive)
B_DOCKS=$(grep -c '^WM: tray: docked' "$HERE/wm-trayrestart-b.log")
drop_desk

# ---- pass C: ARGB, the client LOSES the race to the adopter ----
raise_desk "$HERE/wm-trayrestart-c.log" "$HERE/trayrestart-gtk-c.log"
kill -STOP $GTK
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" "$DISPLAY"
sleep 4        # the fresh instance boots and adopts while the client sleeps
C_ADOPTED=$(grep -c 'was ours and is orphaned' "$HERE/wm-trayrestart-c.log")
kill -CONT $GTK
sleep 4        # the client wakes into the backlog
C_ALIVE=$(alive)
drop_desk

# ---- pass D: ARGB, a crash — the save-set alone saves the icon ----
raise_desk "$HERE/wm-trayrestart-d.log" "$HERE/trayrestart-gtk-d.log"
kill -9 $WM
sleep 3
D_ALIVE=$(alive)
# ...and a fresh instance puts an icon back on the glass (its own
# re-dock or the orphan record — either is a working tray).
XDG_CONFIG_HOME="$CFG" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-trayrestart-d2.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-trayrestart-d2.log" $WM
wait_for 15 grep -q '^WM: tray: docked' "$HERE/wm-trayrestart-d2.log"
D_BACK=$(grep -c '^WM: tray: docked' "$HERE/wm-trayrestart-d2.log")
D_ALIVE2=$(alive)
drop_desk

echo "--- A: alive=$A_ALIVE docks=$A_DOCKS | B: alive=$B_ALIVE docks=$B_DOCKS"
echo "--- C: adopted=$C_ADOPTED alive=$C_ALIVE | D: alive=$D_ALIVE then=$D_ALIVE2 back=$D_BACK"
for p in a b c d d2; do
    [ -f "$HERE/wm-trayrestart-$p.log" ] || continue
    echo "--- $p tray lines:"
    grep -E 'WM: tray|restart' "$HERE/wm-trayrestart-$p.log" | sed "s/^/    /"
done

echo "--- verdict"
[ "$A_ALIVE" = 1 ] && echo "OK: A — the client survived a plain restart" \
    || echo "FAIL: A — the client died on a plain restart"
[ "$A_DOCKS" -ge 2 ] && echo "OK: A — an icon is docked in the fresh instance" \
    || echo "FAIL: A — nothing re-docked ($A_DOCKS dock lines)"
[ "$B_ALIVE" = 1 ] && echo "OK: B — the client survived the ARGB restart (nm-applet's case)" \
    || echo "FAIL: B — the client died on the ARGB restart"
[ "$B_DOCKS" -ge 2 ] && echo "OK: B — an icon is docked in the fresh ARGB instance" \
    || echo "FAIL: B — nothing re-docked ($B_DOCKS dock lines)"
[ "$C_ADOPTED" -ge 1 ] && echo "OK: C — adoption won the race, as arranged" \
    || echo "FAIL: C — adoption never happened; the pass measured nothing"
[ "$C_ALIVE" = 1 ] && echo "OK: C — the client survived losing the race" \
    || echo "FAIL: C — the client died after the lost race"
[ "$D_ALIVE" = 1 ] && echo "OK: D — the save-set saved the icon through a crash" \
    || echo "FAIL: D — the client died with the crashed manager"
[ "$D_ALIVE2" = 1 ] && [ "$D_BACK" -ge 1 ] \
    && echo "OK: D — and the next instance put an icon back ($D_BACK dock line(s))" \
    || echo "FAIL: D — after the crash: alive=$D_ALIVE2, $D_BACK dock line(s)"
# the regression's own signature: the hand-back must never BadMatch
if grep -h 'X error BadMatch.*request=7' "$HERE"/wm-trayrestart-*.log \
        2>/dev/null | grep -q .; then
    echo "FAIL: a reparent BadMatch is back — the icon hand-back is broken:"
    grep -h 'X error BadMatch.*request=7' "$HERE"/wm-trayrestart-*.log \
        | sed 's/^/    /'
else
    echo "OK: no reparent ever BadMatched"
fi
if grep -h 'handler error' "$HERE"/wm-trayrestart-*.log 2>/dev/null | grep -q .; then
    echo "FAIL: handler errors present:"
    grep -h 'handler error' "$HERE"/wm-trayrestart-*.log | sed 's/^/    /'
fi
