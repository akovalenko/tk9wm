# ---- the config layer: defaults, reset, apply ----
# A reload is "put everything back the way the CODE has it, then let the
# config speak again on that clean floor" — the owner's own contract for
# it. What that costs the config is one rule: it must be DECLARATIVE.
# Calling the set-* knobs, declaring panel buttons, style rules and key
# binds is all undoable, because the reset knows where that state
# lives. Redefining a policy or substrate proc is not: a reset has no
# way to remember what the proc used to be, and the next reload would
# be building on the patch. (Procs the config defines FOR ITSELF —
# predicates, launchers — are fine; they are just names, and the config
# redefines them on every load.)
#
# The defaults are not written down twice. They are SNAPSHOTTED from
# the code's own values the moment before the config is first sourced,
# so a default and its copy cannot drift apart: there is no copy.
set config_vars {
    border gripz titleair OUTLINE titlejust winlist_cycle_opt icon_path
    style_rules minimize maximize workarea_follow panels panel_target
    monitors_override ndesks
    panel_live_bar panel_live_face drag_mods drag_slop edge_resist root_cursor
    key_echo key_echo_place key_hold_warn KEY_ECHO_BAD KBMR_BG chord_hold
    last_started
    titlebar_buttons titlebar_gestures fade font_kin look_wishes
    widgets desk_window desk_background desk_background_said widget_gap
    theme
    tray_on tray_icon_size tray_gap tray_pad tray_bg tray_bg_said tray_argb
    tray_panel
    terminal_choice terminal_found emacs_frames emacs_daemons emacs_autodaemon
    emacs_edit emacs_edit_daemon emacs_keep_frame_name
    edit_door edit_door_found
    welcome key_bundles action_raw action_spec action_lint menus
    menu_griped winops_actions winops_items
}
proc policy-snapshot-defaults {} {
    # Incremental on purpose: a Reread may bring NEW config_vars into
    # a running desk, and the reset must find a default for every one
    # of them — each missing entry is snapshotted when first seen
    # (its keep just established the code default), and the entries
    # already taken stay as first taken: a config may have spoken
    # since, and its values are not defaults.
    foreach v $::config_vars {
        if {![info exists ::config_default($v)]} {
            set ::config_default($v) [set ::$v]
        }
    }
    if {![info exists ::config_default(DeskFont)]} {
        set ::config_default(DeskFont) [font actual DeskFont]
    }
}
proc policy-reset {} {
    # The tray is deliberately NOT torn down here, only WISHED away:
    # ::tray_on goes back to 0 with the other variables and the live
    # strip is left standing until policy-apply reconciles it with what
    # the new config asked for. A reload that keeps the tray therefore
    # does not disturb a single icon — and an icon is somebody else's
    # window, which does not always survive being un-embedded (see
    # tray-reconcile).
    foreach v $::config_vars { set ::$v $::config_default($v) }
    # The geometry memo goes with the variables it was measured from:
    # left standing, a mid-load workarea question answered with a
    # FRANKENSTEIN — the RESET panel's default side wearing the OLD
    # config's memoized thickness — and the retitle clamp then moved
    # windows against a workarea no config ever declared (measured:
    # the reflow suite's corner window came off its edge).
    array unset ::panel_geo
    # The base and the RELATIONS are the resettable state; the derived
    # fonts are a consequence and are recomputed from them.
    font configure DeskFont {*}$::config_default(DeskFont)
    fonts-derive
    title-metrics
    # Caches that a config decides the contents of: per-client style
    # verdicts (the rules are gone) and resolved icons (the path may
    # move under them).
    array unset ::styleof
    # The icons stay. They are files, not config state: a reload
    # re-checks each one's mtime and re-reads only what changed, and
    # never destroys an image a standing strip is drawing with.
    # Every chord, ours and the config's alike, and then our own floor
    # back down. keys-reset is the substrate's: the grabs are its.
    keys-reset
    policy-default-bindings
}
# ---- settlers: what a wish COSTS, named and ordered ---------------
#
# The apply used to be fourteen calls in a row with the reasons for
# their order written between them. The order is real knowledge —
# panels before widgets because widgets ride panels, the stack last
# because rebuilding furniture leaves whoever went up first underneath
# — and it was kept in exactly one place, which was good, and in a
# form nothing could ask about, which was not (lifecycle plan, step 3).
#
# So each step gets a NAME and the sequence becomes a declaration. What
# that buys immediately: a knob can say which settler makes its wish
# real (the `settle` facet), one settler failing no longer eats the
# rest of the apply (each runs soft), and the day the order needs a
# dependency graph, the list is already the data to build it from.
set settlers {}
proc settler {name script} { dict set ::settlers $name $script }

