#!/bin/sh
# Regression for the terminal layer: a semantic `terminal` button —
# match and launch derived from {name run ...}, the beast-keyed args
# branches (the active beast's applied, the foreign one not), env
# reaching the terminal's child, the title flag, the nameless
# `terminal {}` button matching a terminal it did not launch, and the
# `needs` gate skipping a button whose command does not exist.
. "$(dirname "$0")/common.sh"
export DISPLAY=:91
rm -f /tmp/.X91-lock /tmp/.X11-unix/X91
Xvfb :91 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/terminal-config"
mkdir -p "$HERE/terminal-config"
cat > "$HERE/terminal-config/tk9wm.tcl" <<'EOF'
set-terminal xterm
action mutt {
    terminal {
        name muttx
        title "именованный терминал"
        env {TERMTEST env-arrived}
        run {sh -c "printenv TERMTEST > __HERE__/terminal-config/envout; exec sleep 30"}
        args {xterm {-bg #223344} kitty {--utterly-bogus-flag}}
    }
    key {<Super>m}
}
action anyterm {terminal {} key {<Super>n}}
action ghost {launch {exec sleep 30 &} needs no-such-cmd-xyzzy}
panel-button mutt
panel-button anyterm
panel-button ghost
EOF
sed -i "s|__HERE__|$HERE|" "$HERE/terminal-config/tk9wm.tcl"

XDG_CONFIG_HOME="$HERE/terminal-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-terminal.log" 2>&1 &
WM=$!
sleep 1.5

key() { xdotool key "$@"; sleep 0.5; }

key super+m            # nothing matches -> spawn xterm -name muttx
sleep 2                # xterm comes up and is managed
key super+m            # the derived match finds it on real WM_CLASS
key super+n            # the nameless button: same window, other predicate

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
