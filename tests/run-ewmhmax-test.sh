#!/bin/sh
# Regression for EWMH maximize: the _NET_WM_STATE maximized pair
# honored as a state action (wmctrl add/remove/toggle), as a pre-map
# request (a client that sets the property before mapping — emacs's
# `fullscreen: maximized` X resource takes this road), and published
# back while the mark holds.
#
# ...and PER AXIS, which is what the pair of atoms always meant:
# maximized_vert alone makes a window tall at its own width (published
# as VERT alone), Maximize-H by key grows a tall window to full and
# toggles back to tall, a gridded client fills the workarea to the
# PIXEL when maximized (the mutter rule: a maximized axis owes the
# increments nothing), and a client that sets VERT alone before its
# first map is BORN tall.
#
# ...and the fit stays a SUM that can be asked again: a client that
# declares its size hints only AFTER it was maximized is re-fitted to
# them, rather than held at a size its own hints forbid.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/ewmhmax-config"
mkdir -p "$HERE/ewmhmax-config"
cat > "$HERE/ewmhmax-config/tk9wm.tcl" <<'EOF'
action dummy {launch {exec true &}}
panel-button dummy
# an UNFORCED style on the zoomed claimant: its own pre-map maximize
# request must outrank this rule (the born-at-full-size asserts below
# fail if the rule wins)
wm-style {filter -title zoomed} {place 50%right}
# ...and the shield case: born maximized by a forced rule, this one
# will ask for its own size mid-state — the request must land in the
# saved way-back geometry, never in the live one
wm-style {filter -title щитовой} {place {max force}}
wm-bind {<Super>u} Unmaximize
wm-bind {<Super>d} Maximize-H
EOF
# a pre-map claimant for ONE axis, RAW X: Tk rewrites _NET_WM_STATE on
# its wrapper at map time (measured — an atom xprop wrote pre-map was
# gone before the WM looked), so this road needs a window Tk does not
# own. tkwmx creates a bare child of the root, the client stamps VERT
# alone on it, and only then maps.
cat > "$HERE/ewmhmax-config/client-tall.tcl" <<'EOF'
set ::auto_path [linsert $::auto_path 0 \
    [file dirname [file dirname [file dirname \
        [file normalize [info script]]]]]]
package require Tk
package require tkwmx
wm withdraw .
proc A {name} { tkwmx::atom intern $name }
set root [lindex [tkwmx::window tree [winfo id .]] 0]
set w [tkwmx::window create $root 10 10 240 120]
tkwmx::prop set $w [A WM_NAME] [A STRING] 8 tall
tkwmx::prop set $w [A _NET_WM_STATE] [A ATOM] 32 \
    [list [A _NET_WM_STATE_MAXIMIZED_VERT]]
tkwmx::window map $w
chan configure stdout -buffering line
puts "TALL: id [format 0x%x $w]"
after 30000 exit
vwait forever
EOF
# a pre-map claimant: -zoomed before the first map
cat > "$HERE/ewmhmax-config/client-zoomed.tcl" <<'EOF'
package require Tk
wm title . zoomed
wm attributes . -zoomed 1
label .l -text zoomed -background #ad7fa8 -font {Sans 14}
pack .l -expand 1 -fill both
chan configure stdout -buffering line
bind . <Map> {
    if {"%W" eq "."} {
        puts "ZOOMED: mapped at [winfo width .]x[winfo height .]"
        bind . <Map> {}
    }
}
after 30000 exit
EOF
# a client that declares its real size hints LATE — lazarus-ide's road:
# the IDE's main bar comes up maximized (from its own profile) and only
# once the toolbar and the component palette have been laid out does the
# LCL declare min height == max height, a bar that CANNOT be tall. The
# maximized fit was computed before that word arrived.
cat > "$HERE/ewmhmax-config/client-late.tcl" <<'EOF'
package require Tk
wm title . поздний
label .l -text late -background #729fcf -font {Sans 14}
pack .l -expand 1 -fill both
chan configure stdout -buffering line
proc ask {} {
    wm geometry . 700x64
    puts "LATE: live [winfo width .]x[winfo height .]"
}
after 4000 {
    wm minsize . 1 64
    wm maxsize . 32767 64
    puts "LATE: hints declared — 64 fixed height"
    for {set i 0} {$i < 8} {incr i} { after [expr {400 * $i}] ask }
}
after 30000 exit
EOF

