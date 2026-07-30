#!/bin/sh
# Regression for the emacs layer: a semantic emacs button — the gui
# path (daemon auto-started, frame named TELEGA = WM_CLASS instance,
# eval landed, second fire finds instead of launching) and the
# terminal path (named terminal running emacsclient -t -F, a hit
# raises the named tty frame, and after the C-x 5 2 scenario — the
# named frame closed, another one left — the fire REBUILDS it on the
# live terminal, re-running the eval).
. "$(dirname "$0")/common.sh"
export DISPLAY=:92
rm -f /tmp/.X92-lock /tmp/.X11-unix/X92
Xvfb :92 -screen 0 1024x768x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/emacs-config"
mkdir -p "$HERE/emacs-config/home" "$HERE/emacs-config/rt"
chmod 700 "$HERE/emacs-config/rt"
export HOME="$HERE/emacs-config/home"
export XDG_RUNTIME_DIR="$HERE/emacs-config/rt"
cat > "$HERE/emacs-config/tk9wm.tcl" <<'EOF'
set-terminal xterm
panel-button tg  {emacs {daemon emtest frame TELEGA eval {(setq tg-evaled 42)}} key {<Super>g}}
panel-button tgt {emacs {daemon emtest frame TTYEM eval {(setq tty-evaled t)} via terminal} key {<Super>h}}
EOF

XDG_CONFIG_HOME="$HERE/emacs-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-emacs.log" 2>&1 &
WM=$!
sleep 1.5

key() { xdotool key "$@"; sleep 0.5; }
ec() { emacsclient -s emtest -e "$1" 2>/dev/null; }
wait_for() { # wait_for SECONDS CMD... — poll until CMD succeeds
    n=$(( $1 * 2 )); shift
    while [ $n -gt 0 ]; do "$@" >/dev/null 2>&1 && return 0; sleep 0.5; n=$((n-1)); done
    return 1
}

echo "--- gui path"
key super+g
wait_for 20 sh -c 'grep -q "managed.*TELEGA" '"$HERE"'/wm-emacs.log || xdotool search --classname "^TELEGA$"' \
    || echo "note: wait for gui frame ran out"
sleep 1
GID=$(xdotool search --classname '^TELEGA$' | head -1)
GCLS=$(xprop -id "$GID" WM_CLASS 2>/dev/null | sed 's/.*= //')
ec '(setq tg-evaled 0)' >/dev/null   # the frame wandered off...
key super+g            # must FIND now, not launch again — and RE-EVAL
sleep 2
GEVAL2=$(ec 'tg-evaled')

echo "--- terminal path"
key super+h
wait_for 20 sh -c 'ec() { emacsclient -s emtest -e "$1" 2>/dev/null; }; [ "$(ec "(and (seq-find (lambda (f) (equal (frame-parameter f (quote name)) \"TTYEM\")) (frame-list)) t)")" = t ]' \
    || echo "note: wait for tty frame ran out"
sleep 1
ec '(setq tty-evaled 0)' >/dev/null
key super+h            # hit: focus the xterm, background-raise TTYEM + re-eval
wait_for 10 grep -q 'verdict: "raised"' "$HERE/wm-emacs.log" \
    || echo "note: wait for the raised verdict ran out"
sleep 0.5
TEVAL2=$(ec 'tty-evaled')

echo "--- the C-x 5 2 scenario: another frame in, TTYEM out"
ec '(let ((f (seq-find (lambda (f) (equal (frame-parameter f (quote name)) "TTYEM")) (frame-list))))
      (make-frame (list (cons (quote terminal) (frame-terminal f)) (cons (quote name) "BEE"))) t)' >/dev/null
ec '(progn (delete-frame (seq-find (lambda (f) (equal (frame-parameter f (quote name)) "TTYEM")) (frame-list))) t)' >/dev/null
ec '(setq tty-evaled nil)' >/dev/null
sleep 1
key super+h            # hit again: must REBUILD the named frame
wait_for 10 grep -q 'verdict: "rebuilt"' "$HERE/wm-emacs.log" \
    || echo "note: wait for the rebuilt verdict ran out"
sleep 0.5
REBUILT=$(ec '(and (seq-find (lambda (f) (equal (frame-parameter f (quote name)) "TTYEM")) (frame-list)) t)')
TOP=$(ec '(frame-parameter (tty-top-frame (frame-terminal (seq-find (lambda (f) (frame-parameter f (quote tty))) (frame-list)))) (quote name))')
REEVAL=$(ec 'tty-evaled')
GEVAL=$(ec 'tg-evaled')

ec '(kill-emacs)' >/dev/null 2>&1
kill $WM 2>/dev/null

echo "--- emacs lines:"
grep -E 'emacs|panel t' "$HERE/wm-emacs.log"
echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-emacs.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ "$GCLS" = '"TELEGA", "Emacs"' ]; then
    echo "OK: the gui frame wears {TELEGA Emacs}"
else
    echo "FAIL: gui frame WM_CLASS is $GCLS"
fi
if [ "$GEVAL" = 42 ]; then
    echo "OK: the gui eval landed in the daemon"
else
    echo "FAIL: tg-evaled is $GEVAL, want 42"
fi
if [ "$GEVAL2" = 42 ]; then
    echo "OK: the gui HIT re-ran the eval (verdict gui)"
else
    echo "FAIL: after the gui hit tg-evaled is $GEVAL2, want 42 again"
fi
if [ "$TEVAL2" = t ]; then
    echo "OK: the raised tty hit re-ran the eval"
else
    echo "FAIL: after the tty hit tty-evaled is $TEVAL2, want t again"
fi
if [ "$(grep -c 'WM: emacs: launch' "$HERE/wm-emacs.log")" = 1 ]; then
    echo "OK: exactly one gui launch — the second fire found the frame"
else
    echo "FAIL: want exactly one gui launch line"
fi
if grep -q 'panel tg: found' "$HERE/wm-emacs.log"; then
    echo "OK: the gui hit was a find"
else
    echo "FAIL: no found-line for the gui button"
fi
if grep -q 'terminal: spawn.*-name TTYEM.*emacsclient' "$HERE/wm-emacs.log"; then
    echo "OK: the terminal path went through the terminal layer, named"
else
    echo "FAIL: no named-terminal spawn for the tty button"
fi
if grep -q 'emacs: verdict: "raised"' "$HERE/wm-emacs.log"; then
    echo "OK: the tty hit raised the named frame"
else
    echo "FAIL: no raised-verdict"
fi
if grep -q 'emacs: verdict: "rebuilt"' "$HERE/wm-emacs.log"; then
    echo "OK: the C-x 5 2 hole was repaired"
else
    echo "FAIL: no rebuilt-verdict"
fi
if [ "$REBUILT" = t ] && [ "$TOP" = '"TTYEM"' ]; then
    echo "OK: the named frame is back and on top of its tty"
else
    echo "FAIL: rebuilt=$REBUILT top=$TOP"
fi
if [ "$REEVAL" = t ]; then
    echo "OK: the rebuild re-ran the button's eval"
else
    echo "FAIL: tty-evaled after rebuild is $REEVAL"
fi
if grep -q 'handler error' "$HERE/wm-emacs.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-emacs.log"
fi
check_invariants "$HERE/wm-emacs.log"
