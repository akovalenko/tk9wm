#!/bin/sh
# Regression for the live WM_TRANSIENT_FOR re-read: a window that maps
# with no leader and aims itself at one AFTER mapping (PropertyNotify)
# must die like a dialog — focus returns to the leader, not to the
# most recently focused window. Actors, in manage order:
#   M (лидер)         the future leader
#   C (отвлекающее)   a distractor, focused between M and D
#   D (потом-диалог)  maps leaderless, becomes transient for M later
# D holds the focus when it dies; without the re-read the refocus pick
# falls back to the history and lands on C.
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$WMTCL" > "$HERE/wm-transient.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client-retrans.tcl" &
CP=$!
sleep 1
"$LINUX/whale" "$HERE/client.tcl" "отвлекающее" 240x120 "#fcaf3e" "" "" 30 &
CB=$!

wait $CP
kill $WM $CB 2>/dev/null

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-transient.log")
MID=$1; CID=$2; DID=$3
echo "--- actors: M=$MID C=$CID D=$DID"
echo "--- transient/focus lines:"
grep -E 'transient|focus ->|unmanaged' "$HERE/wm-transient.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-transient.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -z "$MID" ] || [ -z "$CID" ] || [ -z "$DID" ]; then
    echo "FAIL: missing actor ids (M=$MID C=$CID D=$DID)"
fi
if grep -q "transient $DID -> $MID" "$HERE/wm-transient.log"; then
    echo "OK: the late WM_TRANSIENT_FOR was re-read (D -> M)"
else
    echo "FAIL: no re-read line «transient $DID -> $MID»"
fi
# the first focus decision AFTER D's unmanage must pick the leader M
# (exit in a rule still runs END — the verdict must travel in a flag)
if awk -v d="$DID" -v m="$MID" '
    $0 ~ "unmanaged " d {u=1; next}
    u && /focus -> / {ok = ($NF == m); exit}
    END {exit !ok}' "$HERE/wm-transient.log"; then
    echo "OK: the dying dialog gave the focus back to its late leader"
else
    echo "FAIL: focus after D's death did not land on M"
fi
if grep -q 'handler error' "$HERE/wm-transient.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-transient.log"
fi
