# Client for the visible-title regression: maps under a name a `title`
# style rule matches, renames itself WITHIN the pattern (the rewrite
# must follow — the style cache must not have frozen the verdict),
# then AWAY from it (the rewrite must lift and the published
# _NET_WM_VISIBLE_NAME must go). The driver paces itself on the WM's
# own title lines, so the gaps here only need to be wide enough for
# its xprop polls between the hops.
package require Tk
chan configure stdout -buffering line

wm title . "дин один"
wm geometry . 300x120
label .l -text "визитка" -background #ad7fa8 -font {Sans 12}
pack .l -expand 1 -fill both

after 6000  { wm title . "дин два"; puts "CLIENT: renamed (still matching)" }
after 12000 { wm title . "иное";    puts "CLIENT: renamed (out of the pattern)" }
after 30000 exit
vwait ::forever
