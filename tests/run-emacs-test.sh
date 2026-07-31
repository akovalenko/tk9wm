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
panel-button tg  {emacs {daemon emtest frame TELEGA eval {(setq tg-evaled 42)}
                         env {EMTEST via-env}} key {<Super>g}}
panel-button tgt {emacs {daemon emtest frame TTYEM eval {(setq tty-evaled t)} via terminal} key {<Super>h}}
panel-button pl  {emacs {frame PLAINF daemon none eval {(setq plain t)}} key {<Super>j}}
panel-button na  {emacs {daemon ghostd frame GHOSTF autodaemon off} key {<Super>k}}
panel-button eb  {launch {exec sh -c "printenv BENV > $::env(HOME)/../benv-out" &}
                  env {BENV yes} key {<Super>l}}
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
DENV=$(ec '(getenv "EMTEST")')

echo "--- the plain life: daemon none"
key super+j
wait_for 20 xdotool search --classname '^PLAINF$'
sleep 1
PID2=$(xdotool search --classname '^PLAINF$' | head -1)
PCLS=$(xprop -id "$PID2" WM_CLASS 2>/dev/null | sed 's/.*= //')
key super+j            # must FIND, and stay silent toward any daemon

echo "--- autodaemon off on a dead socket"
key super+k
sleep 3
NASOCK=no
[ -e "$XDG_RUNTIME_DIR/emacs/ghostd" ] && NASOCK=yes

echo "--- a button's own env around a plain launch"
key super+l
sleep 1
BENV=$(cat "$HERE/emacs-config/benv-out" 2>/dev/null)

ec '(kill-emacs)' >/dev/null 2>&1
xdotool windowkill "$PID2" 2>/dev/null
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
if [ "$(grep -c 'WM: emacs: launch.*TELEGA' "$HERE/wm-emacs.log")" = 1 ]; then
    echo "OK: exactly one gui launch — the second fire found the frame"
else
    echo "FAIL: want exactly one TELEGA launch line"
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
if [ "$DENV" = '"via-env"' ]; then
    echo "OK: the auto-started daemon inherited the spec's env"
else
    echo "FAIL: EMTEST in the daemon is $DENV, want via-env"
fi
if [ "$PCLS" = '"PLAINF", "Emacs"' ]; then
    echo "OK: the plain-life button ran a bare emacs, named"
else
    echo "FAIL: plain frame WM_CLASS is $PCLS"
fi
if grep -q 'emacs: launch env.*emacsclient.*TELEGA' "$HERE/wm-emacs.log" \
        && grep -qE 'emacs: launch emacs --name PLAINF' "$HERE/wm-emacs.log"; then
    echo "OK: daemon launch went env+emacsclient, plain went bare emacs"
else
    echo "FAIL: launch lines do not show the two shapes"
fi
if grep -q 'panel pl: found' "$HERE/wm-emacs.log"; then
    echo "OK: the plain hit was a find (same match, no server talk)"
else
    echo "FAIL: no found-line for the plain button"
fi
if [ "$NASOCK" = no ] && grep -q "can't find socket" "$HERE/wm-emacs.log"; then
    echo "OK: autodaemon off left the dead socket dead, and the error is in the log"
else
    echo "FAIL: autodaemon off: socket spawned=$NASOCK"
fi
if [ "$BENV" = yes ]; then
    echo "OK: a button's env wrapped its plain launch"
else
    echo "FAIL: benv-out says '$BENV'"
fi
if grep -q 'handler error' "$HERE/wm-emacs.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-emacs.log"
fi
check_invariants "$HERE/wm-emacs.log"
