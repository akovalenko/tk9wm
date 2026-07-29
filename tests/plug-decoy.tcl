# A decoy for the tray's adoption test: an override-redirect window that
# carries _XEMBED_INFO and is NOT a tray icon — it never asked to dock.
#
# That combination is not exotic. fcitx5 puts _XEMBED_INFO on its input
# window and on its menu window as readily as on its tray icon, so a
# tray that adopts "every plug on the root" swallows the input method's
# own UI (owner's desk, 2026-07-29). This window exists so the suite
# notices if that ever comes back.
# Run on any Tcl/Tk 9: the shim comes from the checkout this file
# lives in (./configure && make at its root), not from the host.
lappend ::auto_path [file dirname [file dirname \
    [file normalize [info script]]]]
package require Tk
package require tkwmx
wm withdraw .
chan configure stdout -buffering line

set root [lindex [tkwmx::window tree [winfo id .]] 0]
set w [tkwmx::window create $root 300 300 120 40 -override]
tkwmx::prop set $w [tkwmx::atom intern _XEMBED_INFO] \
    [tkwmx::atom intern _XEMBED_INFO] 32 {0 1}
tkwmx::window map $w
tkwmx::server sync 0
puts "DECOY: window [format 0x%x $w]"
vwait ::forever
