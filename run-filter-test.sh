#!/bin/sh
# Regression for filter — the declarative match predicate: glob
# comparisons (whole-string, case-sensitive) over -title / -class /
# -command / -machine, the -nocase opt-in, the -regexp comparator swap
# with (?i) per-pattern nocase, single-vs-positional -class patterns
# (including the case drift that made nocase the wrong default:
# {ff XTerm} must NOT answer to `-class xterm`), absent-property-fails, the
# WM_COMMAND -> /proc argv fallback, and filter riding the real call
# sites (a wm-style rule and a panel-button match). The assertion
# battery runs IN-PROCESS (fired by a chord) against two live actors:
# an xterm that declares everything and a whale client that declares
# almost nothing.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:86
rm -f /tmp/.X86-lock /tmp/.X11-unix/X86
Xvfb :86 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/filter-config"
mkdir -p "$HERE/filter-config"
cat > "$HERE/filter-config/tk9wm.tcl" <<'EOF'
# actors: xt = the xterm (declares class/command/machine/pid),
# tk = the whale demo client (declares WM_CLASS and little else)
proc find-by-title {glob} {
    foreach w [array names ::frameof] {
        if {[string match $glob [client-title $w]]} { return $w }
    }
    return 0
}
# clients write gethostname() — the kernel name, not Tcl's possibly
# /etc/hosts-canonicalized [info hostname]
proc host-pat {} {
    set h [info hostname]
    catch {
        set f [open /proc/sys/kernel/hostname r]
        set h [string trim [read $f]]
        close $f
    }
    return "[lindex [split $h .] 0]*"
}
proc filter-battery {name cases} {
    set xt [find-by-title "Browser Window"]
    set tk [find-by-title "проба*"]
    if {$xt == 0 || $tk == 0} {
        puts "FILTER FAIL: actors missing (xt=$xt tk=$tk)"
        return
    }
    puts "FILTER DEBUG: host=[info hostname]\
 xt-machine=[client-machine $xt] xt-command=[client-command $xt]\
 tk-machine=[client-machine $tk] tk-pid=[client-pid $tk]"
    set n 0
    foreach {desc want script} $cases {
        if {[catch {eval $script} got]} { set got "ERR: $got" }
        if {$got eq $want} {
            puts "FILTER PASS: $desc"
        } else {
            puts "FILTER FAIL: $desc (want $want, got $got)"
        }
        incr n
    }
    puts "FILTER BATTERY $name: $n checks"
}
set main_cases {
    {single -class token hits the instance slot}   1 {filter -class ff $xt}
    {single -class token hits the class slot}      1 {filter -class XTerm* $xt}
    {two -class patterns positional as xprop}      1 {filter -class {ff XTerm} $xt}
    {two -class patterns crossed fails}            0 {filter -class {XTerm ff} $xt}
    {-class is case-sensitive}                     0 {filter -class FF $xt}
    {the drift that cost more than it paid}        0 {filter -class xterm $xt}
    {-nocase brings the drift tolerance back}      1 {filter -nocase -class xterm $xt}
    {-title glob}                                  1 {filter -title {Browser*} $xt}
    {-title glob is whole-string}                  0 {filter -title Browser $xt}
    {-title is case-sensitive}                     0 {filter -title {browser window} $xt}
    {-nocase covers -title too}                    1 {filter -nocase -title {browser window} $xt}
    {two options AND}                              1 {filter -class ff -title {Browser*} $xt}
    {AND fails on one leg}                         0 {filter -class ff -title {nope*} $xt}
    {-command via WM_COMMAND}                      1 {filter -command {*xterm*} $xt}
    {-machine glob}                                1 {filter -machine [host-pat] $xt}
    {-command absent everywhere fails}             0 {filter -command * $tk}
    {-machine absent fails}                        0 {filter -machine * $tk}
    {-regexp comparator}                           1 {filter -regexp -title {^Browser} $xt}
    {-regexp is case-sensitive too}                0 {filter -regexp -title {^browser} $xt}
    {-regexp (?i) opts one pattern into nocase}    1 {filter -regexp -title {(?i)^browser} $xt}
    {-nocase and -regexp compose}                  1 {filter -nocase -regexp -title {^browser} $xt}
    {-regexp alternation covers the OR niche}      1 {filter -regexp -class {XTerm|nosuch} $xt}
    {unknown option errors out}                    1 {catch {filter -bogus x $xt}}
    {no options match everything}                  1 {filter $xt}
    {whale client class positional}                1 {filter -class {client.tcl Client.tcl} $tk}
    {cyrillic title glob}                          1 {filter -title {проба*} $tk}
    {wm-style rule with filter applied}       ignore {dict get [style-of $xt] increments}
    {wm-style rule left the whale client alone} respect {dict get [style-of $tk] increments}
}
set fallback_cases {
    {-command falls back to /proc argv}            1 {filter -command {*client.tcl*} $tk}
    {-machine present after decoration}            1 {filter -machine [host-pat] $tk}
    {-command fallback is still whole-string}      0 {filter -command client.tcl $tk}
}
wm-bind {<Super>f} {filter-battery main $::main_cases}
wm-bind {<Super>g} {filter-battery fallback $::fallback_cases}
wm-style {filter -class {ff *}} {increments ignore}
panel-button тест {
    match {filter -title "Browser*"}
    key {<Super>z}
}
EOF

XDG_CONFIG_HOME="$HERE/filter-config" \
    "$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-filter.log" 2>&1 &
WM=$!
sleep 1.5

xterm -name ff -title "Browser Window" -e sleep 60 &
XTPID=$!
"$LINUX/whale" "$HERE/client.tcl" проба-фильтра 240x120 "#729fcf" "" "" 30 &
TKPID=$!
sleep 1.5

key() { xdotool key "$@"; sleep 0.5; }

key super+f            # the main battery, pre-decoration

# hand the whale client the pid+machine it never declared, so
# client-cmdline can vouch for it — the -command fallback leg
set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-filter.log")
XTW=$1; TKW=$2
xprop -id "$TKW" -f _NET_WM_PID 32c -set _NET_WM_PID "$TKPID"
xprop -id "$TKW" -f WM_CLIENT_MACHINE 8s -set WM_CLIENT_MACHINE "$(hostname)"
sleep 0.5

key super+g            # the fallback battery
key super+z            # the panel button matches the xterm via filter

kill $WM $XTPID $TKPID 2>/dev/null

echo "--- actors: xterm=$XTW whale=$TKW"
echo "--- battery lines:"
grep -E 'FILTER|panel ' "$HERE/wm-filter.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-filter.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q 'FILTER FAIL' "$HERE/wm-filter.log"; then
    echo "FAIL: battery failures present (above)"
else
    echo "OK: no battery failures"
fi
PASS=$(grep -c 'FILTER PASS' "$HERE/wm-filter.log")
if [ "$PASS" = 31 ]; then
    echo "OK: all 31 checks passed"
else
    echo "FAIL: $PASS PASS lines, want 31"
fi
if grep -q 'FILTER BATTERY main: 28 checks' "$HERE/wm-filter.log" \
   && grep -q 'FILTER BATTERY fallback: 3 checks' "$HERE/wm-filter.log"; then
    echo "OK: both batteries ran to completion"
else
    echo "FAIL: a battery is missing or truncated"
fi
if grep -q "panel тест: found $XTW" "$HERE/wm-filter.log"; then
    echo "OK: the panel button found the xterm through filter"
else
    echo "FAIL: no panel found-line for $XTW"
fi
if grep -q 'handler error' "$HERE/wm-filter.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-filter.log"
fi
