# The minimize victim: argv = title ?secs? ?at?. A Tk client that
# iconifies ITSELF `at` seconds in and keeps reporting the state it
# believes it is in. `wm iconify` here is XIconifyWindow — the very
# WM_CHANGE_STATE message wine's Win32 SW_MINIMIZE ends up sending —
# so this drives the WM side of the owner's report without a human
# clicking a system menu.
package require Tk
lassign $argv title secs at
if {$secs eq ""} { set secs 14 }
if {$at eq ""} { set at 3 }
wm title . $title
. configure -background #fce94f
label .l -text $title -background #fce94f -font {Helvetica 16}
pack .l -padx 30 -pady 24
wm geometry . 320x160+120+90
update
puts "CLIENT: mapped, state=[wm state .]"
flush stdout

after [expr {$at * 1000}] {
    puts "CLIENT: asking for iconic"
    flush stdout
    wm iconify .
}
# Every second: what does the client think its state is? A WM that
# honors the request drives it to iconic; one that refuses (or that
# brings the window back) drives it to normal — the client's own view
# is the half of the story a screenshot cannot show.
proc tick {n} {
    puts "CLIENT: t+$n state=[wm state .]"
    flush stdout
    if {$n < $::secs} { after 1000 [list tick [incr n]] }
}
after 1000 [list tick 1]
after [expr {$secs * 1000}] { puts "CLIENT: bye"; flush stdout; exit 0 }
