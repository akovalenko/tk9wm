# tk9wm — thin assembly of the two layers:
#
#  substrate.tcl — the mechanism a WM cannot exist without: cffi Xlib +
#    X error handler (installed BEFORE Tk — the order is the whole trick),
#    the fd pump (worker thread + poll ping-pong), redirect / reparent /
#    save-set surgery, adoption, focus core with PointerRoot repair, close
#    machinery, synthetic ConfigureNotify, EWMH minimum. Drives policy-*.
#  policy.tcl — our local decisions: Tk-widget decorations (titlebar/✕/
#    slot), cascade placement, title drag, click-to-focus. Implements the
#    policy-* hooks (contract — substrate.tcl header; discussion — the
#    idea file, step 9).
#
# Sourcing order matters: the substrate must install its X error handler
# before Tk loads, so it comes first; the policy needs Tk, which the
# substrate has already required.

set here [file dirname [file normalize [info script]]]
source [file join $here substrate.tcl]
source [file join $here policy.tcl]

substrate-start

# Demo mode (argv "demo"): timed self-test used by run-demo.sh. Without it
# the WM runs indefinitely — that is the live/Xephyr mode.
if {[lindex $argv 0] eq "demo"} {
    # exercise the close path on whatever has focus (client B by then)
    after 5800 {
        if {$focused != 0} {
            puts "WM: demo: pressing close on focused 0x[format %x $focused]"
            close-client $focused
        }
    }
    # survival demo: provoke a BadWindow on purpose; without the error
    # handler Xlib's default would have exited the whole process here
    after 6000 {
        if {$has_errhandler} {
            puts "WM: injecting BadWindow on purpose (XMapWindow of a bogus id)"
            XMapWindow $dpy 0x666666
            XSync $dpy 0
        }
    }
    after 12000 {xerror-flush; puts "WM: bye"; exit 0}
}
vwait ::forever
