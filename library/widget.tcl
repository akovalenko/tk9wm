# tk9wm widgets — furniture that is not a window
#
# A widget is a small piece of the desk's OWN furniture: a clock, a
# load meter, a note. It is not a client and never will be — a thing
# that wants to be a window should be one (see the line drawn in
# wm-window: its own thread, its own connection, and then it is
# somebody the WM frames like anybody else).
#
# THE WIDGET IS AGNOSTIC ABOUT WHERE IT LIVES, which is the owner's
# requirement and the reason this file exists at all (2026-07-30). What
# a widget knows how to do is fill a FRAME. Where that frame hangs —
# over the panel, in a corner of the workarea, or on the desk itself
# under every client window — is the config's business and is said in
# one line. A widget that had to know it was "on the panel" would have
# to be rewritten to be anywhere else.
#
# THE CONTRACT, both ways:
#
#   the WM gives     a Tk frame and the declaration's options, and
#                    calls the type's `build` once. A widget that needs
#                    a heartbeat declares `every MS` and gets `tick`
#                    with the same frame and options.
#   the WM keeps     where it sits, which layer it is on, how big its
#                    container is, and when it dies.
#
# WIDGETS ARE CHEAP — the owner's premise, and it buys the whole
# design: every widget is destroyed and built again on a config reload,
# exactly as the panels are. So a widget never has to know how to
# change its mind about anything: there is no reconfigure path, no
# partial update, no state to migrate. Build, tick, die.
#
# What a widget must NOT do is block: it runs in the window manager's
# own event loop, and a widget that waits is a desk that has stopped
# (the XIM post-mortem of the same day says what that looks like).
#
# CONTAINMENT, NOT STACKING — the owner's call, and it was earned the
# hard way. The first version gave every widget its own toplevel and
# raised it to the layer it asked for. A raise is a MOMENT, not a
# state: the panel is rebuilt, a client is raised, a menu comes and
# goes, and the widget sinks one raise at a time until it is at the
# bottom of the world — mapped, correctly placed and invisible, which
# is what his clock did — measured on his live desk, at the bottom of
# the stack, under every client frame. (Two attempts to re-state the
# layer from panel-on-top appeared to fail; they were in fact never
# running, the guard `info commands widgets-layer` finding nothing
# because the proc had not been added. Worth writing down: a guarded
# call to a proc that does not exist is a fix that reports success.
# Containment is still the right answer — a raise is a moment and the
# list of places that restack a desk is not something one enumerates
# and keeps enumerated — but it did not need that false evidence.)
#
# So a widget hosted by a panel IS PART OF THE PANEL'S WINDOW — a Tk
# frame inside it — and the question does not arise: a child is over
# its parent by construction, and it dies with it, which is also why
# the flicker went. The desk host still keeps a toplevel of its own for
# now; the owner's next step is to make that one window too, ours and
# shared, with the same kind of area inside it.

keep widget_types {}   ;# TYPE -> {build CMD ?tick CMD? ?every MS?}
keep widgets {}        ;# NAME -> options, in declaration order
array set widget_win {}    ;# NAME -> the content frame, wherever it lives
array set widget_top {}    ;# ...and its own toplevel, if it needed one
array set widget_size {}   ;# ...and the content size it was last placed at

proc wm-widget-type {name spec} {
    if {![dict exists $spec build]} {
        error "wm-widget-type $name: a type must say how to `build`"
    }
    dict set ::widget_types $name $spec
}

# wm-widget NAME -type TYPE ?-on HOST? ?-place TERMS? ?-layer L? ?...?
#
#   -on      workarea (the default) | screen | {panel NAME} — the
#            rectangle the placement is measured against. A panel's own
#            rectangle is what puts a widget ON the panel, and it is
#            the only thing that makes that different from any other
#            corner of the desk.
#   -place   the `place` grammar's edge words, sizeless (a widget is as
#            big as its content). Default {right vcenter}.
#   -layer   top (over the clients, like the panel) or desk (under all
#            of them, on the desktop). Default top.
#   -padding pixels of air inside the container, default 4.
# Anything else is handed to the type verbatim.
proc wm-widget {name args} {
    if {[llength $args] % 2} { error "wm-widget $name: options come in pairs" }
    set opts [dict merge {
        -type "" -on workarea -place {right vcenter} -layer top
        -padding 4 -background #2e3436 -foreground #eeeeec
    } $args]
    if {[dict get $opts -type] eq ""} {
        error "wm-widget $name: -type is what it IS"
    }
    if {[dict get $opts -layer] ni {top desk}} {
        error "wm-widget $name: -layer is top or desk"
    }
    dict set ::widgets $name $opts
    widgets-rebuild-soon
}
# The panels' own pattern, and needed for the same reason: a config
# declares widgets at load time, and there is no policy-apply on the
# way UP — only on a reload. Deferring to idle also coalesces a
# config's five declarations into one build.
proc widgets-rebuild-soon {} {
    if {[info exists ::widget_pending]} return
    set ::widget_pending 1
    after idle {unset ::widget_pending; widgets-build}
}

