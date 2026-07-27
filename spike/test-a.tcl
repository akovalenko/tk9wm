# Test A: does Tk 9 deliver TIP#47 request-events to a script-level bind
# on an ordinary widget? (bind itself must select SubstructureRedirectMask
# on the widget's X window; a redirected child map must then reach us and
# the child must stay unmapped because nobody performs the map.)
package require Tk
wm geometry . 300x200+10+10
frame .holder -width 200 -height 150 -background blue
pack .holder
update

set ::out {}
bind .holder <MapRequest> {lappend ::out "MapRequest W=%W child=%i"}
bind .holder <ConfigureRequest> {lappend ::out "ConfigureRequest W=%W child=%i"}

frame .holder.kid -width 40 -height 40 -background red
puts "A: kid xid=[winfo id .holder.kid]"
place .holder.kid -x 5 -y 5
update

after 700 {
    puts "A: events: [expr {[llength $::out] ? [join $::out { | }] : {NONE}}]"
    puts "A: kid viewable=[winfo viewable .holder.kid] (0 = redirect really intercepted the map)"
    exit 0
}
vwait ::forever
