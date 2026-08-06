#!/bin/sh
# Regression for the telega-recipients model task — the example in
# default-config.tcl, verbatim, against a FAKE emacsclient planted
# ahead on PATH: it logs every call and answers getTopChats with a
# canned two-chat list wearing the real shapes (nested plists, a
# propertized title, a vector of positions, 64-bit and negative
# ids). What is proved: the menu body asks the daemon at open time
# through Exec, elisp-read projects the answer into rows, a pick
# fires the inline emacs spec — and the launch leg carries the
# daemon's socket, the TELEGA frame and the chat-opening eval with
# the picked id baked in.
. "$(dirname "$0")/common.sh"
export DISPLAY=:107
rm -f /tmp/.X107-lock /tmp/.X11-unix/X107
Xvfb :107 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

key() { xdotool key "$@"; sleep 1; }

FIXBIN="$HERE/telega-bin"
rm -rf "$FIXBIN"; mkdir -p "$FIXBIN"
rm -f "$HERE/telega-calls.log"
cat > "$FIXBIN/emacsclient" <<EOF
#!/bin/sh
echo "\$*" >> "$HERE/telega-calls.log"
case "\$*" in
*getTopChats*)
cat <<'ANS'
((:@type "chat" :id 880396138110181 :type (:@type "chatTypePrivate" :user_id 88039613) :title #("Вася Пупкин" 0 4 (face telega-msg-heading)) :positions [(:@type "chatPosition" :order "691")] :unread_count 3) (:@type "chat" :id -1001234567890 :type (:@type "chatTypeSupergroup" :supergroup_id 1234567890) :title "рабочий чат" :positions []))
ANS
;;
*) echo nil ;;
esac
EOF
chmod +x "$FIXBIN/emacsclient"

# The config is the model task from default-config.tcl, word for word.
CONF="$HERE/telega-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
proc telega-chats {} {
    set out [Exec emacsclient -s telega --eval \
                 {(telega--getTopChats "Users" 12)}]
    set items {}
    foreach chat [elisp-read $out] {
        lappend items [list label [dict get $chat :title] \
            do [list telega-open [dict get $chat :id]]]
    }
    return $items
}
proc telega-open {id} {
    Fire [list emacs [list daemon telega frame TELEGA eval \
        "(telega-chat--pop-to-buffer (telega-chat-get $id))"]]
}
wm-menu telega {key {<Super>t t} body {telega-chats}}
EOF

PATH="$FIXBIN:$PATH" XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-telega.log" 2>&1 &
WM=$!
sleep 2

# ---- open, pick the first: the launch carries the picked id
key super+t
key t
key 1
# ---- open again, pick the second: another id, same wiring
key super+t
key t
key 2
sleep 1

kill $WM 2>/dev/null
sleep 0.3

echo "--- WM saw:"
grep -E 'WM: menu telega|WM: emacs' "$HERE/wm-telega.log"
echo "--- the daemon was asked:"
cat "$HERE/telega-calls.log" 2>/dev/null

echo "--- verdict"
BAD=0
if grep -q 'BadAccess request=2' "$HERE/wm-telega.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"; BAD=1
fi
if grep -q 'soft failure\|handler error\|WM: PROBLEM' "$HERE/wm-telega.log"; then
    echo "FAIL: soft failures, handler errors or problems:"
    grep 'soft failure\|handler error\|WM: PROBLEM' "$HERE/wm-telega.log"; BAD=1
fi

OPENS=$(grep -c 'WM: menu telega open (2 items)' "$HERE/wm-telega.log")
if [ "$OPENS" = "2" ]; then
    echo "OK: the daemon's two chats made two rows, at both opens"
else
    echo "FAIL: the menu opened with 2 rows $OPENS times, want 2"; BAD=1
fi
ASKS=$(grep -c 'telega--getTopChats "Users" 12' "$HERE/telega-calls.log")
if [ "$ASKS" = "2" ]; then
    echo "OK: the list was asked of the daemon at each open, not once"
else
    echo "FAIL: getTopChats was asked $ASKS times, want 2"; BAD=1
fi
if grep -q 'WM: menu telega pick «Вася Пупкин»' "$HERE/wm-telega.log"; then
    echo "OK: the propertized title read as its string and labeled the row"
else
    echo "FAIL: the first row's pick line is missing"; BAD=1
fi
if grep -q 'WM: emacs: launch .*-s telega .*TELEGA.*telega-chat-get 880396138110181' \
        "$HERE/wm-telega.log"; then
    echo "OK: the pick fired emacsclient at the telega daemon, TELEGA frame, chat id baked in"
else
    echo "FAIL: the first launch line is missing its socket, frame or id"; BAD=1
fi
if grep -q 'WM: menu telega pick «рабочий чат»' "$HERE/wm-telega.log" \
        && grep -q 'telega-chat-get -1001234567890' "$HERE/wm-telega.log"; then
    echo "OK: the second row carried its own — negative — id to the same door"
else
    echo "FAIL: the second pick or its id is missing"; BAD=1
fi
check_invariants "$HERE/wm-telega.log"
if grep -q 'WM: INVARIANT' "$HERE/wm-telega.log"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: the daemon's chats become rows, and a pick opens the chat in the same emacs"
exit $BAD
