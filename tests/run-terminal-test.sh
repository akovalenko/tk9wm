#!/bin/sh
# Regression for the terminal layer: a semantic `terminal` button —
# match derived from the terminal's name and the launch from the
# action's own run (which the terminal answers), the beast-keyed args
# branches (the active beast's applied, the foreign one not), env
# reaching the terminal's child, the title flag, the nameless
# `terminal {}` button matching a terminal it did not launch, and the
# `needs` gate skipping a button whose command does not exist.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/terminal-config"
mkdir -p "$HERE/terminal-config"
cat > "$HERE/terminal-config/tk9wm.tcl" <<'EOF'
set-terminal xterm
action mutt {
    terminal {
        name muttx
        title "именованный терминал"
        env {TERMTEST env-arrived}
        args {xterm {-bg #223344} kitty {--utterly-bogus-flag}}
    }
    run {sh -c "printenv TERMTEST > __HERE__/terminal-config/envout; exec sleep 30"}
    key {<Super>m}
}
action anyterm {terminal {} key {<Super>n}}
action dirterm {terminal {name dirx} dir ~ key {<Super>d}}
action ghost {launch {Run sleep 30} needs no-such-cmd-xyzzy}
panel-button mutt
panel-button anyterm
panel-button ghost
EOF
sed -i "s|__HERE__|$HERE|" "$HERE/terminal-config/tk9wm.tcl"

XDG_CONFIG_HOME="$HERE/terminal-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-terminal.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-terminal.log" $WM

key() { xdotool key "$@"; sleep 0.5; }

key super+m            # nothing matches -> spawn xterm -name muttx
sleep 2                # xterm comes up and is managed
key super+m            # the derived match finds it on real WM_CLASS
key super+n            # the nameless button: same window, other predicate
key super+d            # run-less terminal with a dir: the emulator stands there

AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-terminal.log" | head -1)
CLS=$(xprop -id "$AID" WM_CLASS 2>/dev/null | sed 's/.*= //')
TTL=$(xprop -id "$AID" WM_NAME 2>/dev/null | sed 's/.*= //')

kill $WM 2>/dev/null

echo "--- actor: A=$AID class=$CLS title=$TTL"
echo "--- terminal lines:"
grep -E 'terminal|panel ' "$HERE/wm-terminal.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-terminal.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q 'panel default up (2 buttons' "$HERE/wm-terminal.log"; then
    echo "OK: two buttons on the strip — the ghost is not among them"
else
    echo "FAIL: want the panel up with exactly 2 buttons"
fi
if grep -q 'action ghost waits on no-such-cmd-xyzzy — the button stands by' "$HERE/wm-terminal.log"; then
    echo "OK: the needs gate said why the ghost is off"
else
    echo "FAIL: no stands-by line for the ghost"
fi
if grep -q 'terminal: xterm at .* (set-terminal)' "$HERE/wm-terminal.log"; then
    echo "OK: resolution took the config's word"
else
    echo "FAIL: no resolution line crediting set-terminal"
fi
SPAWN=$(grep 'terminal: spawn' "$HERE/wm-terminal.log" | head -1)
case $SPAWN in
    *"-name muttx"*) echo "OK: spawn carries -name muttx" ;;
    *) echo "FAIL: spawn line lacks -name muttx: $SPAWN" ;;
esac
case $SPAWN in
    *"-bg #223344"*) echo "OK: the xterm args branch applied" ;;
    *) echo "FAIL: spawn line lacks the xterm branch: $SPAWN" ;;
esac
case $SPAWN in
    *bogus*) echo "FAIL: the kitty branch leaked into an xterm spawn" ;;
    *) echo "OK: the kitty args branch stayed out" ;;
esac
case $SPAWN in
    "WM: terminal: spawn env TERMTEST=env-arrived"*) echo "OK: env prefixes the binary" ;;
    *) echo "FAIL: no env prefix up front: $SPAWN" ;;
esac
# xterm has no dir word of its own, so the dir lands as env -C around
# the emulator itself, with the ~ already a path
DSPAWN=$(grep 'terminal: spawn env -C' "$HERE/wm-terminal.log" | head -1)
case $DSPAWN in
    *"env -C $HOME "*"-name dirx"*)
        echo "OK: a run-less terminal stands in its dir — env -C, tilde expanded" ;;
    *) echo "FAIL: no env -C around the dirx spawn: $DSPAWN" ;;
esac
if [ "$CLS" = '"muttx", "XTerm"' ]; then
    echo "OK: the window wears {muttx XTerm}"
else
    echo "FAIL: WM_CLASS is $CLS, want {muttx XTerm}"
fi
if [ "$TTL" = '"именованный терминал"' ]; then
    echo "OK: the title flag reached the window"
else
    echo "FAIL: WM_NAME is $TTL"
fi
if grep -q "action mutt: found $AID" "$HERE/wm-terminal.log"; then
    echo "OK: the derived match found the named window"
else
    echo "FAIL: no found-line for the mutt button"
fi
if grep -q "action anyterm: found $AID" "$HERE/wm-terminal.log"; then
    echo "OK: the nameless button recognized a terminal it did not launch"
else
    echo "FAIL: no found-line for the anyterm button"
fi
if [ "$(cat "$HERE/terminal-config/envout" 2>/dev/null)" = "env-arrived" ]; then
    echo "OK: env reached the terminal's child"
else
    echo "FAIL: envout says '$(cat "$HERE/terminal-config/envout" 2>/dev/null)'"
fi
if grep -q 'handler error' "$HERE/wm-terminal.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-terminal.log"
fi
check_invariants "$HERE/wm-terminal.log"

# --- A DESK WITH NO EMULATOR AT ALL, which is the fresh machine and
#     the reason the terminal deed carries a need of its own: the
#     button used to be there and do nothing when pressed. It cannot
#     name what it needs (the emulator is DETECTED), so the desk names
#     the whole list it looked through. Driven by emptying the PATH,
#     which is what "this machine has none of them" looks like from
#     inside auto_execok.
BARELOG="$HERE/wm-noterminal.log"
rm -rf "$HERE/noterm-config"
mkdir -p "$HERE/noterm-config"
cat > "$HERE/noterm-config/tk9wm.tcl" <<'EOF'
action shell {terminal {}}
panel-button shell
EOF
XDG_CONFIG_HOME="$HERE/noterm-config" PATH=/var/empty \
    "$LINUX/whale" "$WMTCL" > "$BARELOG" 2>&1 &
BARE=$!
sleep 2
kill $BARE 2>/dev/null
sleep 0.5

echo "--- with an empty PATH:"
grep -E 'terminal:|action shell|panel default up' "$BARELOG"
if grep -q 'action shell waits on .* — the button stands by' "$BARELOG"; then
    echo "OK: with no emulator anywhere, the terminal button STANDS BY"
else
    echo "FAIL: the terminal button did not say it was waiting"
fi
if grep -qE 'action shell waits on .*(xterm|kitty)' "$BARELOG"; then
    echo "OK: ...and names what it looked through, since it cannot name one"
else
    echo "FAIL: the stands-by line does not say what it wanted"
fi
# ...and with that one button standing by there is nothing left to put
# on a strip, so the desk reserves no band at all — the honest end of
# "a button that would do nothing is not drawn".
if grep -qE 'panel default up \([1-9]' "$BARELOG"; then
    echo "FAIL: the button is on the strip after all:\
 $(grep 'panel default up' "$BARELOG" | tail -1)"
else
    echo "OK: ...so nothing is drawn that would do nothing, and with the\
 only button waiting the desk reserves no strip at all"
fi
check_invariants "$BARELOG"
