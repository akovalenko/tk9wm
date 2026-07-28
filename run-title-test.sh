#!/bin/sh
# Regression for live titles: the frame's titlebar must follow the
# client's WM_NAME/_NET_WM_NAME (PropertyNotify), starting with the
# title the client had at manage time. The long rename also exercises
# the treectrl ellipsis path (eyeball title-test.png for the cut).
#
# Second phase: the ENCODINGS a WM_NAME can arrive in. The same
# Cyrillic title, from three xterms in three locales, is three
# different byte streams — ESC-designated ISO 8859-5 compound text,
# JIS X 0208 compound text, and raw UTF-8 under a STRING type — and
# all three must land on the titlebar as the same string. (Before
# 2026-07-28 the compound-text pair came back empty and the frames
# showed their «клиент 0x…» fallback.)
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:75
rm -f /tmp/.X75-lock /tmp/.X11-unix/X75
Xvfb :75 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-title.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client-title.tcl" > "$HERE/title-client.log" &
CT=$!
sleep 4
import -display :75 -window root "$HERE/title-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/title-test.png"
wait $CT

# the encoding phase: one xterm per locale, all titled the same
LC_ALL=en_US.UTF-8 xterm -T 'привет мир' -e sleep 30 &
X1=$!
LC_ALL=ru_RU.utf8 xterm -T 'привет мир' -e sleep 30 &
X2=$!
LC_ALL=C xterm -T 'привет мир' -e sleep 30 &
X3=$!
sleep 4
echo "--- WM_NAME types the three xterms declared:"
for id in $(xdotool search --class -- xterm); do
    xprop -id "$id" WM_NAME | sed 's/^/    /'
done
import -display :75 -window root "$HERE/title-ct.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/title-ct.png"
kill $X1 $X2 $X3 2>/dev/null
sleep 1
kill $WM 2>/dev/null

echo "--- title lines the WM logged:"
grep 'WM: title' "$HERE/wm-title.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-title.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
BAD=0
for want in "первое имя" "второе имя" "длинное третье имя"; do
    if ! grep -q "WM: title 0x[0-9a-f]* -> «.*$want" "$HERE/wm-title.log"; then
        echo "FAIL: no title update for «$want»"; BAD=1
    fi
done
# one decoded Cyrillic title per xterm — three encodings, one string
CT=$(grep -c 'WM: title 0x[0-9a-f]* -> «привет мир»' "$HERE/wm-title.log")
if [ "$CT" -lt 3 ]; then
    echo "FAIL: $CT/3 xterm titles decoded (compound text unread?)"; BAD=1
else
    echo "OK: all three WM_NAME encodings decoded to «привет мир»"
fi
# a policy-title that blows up surfaces as a handler error — that would
# mean the titlebar never followed even though the WM saw the property
if grep -q 'handler error' "$HERE/wm-title.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-title.log"
    BAD=1
fi
[ $BAD -eq 0 ] && echo "OK: titlebar followed both renames from the initial title"
