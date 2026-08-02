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
# the edit door talks to the same daemon the buttons do — the server
# IS the addressing there, and this desk has only the one
set-emacs-edit-daemon emtest
action tg  {emacs {daemon emtest frame TELEGA eval {(setq tg-evaled 42)}
                   env {EMTEST via-env}} key {<Super>g}}
action tgt {emacs {daemon emtest frame TTYEM eval {(setq tty-evaled t)} via terminal} key {<Super>h}}
action pl  {emacs {frame PLAINF daemon none eval {(setq plain t)}} key {<Super>j}}
action na  {emacs {daemon ghostd frame GHOSTF autodaemon off} key {<Super>k}}
# the owner's pattern, said by hand: name the frame (which is what
# WM_CLASS is made from) and hand the TITLE straight back to emacs.
# The desk must still find the frame afterwards — by a handle its name
# cannot take away. Said by hand it is now a no-op twice over: the
# launch does the same thing on its own (see KEEPN below).
action nm  {emacs {daemon emtest frame NAMEBACK eval {(set-frame-name nil)}}
            key {<Super>y}}
# ...and the button that WANTS its word standing in the title.
action kf  {emacs {daemon emtest frame KEEPN keep-frame-name on} key {<Super>u}}
action eb  {launch {exec sh -c "printenv BENV > $::env(HOME)/../benv-out" &}
            env {BENV yes} key {<Super>l}}
panel-button tg
panel-button tgt
panel-button pl
panel-button na
panel-button eb
EOF

XDG_CONFIG_HOME="$HERE/emacs-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-emacs.log" 2>&1 &
WM=$!
sleep 1.5

key() { xdotool key "$@"; sleep 0.5; }
ec() { emacsclient -s emtest -e "$1" 2>/dev/null; }
q() { printf '%s\n' "$1" > "$HERE/emacs-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/emacs-config/q.tcl"; }
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
# WM_CLASS is written once and stays; the NAME is the title, and the
# launch gives that back to emacs unless the button says otherwise.
GNAME=$(ec '(frame-parameter (seq-find (lambda (f) (equal (frame-parameter f (quote tk9wm-frame)) "TELEGA")) (frame-list)) (quote name))')
ec '(setq tg-evaled 0)' >/dev/null   # the frame wandered off...
key super+g            # must FIND now, not launch again — and RE-EVAL
sleep 2
GEVAL2=$(ec 'tg-evaled')

echo "--- terminal path"
# Found by tk9wm-frame throughout, never by name: the launch hands the
# frame's name back to emacs by default now (set-emacs-keep-frame-name
# off), and the parameter is the handle that survives that.
key super+h
wait_for 20 sh -c 'ec() { emacsclient -s emtest -e "$1" 2>/dev/null; }; [ "$(ec "(and (seq-find (lambda (f) (equal (frame-parameter f (quote tk9wm-frame)) \"TTYEM\")) (frame-list)) t)")" = t ]' \
    || echo "note: wait for tty frame ran out"
sleep 1
ec '(setq tty-evaled 0)' >/dev/null
key super+h            # hit: focus the xterm, background-raise TTYEM + re-eval
wait_for 10 grep -q 'verdict: "raised"' "$HERE/wm-emacs.log" \
    || echo "note: wait for the raised verdict ran out"
sleep 0.5
TEVAL2=$(ec 'tty-evaled')

echo "--- the C-x 5 2 scenario: another frame in, TTYEM out"
ec '(let ((f (seq-find (lambda (f) (equal (frame-parameter f (quote tk9wm-frame)) "TTYEM")) (frame-list))))
      (make-frame (list (cons (quote terminal) (frame-terminal f)) (cons (quote name) "BEE"))) t)' >/dev/null
ec '(progn (delete-frame (seq-find (lambda (f) (equal (frame-parameter f (quote tk9wm-frame)) "TTYEM")) (frame-list))) t)' >/dev/null
ec '(setq tty-evaled nil)' >/dev/null
sleep 1
key super+h            # hit again: must REBUILD the named frame
wait_for 10 grep -q 'verdict: "rebuilt"' "$HERE/wm-emacs.log" \
    || echo "note: wait for the rebuilt verdict ran out"
