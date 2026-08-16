# Client for the Rename regression: maps under a name the driver's
# `title` style rule matches, then renames itself ON COMMAND — the
# driver reaches in through Tk send (send-eval.tcl, appname renamec),
# so every hop lands exactly between two of its checks and no timer
# races the polls the way client-vtitle's schedule would here.
package require Tk
chan configure stdout -buffering line
tk appname renamec
wm title . "рен старт"
wm geometry . 300x140+60+60
label .l -text "переименуй меня" -background #729fcf -font {Sans 12}
pack .l -expand 1 -fill both
after 120000 exit
vwait ::forever
