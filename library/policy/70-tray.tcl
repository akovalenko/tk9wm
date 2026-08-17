# ---- the system tray strip ----
# Where docked icons live: a strip of square cells at the FAR end of
# its panel's band (the right end of a horizontal one, the bottom end
# of a vertical one), in its own override-redirect top-level so a panel
# rebuild — which destroys the strip outright — cannot take somebody's
# icon down with it.
#
# WHICH panel is a knob (set-tray-panel, default `default`): with more
# than one panel on the desk the tray has to be told whose bar it is
# part of, and the answer decides its edge, its orientation and the
# band it shares. A tray on a panel with no buttons is the panel-less
# case of old — the band is then the tray's alone.
#
# Off by default, like the panel: `set-tray on` in the config claims
# _NET_SYSTEM_TRAY_S<screen> (the substrate does the protocol; a
# display that already has a tray keeps it and we stay off). The
# cells are plain frames — an icon is a foreign X window reparented
# into one, and the cell's BACKGROUND is what shows through the
# transparent parts of it. That is the whole "why is my icon on a
# black square" story: we hand it the strip's own color, not black.
#
# The strip carves the workarea exactly as the panel does (the two
# share an edge, so the carve is the thicker of them), and the panel
# shortens its button row by the strip's length so the two never
# overlap.
keep tray_on 0
keep tray_icon_size 24    ;# the freedesktop-conventional cell
keep tray_gap 4           ;# between cells
keep tray_pad 3           ;# around the row
keep tray_bg #2e3436      ;# what shows through a transparent icon
keep tray_bg_said {}      ;# ...and the word a layer spoke, if it did
keep tray_sid 0
keep tray_order {}        ;# icon windows, in dock order
keep tray_seen_extent 0   ;# the length the panel last reserved for us
keep tray_geo ""          ;# the strip geometry we last asked for
# A SCRIPT THAT HOLDS THE DESK is worth knowing about whatever the
# reason (the plan's answer to «forbid a bare exec»: measure instead
# of forbidding — a slow `send`, a long `after` and a loop hang the
# desk exactly as well, and no linter can see them).
keep key_hold_warn 1000   ;# ms — over this, the desk says it was held
keep tray_argb 0          ;# the default follows the compositor, see below
keep tray_strip_argb 0    ;# ...and what the LIVE strip was built with
keep tray_laid_size 0     ;# the cell size the live cells were laid out at
keep tray_panel default   ;# whose bar the tray is part of
# The panel the tray rides on. Not resolved against the declared ones:
# a name nobody declared is still a band of its own here (that is the
# tray-and-no-buttons case, and panel-cfg answers for the edge), so the
# tray never loses its strip to a config that only forgot a button.
proc tray-panel {} { return $::tray_panel }
proc tray-side {} { panel-cfg [tray-panel] side }
# One reconcile per config's worth of knob twiddles — the same shape as
# panel-rebuild-soon, and for a sharper reason than saving work.
#
# A reload puts every wish back to the code's default and then lets the
# config speak, so WHILE THE CONFIG IS SPEAKING the wish set is
# half-built, and neither half is the truth yet. At `set-tray-argb on`
# the tray is not asked for at all (::tray_on is still the reset 0); at
# `set-tray on` the ARGB wish may still be the reset 0 under a strip
# that is 32-bit. Reconciling at either of those moments reads the
# half-built wish as a real one — and both readings say "tear the strip
# down", one as "no tray wanted", the other as "the visual moved".
# Which is somebody else's window un-embedded: the Tk client re-docks
# with a NEW window, the GTK one dies outright (measured,
# run-trayargb-test.sh) and so does nm-applet (owner's report,
# 2026-07-29). Deferred to the idle AFTER the config has finished, the
# knobs are seen together, the live-and-still-wanted case does nothing,
# and the order the config writes them in stops mattering for real.
proc tray-reconcile-soon {} {
    if {![info exists ::tray_pending]} {
        set ::tray_pending 1
        after idle {unset ::tray_pending; tray-reconcile}
    }
}
# The wish (::tray_on, ::tray_argb) and the LIVE state (a claimed
# selection, a built strip) are two different things, and this is the
# one place that brings them together. Everything else just says what
# it wants and calls here.
#
# Written this way because of a config RELOAD. The reset puts the wish
# back to "no tray" and the config then asks for one again — and if
# that were carried out literally, every reload would tear the tray
# down and build it again. A tray icon is somebody else's window: GTK
# answers being un-embedded by DESTROYING its icon window and making a
# new one (measured), and nm-applet does not survive the trip at all —
# it takes an X error on a window that went out from under it (owner's
# report, 2026-07-29). So: if the tray is live and still wanted, this
# does NOTHING, and the icons never notice a reload happened.
proc tray-reconcile {} {
    set live [expr {$::tray_owner != 0 && [winfo exists .tray]}]
    # A window's visual is fixed when it is created, so a change of
    # mind about ARGB is the one wish that needs the strip rebuilt.
    set rebuild [expr {$live && $::tray_on && $::tray_strip_argb != $::tray_argb}]
    if {$live && (!$::tray_on || $rebuild)} {
        tray-stop [expr {$rebuild ? {the tray visual changed}
                                  : {the config no longer asks for a tray}}]
        destroy .tray
        if {[winfo exists .traybg]} { destroy .traybg }
        set ::tray_geo ""
        set ::tray_seen_extent 0
        set live 0
    }
    if {$::tray_on && !$live} {
        # The strip is built FIRST: its visual is what the claim
        # advertises, and a client may dock the instant it hears the
        # announcement.
        tray-ensure
        set vis 0
        if {$::tray_argb} { scan [winfo visualid .tray] %x vis }
        # a vertical panel gets a vertical tray — the orientation is
        # published for the icons, which size themselves by it
        set ::tray_on [tray-start [expr {[tray-side] in {left right}
            ? "vertical" : "horizontal"}] $vis]
        if {$::tray_on} {
            set ::tray_strip_argb $::tray_argb
            tray-adopt-orphans   ;# ours from before, if any are waiting
        } else {
            destroy .tray
        }
    }
    # ...and the BAND it lives in comes and goes with it: a panel is
    # built for its buttons, and a tray-only panel has none (see
    # panels-build).
    panel-rebuild-soon
    tray-layout
}
# The ARGB experiment, off by default and deliberately so.
#
# On, the strip becomes a 32-bit top-level and we ADVERTISE that visual
# (_NET_SYSTEM_TRAY_VISUAL): a toolkit that sees the offer makes its
# icon in the same visual and paints it with alpha. Two things then
# have to hold, and both are ours to arrange: the cell must be the same
# depth (only then is ParentRelative legal, and only then does the
# icon's transparency show OUR color rather than black), and a
# compositor must be running to blend the strip — the server never
# blends a child window's alpha by itself.
#
# The catch that makes this more than a flag: Tk computes a color's
# pixel from the visual's masks, and a TrueColor visual has no mask
# over the alpha bits — so every Tk color in a 32-bit visual comes out
# with alpha ZERO, which a compositor draws as "not there". The strip
# would be an invisible bar with icons floating over the wallpaper. So
# the background pixel is set from outside Tk, alpha byte and all (see
# tray-paint-opaque) — that is what the shim's `window background`
# primitive is for.
#
# Chrome ignores the negotiation and makes an ARGB icon whether or not
# we advertise (measured 2026-07-29), so with the offer OFF it is the
# one client that looks wrong, and with it ON it is the one client that
# looks right. Hence a knob and not a default.
# WHAT THE TRAY'S TRANSPARENCY DEFAULTS TO, when nobody has said.
# An ARGB tray on a desk with no compositor shows its icons over
# black, which is worse than not asking for one; with a compositor it
# is what everybody wants. So the answer is the environment's, and
# the config's word — said in either layer — still beats it.
proc tray-argb-default {} {
    foreach layer {custom config} {
        if {[dict exists $::layer_knobs $layer set-tray-argb]} return
    }
    set has [compositor?]
    puts "WM: compositor [expr {$has ? {is running in this session} \
        : {is not running here}}] — tray argb defaults to\
 [expr {$has ? {on} : {off}}]"
    set ::tray_argb [expr {$has ? 1 : 0}]
}
proc set-tray-argb {on} {
    set want [expr {$on ? 1 : 0}]
    if {$want && [argb-visual] eq ""} {
        puts "WM: tray: no 32-bit TrueColor visual on this screen — ARGB refused"
        return
    }
    set ::tray_argb $want
    settle-soon tray      ;# a live strip is rebuilt only if the visual moved
}
# The visual itself is asked of argb-visual (20-geometry) — the frames
# dress by the same answer now, so it lives with them.
# The backdrop, and why the ARGB strip needs one — measured, not
# reasoned (run-trayargb-test.sh, 2026-07-29).
#
# With the ARGB offer taken, an icon's see-through parts are alpha ZERO
# in the top-level's composite pixmap, and the compositor duly shows
# whatever is BEHIND the strip: the wallpaper, through a hole the size
# of the icon. ParentRelative does not save it — the toolkit sets its
# own transparent background in ARGB mode and paints over ours. Nor
# does painting the strip opaque: the icon's own window covers the
# cell, and a child's pixels replace the parent's in that pixmap.
#
# So what is behind the strip has to be OURS: a plain, opaque
# 24-bit top-level of exactly the strip's geometry, stacked directly
# under it. The holes then show the tray's own color, the icon's
# antialiased edge blends against it, and nothing of the desk shows
# through. Only in ARGB mode — the default strip is opaque by itself.
proc tray-backdrop {geo} {
    if {!$::tray_argb} {
        if {[winfo exists .traybg]} { destroy .traybg }
        return
    }
    if {![winfo exists .traybg]} {
        toplevel .traybg -background $::tray_bg
        wm overrideredirect .traybg 1
        # dock, like the strip it floors: its own shadow otherwise
        # falls where the backdrop ends and the panel's widgets begin
        wm attributes .traybg -type dock
        wm withdraw .traybg
    }
    if {$geo eq ""} { wm withdraw .traybg; return }
    wm geometry .traybg $geo
    wm deiconify .traybg
    stack-layer .traybg $::LAYER_DOCK 1   ;# ...the strip's opaque floor...
}
proc set-tray-icon-size {px} {
    set ::tray_icon_size $px
    tray-layout
}
# The cells follow the size knob; so must the foreign windows sitting
# in them, or a reload that changes the size leaves every icon drawn at
# the old one. The refit is the substrate's — it owns what an icon is
# held at — and costs nothing when the size did not move.
proc tray-refit-cells {} {
    if {$::tray_laid_size == $::tray_icon_size} return
    set ::tray_laid_size $::tray_icon_size
    foreach w $::tray_order {
        $::tray_slot($w) configure \
            -width $::tray_icon_size -height $::tray_icon_size
    }
    tray-refit $::tray_icon_size
}
proc set-tray-background {color} {
    set ::tray_bg_said $color
    set ::tray_bg $color
    settle-soon tray
}
# APPLYING A COLOUR IS NOT THE SETTER'S PRIVATE BUSINESS. It was, and
# so a RESET — which puts the variable back and calls nobody — left
# the strip wearing the colour a customization had given it: the
# owner erased his and watched the icon cells go back while the space
# around them stayed (the cells are re-made on the next layout, the
# strip and its backdrop are not). So the application lives in one
# proc, and the apply path calls it like any other reconciliation.
proc tray-recolor {} {
    if {[winfo exists .traybg]} { .traybg configure -background $::tray_bg }
    if {![winfo exists .tray]} return
    .tray configure -background $::tray_bg
    foreach w $::tray_order {
        if {[info exists ::tray_slot($w)] && [winfo exists $::tray_slot($w)]} {
            $::tray_slot($w) configure -background $::tray_bg
        }
    }
}
proc tray-ensure {} {
    if {[winfo exists .tray]} return
    if {$::tray_argb && [set v [argb-visual]] ne ""} {
        toplevel .tray -background $::tray_bg -visual $v -colormap new
    } else {
        toplevel .tray -background $::tray_bg
    }
    wm overrideredirect .tray 1   ;# our own furniture, not a client
    # _NET_WM_WINDOW_TYPE_DOCK — the word a compositor excuses panels
    # from shadows by (compton -C, picom's wintypes). Without it the
    # strip is shadowed like any window, and on the ARGB strip the
    # shadow is drawn BEHIND it — straight through every icon's
    # transparent pixels onto the backdrop, which is how a light theme
    # wore dark grey icon cells the moment shadows went on (the owner,
    # 2026-08-17). Every strip of ours says the word: this one, its
    # backdrop, the panels (65-registry) — and the desk window says
    # DESKTOP (widget.tcl).
    wm attributes .tray -type dock
    wm withdraw .tray             ;# shown by tray-layout once it holds a cell
}
# The substrate's hooks. The Tk round trip before the return is the
# same guarantee policy-attach gives for a frame slot: the window
# exists server-side before anything is reparented into it.
proc policy-tray-attach {w} {
    if {!$::tray_on} { return {0 0} }
    tray-ensure
    set f .tray.i[incr ::tray_sid]
    # The cell inherits the strip's visual (a child of a 32-bit
    # top-level is 32-bit unless told otherwise) — which is what makes
    # ParentRelative legal for an ARGB icon.
    frame $f -width $::tray_icon_size -height $::tray_icon_size \
        -background $::tray_bg
    set ::tray_slot($w) $f
    lappend ::tray_order $w
    tray-layout
    update idletasks
    winfo pointerxy $f
    puts "WM: tray cell $f for 0x[format %x $w]"
    return [list [winfo id $f] $::tray_icon_size]
}
proc policy-tray-detach {w} {
    if {![info exists ::tray_slot($w)]} return
    destroy $::tray_slot($w)
    unset ::tray_slot($w)
    set ::tray_order [lsearch -exact -all -inline -not $::tray_order $w]
    tray-layout
}
proc policy-tray-origin {w} {
    if {![info exists ::tray_slot($w)]} { return {0 0} }
    set f $::tray_slot($w)
    list [winfo rootx $f] [winfo rooty $f]
}
# The strip's measures: extent along its panel's edge, thickness across
# it — zero when the tray is off or empty, so neither the workarea nor
# the panel reserves anything for a strip that is not there. The
# thickness matches its panel's when that panel has buttons, so the two
# read as a single bar.
proc tray-extent {} {
    set n [llength $::tray_order]
    if {!$::tray_on || $n == 0} { return 0 }
    expr {2*$::tray_pad + $n*$::tray_icon_size + ($n - 1)*$::tray_gap}
}
proc tray-thickness {} {
    if {[tray-extent] == 0} { return 0 }
    expr {max(2*$::tray_pad + $::tray_icon_size, [panel-thickness [tray-panel]])}
}
proc tray-layout {} {
    if {![winfo exists .tray]} return
    set len [tray-extent]
    if {$len == 0} {
        wm withdraw .tray
        set ::tray_geo ""
        tray-backdrop ""
        tray-tell-panel
        return
    }
    tray-refit-cells        ;# the size knob may have moved under them
    set thick [tray-thickness]
    set side [tray-side]
    set vert [expr {$side in {left right}}]
    # The FAR end of our panel's band: the end with the larger
    # coordinate along the band's long axis — the right end of a
    # horizontal bar, the bottom end of a vertical one. Taken from the
    # band and not from the screen, so a tray on the second panel
    # declared lands inside what the first one left.
    set band [strip-band [tray-panel]]
    if {$band eq ""} { set band [panel-monitor [tray-panel]] }
    # A PIXEL SHORT OF THE FACE: the band's inner row is the panel's
    # hairline, drawn once on the panel's own window — the tray backs
    # off it rather than re-drawing it (the owner's trade, 2026-08-05).
    # A tray whose band holds no panel window has no line to yield to.
    if {[panel-window [tray-panel]] ne ""} {
        lassign $band - - bandw bandh
        set thick [expr {min($thick, ($vert ? $bandw : $bandh) - 1)}]
    }
    set sz $::tray_icon_size
    set cross [expr {($thick - $sz) / 2}]   ;# centered across the strip
    set i 0
    foreach w $::tray_order {
        set off [expr {$::tray_pad + $i*($sz + $::tray_gap)}]
        if {$vert} {
            place $::tray_slot($w) -x $cross -y $off -width $sz -height $sz
        } else {
            place $::tray_slot($w) -x $off -y $cross -width $sz -height $sz
        }
        incr i
    }
    lassign [band-strip $band $side $thick] bx by bw bh
    if {$vert} {
        set geo ${thick}x${len}+${bx}+[expr {$by + $bh - $len}]
    } else {
        set geo ${len}x${thick}+[expr {$bx + $bw - $len}]+${by}
    }
    wm geometry .tray $geo
    tray-backdrop $geo       ;# the opaque floor under an ARGB strip
    destroy .tray.hair .traybg.hair   ;# step 182's first cut drew here
    wm deiconify .tray
    stack-layer .tray $::LAYER_DOCK 2   ;# ...and the icons over both
    restack-soon             ;# the strip is a new window; seat it by layer
    # The COMPUTED string, not [wm geometry .tray]: that answers with
    # the geometry Tk has processed so far, which right after the
    # request is still the previous one — and a re-layout runs twice per
    # change (the attach, then the panel rebuild it kicks), so the log
    # would show every size one step late. Logged only when it moves.
    if {$geo ne $::tray_geo} {
        set ::tray_geo $geo
        puts "WM: tray strip $geo ([llength $::tray_order] icons)"
        publish-workarea   ;# a strip that grew took more of the screen
    }
    tray-tell-panel
}
# The panel shortens its row by our length — but only a CHANGED length
# is worth a rebuild: panels-build calls tray-layout at its end, so an
# unconditional kick would be an idle loop between the two.
proc tray-tell-panel {} {
    if {$::tray_seen_extent == [tray-extent]} return
    set ::tray_seen_extent [tray-extent]
    panel-rebuild-soon
}