sleep 0.5
REBUILT=$(ec '(and (seq-find (lambda (f) (equal (frame-parameter f (quote tk9wm-frame)) "TTYEM")) (frame-list)) t)')
# ON TOP means the very frame we found is the one the terminal shows —
# an identity, not a name to match: the frame stopped wearing the
# button's word the moment the rebuild handed its title back.
TOP=$(ec '(let ((f (seq-find (lambda (x) (equal (frame-parameter x (quote tk9wm-frame)) "TTYEM")) (frame-list))))
            (and f (eq f (tty-top-frame (frame-terminal f))) t))')
TOPWHO=$(ec '(let ((f (seq-find (lambda (x) (equal (frame-parameter x (quote tk9wm-frame)) "TTYEM")) (frame-list))))
            (and f (list (frame-parameter (tty-top-frame (frame-terminal f)) (quote name))
                         (frame-parameter (tty-top-frame (frame-terminal f)) (quote tk9wm-frame))
                         (frame-parameter f (quote name)))))')
REEVAL=$(ec 'tty-evaled')
GEVAL=$(ec 'tg-evaled')
DENV=$(ec '(getenv "EMTEST")')

echo "--- a frame that gave its name back"
key super+y
wait_for 20 sh -c 'ec() { emacsclient -s emtest -e "$1" 2>/dev/null; }; [ "$(ec "(and (seq-find (lambda (f) (equal (frame-parameter f (quote tk9wm-frame)) \"NAMEBACK\")) (frame-list)) t)")" = t ]' \
    || echo "note: wait for the renamed frame ran out"
sleep 1
NMNAME=$(ec '(frame-parameter (seq-find (lambda (f) (equal (frame-parameter f (quote tk9wm-frame)) "NAMEBACK")) (frame-list)) (quote name))')
NMCOUNT0=$(ec '(length (frame-list))')
key super+y            # the second hit must RAISE it, not build another
sleep 2
NMCOUNT1=$(ec '(length (frame-list))')
NMVERDICT=$(grep -c 'verdict: "gui"' "$HERE/wm-emacs.log")

echo "--- a button that keeps its name"
key super+u
wait_for 20 xdotool search --classname '^KEEPN$'
sleep 1
KFCLS=$(xprop -id "$(xdotool search --classname '^KEEPN$' | head -1)" WM_CLASS 2>/dev/null | sed 's/.*= //')
KFNAME=$(ec '(frame-parameter (seq-find (lambda (f) (equal (frame-parameter f (quote tk9wm-frame)) "KEEPN")) (frame-list)) (quote name))')

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

# THE EDIT DOOR — the other emacs verb. Not an identity: any frame of
# the right server will do, and the only question is whether the file
# lands in one that stands or in a fresh one. Driven through the proc
# the configurator's «in emacs» is bound to.
echo "--- the edit door: reuse, then create"
printf 'one\ntwo\nthree\n' > "$HERE/emacs-config/reused.txt"
printf 'one\ntwo\nthree\n' > "$HERE/emacs-config/fresh.txt"
FRAMES0=$(ec '(length (frame-list))')
q "edit-place emacs $HERE/emacs-config/reused.txt 2" >/dev/null
sleep 2
EDIT1=$(ec '(and (get-file-buffer "'"$HERE"'/emacs-config/reused.txt") t)')
FRAMES1=$(ec '(length (frame-list))')
q 'set-emacs-edit create' >/dev/null
q "edit-place emacs $HERE/emacs-config/fresh.txt 3" >/dev/null
sleep 2
EDIT2=$(ec '(and (get-file-buffer "'"$HERE"'/emacs-config/fresh.txt") t)')
FRAMES2=$(ec '(length (frame-list))')

