# send-restack.tcl — restack a window the way a CLIENT would:
# XConfigureWindow with CWStackMode (XRaiseWindow is the `above`
# spelling of exactly this call, XLowerWindow the `below` one). Under
# a running WM the request does not act on the server — the redirect
# hands it to whoever holds SubstructureRedirect on the window's
# parent, which is the point: this poker speaks the client half of
# the ConfigureRequest conversation, so a suite (or a live diagnosis)
# can say "raise yourself" from outside and watch what the WM does
# with it.
#
#   whale-cli send-restack.tcl <display> <window> above|below|top-if|bottom-if|opposite

package require cffi

cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XConfigureWindow int {dpy pointer.unsafe w ulong mask uint changes pointer.unsafe}
X11 function XSync int {dpy pointer.unsafe discard int}

lassign $argv disp win mode
set modes {above below top-if bottom-if opposite}
set code [lsearch -exact $modes $mode]
if {$win eq "" || $code < 0} {
    puts "usage: send-restack.tcl <display> <window> [join $modes |]"
    exit 1
}
if {$disp eq ""} { set disp $::env(DISPLAY) }
set dpy [XOpenDisplay $disp]
if {[cffi::pointer isnull $dpy]} { puts "no display $disp"; exit 1 }

# XWindowChanges LP64: x@0 y@4 width@8 height@12 border_width@16
# sibling@24 stack_mode@32 — only stack_mode is read under this mask.
set ch [cffi::memory frombinary \
    [binary format iiiiix4wuix4 0 0 0 0 0 0 $code] unsafe]
XConfigureWindow $dpy $win 64 $ch      ;# CWStackMode
XSync $dpy 0
cffi::memory free $ch
puts "sent ConfigureRequest stack-mode=$mode for 0x[format %x $win]"
