# send-restart.tcl — ask a running tk9wm to restart in place (release
# clients, execv itself; fresh code from disk, same pid). Finds the WM's
# wmcheck window via _NET_SUPPORTING_WM_CHECK on the root and sends it a
# TK9WM_RESTART ClientMessage; a zero-mask XSendEvent is delivered to
# the window's creator — the WM's raw connection.
#
#   whale-cli send-restart.tcl ?display?

package require cffi

cffi::Wrapper create X11 libX11.so.6
X11 function XOpenDisplay pointer.unsafe {name string}
X11 function XDefaultRootWindow ulong {dpy pointer.unsafe}
X11 function XInternAtom ulong {dpy pointer.unsafe name string only_if_exists int}
X11 function XGetWindowProperty int {dpy pointer.unsafe w ulong prop ulong
    off long len long delete int reqtype ulong actual_type {ulong out}
    actual_format {int out} nitems {ulong out} bytes_after {ulong out}
    data {pointer unsafe out}}
X11 function XSendEvent int {dpy pointer.unsafe w ulong propagate int mask long ev pointer.unsafe}
X11 function XSync int {dpy pointer.unsafe discard int}
X11 function XFree int {ptr pointer.unsafe}

set disp [lindex $argv 0]
if {$disp eq ""} { set disp $::env(DISPLAY) }
set dpy [XOpenDisplay $disp]
if {[cffi::pointer isnull $dpy]} { puts "no display $disp"; exit 1 }
set root [XDefaultRootWindow $dpy]

set NET_CHECK [XInternAtom $dpy _NET_SUPPORTING_WM_CHECK 0]
set RESTART   [XInternAtom $dpy TK9WM_RESTART 0]
if {[catch {XGetWindowProperty $dpy $root $NET_CHECK 0 1 0 33 \
        atype afmt nitems after data} status] || $status != 0 || $nitems == 0} {
    puts "no _NET_SUPPORTING_WM_CHECK on root — is tk9wm running?"
    exit 1
}
binary scan [cffi::memory tobinary! $data 8] wu wmcheck
catch {XFree $data}

# XClientMessageEvent (LP64): type@0 serial@8 send_event@16 display@24
# window@32 message_type@40 format@48 data@56
set b [binary format iux4wuiux4wuwuwuiux4 33 0 1 0 $wmcheck $RESTART 32]
set ev [cffi::memory frombinary [binary format a192 $b] unsafe]
XSendEvent $dpy $wmcheck 0 0 $ev
XSync $dpy 0
puts "sent TK9WM_RESTART to wmcheck [format 0x%x $wmcheck]"
