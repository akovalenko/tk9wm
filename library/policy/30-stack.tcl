# ---- LAYERS: the stack is a model, and this is its only owner ----
#
# Every window sits in a numbered LAYER, the stack is that number
# first and the order within it second, and ONE proc puts the server in
# agreement with the model. Before this the order was a side effect of
# whoever called `raise` last, out of fourteen places, and every rule
# about it («the panel stays over the clients», «an active fullscreen
# window stays over the panel») had to be re-stated as code inside each
# of them — which is exactly how a fullscreen window ended up
# unescapable and swallowing its own dialogs (7068aa4).
#
# The scale is even numbers with gaps, so anything can be wedged
# between two without renumbering the world:
#
#     0   the desk window — the floor
#     1   a widget area that got a top-level of its own (just off it)
#     2   BELOW: _NET_WM_STATE_BELOW, conky and its kin
#     4   ORDINARY WINDOWS — the default
#     6   ABOVE: _NET_WM_STATE_ABOVE
#     8   DOCK: our panel, tray and their passengers; and a foreign
#         dock that says _NET_WM_WINDOW_TYPE_DOCK
#     9   the ACTIVE fullscreen window (computed, never declared —
#         see layer-effective)
#    12   the ceiling a config may ask for: «over the panel and over
#         fullscreen too», which is the whole point of numbering
#    14   the WM's own question windows
#    16   menus, the compass, the key echo
#
# The last two are ABOVE anything a config can name, and that is not
# an oversight: a desk whose own menu can be covered by a window is
# broken, so a declared layer is clamped into 0..12 (set-layer).
keep LAYER_DESK 0
keep LAYER_AREA 1
keep LAYER_BELOW 2
keep LAYER_NORMAL 4
keep LAYER_ABOVE 6
keep LAYER_DOCK 8
keep LAYER_FS 9
keep LAYER_MAX 12
keep LAYER_WMWIN 14
keep LAYER_POPUP 16

array set layerof {}    ;# client -> the layer it DECLARED (style, EWMH)
array set wm_layer {}   ;# our own top-level -> {layer rank}
keep stack_order {}     ;# clients, bottom first: the order WITHIN a layer
keep restack_pending 0

