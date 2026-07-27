# Demo client: argv = title geometry color ?resizeto? ?minsize? ?secs?
# ?iconcolor?. Reports viewability and focus; announces
# WM_DELETE_WINDOW; optionally requests a resize so the driver log
# shows the frame following; optional minsize (WxH) declares a
# WM_NORMAL_HINTS minimum; optional secs extends the default 8 s
# lifetime for longer test scripts; optional iconcolor declares a
# 32x32 two-tone _NET_WM_ICON (wm iconphoto) in that color.
package require Tk
lassign $argv title geom color resizeto minsize secs iconcolor
if {$secs eq ""} { set secs 8 }
if {$iconcolor ne ""} {
    image create photo appicon -width 32 -height 32
    appicon put $iconcolor -to 0 0 32 32
    appicon put #eeeeec -to 6 6 26 14
    wm iconphoto . appicon
}
if {$minsize ne "" && [regexp {^(\d+)x(\d+)$} $minsize -> mw mh]} {
    wm minsize . $mw $mh
}
if {$title eq ""} { set title client }
if {$geom  eq ""} { set geom 240x120 }
if {$color eq ""} { set color #fce94f }
chan configure stdout -buffering line
wm title . $title
wm geometry . $geom
wm protocol . WM_DELETE_WINDOW {
    puts "CLIENT $title: got WM_DELETE_WINDOW, exiting"
    exit 0
}
label .l -text $title -background $color -font {Sans 14}
pack .l -expand 1 -fill both
after 3000 {puts "CLIENT $title: viewable=[winfo viewable .] focus=[focus]\
 root=+[winfo rootx .]+[winfo rooty .]"}
if {$resizeto ne ""} {
    after 4000 [list wm geometry . $resizeto]
    after 5000 {puts "CLIENT $title: size=[winfo width .]x[winfo height .] after resize request"}
}
after [expr {$secs * 1000}] exit
vwait ::forever
