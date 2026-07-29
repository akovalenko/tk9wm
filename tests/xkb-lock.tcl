# Lock the keyboard into an xkb group, and say what it is afterwards.
#   whale xkb-lock.tcl <checkout> <group>
# The checkout is where the shim is found; the group an index 0..3.
lassign $argv root group
lappend auto_path $root
package require tkwmx
if {$group ne ""} { tkwmx::keyboard group $group }
puts "LOCK: group is now [tkwmx::keyboard group] (locked effective)"
exit    ;# a whale runs its event loop after the script otherwise