# Our own furniture announces itself; the registry is read fresh at
# every restack and a window that died simply is not there.
#
# The RANK is the order WITHIN the layer, and it is not decoration: the
# panel's window spans its whole band, the tray strip sits at the far
# end of that same band, and both are dock — so a layer that did not
# order them left the panel painting over the tray, which from the
# outside looks exactly like a tray that has stopped drawing its icons
# (the owner's desk, 2026-08-04: "выделяется пространство под
# nm-applet и fcitx5... там серое поле фоновым цветом"). Clients need
# no rank: their order within a layer is ::stack_order, which is a
# history and not a rule.
proc stack-layer {path n {rank 0}} {
    set ::wm_layer($path) [list $n $rank]
    restack-soon
}
proc layer-declared {w} {
    expr {[info exists ::layerof($w)] ? $::layerof($w) : $::LAYER_NORMAL}
}
# What a window's layer WORKS OUT to, which is the declared one plus
# the two rules that are about relations rather than about the window:
#
#   the ACTIVE fullscreen window rises over the strips — that is what
#     the state means, and it lasts exactly as long as being active
#     does (the window itself declares nothing and is back among the
#     ordinary windows the moment the focus leaves it);
#   a TRANSIENT is never below its leader — a dialog under the window
#     that put it up is unreachable, and a group split by a layer is
#     not a group. It may still declare a HIGHER layer for itself; what
#     it cannot do is sink.
proc layer-effective {w} {
    set leader [group-leader $w]
    set n [layer-declared $leader]
    if {[fullscreen-active] == $leader} { set n [expr {max($n, $::LAYER_FS)}] }
    if {$w != $leader} { set n [expr {max($n, [layer-declared $w])}] }
    return $n
}
# The model's own answer to "what is on top of what": every client,
# bottom first, layer first and the within-layer order second. This is
# what _NET_CLIENT_LIST_STACKING publishes and what the policy reasons
# with — the server AGREES with it rather than being asked, so an
# answer is right even between the model changing and the restack that
# lands it (bury reads this the instant after it lowers something).
proc client-stacking {} {
    set live {}
    foreach w $::stack_order {
        if {[info exists ::frameof($w)]} { lappend live $w }
    }
    set ::stack_order $live
    set byl {}
    foreach w $live { dict lappend byl [layer-effective $w] $w }
    set out {}
    foreach n [lsort -integer [dict keys $byl]] {
        lappend out {*}[dict get $byl $n]
    }
    return $out
}
# ...and the whole desk in one order, ours and theirs together.
proc stack-desired {} {
    set byl {}
    # Ours first and BY RANK, so the order within a layer is a decision
    # and not whatever an array happened to hand back — a hash order is
    # stable enough to hide a bug for a day and arbitrary enough to
    # produce one.
    set furn {}
    foreach {path pair} [array get ::wm_layer] {
        if {[winfo exists $path]} { lappend furn [list {*}$pair $path] }
    }
    # Stable sorts CHAIN IN REVERSE ORDER OF SIGNIFICANCE: the last one
    # applied is the one that wins. Written the intuitive way round —
    # layer, then rank, then name — the NAME decided everything, so
    # .tray came out under .traybg and the opaque backdrop covered the
    # icons: the very bug the ranks were added to fix, still there and
    # now wearing a fix (the owner's live desk, 2026-08-04, after the
    # first cure).
    foreach e [lsort -integer -index 0 [lsort -integer -index 1 \
                                            [lsort -index 2 $furn]]] {
        dict lappend byl [lindex $e 0] [lindex $e 2]
    }
    foreach w [client-stacking] {
        dict lappend byl [layer-effective $w] $::frameof($w)
    }
    set out {}
    foreach n [lsort -integer [dict keys $byl]] {
        lappend out {*}[dict get $byl $n]
    }
    return $out
}
# Put the server in agreement. Bottom-up, each window over the one
# before it: only windows the model KNOWS are touched, so anything
# else on the display (a client's own override-redirect popup, a
# screensaver) keeps whatever place it took for itself.
#
# NOT XRestackWindows, and the choice is deliberate (the owner asked,
# 2026-08-11). Two halves to the answer. First, the transaction it
# seems to offer does not exist: Xlib's RstWins.c unrolls it into the
# same N-1 ConfigureWindow requests a loop makes — core X has no
# atomic multi-window restack — and OUR loop batches identically
# (raise on an override toplevel is one buffered ConfigureWindow,
# CWSibling|Above, no roundtrip; the server draws nothing for the
# no-op pairs). Second, and decisive: XRestackWindows anchors the TOP
# window and tucks the rest BELOW it, so a foreign window standing
# between two of ours — a client's own menu, exactly the neighbour
# the paragraph above protects — comes out UNDER our block. The
# bottom-up Above chain squeezes the same block together while the
# strangers surface ABOVE it, which is where an override popup wants
# to be. Same requests, opposite courtesy.
proc restack {} {
    set prev ""
    foreach path [stack-desired] {
        if {![winfo exists $path]} continue
        if {$prev ne ""} { catch {raise $path $prev} }
        set prev $path
    }
    publish-client-list
}
# Coalesced, because one gesture moves the stack several times — a
# raise, the strips, a fullscreen bump — and the desk should be
# restacked once, when the dust settles.
proc restack-soon {} {
    if {$::restack_pending} return
    set ::restack_pending 1
    after idle {set ::restack_pending 0; restack}
}
# A new client goes on top of its layer; a departing one leaves no hole.
proc stack-add {w} {
    set ::stack_order [lsearch -exact -all -inline -not $::stack_order $w]
    lappend ::stack_order $w
    restack-soon
}
proc stack-drop {w} {
    set ::stack_order [lsearch -exact -all -inline -not $::stack_order $w]
    unset -nocomplain ::layerof($w)
    restack-soon
}
# What layer a NEWCOMER declares, in the order the answers outrank each
# other — the config last, because a config line is the user speaking
# and the rest is the window speaking about itself.
#
#   _NET_WM_WINDOW_TYPE_DOCK   a foreign panel (trayer, polybar) takes
#                              the same layer ours does, which is the
#                              first time this desk has had anywhere
#                              honest to put one
#   _NET_WM_STATE_ABOVE/BELOW  the EWMH pair, which we could not honor
#                              at all before there were layers
#   the style's `layer`        a number, or one of three words
proc client-layer-declare {w} {
    set n ""
    if {[lsearch -exact [client-window-types $w] dock] >= 0} {
        set n $::LAYER_DOCK
    }
    foreach a [client-net-wm-state $w] {
        if {[info exists ::NET_WM_STATE_ABOVE] && $a == $::NET_WM_STATE_ABOVE} {
            set n $::LAYER_ABOVE
        } elseif {[info exists ::NET_WM_STATE_BELOW]
                  && $a == $::NET_WM_STATE_BELOW} {
            set n $::LAYER_BELOW
        }
    }
    set st [style-of $w]
    if {[dict exists $st layer]} { set n [layer-number [dict get $st layer]] }
    if {$n eq ""} return
    set ::layerof($w) $n
    puts "WM: 0x[format %x $w] on layer $n"
}
# The three words a config may use instead of a number, and the clamp.
# The ceiling is not tidiness: the WM's own menus and question windows
# live above everything a config can name (LAYER_WMWIN, LAYER_POPUP),
# and a desk whose menu can be covered by a window is broken.
proc layer-number {v} {
    switch -- $v {
        below  { return $::LAYER_BELOW }
        normal { return $::LAYER_NORMAL }
        above  { return $::LAYER_ABOVE }
        dock   { return $::LAYER_DOCK }
        top    { return $::LAYER_MAX }
    }
    if {![string is integer -strict $v]} {
        error "layer: a number or below|normal|above|dock|top, got «$v»"
    }
    expr {max(0, min($v, $::LAYER_MAX))}
}
# The user's own hand on it — the ops menu, a config's chord. Same
# clamp, and the desk restacks at once.
proc layer-set {w v} {
    if {![info exists ::frameof($w)]} return
    set ::layerof($w) [layer-number $v]
    puts "WM: 0x[format %x $w] -> layer $::layerof($w)"
    restack-soon
}
# The hand's own way to a layer — the ops menu, a config's chord. Above
# and Below TOGGLE, because a menu entry that only goes one way leaves
# the user nowhere to click to undo it; Unlayer is the unconditional
# way back, the same shape as Unmaximize and Unfullscreen.
proc layer-above-command {w} { layer-toggle $w $::LAYER_ABOVE }
proc layer-below-command {w} { layer-toggle $w $::LAYER_BELOW }
proc layer-clear-command {w} {
    layer-set $w normal
    publish-net-wm-state $w
}
proc layer-toggle {w n} {
    if {![info exists ::frameof($w)]} return
    layer-set $w [expr {[layer-declared $w] == $n ? $::LAYER_NORMAL : $n}]
    publish-net-wm-state $w    ;# ABOVE/BELOW are EWMH state; say so
}
# A newcomer's desk: the style's word, else the desk one is on. The
# style may also say `sticky`, which is the desk answer for a window
# that belongs to all of them.
proc client-desk-declare-and-paint {w} {
    client-desk-declare $w
    frame-sticky-paint $w
}
proc client-desk-declare {w} {
    set st [style-of $w]
    # A window is BORN ON A DESK and stays there. Without this it had
    # no desk of its own, desk-of answered "wherever you are now", and
    # the window followed every switch — every desk showed everything
    # (measured, the first run of the suite).
    #
    # WHERE, in the order the answers outrank each other:
    #
    #   the style's `desk`   the user's standing word about this kind
    #                        of window, and it beats the rest;
    #   the window's own     _NET_WM_DESKTOP, which is BOTH a client
    #     _NET_WM_DESKTOP    asking for a desk before it maps (EWMH
    #                        says so) and the desk this very window was
    #                        on before a restart — the previous
    #                        instance published it, and reading it back
    #                        is the whole of surviving one. Without
    #                        this every window came back to the desk in
    #                        front of you and the property we had
    #                        published was overwritten with it (the
    #                        owner, 2026-08-04: "похоже всё сваливается
    #                        на один стол");
    #   the desk one is on   the ordinary case: a new window appears
    #                        where you are.
    set d ""
    if {[dict exists $st desk]} {
        set d [dict get $st desk]
    } else {
        set d [client-asked-desk $w]
    }
    if {$d eq ""} { set d $::desk }
    if {$d eq "sticky" || $d eq "all"} {
        set ::deskof($w) all
    } elseif {[string is integer -strict $d] && $d >= 0} {
        # PAST THE END IS THE LAST ONE, not a refusal: a window comes
        # back from a session with more desks than this config has, and
        # leaving it with no desk at all would make it follow every
        # switch (which is what "no desk" means here).
        set ::deskof($w) [expr {min($d, $::ndesks - 1)}]
    } else {
        puts "WM: 0x[format %x $w] desk «$d»: not a desk of the [set ::ndesks]"
        return
    }
    publish-desk-of $w
    desk-visibility $w
}
proc raise-group {w} {
    set leader [group-leader $w]
    # Within the layer: the leader first, then its transients (so they
    # end up above it), and the one that was TOUCHED last of all — a
    # click on a dialog puts that dialog on top of its siblings.
    set order [list $leader]
    foreach c [group-members $leader] {
        if {$c != $w} { lappend order $c }
    }
    if {$w != $leader} { lappend order $w }
    foreach c $order {
        set ::stack_order [lsearch -exact -all -inline -not $::stack_order $c]
    }
    lappend ::stack_order {*}$order
    restack-soon
}

# Lower the whole transient group of w — the mirror image, same glue:
# the group goes to the BOTTOM OF ITS LAYER (the ops menu's "lower" is
# the first lower gesture this WM has), keeping its internal order,
# leader underneath. There is no lowering "through the floor" to worry
# about any more: the desk window is a layer of its own and nothing in
# a higher one can sink past it, which is what the old raise-above-the-
# floor dance was for.
proc lower-group {w} {
    if {![info exists ::frameof($w)]} return
    set leader [group-leader $w]
    set order [list $leader]
    foreach c [group-members $leader] { lappend order $c }
    foreach c $order {
        set ::stack_order [lsearch -exact -all -inline -not $::stack_order $c]
    }
    set ::stack_order [concat $order $::stack_order]
    restack-soon
}

