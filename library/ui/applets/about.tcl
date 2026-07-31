# about — the first applet, and the pipeline's proof: everything on
# this card is FETCHED from the live WM over the send door at build
# time, so what it shows is the running desk's truth, whichever image
# this host was started from.
ui-applet about {title "About this desk" build about-build}

proc about-build {W} {
    set facts [wm-call {
        list \
            [package provide tk9wm] \
            $::tk9wm_library \
            [llength [dict keys [knob-table]]] \
            [lindex [terminal-resolve] 0] \
            [llength [array names ::frameof]]
    }]
    lassign $facts version library knobs beast clients
    set rows [list \
        "window manager" "tk9wm $version" \
        "library"        $library \
        "knobs declared" $knobs \
        "terminal"       $beast \
        "clients now"    $clients]
    set r 0
    foreach {k v} $rows {
        grid [label $W.k$r -text $k -anchor e -padx 8 -pady 2] \
             [label $W.v$r -text $v -anchor w -padx 8 -pady 2] \
            -sticky ew
        incr r
    }
    grid columnconfigure $W 1 -weight 1
}
