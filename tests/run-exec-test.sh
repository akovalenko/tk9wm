#!/bin/sh
# Regression for running a process without holding the desk still.
#
# pipe-run is the workhorse: a future settling with {status out err},
# the pipeline read by the event loop, stdout and stderr kept apart
# when asked (the owner's ask, 2026-08-01 — whatever runs processes
# here has to be able to grow into a proper launcher). Exec is the
# same thing said the way one writes a script: it parks its coroutine
# instead of freezing the screen, so a config or a binding can say
#
#     Exec gpg --decrypt secrets.gpg | grep password:
#
# and the desk goes on answering while gpg thinks.
. "$(dirname "$0")/common.sh"
export DISPLAY=:55
rm -f /tmp/.X55-lock /tmp/.X11-unix/X55
Xvfb :55 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/exec-config"
mkdir -p "$HERE/exec-config"
echo '# the stock desk is what this measures' > "$HERE/exec-config/tk9wm.tcl"
XDG_CONFIG_HOME="$HERE/exec-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-exec.log" 2>&1 &
WM=$!
sleep 2
q() { printf '%s\n' "$1" > "$HERE/exec-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/exec-config/q.tcl"; }

STREAMS=$(q 'set f [pipe-run [list sh -c {echo to-out; echo to-err >&2; exit 3}] \
                 -stderr separate]
    wm-errand t1 {set ::t1 [fut::await $f]}
    after 500 {set ::w1 1}; vwait ::w1
    list out [string trim [dict get $::t1 out]] \
         err [string trim [dict get $::t1 err]] \
         status [dict get $::t1 status]')
MERGED=$(q 'set f [pipe-run [list sh -c {echo one; echo two >&2}] -stderr merge]
    wm-errand t2 {set ::t2 [fut::await $f]}
    after 500 {set ::w2 1}; vwait ::w2
    list out [lsort [split [string trim [dict get $::t2 out]] \n]] \
         err [dict get $::t2 err]')
# THE POINT: the desk keeps turning while the process thinks
TURNS=$(q 'set ::ticks 0
    proc tick {} {incr ::ticks; after 20 tick}
    tick
    wm-errand t3 {set ::t3 [Exec sh -c {sleep 0.4; echo hello}]}
    after 800 {set ::w3 1}; vwait ::w3
    list out $::t3 kept-turning [expr {$::ticks > 5}]')
FAILED=$(q 'wm-errand t4 {catch {Exec sh -c {echo nope >&2; exit 7}} ::t4}
    after 500 {set ::w4 1}; vwait ::w4
    set ::t4')
NOCORO=$(q 'catch {Exec true} e; string match {Exec needs a coroutine*} $e')
# a runaway is killed rather than waited for — emacs --daemon deciding
# to byte-compile at startup is allowed to be slow, not to be forever
# ...and the pid is asked about DIRECTLY: a pgrep for the command
# line finds the very shell asking the question (it did, first time
# round), while `kill -0` on the pid the pipeline reported cannot
TIMEOUT=$(q 'set f [pipe-run [list sleep 30] -timeout 300]
    set key [lindex [array names ::pipe_state] 0]
    set pid [lindex [dict get $::pipe_state($key) pids] 0]
    wm-errand t5 {catch {fut::await $f} ::t5 ::t5o
        set ::t5opts [dict get $::t5o -errorcode]}
    after 900 {set ::w5 1}; vwait ::w5
    list said [string match {timed out*} $::t5] \
         tailed [expr {[llength [lindex $::t5opts 2]] >= 0}] \
         gone [catch {exec kill -0 $pid}]')

# ---- and the word itself: `exec` IS the cooperative one, inside a
# coroutine, while keeping every promise the blocking one makes ----
SHIM=$(q 'set ::t6ticks 0
    proc tick6 {} {incr ::t6ticks; after 20 tick6}
    tick6
    wm-errand t6 {set ::t6 [exec sh -c {sleep 0.3; echo shimmed}]}
    after 700 {set ::w6 1}; vwait ::w6
    list out $::t6 kept-turning [expr {$::t6ticks > 5}]')
# ...the background form is not a thing to park on: it answers pids
BG=$(q 'wm-errand t7 {set ::t7 [exec sleep 5 &]}
    after 300 {set ::w7 1}; vwait ::w7
    list pids [llength $::t7] alive [expr {![catch {exec kill $::t7}]}]')
# ...stderr on a SUCCESSFUL run is an error, as it always was, unless
# the caller says otherwise
STDERR=$(q 'wm-errand t8 {
        catch {exec sh -c {echo out; echo grumble >&2}} ::t8a
        set ::t8b [exec -ignorestderr sh -c {echo out; echo grumble >&2}]
    }
    after 500 {set ::w8 1}; vwait ::w8
    list said $::t8a ignored $::t8b')
KEEPNL=$(q 'wm-errand t9 {
        set ::t9a [exec sh -c {echo line}]
        set ::t9b [exec -keepnewline sh -c {echo line}]
    }
    after 500 {set ::w9 1}; vwait ::w9
    list plain [string length $::t9a] kept [string length $::t9b]')

# ---- patience: say it is slow, and go on waiting ----
# Not every wait may end in a kill: `emacsclient -a ''` starts the
# daemon itself, so killing the client throws the answer away without
# stopping anything (the owner, 2026-08-01).
PATIENCE=$(q 'set ::said {}
    proc noted {ms tail} { set ::said [list $ms $tail] }
    set f [pipe-run [list sh -c {echo working; echo still >&2; sleep 1; echo done}] \
               -stderr merge -patience 300 -say [list noted]]
    wm-errand t10 {set ::t10 [fut::await $f]}
    after 1600 {set ::w10 1}; vwait ::w10
    list told [lindex $::said 0] tail [lindex $::said 1] \
         finished [string trim [dict get $::t10 out]] \
         status [dict get $::t10 status]')

kill $WM 2>/dev/null
sleep 0.5

echo "--- streams={$STREAMS} merged={$MERGED}"
echo "--- turns={$TURNS} failed={$FAILED} nocoro=$NOCORO timeout={$TIMEOUT}"
echo "--- shim={$SHIM} bg={$BG} stderr={$STDERR} keepnl={$KEEPNL}"
echo "--- patience={$PATIENCE}"
echo "--- verdict"
if [ "$STREAMS" = "out to-out err to-err status 3" ]; then
    echo "OK: stdout and stderr come back apart, and the status with them"
else
    echo "FAIL: streams: $STREAMS"
fi
if [ "$MERGED" = "out {one two} err {}" ]; then
    echo "OK: merged, both arrive on one stream"
else
    echo "FAIL: merged: $MERGED"
fi
if [ "$TURNS" = "out hello kept-turning 1" ]; then
    echo "OK: Exec returned its output AND the desk kept turning meanwhile"
else
    echo "FAIL: turns: $TURNS"
fi
if [ "$FAILED" = "nope" ]; then
    echo "OK: a failure carries what stderr said, not a number"
else
    echo "FAIL: failure said «$FAILED»"
fi
if [ "$NOCORO" = 1 ]; then
    echo "OK: outside a coroutine it says so instead of hanging"
else
    echo "FAIL: no-coroutine case: $NOCORO"
fi
if [ "$TIMEOUT" = "said 1 tailed 1 gone 1" ]; then
    echo "OK: a timeout cancels and kills, leaving nothing behind"
else
    echo "FAIL: timeout: $TIMEOUT"
fi
check_invariants "$HERE/wm-exec.log"

if [ "$SHIM" = "out shimmed kept-turning 1" ]; then
    echo "OK: exec itself is the cooperative one inside a coroutine"
else
    echo "FAIL: shim: $SHIM"
fi
if [ "$BG" = "pids 1 alive 1" ]; then
    echo "OK: ...and the background form still answers pids, waiting for nothing"
else
    echo "FAIL: background form: $BG"
fi
if [ "$STDERR" = "said grumble ignored out" ]; then
    echo "OK: stderr on a good run is an error, and -ignorestderr still says no"
else
    echo "FAIL: stderr contract: $STDERR"
fi
if [ "$KEEPNL" = "plain 4 kept 5" ]; then
    echo "OK: -keepnewline keeps what the plain form drops"
else
    echo "FAIL: keepnewline: $KEEPNL"
fi

case $PATIENCE in
    "told 300 tail {working still} finished {working"*"done} status 0")
        echo "OK: patience said its piece with the tail, and the wait went on" ;;
    *) echo "FAIL: patience: $PATIENCE" ;;
esac
