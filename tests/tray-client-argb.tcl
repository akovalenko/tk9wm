# The Chrome-shaped tray client: an icon window on a 32-bit visual NO
# MATTER what the tray advertises — Chrome's manner, measured
# 2026-07-29 — with a genuinely transparent background and an opaque
# glyph in the middle. The ring around the glyph is the probe: what
# it shows on the glass, per tray mode and compositor, is the whole
# question run-traymatrix-probe.sh asks.
#
#   tray-client-argb.tcl ?#rrggbb?
#
# The transparency is the real thing, not ParentRelative: the icon's
# background is raw pixel 0x00000000, alpha byte and all, set through
# the shim — the NUMBER branch's one live caller. The manager paints
# parent-relative over a docked icon's background (substrate), and
# GTK's icons paint their own transparency back over that; this
# client re-asserts its background after the dock, which is exactly
# Chrome's manner writ small.
package require Tk
lappend auto_path [file dirname [file dirname [file normalize [info script]]]]
package require tkwmx

set spec [lindex $argv 0]
if {$spec eq ""} { set spec #fcaf3e }
chan configure stdout -buffering line
wm withdraw .

if {"truecolor 32" ni [winfo visualsavailable .]} {
    puts "ARGBICON: no truecolor 32 on this screen"
    exit 77
}
toplevel .i -visual {truecolor 32} -colormap new -background black
wm withdraw .i
wm geometry .i 32x32
frame .i.g -background $spec
place .i.g -relx 0.5 -rely 0.5 -anchor center -width 12 -height 12
update idletasks

# The window the tray takes is Tk's WRAPPER (the csd-client lesson),
# alive while the toplevel is still withdrawn.
set icon [lindex [tkwmx::window tree .i] 1]
# BOTH windows: the wrapper is what docks, but the INNER toplevel
# covers it wholly, and Tk paints that one opaque (the server ORs the
# alpha bits into every allocated pixel — a black Tk background is
# 0xff000000, not a hole).
proc transparent {} {
    foreach w [list $::icon [winfo id .i]] {
        tkwmx::window attrs $w {background 0}
        catch {tkwmx::window clear $w}
    }
}
transparent

set S [tkwmx::atom intern _NET_SYSTEM_TRAY_S0]
set owner [tkwmx::selection get $S]
if {$owner == 0} { puts "ARGBICON: no tray manager on the display"; exit 1 }
set OP [tkwmx::atom intern _NET_SYSTEM_TRAY_OPCODE]
# {time SYSTEM_TRAY_REQUEST_DOCK icon 0 0}, told TO the manager about
# the manager's own window, as the systray spec has it.
tkwmx::event client $owner $OP [list 0 0 $icon 0 0] 32 {} $owner
puts "ARGBICON: 0x[format %x $icon] asked to dock ($spec)"

# The manager reparents, resizes and maps; align Tk's idea of the
# toplevel with that, then re-assert the transparent background over
# the parent-relative the dock painted onto it.
after 700 {wm deiconify .i}
after 1200 {transparent; puts "ARGBICON: transparent background re-asserted"}
after 1800 transparent
vwait ::forever