# A client's own restack request — the CWStackMode bit of a
# ConfigureRequest, handed over by the substrate. XRaiseWindow and
# XLowerWindow are the `above` and `below` spellings, and between them
# they are every request a real toolkit sends; both land on the same
# verbs the user's gestures use, group and layer discipline included —
# a request can no more escape its layer than a click can. Stacking
# only: the focus is a different conversation (_NET_ACTIVE_WINDOW),
# and a window that wants both knows to ask twice, as emacs does. The
# three conditional modes are heard and named rather than silently
# dropped; the first client ever seen sending one will announce
# itself in the log.
proc policy-restack-request {w mode} {
    switch -- $mode {
        above { raise-group $w }
        below { lower-group $w }
        default {
            puts "WM: restack 0x[format %x $w] $mode: unimplemented, ignored"
            return
        }
    }
    puts "WM: restack 0x[format %x $w] $mode honored"
}

# ---- bury: lower, and hand the focus to whatever that uncovered ----
# Lower is a PEEK. It drops the window to the floor and deliberately
# keeps the focus on it, so a glance at what is underneath costs one
# gesture and the way back costs one more — which is exactly right, and
# exactly what is rarely wanted. Bury is the commoner wish and the
# other half of the pair: get this window out of the way AND give me
# what it was covering.
#
# "What it was covering" is meant literally, and is asked of the screen
# rather than of the focus history. After the lower the candidates are
# read TOP DOWN off the server's own stacking order, and the first one
# whose frame actually overlaps the buried group wins: a window that
# never shared a pixel with it was not underneath it in any sense the
# user means, however recently it was focused. Nothing overlapping —
# the topmost other window is the honest fallback. Nothing at all — the
# focus stays where it is, because parking it on the holder would be a
# worse answer than leaving it on a window that is merely at the back.
proc bury-group {w} {
    if {![info exists ::frameof($w)]} return
    set leader [group-leader $w]
    set group [linsert [group-members $leader] 0 $leader]
    lower-group $w
    update idletasks   ;# the restack and the geometry, both settled
    set next [pick-uncovered $group]
    if {$next != 0} { focus-to $next }
    puts "WM: buried 0x[format %x $leader] -> focus\
 [expr {$next ? "0x[format %x $next]" : {nobody else}}]"
}
# The group is what was buried, so the group — not just its leader — is
# what a candidate has to have been under: a dialog can hang well
# outside the window it belongs to.
proc pick-uncovered {group} {
    set best 0
    # bottom-first from the server, so walking it backwards is top-down
    foreach cand [lreverse [client-stacking]] {
        if {$cand in $group || ![info exists ::frameof($cand)]
                || [info exists ::iconic($cand)]} continue
        if {$best == 0} { set best $cand }      ;# the fallback: topmost
        foreach member $group {
            if {[frames-overlap $member $cand]} { return $cand }
        }
    }
    return $best
}
# Do two frames share a pixel? Plain rectangle intersection on settled
# Tk geometry — the frame is what the user sees, so the frame is what
# the question is about, borders and titlebar included.
proc frames-overlap {a b} {
    set fa $::frameof($a); set fb $::frameof($b)
    set ax [winfo rootx $fa]; set ay [winfo rooty $fa]
    set bx [winfo rootx $fb]; set by [winfo rooty $fb]
    expr {$ax < $bx + [winfo width $fb] && $bx < $ax + [winfo width $fa]
       && $ay < $by + [winfo height $fb] && $by < $ay + [winfo height $fa]}
}

# Click-to-focus: a click inside a client's body raises and focuses it.
# focus-to is called UNCONDITIONALLY — the old "skip if ::focused is
# already w" guard turned a single refused XSetInputFocus into a
# permanent wedge (clicks stopped repairing the focus, the keyboard kept
# going to the previous window). One roundtrip per click is the price of
# a click path that always heals.
proc policy-client-click {w} {
    popups-close
    raise-group $w
    focus-to $w
}
# An EWMH activation request is a click's stronger cousin: the client
# SAYS «activate me», so the focus is delivered fresh (see focus-to) —
# a requester whose inner activation went stale gets the honest
# FocusOut/FocusIn pair instead of a silent no-op. A plain click stays
# plain: bouncing the focus under every click on the focused window
# would flap for no one's benefit.
proc policy-client-activate {w} {
    popups-close
    raise-group $w
    focus-to $w 1
}

# A newly managed window is raised with its group — a fresh dialog pulls
# its leader up right under itself, fvwm-style — and gets the focus.
# The frame's FIRST appearance: built withdrawn (policy-attach), it
# goes on the glass only here — client seated, title drawn, dressed
# whole. A window arriving minimized or on another desk simply never
# shows. During the adoption sweep each frame is seated UNDER the one
# shown before it — the desk switch's own cure, so the desk
# reassembles behind its top window — and the flush waits for the
# sweep's end; the ordinary path flushes NOW, because a focus lands
# right after and a focus on a window the server has not mapped yet
# is refused (policy-deiconified's lesson).
proc frame-show {w} {
    if {![info exists ::frameof($w)] || [info exists ::iconic($w)]
            || ![desk-here-p $w]} return
    set t $::frameof($w)
    wm deiconify $t
    if {$::adopting} {
        if {$::adopt_prev != 0 && [info exists ::frameof($::adopt_prev)]} {
            lower $t $::frameof($::adopt_prev)
        }
        set ::adopt_prev $w
    } else {
        update idletasks
    }
}
# The MODEL'S bookkeeping of an arrival, and nothing the eye can see:
# a seat in the stack, a layer, a desk. policy-managed opens with this
# and goes on to the showing and the focus — and a window managed INTO
# iconic gets ONLY this, called by manage AFTER the iconify. It used to
# get nothing: skipping policy-managed (the initial-focus choreography
# is not for a window leaving the screen) skipped the bookkeeping too,
# and the window came back from a restore with no desk — following
# every switch, camping at the head of the focus history — and no seat
# in the stack, so the desk sweep could not even show it (the owner's
# live desk, 2026-08-08: a PDF minimized across a restart). After the
# iconify on purpose: the desk declaration ends in desk-visibility, and
# «iconic outranks» is what keeps that inert — run before, it would
# unmap an elsewhere-window on its own and the iconify's unmap echo
# arithmetic (skip_unmap) would count an echo that never comes.
proc policy-booked {w} {
    if {$::adopting} {
        # The adoption sweep walks TOPMOST FIRST (adopt-existing), so
        # the model seats each arrival at the BOTTOM — the same
        # arithmetic the desk switch runs, and the restack at the end
        # finds nothing left to move.
        lower-group $w
    } else {
        stack-add $w     ;# into the stacking model, at the top of its layer
    }
    client-layer-declare $w
    client-desk-declare-and-paint $w
}
proc policy-managed {w} {
    policy-booked $w
    if {!$::adopting} { raise-group $w }
    frame-show $w
    if {$::adopting} {
        # No focus per adopted window: framing bottom-up used to hand
        # the highlight to every window in turn and leave it with the
        # LAST arrival, whatever was active before the restart. The
        # sweep hands the focus out once, at its end
        # (policy-adopt-settled).
        apply-opacity $w
        panel-match-kick
        return
    }
    # A newcomer does not steal the focus from a STANDING QUESTION —
    # it takes it FOR LATER (the owner, 2026-08-05): seated right
    # behind the box in the focus history, so answering or cancelling
    # the ask lands the focus exactly where this manage would have put
    # it. The raise still happens — the ask's layer is what keeps the
    # question on top of it. A gadget newcomer is the question itself
    # (a displacement's fresh box) and focuses as ever.
    if {[array size ::ask_fut] && $::focused != 0
            && [lindex [client-class $w] 1] ne "Tk9wmGadget"
            && [lindex [client-class $::focused] 1] eq "Tk9wmGadget"} {
        set ::focus_hist [linsert \
            [lsearch -exact -all -inline -not $::focus_hist $w] 1 $w]
        puts "WM: 0x[format %x $w]: the focus is the ask's — taken for later"
        apply-opacity $w
        panel-match-kick
        return
    }
    # the newcomer's focus is the POLICY's move, not the person's —
    # the ask's focus-left rule must not read it as leaving
    set ::focus_by_policy 1
    focus-to $w
    apply-opacity $w
    panel-match-kick
}
# The adoption sweep's ONE focus decision, after every frame is up:
# the window the desk had active before the restart — the previous
# instance's _NET_ACTIVE_WINDOW, read off the root before this
# instance zeroed it — else the topmost thing that can take a focus.
# Candidates pass the same test a refocus applies: alive, on this
# desk, not minimized.
proc policy-adopt-settled {act} {
    update idletasks     ;# every frame the sweep queued is on the glass
    set ::focus_by_policy 1
    if {$act ne "" && $act != 0 && [refocus-ok $act 0]} {
        puts "WM: adoption settled — focus back to 0x[format %x $act]"
        focus-to $act
        return
    }
    foreach w [lreverse [client-stacking]] {
        if {[refocus-ok $w 0]} {
            puts "WM: adoption settled — focus to the top (0x[format %x $w])"
            focus-to $w
            return
        }
    }
    puts "WM: adoption settled — nothing to focus"
}

