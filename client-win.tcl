# Tk client that REPORTS ITS OWN IDEA of where it is — the app-side half
# of the "false location" bug (clicks miss, tooltips and menus land
# offset). Built for whale.exe under Wine, the shape smsrc has, but runs
# natively too.
#
# winfo rootx/rooty is what the toolkit believes; compare it with the
# window's true root origin (probe-at.tcl / xwininfo). A mismatch is the
# bug, and it says nothing about pixels — only about what the client was
# told.
#
#   whale.exe client-win.tcl <report-file> ?seconds? ?mode?
#
# mode "selfsize" makes the app resize ITSELF right after mapping, the way
# a real application lays itself out on startup. That leaves the toolkit
# waiting for its own configure to come back — the state in which a
# client is most likely to drop the WM's synthetic ConfigureNotify.
package require Tk

lassign $argv report secs mode
if {$report eq ""} { set report "location-report.txt" }
if {$secs eq ""} { set secs 20 }

wm title . "клиент-под-wine"
wm geometry . 400x300
label .l -text "я репортю свои координаты" -font {Sans 12}
pack .l -expand 1 -fill both
menu .m
menu .m.file -tearoff 0
.m add cascade -label "Файл" -menu .m.file
.m.file add command -label "Пункт"
. configure -menu .m

if {$mode eq "selfsize"} {
    after 120 { wm geometry . 700x500 }
    after 260 { wm geometry . 900x620 }
    # asking for a POSITION too — what an app does when it restores its
    # saved window placement. A reparenting WM denies the position, and
    # ICCCM 4.1.5 obliges it to say so; a WM that stays silent leaves the
    # app believing it sits where it asked to sit.
    after 420 { wm geometry . 860x580+300+250 }
}

set fh [open $report w]
fconfigure $fh -buffering line
set n 0
proc report {} {
    global fh n secs
    puts $fh "t=[expr {$n}]s rootx=[winfo rootx .] rooty=[winfo rooty .]\
 size=[winfo width .]x[winfo height .]"
    if {[incr n] > $secs} { close $fh; exit 0 }
    after 1000 report
}
report
vwait ::forever