# The rectangle a widget is placed against.
proc widget-host-rect {name opts} {
    set on [dict get $opts -on]
    switch -- [lindex $on 0] {
        workarea { return [workarea] }
        screen   { lassign [screen-size] sw sh; return [list 0 0 $sw $sh] }
        panel {
            set p [lindex $on 1]
            if {$p eq ""} { set p default }
            if {$p ni [panel-names]} {
                puts "WM: widget $name: no panel «$p» to sit on"
                return {}
            }
            # The panel's BAND — the strip of screen it reserved — which
            # is a rectangle. (panel-geometry is the other thing: how
            # the buttons inside it measure up, and it has no corner.)
            set band [strip-band $p]
            if {![llength $band]} {
                puts "WM: widget $name: panel «$p» has no band to sit in"
                return {}
            }
            return $band
        }
    }
    puts "WM: widget $name: cannot read -on «$on»"
    return {}
}


proc widgets-layer {} {
    foreach name [array names ::widget_top] { widget-layer $name }
}
# Only a widget with a WINDOW of its own has a layer to lose; one that
# rides a panel is inside it and needs nobody's help.
proc widget-layer {name} {
    if {![info exists ::widget_top($name)]} return
    set w $::widget_top($name)
    if {![winfo exists $w]} return
    if {[dict get [dict get $::widgets $name] -layer] eq "desk"} {
        lower $w
    } else {
        raise $w
    }
}

# A widget that RIDES A PANEL makes it thicker, exactly as the tray
# does: the band a strip reserves is the deepest thing in it. Without
# that the desk's first clock hung over the edge of a 38px panel, being
# 65px tall — honest, and useless.
#
# The size is only known once the content is built, so the build is in
# two halves: make them all (withdrawn, unmeasured by anyone), and only
# then, if the reserved depth changed, rebuild the strips and publish
# the workarea before placing. Two passes, no settling loop.
array set widget_thick {}   ;# PANEL -> the deepest widget riding it
proc widgets-thickness {panel} {
    expr {[info exists ::widget_thick($panel)] ? $::widget_thick($panel) : 0}
}
proc widget-claims-band {name opts} {
    if {![info exists ::widget_size($name)]} return
    set on [dict get $opts -on]
    if {[lindex $on 0] ne "panel"} return
    set p [lindex $on 1]
    if {$p eq ""} { set p default }
    if {$p ni [panel-names]} return
    # From the MEASUREMENT, not from a window: at this point the widget
    # has no window anywhere, which is what the measuring pass is for.
    lassign $::widget_size($name) cw ch
    set deep [expr {[panel-cfg $p side] in {left right} ? $cw + 2 : $ch + 2}]
    if {$deep > [widgets-thickness $p]} { set ::widget_thick($p) $deep }
}

