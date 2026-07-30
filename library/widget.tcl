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
# the flicker went. THE DESK IS ONE WINDOW TOO (the owner's next call,
# and now done): a single full-screen toplevel of ours at the bottom of
# the stack, which every desk-layer widget lives inside. It is optional
# — somebody who paints the root with xsetroot, or runs another desktop
# manager, switches it off with `set-desk-window off` and gets a
# toplevel per widget again, which is the old behaviour and the honest
# fallback rather than a refusal.
#
# WIDGETS SHARE AN AREA, and the area is what knows about layout. One
# per host and placement: widgets that name the same host and the same
# corner are laid out together, in DECLARATION ORDER, along the host's
# long axis (a row on a horizontal panel, a column on a vertical one
# and on the desk). A panel's area takes the free slot at the far end
# of the strip, BEFORE the tray, and the panel shortens its button row
# to make room — which is the whole of what went wrong before: the
# owner's clock, placed by its own corner, sat under the tray on a
# bottom panel (2026-07-30). Nothing places itself against a strip any
# more; the strip hands out slots.
#
# The layout engine inside an area is `grid`, not another treectrl. The
# owner suggested a treectrl and it would work, but everything it would
# buy here — declaration order, columns, alignment — grid already has
# without window elements, and treectrl's window elements are the
# fiddly part of that widget. If an area ever wants selection, hover or
# scrolling, that is the moment to change engines, and only area-layout
# would change.

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
    # -layer is now a consequence of the HOST — a panel is over the
    # clients, the desk window is under them — and is kept only so an
    # old config does not fail. Where a widget lives is -on.
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