# Refocus pick after w's unmanage (the smsrc observation: an unpatched
# app never refocuses its main window when its dialog closes — that is
# the WM's job). In order:
#  - the closing window's WM_TRANSIENT_FOR leader: a dialog gives focus
#    back to the window it was a dialog FOR, no matter what the user
#    glanced at in between;
#  - the most recently focused window still alive (focus history);
#  - any managed window at all.
# ...and ON THIS DESK, which is the other half of "not iconic" and was
# missing. A window elsewhere is not on the screen, so the server
# refuses the focus (BadMatch on an unviewable window), the focus stays
# parked on the holder, and the desk is left with nothing active — for
# as long as it takes to click something. Whether it happened depended
# on what the focus history held, which is why it came and went
# (the owner, 2026-08-04: "убрать окно на другой стол => остаёшься без
# активного окна... повторить на заказ не получается").
proc refocus-ok {cand w} {
    expr {$cand != $w && [info exists ::frameof($cand)]
          && ![info exists ::iconic($cand)] && [desk-here-p $cand]}
}
proc policy-pick-refocus {w} {
    # whoever this pick lands on gets the focus by the POLICY's hand —
    # the ask's focus-left rule must not read it as the person leaving
    set ::focus_by_policy 1
    if {[info exists ::leaderof($w)]} {
        set leader $::leaderof($w)
        if {$leader != 0 && [refocus-ok $leader $w]} { return $leader }
    }
    foreach cand $::focus_hist {
        if {[refocus-ok $cand $w]} { return $cand }
    }
    foreach cand [array names ::frameof] {
        if {[refocus-ok $cand $w]} { return $cand }
    }
    return 0
}

# ---- layer 1: building the strip, and turning a click into a gesture ----
#
# The titlebar is a treectrl (a one-item one): the title text in an
# expanding column whose -squeeze x text element ellipsizes what does
# not fit, and a fixed square column per button, each a stateful
# outlined box (rect element) around an svg glyph.
#
# ONE builder for both callers. A client's frame and a window the WM
# puts up for itself wear the same strip with different button sets,
# and until this was factored out they wore two COPIES of the same
# forty lines — which is how the two drifted and how adding a button
# would have meant editing both.
#
# What this proc knows about buttons is that they have names, a side
# and a picture. Which ones exist is the catalogue's business and what
# they do is the gesture table's.
proc titlebar-build {t w names title} {
    set names [titlebar-order $names]
    treectrl $t.title -showheader no -showroot no -showbuttons no \
        -showlines no -borderwidth 0 -highlightthickness 0 \
        -background [themed focus] -itemheight $::titleh
    # class binds stripped (a dumb label, not a tree) — but the FRAME's
    # tag stays: press-end must hear a ButtonRelease that happens over
    # the title, or the drag state outlives the drag (the rz-* handlers
    # riding along are harmless — they compute from root coords and see
    # "not a border" here).
    bindtags $t.title [list $t.title $t all]
    $t.title state define pressed   ;# armed by a press; release-inside fires
    foreach name $names {
        if {[titlebar-side $name] eq "left"} {
            $t.title column create -width $::btnw -tags C$name
        }
    }
    $t.title column create -squeeze yes -expand yes -tags C0
    foreach name $names {
        if {[titlebar-side $name] eq "right"} {
            $t.title column create -width $::btnw -tags C$name
        }
    }
    $t.title configure -treecolumn C0
    $t.title state define sticky    ;# on every desk — worn as a texture
    $t.title element create eTxt text -fill white -lines 1 -font TitleFont
    $t.title element create eHatch image -tiled yes \
        -image [list [sticky-hatch [themed focus]] sticky {} {}]
    $t.title element create eBox rect -outline white -outlinewidth 1 \
        -fill [list [shade [themed focus] 0.65] pressed {} {}]
    $t.title style create sTitle
    # the hatch FIRST, so it is under the text; detached and expanded,
    # so it is the whole cell rather than a thing beside the title
    $t.title style elements sTitle {eHatch eTxt}
    $t.title style layout sTitle eHatch -detach yes -iexpand xy
    $t.title style layout sTitle eTxt -expand $::justflags($::titlejust) \
        -padx 4 -squeeze x
    # the box fills its btnw-wide cell (glyph + ipad == btnw) and is
    # one grip shorter than the strip: -expand s sends the slack south,
    # pinning the box flush against the top border — the hole to the
    # client area opens BELOW the buttons
    set cells {}
    foreach name $names {
        # a glyph is svg rendered to a photo, or a bare character
        # drawn in the strip's own font and ink; either way the box
        # union is padded out to the same btnw square, so a text
        # button sits in the row exactly as its svg neighbours do
        set txt [titlebar-glyph-text $name]
        if {$txt ne ""} {
            $t.title element create e$name text -fill white -lines 1 \
                -font BtnGlyphFont -text $txt
            set px [expr {max($::btnpad,
                ($::btnw - [font measure BtnGlyphFont $txt]) / 2)}]
            set py [expr {max($::btnpad,
                ($::btnw - [font metrics BtnGlyphFont -linespace]) / 2)}]
        } else {
            $t.title element create e$name image -image [titlebar-image $name]
            set px $::btnpad
            set py $::btnpad
        }
        $t.title style create s$name
        $t.title style elements s$name [list eBox e$name]
        $t.title style layout s$name eBox -union e$name \
            -ipadx $px -ipady $py -expand s
        $t.title style layout s$name e$name -expand s
        lappend cells C$name s$name
    }
    set item [$t.title item create]   ;# always item 1 in a fresh widget
    $t.title item style set $item C0 sTitle {*}$cells
    $t.title item element configure $item C0 eTxt -text $title
    $t.title item lastchild root $item
    set ::btncols($t) $names
    set ::btnwof($t) $::btnw   ;# the size this strip was BUILT at
    # Three buttons and the double, because all four are gestures the
    # table can name. w == 0 says "no client behind this frame" to the
    # shared handlers.
    foreach n {1 2 3} {
        bind $t.title <ButtonPress-$n> \
            [list title-press $t $w %x %y %X %Y $n]
        bind $t.title <ButtonRelease-$n> \
            [list title-release $t $w %x %y %X %Y $n %s]
    }
    bind $t.title <B1-Motion> [list title-motion $t $w %x %y %X %Y]
    # Buttons 2 and 3 fire on the PRESS, so a menu they open stands
    # under a hand that is still holding the button: their drag belongs
    # to that menu, not to the frame, and the strip passes it on.
    bind $t.title <B2-Motion> [list popup-drag-motion %X %Y]
    bind $t.title <B3-Motion> [list popup-drag-motion %X %Y]
    bind $t.title <Double-ButtonPress-1> [list title-double $t $w %x %y]
}

