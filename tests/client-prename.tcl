# Client for the renamekeep regression's pre-naming leg: it holds its
# window WITHDRAWN and says the window's id out loud, so the driver
# can put _TK9WM_TITLE_TEMPLATE on it before it ever maps; told to —
# through the send door (appname prenamec), between two of the
# driver's checks — it maps, and the manage must meet the template.
package require Tk
chan configure stdout -buffering line
tk appname prenamec
wm withdraw .
wm title . "тихое окно"
wm geometry . 260x120+400+300
label .l -text "pre-named" -background #fce94f -font {Sans 12}
pack .l -expand 1 -fill both
puts "prename id: [format 0x%x [winfo id .]]"
after 120000 exit
vwait ::forever