# PASS ONE: how big is it? Built in a scratch toplevel nobody sees,
# measured, thrown away. The size cannot be asked of the host, because
# what the host reserves depends on the answer.
proc widget-measure {name} {
    set opts [dict get $::widgets $name]
    set type [dict get $opts -type]
    if {![dict exists $::widget_types $type]} {
        puts "WM: widget $name: no type «$type» is declared"
        return 0
    }
    destroy .wgmeasure
    toplevel .wgmeasure
    wm withdraw .wgmeasure
    set c [widget-content .wgmeasure.c $name $opts]
    if {$c eq ""} { destroy .wgmeasure; return 0 }
    update idletasks
    set ::widget_size($name) [list [winfo reqwidth $c] [winfo reqheight $c]]
    destroy .wgmeasure
    widget-claims-band $name $opts
    return 1
}
# The content itself, in whatever parent it is given — the one thing a
# widget type ever sees.
proc widget-content {c name opts} {
    set spec [dict get $::widget_types [dict get $opts -type]]
    frame $c -background [dict get $opts -background] \
        -padx [dict get $opts -padding] -pady [dict get $opts -padding]
    if {[catch {uplevel #0 [list {*}[dict get $spec build] $c $opts]} err]} {
        puts "WM: widget $name: build failed: $err"
        destroy $c
        return ""
    }
    return $c
}
# PASS TWO: build it where it lives, now that the strips know how deep
# to be. A panel host takes the widget INTO its own window; anything
# else gets a toplevel of its own, placed and lowered or raised.
proc widget-show {name} {
    set opts [dict get $::widgets $name]
    set on [dict get $opts -on]
    set rect [widget-host-rect $name $opts]
    if {![llength $rect]} return
    lassign $rect hx hy hw hh
    lassign $::widget_size($name) cw ch
    lassign [anchor-of [dict get $opts -place]] halign valign
    if {[lindex $on 0] eq "panel"} {
        set p [lindex $on 1]
        if {$p eq ""} { set p default }
        set host [panel-window $p]
        if {$host eq ""} return
        # ...inside the panel, in the panel's own coordinates. The old
        # one goes first: a panel rebuild brings us back here, and a
        # frame that is still there from the last time is an error, not
        # a saving.
        destroy $host.wg$name
        set c [widget-content $host.wg$name $name $opts]
        if {$c eq ""} return
        set X [place-axis $hx $hw $cw $halign]
        set Y [place-axis $hy $hh $ch $valign]
        place $c -x [expr {$X - $hx}] -y [expr {$Y - $hy}]
        set ::widget_win($name) $c
        puts "WM: widget $name ([dict get $opts -type]) ${cw}x${ch}+${X}+${Y}\
 inside the «$p» panel's own window"
    } else {
        set w .wg$name
        destroy $w
        toplevel $w -background $::OUTLINE
        wm overrideredirect $w 1
        wm withdraw $w
        wm title $w tk9wm-widget-$name
        set c [widget-content $w.c $name $opts]
        if {$c eq ""} { destroy $w; return }
        place $c -x 1 -y 1
        wm geometry $w [expr {$cw + 2}]x[expr {$ch + 2}]+[place-axis \
            $hx $hw [expr {$cw + 2}] $halign]+[place-axis $hy $hh \
            [expr {$ch + 2}] $valign]
        update idletasks
        wm deiconify $w
        set ::widget_win($name) $c
        set ::widget_top($name) $w
        widget-layer $name
        puts "WM: widget $name ([dict get $opts -type]) [wm geometry $w] on\
 $on, layer [dict get $opts -layer]"
    }
    set spec [dict get $::widget_types [dict get $opts -type]]
    if {[dict exists $spec every]} { widget-tick $name }
}

# The heartbeat. It reschedules itself from the WIDGET's own existence,
# so a rebuild does not need to chase timers: the tick of a widget that
# is gone simply stops.
proc widget-tick {name} {
    if {![info exists ::widget_win($name)]} return
    set c $::widget_win($name)
    if {![winfo exists $c]} { unset ::widget_win($name); return }
    set opts [dict get $::widgets $name]
    set spec [dict get $::widget_types [dict get $opts -type]]
    if {[dict exists $spec tick]} {
        if {[catch {uplevel #0 [list {*}[dict get $spec tick] $c $opts]} err]} {
            puts "WM: widget $name: tick failed: $err"
        }
        # A clock is wider at 10:00 than at 9:00. Re-place only when the
        # content really changed size — and through the whole build,
        # since a wider widget may want a deeper strip.
        update idletasks
        if {[list [winfo reqwidth $c] [winfo reqheight $c]] \
                ne $::widget_size($name)} {
            widgets-rebuild-soon
        }
    }
    after [dict get $spec every] [list widget-tick $name]
}

# All of them, from nothing — the panels' own pattern, and for the same
# reason: what a reload changes about a widget can be anything at all.
# Measure them all, let the strips grow if they must, then build them
# where they live. The flag is what keeps that from spiralling: the
# panels-build in the middle calls back here, and once is enough.
keep widgets_building 0
proc widgets-build {} {
    if {$::widgets_building} return
    set ::widgets_building 1
    try {
        foreach name [array names ::widget_top] { destroy $::widget_top($name) }
        array unset ::widget_top
        array unset ::widget_win
        array unset ::widget_size
        set was [lsort [array get ::widget_thick]]
        array unset ::widget_thick
        dict for {name opts} $::widgets { widget-measure $name }
        if {[lsort [array get ::widget_thick]] ne $was} {
            # A strip has to be deeper (or may be shallower) than it
            # was: rebuild it and say so, before anything is placed.
            panels-build
            publish-workarea
        }
        dict for {name opts} $::widgets { widget-show $name }
    } finally {
        set ::widgets_building 0
    }
}