# Which PART of the strip a point is on: a button's name, or "" for the
# strip itself. The columns asked about are THIS FRAME's, not the whole
# catalogue — a `column compare` against a tag the frame never created
# throws, which the confirmation dialog's close button did, all the way
# out to a bgerror box (owner's report, 2026-07-29).
proc title-button {t x y} {
    set T $t.title
    if {[catch {$T identify -array A $x $y}]} { return "" }
    if {$A(where) ne "item" || $A(column) eq ""} { return "" }
    foreach name [frame-buttons $t] {
        if {[$T column compare $A(column) == C$name]} { return $name }
    }
    return ""
}
# A press on a BUTTON arms it (the pressed state on its column alone —
# forcolumn) and the action fires on release-inside, so a drag away
# cancels. A press on the STRIP is the carry for button 1 and fires at
# once for the others: a menu that waited for the release would feel
# stuck. Arming happens only where something is bound, so a gesture
# that does nothing does not light up as if it might.
proc title-press {t w x y X Y n} {
    set b [title-button $t $x $y]
    if {$b eq ""} {
        if {$n == 1} {
            drag-start $t $w $X $Y
        } else {
            gesture-at $X $Y $n { titlebar-do $t $w title <$n> }
        }
        return
    }
    if {[titlebar-action $b <$n>] eq "" && $w != 0} return
    popups-close $t
    set ::btn($t) [list $b $n]
    $t.title item state forcolumn 1 C$b pressed
}
proc title-motion {t w x y X Y} {
    if {![info exists ::btn($t)]} { drag-move $t $w $X $Y; return }
    lassign $::btn($t) b -
    $t.title item state forcolumn 1 C$b \
        [expr {[title-button $t $x $y] eq $b ? "pressed" : "!pressed"}]
}
proc title-release {t w x y X Y n {s 0}} {
    # First the menu this press may have posted, because a gesture on
    # the STRIP arms no button and the check below is the way it
    # leaves: the release that ends such a gesture is the menu's.
    popup-drag-release $X $Y $s
    if {![info exists ::btn($t)]} return
    lassign $::btn($t) b bn
    if {$n != $bn} return
    unset ::btn($t)
    $t.title item state forcolumn 1 C$b !pressed
    if {[title-button $t $x $y] eq $b} {
        # A BUTTON is a place of its own, and a menu it puts up hangs
        # from THE BUTTON — not from the pixel the finger happened to
        # land on (the owner, 2026-08-04). Pressing the same button
        # twice must put the menu in the same spot both times, the way
        # <Alt>space does; the pointer's x makes it wander by a few
        # pixels each press, which reads as the menu being unmoored.
        # The strip's own gestures (a right-click on the title) keep
        # the hand's point — there the hand IS the place.
        set at [title-button-point $t $b]
        if {![llength $at]} { set at [list $X $Y] }
        gesture-at {*}$at 0 { titlebar-do $t $w $b <$n> }
    }
}
# Root coordinates a button's menu should hang from: the button's own
# left edge, and a y INSIDE the strip — which is what makes the menu
# drop out of the bar's bottom edge rather than out of the pointer
# (see winops). {} when the strip cannot be measured, and the caller
# falls back to the hand.
proc title-button-point {t b} {
    set T $t.title
    if {![winfo exists $T]} { return {} }
    lassign [$T item bbox 1 C$b] bx
    if {$bx eq ""} { return {} }
    list [expr {[winfo rootx $T] + $bx}] [winfo rooty $T]
}
# The second click of a pair. Tk gives it to the Double binding INSTEAD
# of the plain press, so no carry is started by it — and the first
# click's release already ended the one it did start.
proc title-double {t w x y} {
    set b [title-button $t $x $y]
    if {$b eq ""} {
        unset -nocomplain ::drag($t)
        titlebar-do $t $w title <Double-1>
    } else {
        titlebar-do $t $w $b <Double-1>
    }
}

# --- the seam itself: a part and a gesture, resolved and run ---
# The command is a prefix and the window is appended, which is why the
# window COMMANDS fit it exactly — and why a config can put any of them
# on any part without this layer growing a case for each.
proc titlebar-do {t w part gesture} {
    if {$w == 0} {
        # A window of the WM's own is not a client and the window
        # commands have nothing to act on. It answers one gesture: the
        # close box, doing whatever that window said closing means.
        if {$part eq "close" && $gesture eq "<1>"} { wm-window-close $t }
        return
    }
    set cmd [titlebar-action $part $gesture]
    if {$cmd eq ""} return
    puts "WM: titlebar $part $gesture on 0x[format %x $w] -> $cmd"
    # in a coroutine, the winops rule: a stock command returns at once
    # and costs nothing, a config's own button may legitimately wait
    # (Window-Shot, Choose), and its error becomes a problem instead
    # of a line only this proc would print
    run-script "titlebar $part $gesture" [list {*}$cmd $w]
}