# ...and the same door in terminal mode, where reuse cannot be an
# emacsclient flag: a terminal window is found by its WM_CLASS
# instance, so the desk keeps ONE editing terminal and knows its name
# (the daemon's name is in it — two servers must not share a window).
# The first edit builds it; the second must find it and put the file
# in the frame inside, which only the daemon can do.
echo "--- the edit door in a terminal"
printf 'one\ntwo\nthree\n' > "$HERE/emacs-config/tty1.txt"
printf 'one\ntwo\nthree\n' > "$HERE/emacs-config/tty2.txt"
q 'set-emacs-frames terminal' >/dev/null
q 'set-emacs-edit reuse' >/dev/null
q "edit-place emacs $HERE/emacs-config/tty1.txt 2" >/dev/null
wait_for 20 xdotool search --classname '^emacs-tk9wm-emtest$' \
    || echo "note: wait for the editing terminal ran out"
sleep 2
TEDIT1=$(ec '(and (get-file-buffer "'"$HERE"'/emacs-config/tty1.txt") t)')
q "edit-place emacs $HERE/emacs-config/tty2.txt 3" >/dev/null
wait_for 15 grep -q 'verdict: "edited"' "$HERE/wm-emacs.log" \
    || echo "note: wait for the edited verdict ran out"
sleep 1
TEDIT2=$(ec '(and (get-file-buffer "'"$HERE"'/emacs-config/tty2.txt") t)')
TWINS=$(xdotool search --classname '^emacs-tk9wm-emtest$' | wc -l)

ec '(kill-emacs)' >/dev/null 2>&1
xdotool windowkill "$PID2" 2>/dev/null
kill $WM 2>/dev/null

echo "--- emacs lines:"
grep -E 'emacs|action t' "$HERE/wm-emacs.log"
echo "--- name-back: name={$NMNAME} frames $NMCOUNT0 -> $NMCOUNT1 gui-verdicts=$NMVERDICT"
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
if grep -q 'action tg: found' "$HERE/wm-emacs.log"; then
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
if [ "$REBUILT" = t ] && [ "$TOP" = t ]; then
    echo "OK: the named frame is back and on top of its tty"
else
    echo "FAIL: rebuilt=$REBUILT top=$TOP (top frame / ours: $TOPWHO)"
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
if grep -q 'action pl: found' "$HERE/wm-emacs.log"; then
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

if [ "$NMCOUNT0" = "$NMCOUNT1" ] && [ "$NMVERDICT" -ge 1 ] \
        && [ "$NMNAME" != '"NAMEBACK"' ]; then
    echo "OK: a frame that gave its name back is still found, and raised not rebuilt"
else
    echo "FAIL: name-back: name=$NMNAME frames $NMCOUNT0 -> $NMCOUNT1,\
 gui verdicts $NMVERDICT"
fi
if [ "$GNAME" != '"TELEGA"' ]; then
    echo "OK: the launch handed the title back on its own (name=$GNAME)"
else
    echo "FAIL: the gui frame still wears the button's word as its title"
fi
if [ "$KFNAME" = '"KEEPN"' ] && [ "$KFCLS" = '"KEEPN", "Emacs"' ]; then
    echo "OK: keep-frame-name on left the word standing in the title"
else
    echo "FAIL: keep-frame-name on: name=$KFNAME class=$KFCLS"
fi
echo "--- edit door: frames $FRAMES0 -> $FRAMES1 -> $FRAMES2,\
 visited $EDIT1 / $EDIT2"
if [ "$EDIT1" = t ] && [ "$FRAMES1" = "$FRAMES0" ]; then
    echo "OK: reuse put the file in a frame that already stood"
else
    echo "FAIL: reuse: visited=$EDIT1, frames $FRAMES0 -> $FRAMES1"
fi
if [ "$EDIT2" = t ] && [ "$FRAMES2" -gt "$FRAMES1" ]; then
    echo "OK: create opened a frame of its own for the edit"
else
    echo "FAIL: create: visited=$EDIT2, frames $FRAMES1 -> $FRAMES2"
fi
echo "--- edit door in a terminal: visited $TEDIT1 / $TEDIT2,\
 windows named for the server: $TWINS"
if [ "$TEDIT1" = t ] && [ "$TEDIT2" = t ] && [ "$TWINS" = 1 ] \
        && grep -q 'emacs: verdict: "edited"' "$HERE/wm-emacs.log"; then
    echo "OK: one editing terminal, and the second file went into it"
else
    echo "FAIL: terminal door: $TEDIT1 / $TEDIT2, windows $TWINS"
fi
