# send-eval.tcl — evaluate a script inside another Tk app on this
# display via Tk send: the debugging door into a LIVE tk9wm (the WM
# registers under its argv0 basename, e.g. run-tk9wm.tcl or
# tk9wm.tcl).  The script travels via a FILE so no shell or ssh
# quoting layer can eat braces on the way.
#
#   whale send-eval.tcl                  -> list the display's interps
#   whale send-eval.tcl APP SCRIPTFILE   -> eval the file's content in APP
#
# Proven in the field 2026-07-31: ::errorInfo and a ::style_rules dump
# through this door found a malformed rule that a log line alone never
# named.
package require Tk
wm withdraw .
if {[llength $argv] < 2} {
    puts "interps: [winfo interps]"
    exit 0
}
lassign $argv app path
set ch [open $path r]
set script [read $ch]
close $ch
if {[catch {send -- $app $script} out]} {
    puts "SEND ERROR: $out"
    exit 1
}
puts $out
exit 0