XDG_CONFIG_HOME="$HERE/ewmhmax-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-ewmhmax.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-ewmhmax.log" $WM

"$LINUX/whale" "$HERE/client.tcl" "жертва" 240x120 "#8ae234" "" "" 30 &
CA=$!
wait_client "$HERE/wm-ewmhmax.log" 'жертва'
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-ewmhmax.log" | head -1)
PH=$(sed -n 's/^WM: panel [^ ]* up (1 buttons, \([0-9]*\) px.*/\1/p' "$HERE/wm-ewmhmax.log" | head -1)
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-ewmhmax.log" | head -1)
MAXH=$((600 - ${PH:-38} - ${TOP:-30} - 6))
WANTMAX="788x$MAXH"

size_of() { xwininfo -id "$1" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}'; }

wmctrl -i -r "$AID" -b add,maximized_vert,maximized_horz;    sleep 1
SZ_ADD=$(size_of "$AID")
ST_ADD=$(xprop -id "$AID" _NET_WM_STATE | sed 's/.*= //')
wmctrl -i -r "$AID" -b remove,maximized_vert,maximized_horz; sleep 1
SZ_REM=$(size_of "$AID")
ST_REM=$(xprop -id "$AID" _NET_WM_STATE | sed 's/.*= //')
wmctrl -i -r "$AID" -b toggle,maximized_vert,maximized_horz; sleep 1
SZ_TOG=$(size_of "$AID")

# --- one axis at a time: tall by wmctrl, wide by key, and back
wmctrl -i -r "$AID" -b remove,maximized_vert,maximized_horz; sleep 1
wmctrl -i -r "$AID" -b add,maximized_vert;                   sleep 1
SZ_V=$(size_of "$AID")
ST_V=$(xprop -id "$AID" _NET_WM_STATE | sed 's/.*= //')
xdotool key super+d; sleep 1     # Maximize-H: the tall window grows wide
SZ_VH=$(size_of "$AID")
xdotool key super+d; sleep 1     # ...and the same key toggles wide off
SZ_VH2=$(size_of "$AID")
wmctrl -i -r "$AID" -b remove,maximized_vert; sleep 1
SZ_V0=$(size_of "$AID")

"$LINUX/whale" "$HERE/ewmhmax-config/client-zoomed.tcl" > "$HERE/ewmhmax-config/zoomed.log" 2>&1 &
CZ=$!
sleep 2
ZID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-ewmhmax.log" | sed -n 2p)
SZ_Z=$(size_of "$ZID")

# the shield: born maximized, asks for 300x150 at t+4s
"$LINUX/whale" "$HERE/client.tcl" "щитовой" 240x120 "#fcaf3e" 300x150 "" 30 &
CS=$!
sleep 6                # past the client's own resize request
SID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-ewmhmax.log" | sed -n 3p)
SZ_S=$(size_of "$SID")
wmctrl -i -r "$SID" -b remove,maximized_vert,maximized_horz; sleep 1
SZ_PIN=$(size_of "$SID")
xdotool key super+u; sleep 1     # the USER unmaximizes — the pin binds clients only
SZ_SR=$(size_of "$SID")

# --- the mutter rule: a gridded client (10x10 increments) maximizes to
# the PIXEL, not to the nearest cell — 788x$MAXH, never 780x520
"$LINUX/whale" "$HERE/client-grid.tcl" сетка "#729fcf" "" 30 &
CG=$!
sleep 1.5
GID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-ewmhmax.log" | sed -n 4p)
wmctrl -i -r "$GID" -b add,maximized_vert,maximized_horz;    sleep 1
SZ_G=$(size_of "$GID")
wmctrl -i -r "$GID" -b remove,maximized_vert,maximized_horz; sleep 1
SZ_G0=$(size_of "$GID")

# --- born TALL: VERT alone set before the first map, by the client
# itself, on a raw window (see the claimant above for why not Tk)
"$LINUX/whale" "$HERE/ewmhmax-config/client-tall.tcl" \
    > "$HERE/ewmhmax-config/tall.log" 2>&1 &