# The screen changed size under us (RandR: a resized Xephyr window, a
# mode switch): the panel is glued to the bottom edge, so re-place it.
# Debounced — an interactive Xephyr resize streams a notify per step,
# and rebuilding the strip on each would thrash.
keep panel_resize_pending ""
proc policy-screen-changed {} {
    after cancel $::panel_resize_pending
    # the tray is glued to a corner of the same band; panels-build ends
    # by re-laying it out, and tray-layout covers the panel-less case
    set ::panel_resize_pending \
        [after 200 {panels-build; fullscreen-refit}]
}
# A fullscreen window is glued to the screen the same way the strips
# are glued to its edge, so the same notify has to re-fit it — a screen
# that grew would otherwise leave the window at the old size with a
# band of desk around it, and one that shrank would leave it hanging
# off the edge.
proc fullscreen-refit {} {
    foreach w [array names ::fullscreen] {
        if {![info exists ::frameof($w)]} continue
        set t $::frameof($w)
        # per window, because each covers ITS monitor — and re-judged
        # by overlap, so a window whose monitor left the layout lands
        # on whatever glass owns that ground now
        lassign [monitor-of-frame $t] mx my mw mh
        frame-layout $t $mw $mh $mx $my
        wm-resize-client $w $mw $mh
        send-synthetic-configure $w
    }
}

