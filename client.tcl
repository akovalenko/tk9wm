# Demo client: argv = title geometry color ?resizeto? ?minsize?. Reports
# viewability and focus; announces WM_DELETE_WINDOW; optionally requests a
# resize so the driver log shows the frame following; optional minsize
# (WxH) declares a WM_NORMAL_HINTS minimum.
package require Tk
lassign $argv title geom color resizeto minsize
if {$minsize ne "" && [regexp {^(\d+)x(\d+)$} $minsize -> mw mh]} {
    wm minsize . $mw $mh
}
if {$title eq ""} { set title client }
if {$geom  eq ""} { set geom 240x120+30+30 }
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
after 8000 exit
vwait ::forever