settler styles {
    # A VERDICT COMPUTED WHILE THE CONFIG WAS STILL SPEAKING IS
    # PROVISIONAL. policy-reset drops this cache before the config is
    # read, which is not enough: a knob that touches live frames —
    # set-title-font and set-title-justify both do, through
    # retitle-frames — asks every framed client for its style ON THE
    # SPOT, and the rules declared LATER in the same file are not there
    # yet. The verdict computed from half a config is then cached and
    # nothing drops it again.
    #
    # That is the owner's report (2026-07-30): his `wm-style always
    # {increments ignore}` sits below his set-title-font, so every
    # reload cached "respect" for every window on the desk and his
    # terminals started snapping to cells again. It depended on the
    # ORDER OF LINES IN HIS CONFIG, which is why it looked arbitrary —
    # and a RESTART cured it, adoption happening after the whole config
    # is read, which is why he could not pin it on either.
    array unset ::styleof
}
settler theme {
    # FIRST, because it decides the colours everything after it paints
    # with. Cheap to have here: theme-apply already goes through the
    # deferred builders rather than the direct ones, for the same
    # reason this whole mechanism exists.
    theme-apply
}
settler fonts       {fonts-derive}       ;# the derived faces follow the base
settler panels      {panels-build}       ;# no buttons declared -> the strip goes
settler tray        {tray-reconcile
                     tray-recolor}       ;# start, stop, or leave it exactly alone
settler desk-window {desk-window-build}  ;# on, off, and the colour of it
settler welcome     {welcome-inject}     ;# re-decided per load
settler widgets     {widgets-build}      ;# cheap by construction: all, from nothing
settler titles      {retitle-frames}     ;# live frames follow metrics and font
settler decor {
    # The corner grips: their length is drawn and hit-tested from the
    # frame's chrome verdict, so carry the wish into the look record —
    # gripz derives nothing, so no look-derive is owed — then refresh
    # each frame's verdict and repaint. No re-layout: the geometry did
    # not move. (A BORDER change is the titles settler's: everything
    # derives from it, so retitle-frames re-derives the record whole,
    # and the <Configure> it causes repaints the underlay by itself.)
    dict set ::looks default gripz $::gripz
    # ...and into every scheme whose wish does not SAY grips: an
    # unsaid key inherits from the desk live, here as at derivation.
    dict for {name wish} $::look_wishes {
        if {![dict exists $wish grips] && [dict exists $::looks $name]} {
            dict set ::looks $name gripz $::gripz
        }
    }
    foreach {w t} [array get ::frameof] {
        set ::chromeof($t) [chrome-of $w]
        deco-redraw $t
    }
}
settler cursor      {root-cursor-apply}  ;# the desk stops wearing the server's X
settler applets {
    # The APPLETS are not the desk: they live in their own processes
    # and are TOLD what the desk looks like now (ui-restyle). Same
    # shape as everything else here — a deed somebody owes, named.
    if {[llength [info commands ui-restyle]]} { ui-restyle }
}
settler workarea    {publish-workarea}
settler stack       {panel-on-top}
settler desks {
    # ...on whatever the layers finally said, including a config that
    # stopped saying anything (desks-apply is idle and coalesced, so
    # several declarations cost one settling).
    if {[llength [info commands desks-apply-soon]]} { desks-apply-soon }
}
settler layers {
    # Every framed client re-reads its layer, for the same reason the
    # style cache is dropped: the rules that decide it have just been
    # re-read, and a window keeping the layer an old config gave it
    # would be the one thing on the desk that did not hear the reload.
    foreach w [array names ::frameof] {
        unset -nocomplain ::layerof($w)
        client-layer-declare $w
    }
    restack-soon
}
settler matches     {panel-match-kick}
settler keys {
    # What holding the modifier would swallow, asked of the FINISHED
    # keymap: a config states the knob and its binds in whatever order
    # it likes, and a warning computed halfway through names half the
    # collisions.
    chord-hold-shadows
}

