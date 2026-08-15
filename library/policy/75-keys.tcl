# ---- default key bindings ----
# The defaults live IN CODE — the config is an override layer, not a
# preset carrier. The window OPS menu (actions on the focused window)
# answers both the one-chord Alt+Space and the stumpwm-style sequence
# Super+t w m; the window LIST sits on Alt+Tab — where the held Alt
# turns it into the fvwm cycle — and on Super+t w w as a plain static
# menu (the sequence ends with everything released).
#
# They live in a PROC because a config reload has to put them back: the
# reset drops every grab this WM holds (a config is free to bind over a
# default, and an override cannot be un-bound piecemeal), and then the
# in-code defaults are laid down again as a fresh floor.
# ---- key bundles: bindings that come and go together ----
# A desk's keys are not thirty unrelated declarations; they come in
# FAMILIES — the stumpwm-flavored prefix tree, the Windows-shaped
# reflexes one's hands already have — and a family is what a user
# wants to turn on, off or MOVE (the owner, 2026-08-01: "подставьте
# своё вместо Win+h и Win+t"). So a bundle is declared once, with
# parameters, and `wm-keys` is how a config or a click speaks about
# it:
#
#   wm-keys chords -prefix {<Super>x}   ;# the whole tree moves
#   wm-keys windows off                  ;# the reflexes go away
#
# Re-declaring a bundle UNBINDS what its previous instance bound —
# which is the whole point of parameterizing rather than asking a
# config layer to move subtrees: the family knows its own members and
# nothing else has to.
keep key_bundles {}       ;# name -> {params {...} chords {...}}
set key_bundle_defs {}    ;# name -> {params {...} body {...}}
proc key-bundle {name params body} {
    dict set ::key_bundle_defs $name [dict create params $params body $body]
}
# Inside a bundle body: bind, and remember what was bound so the next
# instance can take it away. While the body runs in wm-keys's
# transaction the bind is STAGED, not made — the chords are parsed
# here and now, so a bad one fails the body with the working keymap
# untouched, and the stage lands only after the whole body stood.
proc bundle-bind {spec script {label ""}} {
    if {[info exists ::key_bundle_staging]} {
        lmap tok $spec {parse-chord $tok}
        lappend ::key_bundle_staging [list $spec $script $label]
        dict lappend ::key_bundle_current chords $spec
        return
    }
    wm-bind $spec $script $label
    dict lappend ::key_bundle_current chords $spec
}
proc wm-keys {name args} {
    if {![dict exists $::key_bundle_defs $name]} {
        error "wm-keys: no such bundle «$name» —\
 one of: [dict keys $::key_bundle_defs]"
    }
    set def [dict get $::key_bundle_defs $name]
    # -prefix on the call, prefix in the declaration: the dash is how
    # one WRITES an option and not part of its name, and merging the
    # two spellings quietly gave the body its defaults while the
    # caller's values sat beside them under other keys (caught by the
    # regression, which is what a regression is for).
    set given {}
    if {[lindex $args 0] ne "off"} {
        foreach {k v} $args {
            set k [string trimleft $k -]
            if {![dict exists [dict get $def params] $k]} {
                if {![dict size [dict get $def params]]} {
                    error "wm-keys $name takes no parameters"
                }
                error "wm-keys $name: no parameter «$k» —\
 one of: [dict keys [dict get $def params]]"
            }
            dict set given $k $v
        }
    }
    # THE BODY RUNS AGAINST A STAGE, NOT THE MAP. A body may fail for
    # any reason of its own — a bad parameter today, a bundle that
    # reads somebody's xbindkeysrc and cannot parse it tomorrow (the
    # owner, 2026-08-03) — and a failure used to leave the family
    # half-dismantled: the previous instance was taken down FIRST,
    # so one refused word turned the bundle off while the tree went
    # on showing it standing. The transaction is the fix, not a
    # pre-check: bundle-bind collects into the stage, the working
    # keymap is not touched while the body runs, and a body that
    # falls is simply discarded — the standing instance never moved.
    if {[lindex $args 0] ne "off"} {
        set params [dict merge [dict get $def params] $given]
        set ::key_bundle_current [dict create params $params chords {}]
        set ::key_bundle_staging {}
        try {
            # everything the body binds is the FAMILY's word,
            # whichever layer asked for the family (see say-as)
            say-as [list bundle $name] \
                [list apply [list {params} [dict get $def body]] $params]
        } on error {err opts} {
            unset ::key_bundle_staging
            return -options $opts $err
        }
    }
    # THE WORDS ARE GOOD — now the previous instance leaves, but ONLY
    # what is still the family's. A chord somebody has taken since (a
    # `take` out of this very bundle, a plain wm-bind over it) belongs
    # to them now, and a departing family that swept it away destroyed
    # the one thing its owner meant to keep (the owner's desk,
    # 2026-08-01: on-then-off after a take left three customizations
    # that said their piece and answered nothing).
    #
    # The keys-pass claim settles ONCE, over the finished move: the
    # departure and the landing both move top chords, and a claim on
    # THIS bundle consulted halfway would see the family half-gone —
    # and gripe about a bundle that is merely mid-flight. The finally
    # both disarms the deferral on every path (off returns from inside)
    # and runs the one settling that counts.
    set ::keys_pass_defer 1
    try {
        if {[dict exists $::key_bundles $name]} {
            set kept 0
            foreach spec [dict get $::key_bundles $name chords] {
                if {![catch {wm-unbind-owned $spec [list bundle $name]} gone]
                        && !$gone} { incr kept }
            }
            if {$kept} {
                puts "WM: keys: bundle $name leaves $kept chord(s) —\
 not its own any more"
            }
            dict unset ::key_bundles $name
        }
        if {[lindex $args 0] eq "off"} {
            puts "WM: keys: bundle $name off"
            return
        }
        # ...and the staged binds land, in the family's own name
        set staged $::key_bundle_staging
        unset ::key_bundle_staging
        say-as [list bundle $name] {
            foreach b $staged { wm-bind {*}$b }
        }
        dict set ::key_bundles $name $::key_bundle_current
        puts "WM: keys: bundle $name on\
 ([llength [dict get $::key_bundle_current chords]] bindings)"
    } finally {
        set ::keys_pass_defer 0
        keys-pass-apply
    }
}
# WHICH CHORD DOES THIS? — the keymap read backwards, for anything
# that wants to TELL the user where a thing lives instead of assuming
# (the welcome mat asks; a help line could). Empty when nothing is
# bound to it, which is an answer too.
proc chord-of {script} {
    return [keymap-find $::keymap $script {}]
}
proc keymap-find {node script path} {
    dict for {k entry} $node {
        lassign [split $k ,] mods ks
        set here [concat $path [list [chord-name $mods $ks]]]
        lassign $entry kind payload
        if {$kind eq "map"} {
            set r [keymap-find $payload $script $here]
            if {$r ne ""} { return $r }
        } elseif {[string trim $payload] eq [string trim $script]} {
            return [join $here " "]
        }
    }
    return ""
}

