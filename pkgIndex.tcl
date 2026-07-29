# Package index for a tk9wm CHECKOUT: put this directory on auto_path
# (or TCLLIBPATH) and both of the project's packages become available —
# `tkwmx` from the shared shim built right here, `tk9wm` from library/,
# which Tcl finds by itself when it scans this directory's children.
#
#   ./configure --with-tcl=/usr/lib && make
#   TCLLIBPATH=$PWD wish
#
# The shim entry is conditional on purpose. Before `make` there is no
# libtkwmx.so, and an unconditional `package ifneeded` would then hand
# `package require tkwmx` a load of a file that is not there — an error
# that says nothing about the real cause. Silence instead lets the
# require fail with "can't find package tkwmx", and lets a host that
# has the shim compiled IN (a whale with the battery) answer from its
# own image without this checkout shadowing it.
if {[file exists [file join $dir libtkwmx.so]]} {
    package ifneeded tkwmx 0.1 \
	[list load [file join $dir libtkwmx.so] Tkwmx]
}