# ---- strips: the furniture glued to the screen's edges ----
# ---- monitors: the rectangles the screen is made of ----
#
# One X screen, one root — that much stays true on a multihead desk.
# What multihead adds is STRUCTURE INSIDE the root: each monitor is a
# rectangle within it (RandR 1.5 names them, Xinerama only numbers
# them), the root is their bounding box, and where the monitors do not
# tile the box exactly it has DEAD ZONES — coordinates that exist and
# show on no glass. So everything that carves, places, snaps or
# maximizes thinks in a MONITOR's rectangle below; `screen-size` keeps
# meaning the whole box, which is what root properties and honored
# user claims are about.
#
# The fact is read FRESH at each decision, like screen-size and for
# the same reason: the layout changes under us (xrandr, a dock, a
# projector) and a cached answer would place windows on monitors that
# are no longer there. Sources, most trusted first:
#
#   1. set-monitors — the config/test override. Not a debug backdoor:
#      it is the one way to hand a headless test (or a desk whose
#      driver lies) a layout, and it resets with the config like any
#      other knob.
#   2. RandR 1.5 GetMonitors — when it reports more than one. Real
#      desks live here, and `xrandr --setmonitor` splits count.
#   3. Xinerama — when IT reports more than one. Not a legacy custom:
#      a nested Xephyr +xinerama (the fake multihead a test can
#      raise) answers GetMonitors with one bogus monitor while its
#      Xinerama tells the truth (measured, 2026-08-04).
#   4. the whole screen as one monitor — every single-headed desk,
#      and every desk that was one a moment ago.
#
# An entry is {name primary x y w h}. Exactly one entry is primary —
# the flagged one, else the first — and `primary-monitor` is where
# everything with no better anchor goes: the panels (this round all
# of them — see panel-monitor), the cascade, the furniture.
keep monitors_override {}
proc set-monitors {spec} {
    foreach m $spec {
        if {[llength $m] != 6} {
            error "set-monitors: an entry is {name primary x y w h}"
        }
        foreach v [lrange $m 2 5] {
            if {![string is integer -strict $v]} {
                error "set-monitors: geometry must be integers, got «$v»"
            }
        }
        if {[lindex $m 4] <= 0 || [lindex $m 5] <= 0} {
            error "set-monitors: a monitor has area"
        }
    }
    set ::monitors_override $spec
    # the ground moved the same way a RandR resize moves it: the
    # strips re-place (debounced there) and the workarea answer flips
    policy-screen-changed
    publish-workarea
}
proc monitors {} {
    if {[llength $::monitors_override]} {
        return [monitors-normalized $::monitors_override]
    }
    set l [soft "monitors (randr)" { x-monitors-randr } {}]
    if {[llength $l] <= 1} {
        set xi {}
        set i 0
        foreach h [soft "monitors (xinerama)" { x-monitors-xinerama } {}] {
            lappend xi [list xinerama$i 0 {*}$h]
            incr i
        }
        if {[llength $xi] > 1} { set l $xi }
    }
    if {[llength $l] <= 1} {
        # one monitor or no answer at all: the whole screen, which is
        # exactly what every decision below used before monitors were
        # a fact — the single-head desk goes through here unchanged
        return [list [list screen 1 0 0 {*}[screen-size]]]
    }
    monitors-normalized $l
}
proc monitors-normalized {l} {
    foreach m $l { if {[lindex $m 1]} { return $l } }
    lset l 0 1 1     ;# nobody claimed primary: the first one is
    return $l
}
proc primary-monitor {} {
    foreach m [monitors] {
        if {[lindex $m 1]} { return [lrange $m 2 5] }
    }
}
# The monitor a rectangle belongs to: the one it overlaps most, ties
# to the earlier in the list. A rect on no monitor at all — parked in
# a dead zone, dragged past every edge — belongs to the primary, the
# same "no better anchor" answer as everywhere else.
proc monitor-of-rect {rect} {
    lassign $rect x y w h
    set best {}
    set besta 0
    foreach m [monitors] {
        lassign [lrange $m 2 5] mx my mw mh
        set a [expr {max(0, min($x + $w, $mx + $mw) - max($x, $mx))
                   * max(0, min($y + $h, $my + $mh) - max($y, $my))}]
        if {$a > $besta} { set besta $a; set best [lrange $m 2 5] }
    }
    if {$besta > 0} { return $best }
    primary-monitor
}
proc monitor-of-frame {t} {
    if {[regexp {^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$} [wm geometry $t] \
            -> fw fh fx fy]} {
        return [monitor-of-rect [list $fx $fy $fw $fh]]
    }
    primary-monitor
}
proc pointer-monitor {} {
    lassign [winfo pointerxy .] px py
    monitor-of-rect [list $px $py 1 1]
}
# ...and the workarea each of them keeps: the monitor's rectangle
# minus the strips of ITS panels. The per-window callers below ask
# through these, so a window maximizes, clamps and snaps on the
# monitor it stands on and never against the far side of the desk.
proc monitor-workarea {mrect} { lindex [strip-bands-for $mrect] 1 }
proc workarea-at {rect} { monitor-workarea [monitor-of-rect $rect] }
proc workarea-of-frame {t} { monitor-workarea [monitor-of-frame $t] }

# A STRIP is anything the WM glues to a screen edge and reserves room
# for: a button panel, the tray riding on one. Each claims a BAND
# across one edge of ITS MONITOR, and the bands are carved IN
# DECLARATION ORDER out of what is left of that monitor — the first
# panel declared spans its whole edge, the next spans what that one
# left of its own. So the corner between two edges belongs to
# whichever strip was declared first, which is a rule the config
# steers by writing its panels in an order and nothing has to
# negotiate at run time. What survives the last carve is that
# monitor's WORKAREA: where maximize expands to and where new frames
# are placed.
#
# The tray is NOT a strip of its own. It rides on the panel it is bound
# to (set-tray-panel): the two share one band, the tray sits at its far
# end, and the band is the THICKER of them — which is what makes the
# pair read as a single bar. Either may be absent, both are opt-in, and
# a panel that nothing asks for reserves nothing at all.
proc carve-band {rect edge thick} {
    lassign $rect x y w h
    # a strip cannot claim more than there is: the workarea must stay a
    # rectangle with sides, whatever a config asks for
    set thick [expr {max(0, min($thick, ($edge in {left right}) ? $w : $h))}]
    switch -- $edge {
        top    { return [list [list $x $y $w $thick] \
                              [list $x [expr {$y + $thick}] $w [expr {$h - $thick}]]] }
        bottom { return [list [list $x [expr {$y + $h - $thick}] $w $thick] \
                              [list $x $y $w [expr {$h - $thick}]]] }
        left   { return [list [list $x $y $thick $h] \
                              [list [expr {$x + $thick}] $y [expr {$w - $thick}] $h]] }
        right  { return [list [list [expr {$x + $w - $thick}] $y $thick $h] \
                              [list $x $y [expr {$w - $thick}] $h]] }
    }
    error "carve-band: no such edge: $edge"
}
# Every band and the workarea in one pass, because they are one answer:
# each band is what its strip took from the running rectangle, and the
# workarea is that rectangle at the end. Returns {bands-dict workarea} —
# a pair and not one dict, so that a panel NAMED workarea could not
# shadow the answer.
proc strip-carve {rect names} {
    set free $rect
    set bands {}
    foreach name $names {
        set thick [panel-thickness $name]
        if {[tray-panel] eq $name} {
            set thick [expr {max($thick, [tray-thickness])}]
        }
        # ...and any widget riding this panel, for the same reason.
        if {[llength [info commands widgets-thickness]]} {
            set thick [expr {max($thick, [widgets-thickness $name])}]
        }
        if {$thick <= 0} continue
        lassign [carve-band $free [panel-cfg $name side] $thick] band free
        dict set bands $name $band
    }
    list $bands $free
}
# The carve on ONE monitor: the strips that live there, out of its
# rectangle. Declaration order still decides the corners — among the
# panels of that monitor, which is the only place a corner is shared.
proc strip-bands-for {mrect} {
    set names {}
    foreach name [strip-order] {
        if {[panel-monitor $name] eq $mrect} { lappend names $name }
    }
    strip-carve $mrect $names
}
proc strip-bands {} { strip-bands-for [primary-monitor] }
# Which monitor a panel lives on. THIS round the answer is a constant
# — every strip goes to the primary — and this proc is the seam a
# future config verb widens: store a name per panel here, resolve it
# against [monitors], and nothing downstream changes. (Deliberately
# not grown now: the grammar for "panel on the second monitor" is a
# decision of its own.)
proc panel-monitor {name} { primary-monitor }
# Who gets to carve, in order. The declared panels — and the tray's own
# panel even when nothing declared it: a config that asks for a tray
# and no buttons at all still gets a bar, which is what it got when the
# tray was the panel's lodger rather than a named panel's.
proc strip-order {} {
    set names [panel-names]
    if {[tray-panel] ni $names} { lappend names [tray-panel] }
    return $names
}
# The band a named panel holds, {} when it reserves nothing (no
# buttons, no tray of its own) — the callers that place furniture.
proc strip-band {name} {
    lassign [strip-bands-for [panel-monitor $name]] bands -
    if {[dict exists $bands $name]} { return [dict get $bands $name] }
    return {}
}
# The band's own edge-hugging sub-strip of THICK px: a panel thinner
# than its band (a fat tray widened it) still hugs the screen edge
# rather than floating in the middle of what it reserved.
proc band-strip {band edge thick} {
    lassign [carve-band $band $edge $thick] strip -
    return $strip
}
# The no-argument spelling is the PRIMARY monitor's workarea — where
# everything that has no window to anchor by (the cascade, the
# furniture, a place rule sizing a newcomer) happens. A caller with a
# window in hand asks workarea-of-frame / workarea-at instead.
proc workarea {} { lindex [strip-bands] 1 }
# The answer for the world: EWMH's _NET_WORKAREA. The property is ONE
# rect per desktop — it predates multihead and cannot say "a workarea
# per monitor" (the GTKs of the world invented private properties for
# that). Publishing the primary's rect would invite a toolkit to clamp
# a popup from another monitor across the desk, so the property keeps
# the OLD arithmetic: the whole screen, carved by every strip — exact
# on one monitor, conventional on many.
proc policy-workarea {} {
    lindex [strip-carve [list 0 0 {*}[screen-size]] [strip-order]] 1
}
# ...and the full per-monitor picture, which is what the substrate
# WATCHES for change: a monitor resized under an unchanged primary
# must still reflow its windows. name -> {primary 0|1 mon RECT wa
# RECT}, and policy-workarea-changed receives two of these.
proc policy-workareas {} {
    set d {}
    foreach m [monitors] {
        set mrect [lrange $m 2 5]
        dict set d [lindex $m 0] [dict create primary [lindex $m 1] \
            mon $mrect wa [monitor-workarea $mrect]]
    }
    return $d
}

