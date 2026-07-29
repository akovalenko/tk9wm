# Lock the keyboard into an xkb group, and say what it is afterwards.
#   whale xkb-lock.tcl <checkout> <group>
# The checkout is where the shim is found; the group an index 0..3.
lassign $argv root group
lappend auto_path $root
package require tkwmx
if {$group ne ""} { tkwmx::keyboard group $group }
puts "LOCK: group is now [tkwmx::keyboard group] (locked effective)"
# Explicit, because a whale enters its event loop after the script ONCE
# TK IS IN — a script that never loads Tk exits by itself (measured:
# 0 s against 6 s under a timeout). This one loads Tk without asking
# for it: `package require tkwmx` loads libtkwmx.so, which is a Tk
# extension and pulls `package require -exact tk` along.
exit
