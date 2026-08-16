#!/bin/sh
# Regression for the visible title — the style key `title` and its
# published witness _NET_WM_VISIBLE_NAME:
#
#   статик   a literal-ish template {приб %% ит: %t} — checks the
#            replacement itself, %t expansion and %% escaping in one
#            string; the property must carry exactly the shown words
#   простой  no rule — the property must be ABSENT (EWMH: it stands
#            only while the shown name differs from the client's)
#   дин…     client-vtitle.tcl renames itself twice: first WITHIN the
#            rule's pattern (the rewrite must follow — the per-client
#            style cache must not have frozen the manage-time verdict)
#            and then AWAY from it (the rewrite lifts, the property
#            is deleted). Also the raw-matching rule: the rewritten
#            title «dyn: …» does not match the rule's own {дин *},
#            so a filter that saw the SHOWN title would drop the rule
#            after the first repaint — the second hop still being
#            rewritten proves filters keep matching the client's words.
. "$(dirname "$0")/common.sh"
start_xvfb
CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT
cat > "$CONF/tk9wm.tcl" <<'EOF'
wm-style {filter -title статик*} {title {приб %% ит: %t}}
wm-style {filter -title {дин *}} {title {dyn: %t}}
EOF

LOG="$HERE/wm-vtitle.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM

"$LINUX/whale" "$HERE/client.tcl" статик "" "" "" "" 40 \
    > "$HERE/vtitle-static.log" 2>&1 &
wait_client "$LOG" статик
"$LINUX/whale" "$HERE/client.tcl" простой "" "#8ae234" "" "" 40 \
    > "$HERE/vtitle-plain.log" 2>&1 &
wait_client "$LOG" простой
"$LINUX/whale" "$HERE/client-vtitle.tcl" > "$HERE/vtitle-dyn.log" 2>&1 &
wait_client "$LOG" "дин один"

# the ids, in manage order
set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG")
STATIC=$1; PLAIN=$2; DYN=$3

vname_is()     { xprop -id "$1" _NET_WM_VISIBLE_NAME | grep -qF "= \"$2\""; }
vname_absent() { xprop -id "$1" _NET_WM_VISIBLE_NAME | grep -q 'not found'; }
check_name() {  # label id want — poll, then say what actually stands
    if wait_for 10 vname_is "$2" "$3"; then
        echo "OK: $1 — «$3»"
    else
        echo "FAIL: $1 — want «$3», got: $(xprop -id "$2" _NET_WM_VISIBLE_NAME)"
    fi
}

echo "--- actors: static=$STATIC plain=$PLAIN dyn=$DYN"
echo "--- verdict"
if grep -q 'BadAccess request=2' "$LOG"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -z "$DYN" ]; then
    echo "FAIL: missing actor ids (got $*)"
fi

if xprop -root _NET_SUPPORTED | grep -q _NET_WM_VISIBLE_NAME; then
    echo "OK: _NET_WM_VISIBLE_NAME advertised in _NET_SUPPORTED"
else
    echo "FAIL: _NET_WM_VISIBLE_NAME missing from _NET_SUPPORTED"
fi

check_name "static template expanded (%t and %% both)" \
    "$STATIC" "приб % ит: статик"
if vname_absent "$PLAIN"; then
    echo "OK: unruled client carries no _NET_WM_VISIBLE_NAME"
else
    echo "FAIL: unruled client — $(xprop -id "$PLAIN" _NET_WM_VISIBLE_NAME)"
fi
check_name "dynamic rule at manage" "$DYN" "dyn: дин один"

# the client's first hop stays within the pattern: the rewrite follows
wait_client "$LOG" "дин два"
check_name "rewrite FOLLOWED the rename (cache not frozen; raw matched)" \
    "$DYN" "dyn: дин два"

# ...and the second leaves it: the rewrite lifts, the property goes
wait_client "$LOG" иное
if wait_for 10 vname_absent "$DYN"; then
    echo "OK: property deleted once the shown name matches the client's"
else
    echo "FAIL: stale property — $(xprop -id "$DYN" _NET_WM_VISIBLE_NAME)"
fi

import -display "$DISPLAY" -window root "$HERE/vtitle-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/vtitle-test.png"

if grep -q 'handler error' "$LOG"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$LOG"
fi
check_invariants "$LOG"
kill $WM 2>/dev/null
