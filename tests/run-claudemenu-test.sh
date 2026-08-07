#!/bin/sh
# Regression for the claude-projects model task — the example in
# default-config.tcl, verbatim: a dynamic menu built by parsing
# ~/.claude.json with tcllib's vendored json, ordered by the newest
# session transcript under ~/.claude/projects/<slug>/, Return firing
# a fresh `claude` in the project's own terminal and Shift-Return a
# `claude --continue`, both through the same run-or-raise spec.
#
# The HOME the desk sees is a fixture: four projects in
# .claude.json, three with transcripts at staggered mtimes (the
# dotted path proves the slug turns EVERY non-alphanumeric to a
# dash), one with none — a project that never held a session is not
# recent, and drops out.
. "$(dirname "$0")/common.sh"
start_xvfb

key() { xdotool key "$@"; sleep 1; }

FIXHOME="$HERE/claudemenu-home"
rm -rf "$FIXHOME"; mkdir -p "$FIXHOME/.claude/projects"
cat > "$FIXHOME/.claude.json" <<'EOF'
{"numStartups": 7, "projects": {
    "/home/u/alpha":     {"lastCost": 0},
    "/home/u/beta.dot":  {},
    "/home/u/gamma":     {},
    "/home/u/nosession": {}
}}
EOF
for slug in -home-u-alpha -home-u-beta-dot -home-u-gamma; do
    mkdir -p "$FIXHOME/.claude/projects/$slug"
done
touch -d 2026-01-01 "$FIXHOME/.claude/projects/-home-u-alpha/s1.jsonl"
touch -d 2026-03-03 "$FIXHOME/.claude/projects/-home-u-beta-dot/s1.jsonl"
touch -d 2026-02-02 "$FIXHOME/.claude/projects/-home-u-gamma/s1.jsonl"
touch -d 2026-02-15 "$FIXHOME/.claude/projects/-home-u-gamma/s2.jsonl"

# The config is the model task from default-config.tcl, word for word.
CONF="$HERE/claudemenu-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
proc claude-recent-projects {{n 12}} {
    package require json
    set ch [open [file join $::env(HOME) .claude.json] r]
    set cfg [json::json2dict [read $ch]]
    close $ch
    set stamped {}
    foreach dir [dict keys [dict getdef $cfg projects {}]] {
        set slug [regsub -all {[^A-Za-z0-9]} $dir -]
        set newest 0
        foreach f [glob -nocomplain -directory [file join \
                $::env(HOME) .claude projects $slug] *.jsonl] {
            set m [file mtime $f]
            if {$m > $newest} { set newest $m }
        }
        if {$newest} { lappend stamped [list $newest $dir] }
    }
    set out {}
    foreach p [lrange [lsort -integer -decreasing -index 0 \
                           $stamped] 0 [expr {$n - 1}]] {
        lappend out [lindex $p 1]
    }
    return $out
}
proc claude-items {} {
    set items {}
    foreach dir [claude-recent-projects] {
        set slug [regsub -all {[^A-Za-z0-9]} $dir _]
        set t [list terminal [list name claude_$slug] dir $dir]
        lappend items [list \
            label [string map [list $::env(HOME) ~] $dir] \
            do       [list Fire [concat $t {run claude}]] \
            shift-do [list Fire [concat $t {run {claude --continue}}]]]
    }
    return $items
}
wm-menu claude {key {<Super>t p} body {claude-items}}
EOF

HOME="$FIXHOME" XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-claudemenu.log" 2>&1 &
WM=$!
sleep 2

# ---- Return: a fresh session in the freshest project
key super+t
key p
key Return
# ---- Shift-Return: continue, same row, same spec
key super+t
key p
key shift+Return
# ---- the order is the transcripts': gamma second by its newest file
key super+t
key p
key 2
key super+t
key p
key Escape
sleep 1

kill $WM 2>/dev/null
sleep 0.3

echo "--- WM saw:"
grep -E 'WM: menu claude|WM: terminal: spawn' "$HERE/wm-claudemenu.log"

echo "--- verdict"
BAD=0
if grep -q 'BadAccess request=2' "$HERE/wm-claudemenu.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"; BAD=1
fi
if grep -q 'soft failure\|handler error\|WM: PROBLEM' "$HERE/wm-claudemenu.log"; then
    echo "FAIL: soft failures, handler errors or problems:"
    grep 'soft failure\|handler error\|WM: PROBLEM' "$HERE/wm-claudemenu.log"; BAD=1
fi

OPENS=$(grep -c 'WM: menu claude open (3 items)' "$HERE/wm-claudemenu.log")
if [ "$OPENS" = "4" ]; then
    echo "OK: three rows of four projects — the one with no session dropped out"
else
    echo "FAIL: the menu opened with 3 rows $OPENS times, want 4"; BAD=1
fi
if grep -q 'WM: menu claude pick «/home/u/beta.dot»$' "$HERE/wm-claudemenu.log"; then
    echo "OK: the freshest transcript put beta.dot first, and Return picked it plain"
else
    echo "FAIL: beta.dot was not first, or the plain pick is missing"; BAD=1
fi
if grep -q 'WM: menu claude pick «/home/u/beta.dot» (shift)' "$HERE/wm-claudemenu.log"; then
    echo "OK: Shift-Return took the same row's other reading"
else
    echo "FAIL: the shifted pick on beta.dot is missing"; BAD=1
fi
if grep -q 'WM: terminal: spawn .*-name claude__home_u_beta_dot .*env -C /home/u/beta.dot claude$' \
        "$HERE/wm-claudemenu.log"; then
    echo "OK: the fresh leg spawned claude in the project's named terminal and directory"
else
    echo "FAIL: the fresh spawn line is missing or malformed"; BAD=1
fi
if grep -q 'WM: terminal: spawn .*env -C /home/u/beta.dot claude --continue$' \
        "$HERE/wm-claudemenu.log"; then
    echo "OK: the shift leg spawned claude --continue in the same place"
else
    echo "FAIL: the --continue spawn line is missing"; BAD=1
fi
if grep -q 'WM: menu claude pick «/home/u/gamma»' "$HERE/wm-claudemenu.log"; then
    echo "OK: gamma stands second by its newest transcript, above the older alpha"
else
    echo "FAIL: row 2 was not gamma"; BAD=1
fi
check_invariants "$HERE/wm-claudemenu.log"
if grep -q 'WM: INVARIANT' "$HERE/wm-claudemenu.log"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: the model task reads recency where it lives and fires both readings"
exit $BAD