# ---- maximize, fvwm semantics ----

# Maximize fills the workarea and remembers what the window was; the
# second toggle restores it. "Maximized" is a saved geometry and not a
# state the client is held in: the window can be moved and resized by
# hand meanwhile like any other.
# It is PER AXIS, the way the EWMH pair of atoms always said it was:
# ::maxaxes($w) names which axes the state holds (h, v or both) and
# ::maxsaved($w) keeps the way back, one rect for both axes. A window
# maximized tall keeps its own width and its own X; only the axes the
# state holds belong to it — the mark, the shield, the published atoms
# and the restore all answer axis by axis. The two arrays live and die
# together: ::maxsaved exists iff ::maxaxes is non-empty, and every
# existence check on "is this window maximized at all" reads ::maxsaved
# as it always did.
# Three operations, not one with a mood. A MENU naturally toggles — you
# open it over a window, and the entry means "the other way" — but a
# config wants to force: `Apply-To-Matching always Maximize` that
# un-maximized every already-maximized window would be nobody's idea of
# maximizing a desk, and a key bound to Maximize should leave the window
# maximized however many times it is pressed. So the vocabulary forces
# and the menu names the toggle (owner, 2026-07-29).
# What a HAND resize does to the maximized mark: two honest readings, so
# it is a knob (2026-07-29) — and the default is the MEASURED one, since
# the attribution was wrong when the knob was written. fvwm3, driven by
# hand (owner, 2026-07-30):
#
#   drop (default) — fvwm3's own, measured. A hand resize means this is
#     no longer the maximized window: the mark goes, the next toggle
#     MAXIMIZES rather than restoring — in either direction, a window
#     pulled BIGGER maximizes just the same — and it saves the hand-set
#     geometry, so the toggle after that comes back to what the hand
#     made. Windows and GNOME read it this way too.
#   keep — the mark survives; the toggle puts back what was saved AT
#     MAXIMIZE TIME however the window has been pulled about since. This
#     was called fvwm's here and is nobody's that we know of, but it is
#     a coherent reading of "the mark is a saved geometry, full stop"
#     and it stays available.
#
# It is about resizing only. Carrying a maximized window somewhere else
# leaves it maximized under either reading — measured in fvwm3 too — that
# gesture moves a window and says nothing about its size, and the
# desktops that unmaximize on a title drag are doing something else
# entirely (they resize it to the saved size under the pointer, which
# nobody has asked for here).
keep maximize drop
proc maximize-guard {w} {
    if {![info exists ::frameof($w)]} { return 0 }
    # Fullscreen already owns this window's geometry, and the two would
    # fight over the same saved copy. Refused audibly rather than
    # silently: the request came from a menu the user just used.
    if {[info exists ::fullscreen($w)]} {
        puts "WM: maximize ignored — 0x[format %x $w] is fullscreen"
        return 0
    }
    return 1
}
# The axes argument every maximize verb takes — h, v, or both. Checked
# once, here, because a config's hand reaches every entry point: a
# typo'd axis must die at its own line, not half-apply.
proc max-axes {axes} {
    set out {}
    foreach a $axes {
        if {$a ni {h v}} { error "maximize: axis is h or v, not «$a»" }
        if {$a ni $out} { lappend out $a }
    }
    if {![llength $out]} { error "maximize: no axes" }
    return $out
}
# The client size maximize gives THIS window in that rect: the rect
# minus this frame's decoration, run through the size hints — where the
# minimum binds but the axes being maximized owe the increments nothing
# (see apply-size-hints for the rule and its pedigree).
#
# Its own proc because two callers need the same arithmetic and must not
# each carry a copy: maximize does it TO a window, and the reflow below
# asks whether a window already IS the shape it would have made — which
# is only answerable by the same sum.
proc maximize-fit {w rect {axes {h v}}} {
    lassign [frame-chrome $::frameof($w)] B top
    lassign $rect - - rw rh
    apply-size-hints $w [expr {$rw - 2*$B}] [expr {$rh - $top - $B}] $axes
}
proc maximize-client {w {axes {h v}}} {
    if {![maximize-guard $w]} return
    set axes [max-axes $axes]
    set t $::frameof($w)
    set cw [$t.slot cget -width]; set ch [$t.slot cget -height]
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> X Y
    # Only the FIRST maximize of an axis records where that axis goes
    # back to. Calling this on an already-maximized axis re-fits it to
    # the workarea as it is now — and must not overwrite the saved
    # geometry with the maximized one, which would lose the way back
    # entirely. An axis JOINING a held state records its way back NOW,
    # not at the first mark: the free axis's requests are granted live
    # while the state holds (see the shield), so the number written
    # when the OTHER axis maximized may long since be stale.
    if {![info exists ::maxsaved($w)]} {
        set ::maxsaved($w) [list $cw $ch $X $Y]
        set ::maxaxes($w) {}
    } else {
        lassign $::maxsaved($w) scw sch sX sY
        if {"h" in $axes && "h" ni $::maxaxes($w)} { set scw $cw; set sX $X }
        if {"v" in $axes && "v" ni $::maxaxes($w)} { set sch $ch; set sY $Y }
        set ::maxsaved($w) [list $scw $sch $sX $sY]
    }
    foreach a {h v} {
        if {$a in $axes && $a ni $::maxaxes($w)} { lappend ::maxaxes($w) $a }
    }
    # the workarea of the monitor the window STANDS ON: maximize fills
    # the glass under the window, never the bounding box of the desk —
    # and only along its own axes: a window maximized tall stands where
    # it stood and as wide as it was.
    set wa [workarea-of-frame $t]
    lassign [maximize-fit $w $wa $::maxaxes($w)] mw mh
    set nx $X; set ncw $cw; set ny $Y; set nch $ch
    if {"h" in $::maxaxes($w)} { set nx [lindex $wa 0]; set ncw $mw }
    if {"v" in $::maxaxes($w)} { set ny [lindex $wa 1]; set nch $mh }
    wm geometry $t +$nx+$ny
    wm-resize-client $w $ncw $nch
    maximize-settle $w
    publish-net-wm-state $w   ;# the mark is EWMH state now; say so
}
proc unmaximize-client {w {axes {h v}}} {
    if {![maximize-guard $w]} return
    if {![info exists ::maxsaved($w)]} return   ;# not maximized: nothing to undo
    set drop {}
    foreach a [max-axes $axes] {
        if {$a in $::maxaxes($w)} { lappend drop $a }
    }
    if {![llength $drop]} return   ;# none of these axes are held
    set t $::frameof($w)
    lassign $::maxsaved($w) scw sch sX sY
    set ncw [$t.slot cget -width]; set nch [$t.slot cget -height]
    regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> nx ny
    if {"h" in $drop} { set ncw $scw; set nx $sX }
    if {"v" in $drop} { set nch $sch; set ny $sY }
    set keep {}
    foreach a $::maxaxes($w) { if {$a ni $drop} { lappend keep $a } }
    if {[llength $keep]} {
        set ::maxaxes($w) $keep
    } else {
        unset ::maxsaved($w) ::maxaxes($w)
    }
    wm geometry $t +$nx+$ny
    wm-resize-client $w $ncw $nch
    maximize-settle $w
    publish-net-wm-state $w
}
# Is this window's maximization PINNED by the config — a forced max
# place rule? `force` already means "over the client's own claims";
# a client MESSAGE un-maximizing the window is one more of those, and
# the live case is emacs: a frame whose fullscreen parameter is nil
# sends "remove maximized" right after mapping, enforcing its own nil
# against what the desk just did (the owner's log, 2026-07-31:
# born 1908 by place {max force}, snapped to 1218 a beat later by
# that message). The pin binds CLIENTS, not the user: the titlebar
# button, winops and the hand resize stay the way out.
proc maximize-pinned {w} {
    set st [style-of $w]
    if {![dict exists $st place]} { return 0 }
    lassign [place-force [dict get $st place]] spec forced
    expr {$forced && [string trim $spec] eq "max"}
}
# The toggle asks about ITS axes: any of them free means maximize (a
# tall window's full toggle goes to full, which is what the button
# means over a half-held window everywhere else); all of them held
# means those axes let go. The full restore after tall-then-full comes
# back whole — the way back was recorded axis by axis.
proc maximize-toggle {w {axes {h v}}} {
    set have [expr {[info exists ::maxaxes($w)] ? $::maxaxes($w) : {}}]
    foreach a [max-axes $axes] {
        if {$a ni $have} { maximize-client $w $axes; return }
    }
    unmaximize-client $w $axes
}
# wm-resize-client skips a no-op resize and tells the client nothing
# then — but the frame MOVED either way, so state the origin once more,
# from settled Tk geometry.
proc maximize-settle {w} {
    update idletasks
    send-synthetic-configure $w
}