CT=$!
sleep 2
TXID=$(sed -n 's/^TALL: id //p' "$HERE/ewmhmax-config/tall.log" | head -1)
SZ_T=$(size_of "$TXID")
ST_T=$(xprop -id "$TXID" _NET_WM_STATE | sed 's/.*= //')

# --- the hints declared LATE, under a maximized window. The fit is a
# SUM — workarea, chrome, hints — and one of the three just moved: it
# has to be asked again, or the window stands at a height its own hints
# forbid and spends the rest of its life asking to be let down (the
# lazarus-ide fight, the owner 2026-08-19)
"$LINUX/whale" "$HERE/ewmhmax-config/client-late.tcl" \
    > "$HERE/ewmhmax-config/late.log" 2>&1 &
CL=$!
wait_client "$HERE/wm-ewmhmax.log" 'поздний'
LID=$(wmctrl -l | awk '/поздний/{print $1; exit}')
wmctrl -i -r "$LID" -b add,maximized_vert,maximized_horz; sleep 1
SZ_L0=$(size_of "$LID")   # maximized while the height is still free
sleep 8                   # ...and now the client says what it really is
SZ_L=$(size_of "$LID")
LLIVE=$(sed -n 's/^LATE: live //p' "$HERE/ewmhmax-config/late.log" | tail -1)

kill $WM $CA $CZ $CS $CG $CT $CL 2>/dev/null

echo "--- actors: A=$AID Z=$ZID want-max=$WANTMAX"
echo "--- maximize lines:"
grep -E 'maximize|maximized' "$HERE/wm-ewmhmax.log"
echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-ewmhmax.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ "$SZ_ADD" = "$WANTMAX" ]; then
    echo "OK: add,maximized_* fit the workarea ($SZ_ADD)"
else
    echo "FAIL: after add the client is $SZ_ADD, want $WANTMAX"
fi
case $ST_ADD in
    *_NET_WM_STATE_MAXIMIZED_VERT*_NET_WM_STATE_MAXIMIZED_HORZ*)
        # VERT before HORZ — the EWMH listing order the publisher
        # deliberately keeps since the emacs fold fix (31d5098)
        echo "OK: the maximized pair is published while it holds" ;;
    *) echo "FAIL: published state after add: $ST_ADD" ;;
esac
if [ "$SZ_REM" = "240x120" ]; then
    echo "OK: remove restored the asked-for size"
else
    echo "FAIL: after remove the client is $SZ_REM, want 240x120"
fi
case $ST_REM in
    *MAXIMIZED*) echo "FAIL: maximized still published after remove: $ST_REM" ;;
    *) echo "OK: the pair left the published state on remove" ;;
esac
if [ "$SZ_TOG" = "$WANTMAX" ]; then
    echo "OK: toggle maximized again ($SZ_TOG)"
else
    echo "FAIL: after toggle the client is $SZ_TOG, want $WANTMAX"
fi
if [ "$SZ_V" = "240x$MAXH" ]; then
    echo "OK: maximized_vert alone made it tall at its own width ($SZ_V)"
else
    echo "FAIL: after add,maximized_vert the client is $SZ_V, want 240x$MAXH"
fi
case $ST_V in
    *MAXIMIZED_HORZ*)
        echo "FAIL: a tall window published HORZ too: $ST_V" ;;
    *MAXIMIZED_VERT*)
        echo "OK: the tall window publishes VERT alone" ;;
    *)  echo "FAIL: published state while tall: $ST_V" ;;
esac
if [ "$SZ_VH" = "$WANTMAX" ]; then
    echo "OK: Maximize-H by key grew the tall window to full ($SZ_VH)"
else
    echo "FAIL: after Maximize-H the client is $SZ_VH, want $WANTMAX"
fi
if [ "$SZ_VH2" = "240x$MAXH" ]; then
    echo "OK: ...and the same key toggled wide back off ($SZ_VH2)"
else
    echo "FAIL: after the second Maximize-H the client is $SZ_VH2, want 240x$MAXH"
fi
if [ "$SZ_V0" = "240x120" ]; then
    echo "OK: remove,maximized_vert restored the asked-for size"
