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

keep widget_types {}   ;# TYPE -> {build CMD ?tick CMD? ?every MS?}
keep widgets {}        ;# NAME -> options, in declaration order
array set widget_win {}    ;# NAME -> the container toplevel
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

proc widget-place {name} {
    if {![info exists ::widget_win($name)]} return
    set w $::widget_win($name)
    set opts [dict get $::widgets $name]
    set rect [widget-host-rect $name $opts]
    if {![llength $rect]} return
    lassign $rect hx hy hw hh
    update idletasks
    set cw [winfo reqwidth $w.c]
    set ch [winfo reqheight $w.c]
    set W [expr {$cw + 2}]
    set H [expr {$ch + 2}]
    lassign [anchor-of [dict get $opts -place]] halign valign
    wm geometry $w ${W}x${H}+[place-axis $hx $hw $W $halign]+[place-axis\
 $hy $hh $H $valign]
    set ::widget_size($name) [list $cw $ch]
    update idletasks
}

proc widget-layer {name} {
    if {![info exists ::widget_win($name)]} return
    set w $::widget_win($name)
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
    if {![info exists ::widget_win($name)]} return
    set on [dict get $opts -on]
    if {[lindex $on 0] ne "panel"} return
    set p [lindex $on 1]
    if {$p eq ""} { set p default }
    if {$p ni [panel-names]} return
    set w $::widget_win($name)
    set deep [expr {[panel-cfg $p side] in {left right}
        ? [winfo reqwidth $w.c] + 2 : [winfo reqheight $w.c] + 2}]
    if {$deep > [widgets-thickness $p]} { set ::widget_thick($p) $deep }
}

# Nothing maps before it knows where it goes — the key echo's lesson,
# and it costs one line here (the container is built withdrawn).
proc widget-build {name} {
    set opts [dict get $::widgets $name]
    set type [dict get $opts -type]
    if {![dict exists $::widget_types $type]} {
        puts "WM: widget $name: no type «$type» is declared"
        return
    }
    set spec [dict get $::widget_types $type]
    set w .wg$name
    destroy $w
    toplevel $w -background $::OUTLINE
    wm overrideredirect $w 1
    wm withdraw $w
    wm title $w tk9wm-widget-$name
    frame $w.c -background [dict get $opts -background] \
        -padx [dict get $opts -padding] -pady [dict get $opts -padding]
    place $w.c -x 1 -y 1
    if {[catch {uplevel #0 [list {*}[dict get $spec build] $w.c $opts]} err]} {
        puts "WM: widget $name: build failed: $err"
        destroy $w
        return
    }
    set ::widget_win($name) $w
    update idletasks          ;# the content settles; its size is now known
    widget-claims-band $name $opts
}
# ...and the second half, once the strips know how deep to be.
proc widget-show {name} {
    if {![info exists ::widget_win($name)]} return
    set w $::widget_win($name)
    set opts [dict get $::widgets $name]
    widget-place $name
    wm deiconify $w
    widget-layer $name
    puts "WM: widget $name ([dict get $opts -type]) [wm geometry $w] on\
 [dict get $opts -on], layer [dict get $opts -layer]"
    set spec [dict get $::widget_types [dict get $opts -type]]
    if {[dict exists $spec every]} { widget-tick $name }
}

# The heartbeat. It reschedules itself from the WIDGET's own existence,
# so a rebuild does not need to chase timers: the tick of a widget that
# is gone simply stops.
proc widget-tick {name} {
    if {![info exists ::widget_win($name)]} return
    set w $::widget_win($name)
    if {![winfo exists $w]} { unset ::widget_win($name); return }
    set opts [dict get $::widgets $name]
    set spec [dict get $::widget_types [dict get $opts -type]]
    if {[dict exists $spec tick]} {
        if {[catch {uplevel #0 [list {*}[dict get $spec tick] $w.c $opts]} err]} {
            puts "WM: widget $name: tick failed: $err"
        }
        # A clock is wider at 10:00 than at 9:00: re-place, but only
        # when the content really changed size.
        update idletasks
        if {[list [winfo reqwidth $w.c] [winfo reqheight $w.c]] \
                ne $::widget_size($name)} {
            widget-place $name
            widget-layer $name
        }
    }
    after [dict get $spec every] [list widget-tick $name]
}

# All of them, from nothing — the panels' own pattern, and for the same
# reason: what a reload changes about a widget can be anything at all.
proc widgets-build {} {
    foreach {name w} [array get ::widget_win] { destroy $w }
    array unset ::widget_win
    array unset ::widget_size
    set was [lsort [array get ::widget_thick]]
    array unset ::widget_thick
    dict for {name opts} $::widgets { widget-build $name }
    if {[lsort [array get ::widget_thick]] ne $was} {
        # A strip has to be deeper (or may be shallower) than it was:
        # rebuild it and say so, before anything is placed against it.
        panels-build
        publish-workarea
    }
    dict for {name opts} $::widgets { widget-show $name }
}
