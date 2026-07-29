# Can the window manager offload a GUI into a THREAD with its own Tk —
# a window that is an ordinary X client, on equal terms with every
# other, decorated by the redirect like anything else?
#
# The whole idea rests on one assumption: that Tk initializes in a
# thread that is not the main one, and opens its OWN display connection
# there. A connection of its own makes the thread a different CLIENT to
# the server, and that is what makes its windows redirectable — ours
# are not, and cannot be (tools/probe-selftoplevel.tcl).
#
# Run it under tk9wm and watch whether the window arrives decorated:
#   whale tools/probe-threadgui.tcl
package require Thread
chan configure stdout -buffering line
proc note {msg} { puts $msg }
set main [thread::id]
puts "main thread: $main"

set t [thread::create -joinable [string map [list @MAIN@ [list $main]] {
    package require Tk
    set main @MAIN@
    wm title . "a form in a thread"
    wm geometry . 260x120+60+60
    label .l -text "an ordinary client" -padx 20 -pady 20
    pack .l
    update
    thread::send -async $main [list note \
        "thread [thread::id]: Tk up, window [winfo id .], viewable [winfo viewable .]"]
    # Whose connection is this? If Tk in this thread opened one of its
    # own, the window manager sees a client it does not know — and
    # frames it. If it somehow shared the main thread's, the redirect
    # would pass it over in silence.
    vwait forever
}]]
puts "spawned thread $t"
after 5000 {
    puts "probe done"
    exit 0
}
vwait forever
