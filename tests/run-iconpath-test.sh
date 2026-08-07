#!/bin/sh
# Regression for resolve-icon — the polymorphic `icon` value: a Tk
# image name passes through untouched, a file path loads any format
# Tk reads, a bare name is searched as NAME.png through the icon-path
# directories and, only where no png of that name exists anywhere,
# as NAME.svg — the last resort, because a poor icon beats none (the
# owner, 2026-08-02); an oversized image is resampled down
# with alpha, a smaller one stays smaller, everything is cached per
# {spec size}, and a miss logs once and yields "". Integration: the
# panel button face resolves a bare name, and a wm-style icon key
# rides through winlist-icon.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/iconpath-config"
mkdir -p "$HERE/iconpath-config/icons"

# test icons: an oversized square, a small one, an svg standing beside
# a png of the same name (the png must win), and an svg with no png
# anywhere — which is the case that used to have no icon at all
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
svg() { printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="64"\
 height="64" viewBox="0 0 64 64"><rect width="64" height="64" fill="#3465a4"/></svg>' \
    > "$1"; }
svg "$HERE/iconpath-config/icons/svgonly.svg"
svg "$HERE/iconpath-config/icons/ff.svg"    ;# beside ff.png, and must lose

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
        {a png beats an svg of the same name}       48 {image width [resolve-icon ff 48]}
        {an svg is taken when no png is anywhere}   1  {expr {[resolve-icon svgonly 48] ne ""
            && [image height [resolve-icon svgonly 48]] <= 48}}
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
wait_wm "$HERE/wm-iconpath.log" $WM

"$LINUX/whale" "$HERE/client.tcl" проба-иконок 240x120 "#729fcf" "" "" 20 &
TK=$!
sleep 1.5

xdotool key super+f
sleep 0.5

q() { printf '%s\n' "$1" > "$HERE/iconpath-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/iconpath-config/q.tcl"; }
# ---- an icon that has not changed is not re-read, and the image a
# strip is drawing with is never destroyed under it ----
IMG0=$(q 'resolve-icon ff 48')
SIZE0=$(q 'image width [resolve-icon ff 48]')
q reload-config >/dev/null
sleep 1
IMG1=$(q 'resolve-icon ff 48')
LIVE1=$(q 'expr {[resolve-icon ff 48] in [image names]}')
READS1=$(grep -c 'WM: icon «ff»' "$HERE/wm-iconpath.log")
# ...and a file that HAS changed is poured into that same image
"$LINUX/whale" "$HERE/iconpath-config/make-png.tcl" \
    "$HERE/iconpath-config/icons/ff.png" 32 '#3465a4'
sleep 1
IMG2=$(q 'resolve-icon ff 48')
SIZE2=$(q 'image width [resolve-icon ff 48]')
INPLACE=$(grep -c 're-read in place' "$HERE/wm-iconpath.log")

kill $WM $TK 2>/dev/null

echo "--- battery lines:"
grep -E 'ICON|WM: icon' "$HERE/wm-iconpath.log"

echo "--- icons: $IMG0 -> $IMG1 -> $IMG2, size $SIZE0 -> $SIZE2,\
 reads=$READS1 inplace=$INPLACE live=$LIVE1"
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
if [ "$PASS" = 10 ]; then
    echo "OK: all 10 checks passed"
else
    echo "FAIL: $PASS PASS lines, want 10"
fi
if grep -q 'ICON BATTERY: 10 checks' "$HERE/wm-iconpath.log"; then
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

if [ "$IMG0" = "$IMG1" ] && [ "$LIVE1" = 1 ]; then
    echo "OK: a reload left the image standing — same object, not re-read"
else
    echo "FAIL: after the reload: «$IMG0» -> «$IMG1» live=$LIVE1"
fi
if [ "$IMG1" = "$IMG2" ] && [ "$SIZE0" = 48 ] && [ "$SIZE2" = 32 ] \
        && [ "$INPLACE" -ge 1 ]; then
    echo "OK: a changed file was poured into the same image"
else
    echo "FAIL: after the change: «$IMG1» -> «$IMG2»,\
 $SIZE0 -> $SIZE2, in-place lines $INPLACE"
fi