# Only an area with a WINDOW of its own has a layer to lose — which is
# to say, only when the desk window is switched off. Inside a panel or
# inside the desk window, containment settles it and nobody has to
# keep saying so.
proc widgets-layer {} {
    foreach k [array names ::widget_top] {
        set w $::widget_top($k)
        if {[winfo exists $w]} { lower $w }
    }
    if {[winfo exists .desk]} { lower .desk }
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
array set widget_extent {}  ;# ...and how much of its LENGTH they want
array set widget_area {}    ;# area key -> the frame that holds them
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
    set vert [expr {[panel-cfg $p side] in {left right}}]
    set deep [expr {$vert ? $cw + 2 : $ch + 2}]
    set long [expr {$vert ? $ch : $cw}]
    if {$deep > [widgets-thickness $p]} { set ::widget_thick($p) $deep }
    # ...and along the strip they QUEUE, so the lengths add up (plus a
    # gap between neighbours, and one at each end).
    set have [widgets-extent $p]
    set ::widget_extent($p) [expr {$have + $long + $::widget_gap}]
}
keep widget_gap 6
proc widgets-extent {panel} {
    expr {[info exists ::widget_extent($panel)] ? $::widget_extent($panel) : 0}
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
# ---- the desk: one window of ours, at the bottom, optional ----
#
# Default ON, because a desk that owns its own background can put
# things on it; off for anybody who paints the root themselves
# (xsetroot, feh, another desktop manager), and then the desk-layer
# widgets fall back to a toplevel apiece.
keep desk_window 1
keep desk_background #2e3436
proc set-desk-window {on} {
    if {![string is boolean -strict $on]} {
        error "set-desk-window: on or off"
    }
    set ::desk_window [expr {$on ? 1 : 0}]
}
proc set-desk-background {colour} { set ::desk_background $colour }
proc desk-window {} { expr {[winfo exists .desk] ? ".desk" : ""} }
proc desk-window-build {} {
    if {!$::desk_window} { destroy .desk; return }
    if {![winfo exists .desk]} {
        toplevel .desk -background $::desk_background
        wm overrideredirect .desk 1
        wm title .desk tk9wm-desk
    }
    .desk configure -background $::desk_background
    lassign [screen-size] sw sh
    wm geometry .desk ${sw}x${sh}+0+0
    lower .desk
}

# PASS TWO: build it where it lives, now that the strips know how deep
# to be. A panel host takes the widget INTO its own window; anything
# else gets a toplevel of its own, placed and lowered or raised.
# An area is a frame in its host, holding the widgets that named the
# same host and corner, in declaration order. It is what gets placed;
# the widgets inside it only get gridded.
proc widget-area-of {opts} {
    set on [dict get $opts -on]
    if {[lindex $on 0] eq "panel"} {
        set p [lindex $on 1]
        if {$p eq ""} { set p default }
        return [list panel $p]
    }
    # desk, screen and workarea are all the desk, differing in the rect
    # a corner is measured against.
    list desk [lindex $on 0]
}
proc widget-host-window {area} {
    lassign $area kind what
    if {$kind eq "panel"} { return [panel-window $what] }
    return [desk-window]
}
# With the desk window switched off there is nothing to be inside, so
# an area on the desk layer gets a toplevel of its own — the old
# behaviour, kept as the fallback rather than as a refusal. It is the
# one case left where a layer has to be re-stated, and widgets-layer
# still does it.
proc area-own-toplevel {idx bg} {
    set w .wgarea$idx
    destroy $w
    toplevel $w -background $::OUTLINE
    wm overrideredirect $w 1
    wm withdraw $w
    wm title $w tk9wm-widget-area$idx
    return $w
}
proc widgets-in-area {area place} {
    set out {}
    dict for {name opts} $::widgets {
        if {[widget-area-of $opts] ne $area} continue
        if {[dict get $opts -place] ne $place} continue
        lappend out $name
    }
    return $out
}
proc widget-areas {} {
    set seen {}
    dict for {name opts} $::widgets {
        set k [list [widget-area-of $opts] [dict get $opts -place]]
        if {$k ni $seen} { lappend seen $k }
    }
    return $seen
}
proc area-build {area place idx} {
    lassign $area kind what
    set members [widgets-in-area $area $place]
    if {![llength $members]} return
    set bg [dict get [dict get $::widgets [lindex $members 0]] -background]
    set host [widget-host-window $area]
    set own ""
    if {$host eq ""} {
        if {$kind eq "panel"} return
        set own [area-own-toplevel $idx $bg]
        set host $own
    }
    set A $host.wgarea$idx
    destroy $A
    frame $A -background $bg
    set vert [expr {$kind eq "desk" ? 1
        : [panel-cfg $what side] in {left right}}]
    set i 0
    foreach name $members {
        set c [widget-content $A.w$name $name [dict get $::widgets $name]]
        if {$c eq ""} continue
        if {$vert} {
            grid $c -row $i -column 0 -sticky ew -pady [expr {$i ? 2 : 0}]
        } else {
            grid $c -row 0 -column $i -sticky ns -padx [expr {$i ? 2 : 0}]
        }
        set ::widget_win($name) $c
        incr i
    }
    update idletasks
    set aw [winfo reqwidth $A]
    set ah [winfo reqheight $A]
    if {$kind eq "panel"} {
        # THE STRIP HANDS OUT THE SLOT: the far end, before the tray,
        # centred across. A corner of one's own is what put the owner's
        # clock under the tray.
        set band [strip-band $what]
        if {$band eq ""} return
        lassign $band bx by bw bh
        set tray [expr {[tray-panel] eq $what ? [tray-extent] : 0}]
        if {$vert} {
            set ax [expr {($bw - $aw) / 2}]
            set ay [expr {$bh - $tray - $ah - $::widget_gap}]
        } else {
            set ax [expr {$bw - $tray - $aw - $::widget_gap}]
            set ay [expr {($bh - $ah) / 2}]
        }
        place $A -x $ax -y $ay
        puts "WM: widget area ${aw}x${ah}+[expr {$bx + $ax}]+[expr {$by + $ay}]\
 in the «$what» panel, before the tray ([llength $members]: $members)"
    } else {
        lassign [widget-host-rect-for $what] hx hy hw hh
        lassign [anchor-of $place] halign valign
        set ax [place-axis $hx $hw $aw $halign]
        set ay [place-axis $hy $hh $ah $valign]
        if {$own ne ""} {
            # ...in a window of its own, which then has to be placed
            # and kept on its layer.
            place $A -x 1 -y 1
            wm geometry $own [expr {$aw + 2}]x[expr {$ah + 2}]+${ax}+${ay}
            update idletasks
            wm deiconify $own
            lower $own
            set ::widget_top(area$idx) $own
        } else {
            place $A -x $ax -y $ay
        }
        puts "WM: widget area ${aw}x${ah}+${ax}+${ay} on the desk over $what\
 at «$place» ([llength $members]: $members)"
    }
    set ::widget_area([list $area $place]) $A
    foreach name $members {
        set spec [dict get $::widget_types [dict get [dict get $::widgets \
            $name] -type]]
        if {[dict exists $spec every]} { widget-tick $name }
    }
}
# What a desk-hosted corner is measured against.
proc widget-host-rect-for {what} {
    switch -- $what {
        workarea { return [workarea] }
        default  { lassign [screen-size] sw sh; return [list 0 0 $sw $sh] }
    }
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
        foreach k [array names ::widget_area] { destroy $::widget_area($k) }
        array unset ::widget_top
        array unset ::widget_area
        array unset ::widget_win
        array unset ::widget_size
        set was [lsort [array get ::widget_thick]]
        array unset ::widget_thick
        array unset ::widget_extent
        dict for {name opts} $::widgets { widget-measure $name }
        desk-window-build
        if {[lsort [array get ::widget_thick]] ne $was} {
            # A strip has to be deeper (or may be shallower) than it
            # was: rebuild it and say so, before anything is placed.
            panels-build
            publish-workarea
        }
        set idx 0
        foreach k [widget-areas] {
            incr idx
            area-build [lindex $k 0] [lindex $k 1] $idx
        }
    } finally {
        set ::widgets_building 0
    }
}
