# An ordinary X client playing the WM "customer": maps a toplevel and
# reports whether it actually became viewable (i.e. whether the WM spike
# honored our MapRequest).
package require Tk
wm title . tk9wm-client
wm geometry . 180x80+30+30
label .l -text "hello from client"
pack .l
after 2000 {puts "CLIENT: viewable=[winfo viewable .] (1 = the WM spike mapped us)"; exit 0}
vwait ::forever
