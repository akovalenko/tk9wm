# Client for the live-title regression: maps under one name, renames
# itself twice — the second time to a title long enough that the
# titlebar must ellipsize it.
package require Tk
chan configure stdout -buffering line

wm title . "первое имя"
wm geometry . 300x120+10+10
label .l -text "переименовыватель" -background #fce94f -font {Sans 12}
pack .l -expand 1 -fill both

after 2000 { wm title . "второе имя"; puts "CLIENT: renamed (short)" }
after 3000 {
    wm title . "очень длинное третье имя, которому положено обрезаться многоточием"
    puts "CLIENT: renamed (long)"
}
after 5000 exit
vwait ::forever
