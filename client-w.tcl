# Withdraw/deiconify torture client: used to be KILLED by the WM (frame
# destroy took the reparented client window with it).
package require Tk
chan configure stdout -buffering line
wm title . withdraw-client
wm geometry . 200x100
label .l -text "withdraw me" -background #e9b96e
pack .l -expand 1 -fill both
after 2500 { puts "CLIENTW: withdrawing"; wm withdraw . }
after 4000 { puts "CLIENTW: deiconifying"; wm deiconify . }
after 5500 { puts "CLIENTW: still alive, viewable=[winfo viewable .]" }
after 7000 exit
vwait ::forever