# ---- keys-pass: leaders the focused window claims for itself ----
# The style key `keys-pass` names top chords the desk GIVES UP while
# the window holds the focus — a fullscreen RDP viewer whose remote
# desk has an Alt+Tab of its own gets Alt+Tab back, and the prefixes
# stay home. Flat {kind spec} pairs, repeats legal:
#
#   wm-style {filter -class xfreerdp} \
#       {keys-pass {bundle windows chord <Super>d}}
#
# `bundle` passes the CURRENT leaders of a bundle — all of them (for
# chords that is the prefix and the help key); `chord` one chord
# token. What is passed is the GRAB, not an ownership: everything
# under a passed leader goes quiet for that window, a custom bind
# under the same umbrella included — whoever bound `<Super>t k` chose
# to stand under the chords prefix. Resolution is LATE — the set is
# re-derived at every settling, never snapshotted at the style merge,
# so a re-parameterized bundle keeps passing its new prefix. A
# crooked element fails CLOSED — the chord stays the desk's, which
# is visible and safe — with one complaint per unique cause, not a
# storm of them.
#
# Two askers in the substrate: keys-pass-apply LIFTS the server grabs
# of the claimed leaders while the window holds the focus (the way a
# modifier survives the trip — see the apply for the RDP story), and
# handle-key's fallback replays a frozen press that should not have
# arrived. Both want the same answer: the leaders this window claims.
keep keys_pass_griped {}
proc keys-pass-gripe {why} {
    if {$why in $::keys_pass_griped} return
    lappend ::keys_pass_griped $why
    puts "WM: keys-pass: $why — element ignored, the chord stays the desk's"
}
proc policy-keys-pass-set {w} {
    if {$w == 0 || ![info exists ::managed($w)]} { return {} }
    set st [style-of $w]
    if {![dict exists $st keys-pass]} { return {} }
    set val [dict get $st keys-pass]
    if {[llength $val] % 2} {
        keys-pass-gripe "odd pair list «$val»"
        return {}
    }
    set out {}
    foreach {kind spec} $val {
        switch -- $kind {
            bundle {
                if {![dict exists $::key_bundles $spec]} {
                    keys-pass-gripe "bundle «$spec» is not on"
                    continue
                }
                foreach cspec [dict get $::key_bundles $spec chords] {
                    if {[catch {parse-chord [lindex $cspec 0]} top]} continue
                    if {$top ni $out} { lappend out $top }
                }
            }
            chord {
                if {[catch {parse-chord $spec} top]} {
                    keys-pass-gripe "bad chord «$spec»: $top"
                    continue
                }
                if {$top ni $out} { lappend out $top }
            }
            default {
                keys-pass-gripe "unknown kind «$kind» (bundle or chord)"
            }
        }
    }
    return $out
}
proc policy-key-pass {w mods ks} {
    expr {[list $mods $ks] in [policy-keys-pass-set $w]}
}