else
    echo "FAIL: after the vert remove the client is $SZ_V0, want 240x120"
fi
if [ "$SZ_G" = "$WANTMAX" ]; then
    echo "OK: the gridded client maximized to the pixel ($SZ_G — the mutter rule)"
else
    echo "FAIL: the gridded client maximized to $SZ_G, want $WANTMAX exactly"
fi
if [ "$SZ_G0" = "300x200" ]; then
    echo "OK: ...and restored to its own gridded size"
else
    echo "FAIL: the gridded client restored to $SZ_G0, want 300x200"
fi
if [ "$SZ_T" = "240x$MAXH" ]; then
    echo "OK: VERT alone before the first map bore a tall window ($SZ_T)"
else
    echo "FAIL: the born-tall client is $SZ_T, want 240x$MAXH"
fi
case $ST_T in
    *MAXIMIZED_HORZ*)
        echo "FAIL: the born-tall window published HORZ too: $ST_T" ;;
    *MAXIMIZED_VERT*)
        echo "OK: ...and it publishes VERT alone" ;;
    *)  echo "FAIL: published state on the born-tall window: $ST_T" ;;
esac
if [ "$SZ_Z" = "$WANTMAX" ]; then
    echo "OK: the -zoomed client mapped maximized ($SZ_Z)"
else
    echo "FAIL: the -zoomed client is $SZ_Z, want $WANTMAX"
fi
if grep -qE 'asks to be born maximized|client asks maximize [hv] on' "$HERE/wm-ewmhmax.log"; then
    echo "OK: the zoomed request was heard (whichever road Tk took)"
else
    echo "FAIL: no sign the zoomed request arrived"
fi
MAPPED=$(sed -n 's/^ZOOMED: mapped at //p' "$HERE/ewmhmax-config/zoomed.log" | head -1)
if [ "$MAPPED" = "$WANTMAX" ]; then
    echo "OK: born at full size — mapped once at $MAPPED, no narrow flash"
else
    echo "FAIL: first map was $MAPPED, want $WANTMAX (the narrow-flash bug)"
fi
if [ "$SZ_S" = "$WANTMAX" ]; then
    echo "OK: the shield held — a mid-state size request left the window maximized"
else
    echo "FAIL: after its own resize request the shielded client is $SZ_S, want $WANTMAX"
fi
if grep -q 'while maximized — saved for the way back' "$HERE/wm-ewmhmax.log"; then
    echo "OK: ...and said where the request went"
else
    echo "FAIL: no shield log line"
fi
if [ "$SZ_PIN" = "$WANTMAX" ] \
        && grep -q 'pinned by place {max force}, refused' "$HERE/wm-ewmhmax.log"; then
    echo "OK: a client's remove bounced off the forced rule, and said so"
else
    echo "FAIL: after a client remove the pinned window is $SZ_PIN (want $WANTMAX)"
fi
if [ "$SZ_SR" = "300x150" ]; then
    echo "OK: the USER'S unmaximize works and restores what the client last meant"
else
    echo "FAIL: user unmaximize landed at $SZ_SR, want the requested 300x150"
fi
if [ "$SZ_L0" = "$WANTMAX" ]; then
    echo "OK: the late client maximized to the workarea while its height was free"
else
    echo "FAIL: the late client maximized to $SZ_L0, want $WANTMAX"
fi
if [ "$SZ_L" = "788x64" ]; then
    echo "OK: hints declared mid-state re-fitted the maximized window ($SZ_L)"
else
    echo "FAIL: after its late hints the maximized client is $SZ_L, want 788x64\
 — held at a height its own hints forbid"
fi
if grep -q 'changed its size hints while maximized' "$HERE/wm-ewmhmax.log"; then
    echo "OK: ...and said so"
else
    echo "FAIL: no re-fit log line"
fi
if [ "$LLIVE" = "788x64" ]; then
    echo "OK: the client agrees it is 788x64 — the fight is over"
else
    echo "FAIL: the client's last word is $LLIVE, want 788x64"
fi
if grep -q 'handler error' "$HERE/wm-ewmhmax.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-ewmhmax.log"
fi
check_invariants "$HERE/wm-ewmhmax.log"