# THE ORDER, and this list is the only place it lives.
keep settle_order {
    styles theme fonts panels tray desk-window welcome widgets titles
    decor cursor applets workarea stack desks layers matches keys
}
# ONE settler, ASKED FOR rather than done — the shape the invariant
# needs: a word writes its wish and says which settler owes it a deed.
# Coalesced, and run in the DECLARED order rather than the order they
# were asked in, because three words in one config file must cost one
# settling and must not reorder the desk between them.
#
# Before this there were three deferral mechanisms with three private
# flags (panel-rebuild-soon, tray-reconcile-soon, widgets-rebuild-soon,
# desks-apply-soon) and a dozen setters that did their work on the
# spot. The flags stay where they are — they are each a settler's own
# business — but a WORD now has one way to ask.
array set settle_pending {}
keep settle_scheduled 0
proc settle-soon {name} {
    set ::settle_pending($name) 1
    if {$::settle_scheduled} return
    set ::settle_scheduled 1
    after idle settle-pending
}
proc settle-pending {} {
    set ::settle_scheduled 0
    set want [array names ::settle_pending]
    array unset ::settle_pending
    foreach n $::settle_order {
        if {[lsearch -exact $want $n] < 0} continue
        soft "settle $n" [dict get $::settlers $n]
    }
}
# WHAT LAST SETTLED, which is a different question from what the code
# defaults to. config_default answers «what does a reload reset the
# wishes to»; this answers «what did the desk last actually become»,
# and the difference between the two is the only way to say «this
# reload changed nothing» honestly (lifecycle plan, the last open
# question — the owner: "идея мне нравится, если для этого нужен
# второй снимок, то ok").
#
# It remembers the WHOLE config-produced state and not just the knobs'
# wishes, because most settlers are driven by collections — the panels'
# buttons, the widgets, the style rules — and a snapshot that watched
# only scalars would happily skip a reload that added a button.
array set settled_state {}
proc settle-remember {} {
    array unset ::settled_state
    foreach v $::config_vars {
        set ::settled_state($v) [expr {[info exists ::$v] ? [set ::$v] : ""}]
    }
}
# The first thing that differs, or "" when nothing does. The name is
# for the log: «nothing changed» is a claim worth being able to check,
# and «tray_on changed» says which word to look at.
proc settle-changed {} {
    foreach v $::config_vars {
        set now [expr {[info exists ::$v] ? [set ::$v] : ""}]
        if {![info exists ::settled_state($v)]} { return $v }
        if {$::settled_state($v) ne $now} { return $v }
    }
    return ""
}
proc settle-all {} {
    foreach name $::settle_order {
        if {![dict exists $::settlers $name]} {
            puts "WM: settle: no such settler «$name»"
            continue
        }
        # SOFT, one by one: before this the apply was a straight line,
        # so a settler that threw took every settler after it with it —
        # a desk half-applied and silent about which half.
        soft "settle $name" [dict get $::settlers $name]
    }
}

proc policy-apply {} {
    # NOTHING TO DO IS A THING TO SAY. A reload of an unchanged config
    # used to rebuild the panels, the widgets, the tray and every
    # titlebar to arrive exactly where it started — visible as a blink
    # and paid for in full. The snapshot makes the answer cheap, and
    # the FIRST apply has no snapshot, so a fresh desk always settles.
    # The FIRST apply has nothing to compare against, and saying that a
    # variable «moved» when nothing was ever remembered would be a lie
    # with a name in it.
    set first [expr {[array size ::settled_state] == 0}]
    set why [expr {$first ? "" : [settle-changed]}]
    if {!$first && $why eq ""} {
        puts "WM: config applied — nothing the layers say has changed"
        return
    }
    # REMEMBERED BEFORE, not after: a settler may add to the very state
    # this compares — welcome-inject writes the mat into ::widgets —
    # and a snapshot taken afterwards never matches what the layers say
    # next time, so the early-out could never fire (measured: the
    # widgets «moved» on every reload). What is compared is what the
    # LAYERS SAID, which is the question being asked.
    settle-remember
    settle-all
    # DECLARED buttons, not shown ones: under panels-held the strips
    # have not rebuilt yet and the shown lists are stale — the summary
    # was reading «0 buttons» on every reload. What the config APPLIED
    # is its declarations; the per-panel «up» lines say what shows.
    set nrefs 0
    foreach p [panel-names] { incr nrefs [dict size [panel-cfg $p refs]] }
    # ...and WHAT MOVED, which is the snapshot's other use: a reload
    # that settles says which wish it settled for, so «why did my desk
    # blink» has an answer in the log rather than in a bisect.
    puts "WM: config applied ($nrefs buttons on\
 [llength [panel-names]] panel(s), [llength $::style_rules] style rules,\
 tray [expr {$::tray_on ? {on} : {off}}])[expr {$why eq {} ? {} : " — «$why» moved"}]"
}