# ---- the workarea moved: the windows follow it ----
#
# The panel changes side on a reload, or grows a row, or a tray icon
# widens the band, or the screen resizes under everything — and the
# windows that were arranged AGAINST the old workarea are suddenly
# arranged against nothing. A maximized window keeps the old
# maximization's size in the new geometry; a window flush against the
# bottom strip now floats above where the strip used to be. Nothing
# moved them before this (owner's wish, 2026-07-30).
#
# ONE RULE, applied to each axis on its own, and everything else falls
# out of it. In an axis a window either
#
#   SPANS the workarea — it sits at the origin and is exactly as long as
#     maximize would have made it there — and then it spans the new one;
#   is flush at the NEAR edge, and stays flush at the new near edge;
#   is flush at the FAR edge, and stays flush at the new far one;
#   is flush at neither, and does not move in this axis at all.
#
# Both of the owner's asks are that rule: "what arithmetically looks
# maximized goes to the new maximization" is spanning in BOTH axes, and
# "what was stuck to the old border sticks to the new one" is the two
# flush cases. It also answers what he did not ask about and would have
# had to: a full-height column down the left side spans one axis and
# hugs one edge, and comes out re-fitted in the axis it filled and
# re-stuck in the other, which is the only reading that keeps it a
# column.
#
# Spanning is measured with maximize-fit and not with the raw extent,
# which is the whole reason that proc exists. An xterm maximized on an
# 800x562 workarea is not 562 tall — it is a whole number of cells and
# leaves slack at the edge — and a test that wanted the extent exactly
# would call the most obviously maximized window on the desk "flush at
# the near edge, nothing more" and never re-fit it.
#
# What the reflow does NOT do:
#
#   - it does not touch the maximized MARK, in either direction. This is
#     the WM moving furniture, not a hand on the window: `drop` sheds the
#     mark in resize-by-edge and only there, so a re-fitted maximized
#     window stays maximized. And a window that merely LOOKS maximized
#     is not marked as such by being re-fitted — it has no saved
#     geometry, and inventing one would lie to the toggle exactly the way
#     a size-yielding `place max` would (see the place grammar).
#   - it does not clamp anything back onto the screen. A window parked
#     half off the edge on purpose has a relation to no edge of ours,
#     and hauling it back would be a policy nobody asked for; a window
#     that sits UNDER the panel because it claimed that corner keeps
#     sitting there for the same reason (see clamp-to-screen).
#   - it leaves alone whatever a hand is holding — see geometry-held-p.
#
#   off    nothing follows: the workarea changes and the windows sit
#          where they were, which is what every version before this did.
#   max    only what looks maximized (spanning BOTH axes) follows.
#   stick  the whole rule above. The default.
#
# With monitors in the picture the rule runs PER MONITOR: the change
# arrives as two per-monitor pictures (policy-workareas), each window
# is judged against the workarea of the monitor it stood on in the OLD
# layout, and reflows to that monitor's new workarea. A monitor that
# left the layout takes its windows to the primary by the same axis
# rule — their workarea "moved" there, which is the honest reading of
# a projector unplugged.
keep workarea_follow stick
proc set-workarea-follow {mode} {
    if {$mode ni {off max stick}} {
        error "set-workarea-follow: off, max or stick"
    }
    set ::workarea_follow $mode
}
# Whose ground a rect stood on, among the monitors of ONE picture:
# largest overlap with the MONITOR rects (not the workareas — a window
# under the panel still belongs to that monitor), falling back to the
# picture's primary for a rect that touched none.
proc workarea-owner {d rect} {
    lassign $rect x y w h
    set best {}
    set besta 0
    dict for {key m} $d {
        lassign [dict get $m mon] mx my mw mh
        set a [expr {max(0, min($x + $w, $mx + $mw) - max($x, $mx))
                   * max(0, min($y + $h, $my + $mh) - max($y, $my))}]
        if {$a > $besta} { set besta $a; set best $key }
    }
    if {$besta > 0} { return $best }
    workarea-primary-key $d
}
proc workarea-primary-key {d} {
    dict for {key m} $d {
        if {[dict get $m primary]} { return $key }
    }
    lindex [dict keys $d] 0
}
proc policy-workarea-changed {old new} {
    if {$::workarea_follow eq "off"} return
    foreach w [array names ::frameof] {
        # Fullscreen is the screen's business and has its own refit; a
        # window under a gesture is somebody's business right now.
        if {[info exists ::fullscreen($w)] || [geometry-held-p $w]} continue
        set t $::frameof($w)
        if {![regexp {^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$} [wm geometry $t] \
                -> fw fh fx fy]} continue
        set key [workarea-owner $old [list $fx $fy $fw $fh]]
        set owa [dict get $old $key wa]
        set nwa [dict get $new [expr {[dict exists $new $key]
                                      ? $key : [workarea-primary-key $new]}] wa]
        if {$owa eq $nwa} continue
        reflow-client $w $owa $nwa
    }
}
# A hand is on this window's geometry at this moment: a title carry, a
# border or modifier-drag resize, a keyboard move/resize mode. The
# reflow leaves it be — it would be writing over the numbers the gesture
# is negotiating, and the keyboard mode's Escape remembers a geometry
# from before, which it would then restore to a workarea that no longer
# exists.
proc geometry-held-p {w} {
    if {[kbmr-owns $w]} { return 1 }
    if {[info exists ::drag($::frameof($w))]} { return 1 }
    if {[info exists ::mdrag] && [lindex $::mdrag 2] == $w} { return 1 }
    if {[info exists ::rz] && [lindex $::rz 7] == $w} { return 1 }
    return 0
}
# One axis. o0/o and n0/n are that axis of the old and the new workarea,
# p/s where the frame sits and how long it is, om/nm the length a
# maximized frame would have in each. Returns {position length how}.
# The FAR edge is asked about with SLACK, and that is not a fudge — it
# is the difference between this rule working for a browser and working
# for a terminal (the owner's report, 2026-07-30: on a panel change the
# browsers re-stuck and xterm and emacs sat where they were).
#
# A window whose size is quantized CANNOT put its far edge on the
# workarea's. Drag an xterm's bottom edge down until it stops at the
# panel and the height snaps to whole cells: the frame ends a few
# pixels short, for good, by construction. Asked for an exact match
# that window is "flush at neither edge" and never moves again —
# whereas a browser, free to be any height, lands on the pixel and
# re-sticks. Nothing about it is a browser-versus-terminal difference;
# it is a divisible-versus-quantized one.
#
# So flush at the far edge means AS CLOSE AS THIS WINDOW CAN GET: short
# by less than one increment. For a client with no increments the slack
# is 1 and the test is the exact one it always was. The near edge needs
# none of this — a position is never quantized — and neither does span:
# maximize fills to the pixel now (a maximized axis owes the increments
# nothing), so the span test is measured against an exact fit.
proc reflow-axis {o0 o n0 n p s om nm {slack 1}} {
    if {$p == $o0 && $s == $om}  { return [list $n0 $nm span] }
    if {$p == $o0}               { return [list $n0 $s near] }
    set short [expr {$o0 + $o - ($p + $s)}]
    if {$short >= 0 && $short < $slack} {
        # The near edge wins a window too long to fit, the same way
        # clamp-to-rect decides it: better to lose the far edge than the
        # one with the title bar on it. The slack travels with it: the
        # window keeps its size, so it ends up as short of the new far
        # edge as it was of the old one, which is how it looked.
        return [list [expr {max($n0, $n0 + $n - $s - $short)}] $s far]
    }
    return [list $p $s stay]
}
proc reflow-client {w old new} {
    set t $::frameof($w)
    lassign [frame-chrome $t] B top
    # Frame lengths throughout — the client's own size plus what the
    # decoration adds — because it is the FRAME that is flush with an
    # edge or fills the workarea, and the client size is what has to be
    # asked for at the end.
    set cw [$t.slot cget -width]; set ch [$t.slot cget -height]
    set fw [expr {$cw + 2*$B}];   set fh [expr {$ch + $top + $B}]
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> X Y
    lassign [maximize-fit $w $old] omw omh
    lassign [maximize-fit $w $new] nmw nmh
    # How close this client can get to a far edge at all — its own
    # granularity, whoever imposed it (see reflow-axis).
    lassign [client-size-hints $w] - - incw inch
    set incw [expr {max($incw, 1)}]
    set inch [expr {max($inch, 1)}]
    lassign [reflow-axis [lindex $old 0] [lindex $old 2] \
                         [lindex $new 0] [lindex $new 2] $X $fw \
                         [expr {$omw + 2*$B}] [expr {$nmw + 2*$B}] $incw] nX nfw hx
    lassign [reflow-axis [lindex $old 1] [lindex $old 3] \
                         [lindex $new 1] [lindex $new 3] $Y $fh \
                         [expr {$omh + $top + $B}] [expr {$nmh + $top + $B}] \
                         $inch] nY nfh hy
    # `max` means what it says: a window that does not look maximized —
    # spanning BOTH axes — is not touched at all, not even in the axis it
    # happens to fill.
    if {$::workarea_follow eq "max" && ($hx ne "span" || $hy ne "span")} return
    if {$nX == $X && $nY == $Y && $nfw == $fw && $nfh == $fh} return
    wm geometry $t +$nX+$nY
    wm-resize-client $w [expr {$nfw - 2*$B}] [expr {$nfh - $top - $B}]
    puts "WM: reflow 0x[format %x $w] $hx/$hy ->\
 [expr {$nfw - 2*$B}]x[expr {$nfh - $top - $B}]+$nX+$nY"
    maximize-settle $w    ;# the frame moved even where the size did not
    # The way back travels with the window. ::maxsaved is a rect in the
    # workarea that just moved, so the same rule says where it belongs
    # now: a window maximized on a desk whose panel then moved to the top
    # must not un-maximize to a place under the panel.
    if {![info exists ::maxsaved($w)]} return
    lassign $::maxsaved($w) scw sch sX sY
    lassign [reflow-axis [lindex $old 0] [lindex $old 2] \
                         [lindex $new 0] [lindex $new 2] $sX [expr {$scw + 2*$B}] \
                         [expr {$omw + 2*$B}] [expr {$nmw + 2*$B}] $incw] sX sfw -
    lassign [reflow-axis [lindex $old 1] [lindex $old 3] \
                         [lindex $new 1] [lindex $new 3] $sY [expr {$sch + $top + $B}] \
                         [expr {$omh + $top + $B}] [expr {$nmh + $top + $B}] \
                         $inch] sY sfh -
    set ::maxsaved($w) \
        [list [expr {$sfw - 2*$B}] [expr {$sfh - $top - $B}] $sX $sY]
}

