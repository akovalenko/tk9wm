# A tray-ONLY client for the tray regression: no window of its own,
# just an icon docked through the system tray protocol (Tk's own `tk
# systray`, which speaks the client half of XEMBED — tkUnixSysTray.c).
#
# The icon is a filled circle with TRANSPARENT corners: what shows
# around it is the tray cell's background, and a black square there
# would be the classic ARGB-without-compositing failure.
#
#   tray-client.tcl ?COLOR? ?SECONDS-BEFORE-UNDOCK?
# With a second argument the icon is destroyed after that many seconds
# (the undock path); without one it stays until the process is killed.
package require Tk
wm withdraw .

set color [lindex $argv 0]
if {$color eq ""} { set color #8ae234 }
set gone [lindex $argv 1]

set S 22
image create photo trayimg -width $S -height $S
trayimg put $color -to 0 0 $S $S
set c [expr {($S - 1) / 2.0}]
for {set y 0} {$y < $S} {incr y} {
    for {set x 0} {$x < $S} {incr x} {
        if {($x-$c)*($x-$c) + ($y-$c)*($y-$c) > $c*$c} {
            trayimg transparency set $x $y 1
        }
    }
}

tk systray create -image trayimg -text "tk9wm tray test" \
    -button1 {puts "TRAYCLIENT: button1"} \
    -button3 {puts "TRAYCLIENT: button3"}
chan configure stdout -buffering line
puts "TRAYCLIENT: icon created ($color)"

if {$gone ne ""} {
    after [expr {int($gone * 1000)}] {
        tk systray destroy
        puts "TRAYCLIENT: icon destroyed"
    }
}
vwait ::forever