# THE ACCORD TREE — stumpwm's shape: one prefix, everything under it,
# and a key that says what is under the prefix you are standing in.
# Both are parameters, because a prefix is exactly the thing a user
# has an opinion about.
key-bundle chords {prefix {<Super>t} help {<Super>h}} {
    set p [dict get $params prefix]
    bundle-bind [concat $p {w m}] winops
    bundle-bind [concat $p {w w}] winlist-all \
        "every window there is, whatever desk it is on"
    bundle-bind [concat $p {w r}] Reload
    # The configurator is a STOCK chord and not a member of any set
    # (the owner, 2026-08-02, choosing between the two): it is the way
    # in to everything else this desk can be told, so a desk that has
    # to be furnished before it can be configured has the dependency
    # backwards. It sits one letter under the prefix like the rest.
    bundle-bind [concat $p c] {applet configurator} \
        "everything this desk can be told"
    bundle-bind [concat $p p] panel-pin-last \
        "pin the last thing you started to the panel"
    bundle-bind [concat $p q] Quit
    # The keymap from the top — the same key that answers "what is
    # under this prefix" inside a sequence answers "what is there at
    # all" outside one (see key-help-open).
    bundle-bind [dict get $params help] key-help-open \
        "every key this desk answers to"
    set-key-help [dict get $params help]
}
# THE REFLEXES one's hands arrive with. Reckless on purpose: these
# chords belong to applications too, and taking them is a choice —
# which is why they are a bundle one can turn off, and why the ones
# that CLOSE things are named separately from the ones that only
# look.
#
# NO parameters, deliberately (the owner, 2026-07-31): a parameter
# per member is not a family parameter, it is the member list spelled
# twice — chords' prefix moves a whole tree, these would each move
# one key. The way to keep two reflexes and drop the rest is decision
# 4: take the keepers into the custom layer as plain wm-bind and turn
# the family off.
# THE DESKS, on their own modifier. A family of its own because it is
# neither of the other two: not the stumpwm tree (these are one press,
# not a sequence) and not the Windows reflexes (Windows has no such
# key). The modifier is a parameter for the same reason a prefix is —
# it is the thing one has an opinion about.
#
# It binds exactly as many digits as there are desks, and set-desks
# re-applies it when that number changes: nine bindings on a two-desk
# machine would take Super+3 away from whoever else wants it. Shift
# sends the window instead of going there — the convention every desk
# with desks uses.
#
# The help does NOT list these one per desk: a run of digits collapses
# to «Super+1..4» with the digit standing as N in the words (see
# help-collapse). That is the whole reason the collapsing exists.
key-bundle desks {mods {<Super>} send {<Super><Shift>}} {
    set m [dict get $params mods]
    set sm [dict get $params send]
    # ONE DESK BINDS NOTHING. There is nowhere to go, and Super+1 is
    # somebody else's key until the day a config asks for desks — which
    # is what lets this bundle be on by default and cost nothing.
    if {$::ndesks <= 1} return
    for {set i 0} {$i < $::ndesks} {incr i} {
        set d [expr {$i + 1}]
        bundle-bind [list $m$d] [list desk-go $i] "go to desk $d"
        bundle-bind [list $sm$d] [list desk-send-current $i] \
            "send this window to desk $d"
    }
}
key-bundle windows {} {
    bundle-bind {<Alt>Tab} winlist
    bundle-bind {<Alt>space} winops
    bundle-bind {<Alt>F4} Close "close the active window"
    bundle-bind {<Super>d} {Apply-To-Matching always Minimize} \
        "minimize everything"
}

proc policy-default-bindings {} {
    wm-keys chords
    wm-keys windows
    wm-keys desks       ;# binds nothing while there is one desk
    # Re-read the config in place. Deliberately a default: the whole
    # point of the reload is to try a config without restarting, and
    # having to configure the way to reload the config first would be a
    # poor joke. Bind over it like any other default.

    # The way out, and a default for the same reason: a desk you can
    # only leave by finding another terminal and killing yourself is
    # the "how do I exit vim" joke with a whole login in it. It sits in
    # the Super+t family with the rest, one letter under a prefix — far
    # enough that nobody arrives by accident, and guessable from the
    # others rather than needing to be looked up (owner, 2026-07-29).
}
# Once per process, not per source: the keymap is kept state a config
# writes into, "later binds win" — so a bare call here made every
# Reread re-state the defaults OVER whatever the config had rebound
# those chords to (the fonts' disease, third patient). A Reload still
# re-floors the keymap on purpose: policy-reset calls this itself.
unless-already {[info exists ::policy_bindings_up]} {
    set ::policy_bindings_up 1
    policy-default-bindings
}