# ---- fullscreen, the substrate's policy-fullscreen hook ----
# Maximize's stronger cousin, and the differences are all deliberate.
# It takes its MONITOR whole and not the workarea (a fullscreen window
# that stopped at the panel would be no such thing); the decoration goes
# away with the strips rather than staying around the edge; and the
# size hints do NOT bind it — EWMH says a fullscreen window fills the
# screen, so a terminal shows a few pixels of slack at one edge
# instead of leaving a decorated band there. The saved geometry is its
# own (::fssaved), separate from maximize's: a window can be
# maximized, go fullscreen and come back to being maximized, and each
# toggle still restores what IT remembered.
proc policy-fullscreen {w on} {
    if {![info exists ::frameof($w)]} return
    set t $::frameof($w)
    if {$on} {
        regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> X Y
        set ::fssaved($w) \
            [list [$t.slot cget -width] [$t.slot cget -height] $X $Y]
        # ITS monitor, read before the mark changes the layout: a
        # fullscreen window covers the glass it stood on, and the
        # bounding box of a multihead desk is not a screen anyone sees
        lassign [monitor-of-frame $t] mX mY cw ch
        set ::fullframe($t) 1
        set X $mX; set Y $mY
    } else {
        if {![info exists ::fssaved($w)]} return
        lassign $::fssaved($w) cw ch X Y
        unset ::fssaved($w)
        unset -nocomplain ::fullframe($t)
    }
    # The furniture FIRST and the client second, and the frame-layout
    # call is not left to wm-resize-client's: that one skips a resize
    # whose numbers did not move (a window already the size of the
    # screen going fullscreen is exactly that case) and would leave the
    # decoration standing around a window that has none.
    frame-layout $t $cw $ch $X $Y
    wm-resize-client $w $cw $ch
    # Either direction changes which layer this window works out to
    # (see layer-effective), and nothing here needs to know which: the
    # model is asked again and the desk is restacked once.
    restack-soon
    update idletasks
    send-synthetic-configure $w
}
# Nothing of ours stays above THE ACTIVE fullscreen window — that is
# what the state means, and the panel and the tray are the two that
# would. It is a LAYER now (LAYER_FS, computed in layer-effective) and
# not a rule re-stated at every lift: the strips rebuild, an icon
# docks, the focus moves, and each of those ends in one restack that
# gets this right by construction.
#
# ACTIVE is the whole of it, and it used to be missing: the rule was
# "every fullscreen window, always, to the very top", which made a
# fullscreen window a thing you could not get out from under. Alt-Tab
# away and it came straight back over the window you had just picked;
# and it swallowed its OWN dialogs, because whatever seated a transient
# above its leader was undone a moment later (owner's report,
# 2026-08-04).
#
# The reading every other desk uses, and the owner's own words for it:
# a fullscreen window that lost the focus is JUST A WINDOW — it lies
# where the stacking left it, under the panel, undecorated, and it does
# not come back up until you switch to it. The top layer is a property
# of being ACTIVE, not of the state.
#
# The group, not the window: the focus may sit on a DIALOG of the
# fullscreen window, and then the fullscreen window is still what the
# user is looking at — so the answer is the LEADER, and every member
# rides at least as high as its leader (layer-effective).
proc fullscreen-active {} {
    if {$::focused == 0} { return 0 }
    if {[info exists ::fullscreen($::focused)]} { return $::focused }
    set leader [group-leader $::focused]
    if {$leader != $::focused && [info exists ::fullscreen($leader)]} {
        return $leader
    }
    return 0
}
# The user's own toggle (the ops menu, or a config's chord), as opposed
# to the client asking through EWMH. Both end in the substrate's pair,
# which is where the state and the property live.
proc fullscreen-toggle {w} {
    if {[info exists ::fullscreen($w)]} {
        unfullscreen-client $w
    } else {
        fullscreen-client $w
    }
}

