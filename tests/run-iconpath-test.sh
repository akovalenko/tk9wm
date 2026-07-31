#!/bin/sh
# Regression for resolve-icon — the polymorphic `icon` value: a Tk
# image name passes through untouched, a file path loads any format
# Tk reads, a bare name is searched as NAME.png (png ONLY) through
# the icon-path directories; an oversized image is resampled down
# with alpha, a smaller one stays smaller, everything is cached per
# {spec size}, and a miss logs once and yields "". Integration: the
# panel button face resolves a bare name, and a wm-style icon key
# rides through winlist-icon.
. "$(dirname "$0")/common.sh"
export DISPLAY=:84
rm -f /tmp/.X84-lock /tmp/.X11-unix/X84
Xvfb :84 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/iconpath-config"
mkdir -p "$HERE/iconpath-config/icons"

# test icons: an oversized square, a small one, and an svg decoy that
# a bare-name lookup must NOT pick
cat > "$HERE/iconpath-config/make-png.tcl" <<'EOF'
package require Tk
lassign $argv path size color
image create photo p -width $size -height $size
p put $color -to 0 0 $size $size
p write $path -format png
exit
EOF
"$LINUX/whale" "$HERE/iconpath-config/make-png.tcl" \
    "$HERE/iconpath-config/icons/ff.png" 128 '#cc4444'
"$LINUX/whale" "$HERE/iconpath-config/make-png.tcl" \
    "$HERE/iconpath-config/icons/small.png" 24 '#4e9a06'
echo '<svg xmlns="http://www.w3.org/2000/svg"/>' \
    > "$HERE/iconpath-config/icons/svgonly.svg"

cat > "$HERE/iconpath-config/tk9wm.tcl" <<'EOF'
set-icon-path [list __ICONS__]
image create photo imgOwn -width 100 -height 100
wm-style {filter -title {проба*}} {icon ff}
action тест {icon ff}
panel-button тест
proc icon-battery {} {
    set tk 0
    foreach w [array names ::frameof] {
        if {[string match проба* [client-title $w]]} { set tk $w }
    }
    set n 0
    foreach {desc want script} {
        {bare name resolves and shrinks to 48}      48 {image width [resolve-icon ff 48]}
        {resolve is cached, same image back}        1  {string equal [resolve-icon ff 48] [resolve-icon ff 48]}
        {explicit path resolves}                    48 {image width [resolve-icon __ICONS__/ff.png 48]}
        {tk image name passes through untouched}    imgOwn {resolve-icon imgOwn 48}
        {small icon is not upscaled}                24 {image width [resolve-icon small 48]}
        {miss yields empty}                         {} {resolve-icon nosuchicon 48}
        {bare name never picks svg}                 {} {resolve-icon svgonly 48}
        {winlist style icon resolves to row size}   1  {expr {[lindex [winlist-icon $tk 22] 0] eq "image"
            && [image width [lindex [winlist-icon $tk 22] 1]] <= 22}}
        {panel face carries the resolved image}     1  {expr {[[panel-tree default] item element cget 1 C0 eBIcon -image] ne ""}}
    } {
        if {[catch {eval $script} got]} { set got "ERR: $got" }
        if {$got eq $want} {
            puts "ICON PASS: $desc"
        } else {
            puts "ICON FAIL: $desc (want $want, got $got)"
        }
        incr n
    }
    puts "ICON BATTERY: $n checks"
}
wm-bind {<Super>f} icon-battery
EOF
sed -i "s|__ICONS__|$HERE/iconpath-config/icons|g" "$HERE/iconpath-config/tk9wm.tcl"

XDG_CONFIG_HOME="$HERE/iconpath-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-iconpath.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" проба-иконок 240x120 "#729fcf" "" "" 20 &
TK=$!
sleep 1.5

xdotool key super+f
sleep 0.5

kill $WM $TK 2>/dev/null

echo "--- battery lines:"
grep -E 'ICON|WM: icon' "$HERE/wm-iconpath.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-iconpath.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q 'ICON FAIL' "$HERE/wm-iconpath.log"; then
    echo "FAIL: battery failures present (above)"
else
    echo "OK: no battery failures"
fi
PASS=$(grep -c 'ICON PASS' "$HERE/wm-iconpath.log")
if [ "$PASS" = 9 ]; then
    echo "OK: all 9 checks passed"
else
    echo "FAIL: $PASS PASS lines, want 9"
fi
if grep -q 'ICON BATTERY: 9 checks' "$HERE/wm-iconpath.log"; then
    echo "OK: the battery ran to completion"
else
    echo "FAIL: the battery is missing or truncated"
fi
if grep -q 'WM: icon «nosuchicon»: no Tk image' "$HERE/wm-iconpath.log"; then
    echo "OK: the miss logged its one line"
else
    echo "FAIL: no miss log line for nosuchicon"
fi
if grep -q 'handler error' "$HERE/wm-iconpath.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-iconpath.log"
fi
