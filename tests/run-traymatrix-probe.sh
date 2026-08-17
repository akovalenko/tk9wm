#!/bin/sh
# The tray matrix, measured rather than argued about: {ARGB strip,
# 24-bit strip} × {compositor, none} × {a negotiating GTK icon
# (nm-applet's manner), a 32-bit-always icon (Chrome's manner,
# tray-client-argb.tcl)}. Eight cells, two pixels each — the corner
# (the icon's transparent part) and the middle (its glyph).
#
# Why it exists (the owner, 2026-08-17): could the tray be a plain
# frame ON the panel instead of a toplevel of its own? By pixels a
# frame on the 24-bit panel IS the 24-bit strip — same depth, same
# parent-relative story — so the argb=off rows answer the in-panel
# question without building it. What the separate toplevel buys
# besides the pixels is lifecycle (a panel rebuild must never
# un-embed icons — un-embedding kills nm-applet, owner's report
# 2026-07-29) and the 32-bit visual itself, which no in-panel frame
# can have: a child's alpha flattens into the toplevel's depth.
#
# Reading the corner: #2e3436 is the tray's color (right); #ff00ff is
# the wallpaper (a hole); #000000 is flattened alpha (the black
# square of the classic failure).
. "$(dirname "$0")/common.sh"

TRAYBG='#2e3436'
run_case() {  # run_case NAME ARGB COMP
    NAME=$1; ARGB=$2; WANTCOMP=$3
    start_xvfb 800x600x24 +extension Composite +extension RENDER
    hsetroot -solid '#ff00ff' 2>/dev/null
    COMP=""
    if [ "$WANTCOMP" = yes ]; then
        compton --backend xrender --config /dev/null \
            > "$HERE/traymatrix-$NAME-compton.log" 2>&1 &
        COMP=$!
        sleep 1
    fi
    rm -rf "$HERE/traymatrix-config"
    mkdir -p "$HERE/traymatrix-config"
    cat > "$HERE/traymatrix-config/tk9wm.tcl" <<EOF
set-desk-window off
set-tray on
set-tray-argb $ARGB
set-tray-background $TRAYBG
set-tray-icon-size 32
EOF
    XDG_CONFIG_HOME="$HERE/traymatrix-config" \
        "$LINUX/whale" "$WMTCL" > "$HERE/wm-traymatrix-$NAME.log" 2>&1 &
    WM=$!
    wait_wm "$HERE/wm-traymatrix-$NAME.log" $WM
    LOG="$HERE/wm-traymatrix-$NAME.log"
    "$LINUX/whale" "$HERE/tray-client.tcl" "#8ae234" \
        > "$HERE/traymatrix-$NAME-gtk.log" 2>&1 &
    CA=$!
    wait_for 10 grep -q 'tray: docked' "$LOG"
    "$LINUX/whale" "$HERE/tray-client-argb.tcl" "#fcaf3e" \
        > "$HERE/traymatrix-$NAME-argb.log" 2>&1 &
    CB=$!
    sleep 3
    import -display "$DISPLAY" -window root "$HERE/traymatrix-$NAME.png" \
        2>/dev/null
    STRIP=$(sed -n 's/^WM: tray strip \([0-9]*\)x\([0-9]*\)+\([0-9]*\)+\([0-9]*\).*(2 icons)/\3 \4/p' \
        "$LOG" | tail -1)
    kill $CA $CB 2>/dev/null
    sleep 0.3
    kill $WM 2>/dev/null
    [ -n "$COMP" ] && kill $COMP 2>/dev/null
    sleep 0.3
    kill $XVFB 2>/dev/null; wait $XVFB 2>/dev/null
    if [ -z "$STRIP" ]; then
        echo "$NAME: the strip never held 2 icons — see $LOG"
        return
    fi
    set -- $STRIP; SX=$1; SY=$2
    P="$HERE/traymatrix-$NAME.png"
    px() { convert "$P" -format "%[pixel:p{$1,$2}]" info:; }
    # pad 3, cell 32, gap 4: cell N starts at SX+3+N*36; the first
    # docked (tk systray, the negotiating one) is cell 0, the
    # 32-bit-always one cell 1.
    echo "--- $NAME (argb=$ARGB compositor=$WANTCOMP)"
    echo "    negotiating: corner=$(px $((SX+5)) $((SY+5))) middle=$(px $((SX+19)) $((SY+19)))"
    echo "    argb-always: corner=$(px $((SX+41)) $((SY+5))) middle=$(px $((SX+55)) $((SY+19)))"
}

run_case argb-comp   on  yes
run_case argb-bare   on  no
run_case plain-comp  off yes
run_case plain-bare  off no
echo "--- legend: corner 46,52,54 = tray color (right); 255,0,255 = wallpaper"
echo "    hole; 0,0,0 = flattened alpha (the black square). Glyph middles:"
echo "    negotiating #8ae234=(138,226,52), argb-always #fcaf3e=(252,175,62)."
