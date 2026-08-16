# ---- the panel ----
# Our own strip panel, wmaker-flavored buttons — and a button is a
# REFERENCE: the deed itself is an action (see below), a button is
# how a panel wears one. Fired by click it does what the action's
# name does — focus the most recent match, else launch — and the
# face flashes the verdict either way (green "found it", orange
# "launching"); the chord is the ACTION's own business, live with no
# panel at all. Declared from the config:
#
#   panel-button NAME ?{label TEXT icon SPEC}?
#
# NAME names an action; the optional overrides dress it for THIS
# panel — label is display only (the reference's key stays the
# action's name), icon covers the action's own face. The panel
# exists only when at least one reference resolves — stock behavior
# is panel-less — and the workarea hands the strip over the moment
# there are buttons, so maximize never covers it. Every raise-group
# ends by lifting the panel back on top: fvwm's StaysOnTop for the
# poor, good enough until layers exist.
#
# Where and how, two knobs. set-panel-side top|bottom|left|right picks
# the screen edge (left and right are vertical treectrls — only the
# flow orientation and the band's geometry change, the button logic
# never sees the side). set-panel-preset row|stack picks the button
# layout when any face is iconic: row is <image> Text, stack puts the
# label under the icon — the tall-strip look for a thick bottom bar or
# a narrow side one.
#
# There can be MORE THAN ONE. A panel is an instance, named, declared
# with a block:
#
#   panel dock { set-panel-side left; panel-button терм {...} }
#
# and everything said outside a block belongs to the panel named
# `default` — which is why a config that never heard of the plural
# keeps working unchanged. Each panel carries its own side, preset,
# icon size and buttons; the bands they reserve are carved in
# declaration order (see the strips section), so two panels are a
# taskbar and a dock without either knowing about the other.
#
# Geometry is precomputed per (re)build — fonts, RandR and the config
# all funnel into panel-build. With no iconic face anywhere the strip
# keeps today's text-chip height (back-compat); once ANY face
# resolves, every iconless button wears the winlist's auto-badge as a
# placeholder (letters of the label on a crc32 color), so the mixed
# case holds one unified height. panel-icon-size (default 48, the
# hicolor stock) is the resolve-icon target; a foreign size is
# resampled by resolve-icon itself.
#
# A button whose match sees a LIVE window says so persistently: an
# indicator bar along the button's bottom edge plus a light tint of
# the face — the same state machinery the flash feedback uses, only
# not timed out (set-panel-live-colors BAR FACE re-paints). More
# than one match grows an ARROW zone at the button's east edge:
# clicking it drops the winlist filtered to the matches, anchored by
# the button (MRU, icons, numbered hotkeys — the shared machinery),
# picking focuses; a body click keeps the old idempotent fire on the
# most recent match. Matches are re-judged on manage, unmanage and
# every title change (a title flip can turn a -title filter around),
# debounced like the RandR rebuild.
# Every panel's settings in ONE variable, keyed by name — a Tcl dict
# keeps its insertion order, so the dict IS the declaration order the
# bands are carved in, and the config layer's snapshot/restore machinery
# (which knows how to put a variable back) covers panels for free.
# `refs` is what the layers SAID: per action name, the merged display
# overrides — a dict again, so its order is the strip's order.
# `shown` is what a build RESOLVED out of that against the action
# registry (waiting and undeclared names skipped), {name label spec}
# per button. A build product, riding in the same dict for the
# asking — safe there because every build re-resolves it from
# nothing, so a restored stale copy can mislead nobody. The live
# widget and the arrow zone stay out as before.
proc panel-defaults {} {
    dict create side bottom preset row icon_size 48 refs {} shown {}
}
# Empty, and `default` is created on first mention like any other name.
# That is what makes the dict's order the CONFIG's order: a `default`
# present from the start would always have been the first band carved,
# whatever the config wrote first, and the corner rule would be a rule
# about our initialization rather than about the config.
keep panels {}
keep panel_target default   ;# whose knobs the config is turning right now
array set panel_win {}     ;# name -> the live top-level, absent = not built
array set panel_zone {}    ;# name -> its reserved arrow strip, set per build
# name -> {action-name -> treectrl item}, set per build. THE one
# bridge between the model and the strip's items: everything that
# aims at a button — a flash, a re-judged match, a click, the
# winlist anchoring itself by the arrow's button — asks this map,
# never «button i = item i+1». An item number is not a position
# promise: reconciliation moves items without renumbering them.
array set panel_items {}
# name -> the last build's STRUCTURE signature (panel-geometry sans
# faces, plus the side): same signature — the tree stands and its
# items reconcile; changed — the tree is built from nothing, its
# styles being the structure. See panel-build.
array set panel_sig {}
# The block form. `panel NAME BODY` points the knobs at NAME for the
# length of BODY and puts them back afterwards — uplevel, so the body
# is ordinary config code that can call anything, and the target is
# restored even if it throws (a config that dies mid-block must not
# leave every later declaration landing in a panel nobody can see).
proc panel {name body} {
    if {$name eq ""} { error "panel: a panel needs a name" }
    panel-ensure $name
    set outer $::panel_target
    set ::panel_target $name
    set code [catch {uplevel 1 $body} res opts]
    set ::panel_target $outer
    if {$code} { return -options $opts $res }
    return $res
}
proc panel-ensure {name} {
    if {![dict exists $::panels $name]} {
        dict set ::panels $name [panel-defaults]
    }
}
proc panel-names {} { dict keys $::panels }
# A panel nobody declared answers with the CODE's defaults rather than
# throwing: the tray can be pointed at a name that never came to exist
# (a typo, a block that died before its first button), and the honest
# answer to "which edge is it on then" is the default edge — not an
# error that takes the desk's geometry down with it.
proc panel-cfg {name key} {
    if {[dict exists $::panels $name]} { return [dict get $::panels $name $key] }
    return [dict get [panel-defaults] $key]
}
proc panel-set {name key value} {
    panel-ensure $name
    dict set ::panels $name $key $value
    panel-rebuild-soon
}
# The live widgets of a built panel: the top-level and its treectrl.
# "" when this panel has no strip up (no buttons, or not built yet) —
# every caller that pokes at the tree checks, because a panel can be
# rebuilt out from under a deferred callback.
proc panel-window {name} {
    if {[info exists ::panel_win($name)] && [winfo exists $::panel_win($name)]} {
        return $::panel_win($name)
    }
    return ""
}
proc panel-tree {name} {
    set p [panel-window $name]
    expr {$p eq "" ? "" : "$p.t"}
}
proc set-panel-side {side} {
    if {$side ni {top bottom left right}} {
        error "set-panel-side: top, bottom, left or right"
    }
    panel-set $::panel_target side $side
}
proc set-panel-preset {preset} {
    if {$preset ni {row stack icons}} {
        error "set-panel-preset: row, stack or icons"
    }
    panel-set $::panel_target preset $preset
}
proc set-panel-icon-size {px} {
    panel-set $::panel_target icon_size $px
}
keep panel_live_bar  #8ae234  ;# the indicator strip
keep panel_live_face #5d6e59  ;# the face tint under a live match
proc set-panel-live-colors {bar face} {
    set ::panel_live_bar $bar
    set ::panel_live_face $face
    panel-rebuild-soon
}
# ---- actions: named deeds, prior to any button ----
# The owner's turn of the model (2026-07-31): PRIMARY is not the
# button but the ACTION — a named thing this desk can do, usually
# run-or-raise. `run` says what to start (RAW ARGV, one uniform
# spelling whether it runs bare or inside a terminal — the wrapping
# is the machinery's business, see run-argv); `match` says which
# window counts as already-running (no match — plain launcher);
# `icon` is a face for whatever panel may some day carry it; `key`
# is the chord that does it — bound to the NAME, live whether or not
# any panel shows a button; `needs` gates the whole action on the
# machine having the software. An unmet needs leaves the action
# WAITING — declared, visible, not bound — and it comes alive by
# itself on the reload after the command appears. The `terminal` and
# `emacs` words are ADAPTERS, not kinds: they derive match, launch
# and activate into the one native shape everything else consumes
# (spec-derive — the same providers the buttons had).
#
# The name is the primary key, and a second declaration REFINES the
# first: raw words merge, an empty value un-says its key (`terminal`
# exempt — its empty dict is a word, see the buttons' lesson 117).
keep action_raw {}    ;# NAME -> the merged raw words (what the layers SAID)
keep action_spec {}   ;# NAME -> what the machinery runs on (derived + state)
keep action_lint {}   ;# NAME -> the linter's verdicts on the raw words

proc action {name settings} {
    set raw $settings
    if {[dict exists $::action_raw $name]} {
        set raw [dict merge [dict get $::action_raw $name] $settings]
    }
    foreach k [dict keys $raw] {
        if {[dict get $raw $k] eq ""
                && [node-empty-means [list @spec action $k]] eq "unsay"} {
            dict unset raw $k
        }
    }
    # Read before it is believed, against the table that says what an
    # action may carry (spec-check): a key nobody registered is a
    # typo, and `run` beside `launch` is one slot said twice — which
    # used to be settled silently in favour of the launch, the worst
    # place for a silence, since an owner editing the command would
    # watch the button keep running the old script and hear nothing.
    # On the RAW words, before any deriving: the derived spec always
    # has a launch, sugar or not.
    spec-check "action $name" action $raw
    dict set ::action_raw $name $raw
    action-realize $name
    # style is a shorthand landing WHEN SAID — this call's word, not
    # the merged memory's (the panel-button rule, for the same
    # reasons); a waiting action styles nothing, exactly as it runs
    # nothing.
    if {[dict exists $settings style] && [dict get $settings style] ne ""} {
        set spec [dict get $::action_spec $name]
        if {[dict get $spec state] eq "active"} {
            if {![dict exists $spec match]} {
                error "action $name: style needs a match to apply to"
            }
            wm-style [dict get $spec match] [dict get $settings style]
        }
    }
}
# Derive what the machinery runs on. `run` is SUGAR and desugars
# first: `run {mutt}` is `launch {Run mutt}` and nothing else, so
# there is one runtime form and two spellings of it. The adapters
# then see a launch that already stands and leave it alone — which is
# how a terminal action stopped needing a rule of its own about
# whose command goes inside the terminal. `Run` is answered by the
# context the adapter sets up (spec-derive's runvia); the script
# says WHAT, the words beside it say WHERE.
#
# The two cannot both be said — that is judged on the raw words, in
# `action`, before anything derived exists.
proc action-derive {name raw} {
    if {[dict exists $raw run]} {
        dict set raw launch [list Run {*}[dict get $raw run]]
    }
    # A DEED THAT SAYS `emacs` ALREADY HAS A NAME — ITS OWN. The frame
    # name is what the desk finds the window by (it is the WM_CLASS
    # instance), so an emacs deed cannot do without one; but making a
    # person type `action telega {emacs {frame telega …}}` is asking
    # them to say the same word twice. Unsaid, the deed lends its own.
    #
    # This is the answer to «let a nameless button just find some
    # Emacs» (the owner's sketch, 2026-08-02) — a reading that holds
    # only on a one-server desk. X carries no word about which daemon
    # a frame belongs to: every gui frame is classed Emacs, so on a
    # desk with two servers a nameless button raises whichever frame
    # the search happened to reach first. A name derived from the deed
    # costs the same nothing to write and keeps the identity exact.
    #
    # The name becomes an X property, so a deed called in a script one
    # cannot type in Latin-1 (or one with a glob character in it) is
    # the case for saying `frame` outright — the door is not closed,
    # it is simply not the one most people need.
    if {[action-type $raw] eq "emacs" && ![dict exists $raw emacs frame]} {
        dict set raw emacs frame $name
    }
    return [spec-derive "action $name" $raw]
}
# Alive or waiting — needs is the gate, judged NOW: every replay
# re-judges, which is what lets a declared action surface by itself
# once its software lands. The chord follows the state: bound only
# while active, and the old chord goes with the old spec whatever
# happens next.
# action-remove NAME — the negative word actions lacked. Every other
# family could say «not this one» about something a lower layer
# declared: bindings have wm-unbind, widgets wm-widget-remove, a panel
# is owned whole. An action could only be REFINED, so a config's deed
# was undroppable from the layer above it and the applet said as much
# and stopped there.
#
# It keys as `action NAME`, which is the same key the declaration
# takes: my last word about this deed replaces my previous one, and
# the layers replay in their own order — the code and the config
# declare, and this comes after.
proc action-remove {name} {
    if {[dict exists $::action_spec $name key]} {
        catch {wm-unbind [dict get $::action_spec $name key]}
    }
    dict unset ::action_raw $name
    dict unset ::action_spec $name
    dict unset ::action_lint $name
    puts "WM: action $name: removed"
    panel-rebuild-soon
}
proc action-realize {name} {
    set raw [dict get $::action_raw $name]
    if {[dict exists $::action_spec $name]
            && [dict exists $::action_spec $name key]} {
        catch {wm-unbind [dict get $::action_spec $name key]}
    }
    set state active
    if {[dict exists $raw needs] && ![needs-met [dict get $raw needs]]} {
        set state waiting
    }
    # A TERMINAL DEED NEEDS A TERMINAL, and it is the one need an
    # action cannot state for itself: WHICH emulator is a detection
    # (terminal-resolve walks the config's word, $TERMINAL,
    # x-terminal-emulator and then the adapters), so «needs xterm»
    # would be a lie on a machine carrying kitty and nothing else.
    # It is also the other quantifier: `needs` above is ALL-OF, every
    # word on the PATH, and this is ANY-OF — so it is its own check
    # rather than a clever entry in that list.
    #
    # The point is the fresh desk, and the owner's own case: a
    # terminal button on a machine with no emulator used to be a
    # button that did nothing when pressed. Now it stands by and says
    # what it is waiting for, which is what `needs` was built to do
    # («accepted with a sentence, not refused»).
    set no_terminal 0
    if {$state eq "active" && [action-type $raw] eq "terminal"
            && [lindex [terminal-resolve] 0] eq ""} {
        set state waiting
        set no_terminal 1
    }
    if {$state eq "active"} {
        set spec [action-derive $name $raw]
    } else {
        set spec $raw
        # Said into the SPEC and not into the raw: what the config
        # wrote is what the config wrote, and the lint below judges
        # that. This is the desk's own reading, and it goes where the
        # rest of the desk's readings go.
        if {$no_terminal} {
            dict set spec needs [dict keys $::terminal_adapters]
        }
        puts "WM: action $name: needs [dict get $spec needs] — waiting"
    }
    dict set spec state $state
    dict set ::action_spec $name $spec
    # ...and what a reader of the table would REMARK on. Said to the
    # log only when it changes, because a realize happens on every
    # word said about this deed and on every replay of the layers —
    # the same three sentences at every reload would be noise, and
    # noise is how a log stops being read.
    set lint [spec-lint action $raw]
    if {![dict exists $::action_lint $name]
            || [dict get $::action_lint $name] ne $lint} {
        foreach verdict $lint {
            puts "WM: action $name: [dict get $verdict level] —\
 [dict get $verdict text]"
        }
    }
    dict set ::action_lint $name $lint
    if {$state eq "active" && [dict exists $spec key]} {
        wm-bind [dict get $spec key] [list action-fire $name] $name
    }
    # any strip carrying this name shows the NEW spec — the panels
    # resolve their references at build, so the build must come
    panel-rebuild-soon
}

# THE ONE DOOR every plain launch walks through. Today it is exec's
# fire-and-forget; the point of a single door is that tomorrow it can
# be `open |cmd` with error monitoring, or consult a registry of
# environments by argv[0] ("every firefox runs under
# GTK_IM_MODULE=fcitx") — and no caller will change a word.
proc run-argv {argv} {
    exec {*}$argv &
}

# ---- Run — the door said out loud, and what the context makes of it ----
# `Run words…` is how a launch SCRIPT starts something, and it is
# Capitalized for the reason every window command is: it acts, now.
# What it does not do is read its words — no tilde, no expansion of
# any kind (the owner, 2026-08-01). It needs none: a launch script is
# evaluated at fire time, at the global level like every callback
# here, so Tcl's own substitution has already run and `$env(HOME)`
# means what it says.
#
# What the words become is the CONTEXT's business, which is what
# collapsed three ways of saying "what this button starts" into one.
# Bare, they are a command. Under an adapter that knows how to wrap a
# command — a terminal — the same line means "start this THERE":
#
#     action Log {
#         terminal {name log}
#         launch {Run tail -f $env(HOME)/log}
#     }
#
# The script never learns about `xterm -e`, and the adapter never
# learns what it is wrapping. `run {tail -f …}` is the same thing said
# shorter: sugar for exactly this launch (action-derive).
keep run_via {}    ;# a STACK: the innermost fire decides, and unwinds
proc run-via {via script} {
    lappend ::run_via $via
    try {
        uplevel #0 $script
    } finally {
        set ::run_via [lrange $::run_via 0 end-1]
    }
}
# WHERE the deed runs — the `dir` spec key, a stack exactly like the
# via. It lands as an `env -C DIR` prefix on the words BEFORE the via
# sees them, which is the whole trick (the owner, 2026-08-04): bare,
# the launch becomes `env -C … cmd`; through a terminal it becomes
# `xterm -e env -C … cmd`. GNU coreutils ≥ 8.28, which a desk this
# X11-bound already stands on. (The terminal adapter hears about dir
# too, separately — spec-derive threads it so the EMULATOR stands
# there as well, run or no run.)
#
# A `~` in dir is a path said the human way — expanded here, at use
# time, the icon-file-of pattern (Tcl 9 dropped the implicit
# expansion). The WORDS of a Run stay unread as ever: dir is a path
# by its own declaration, the words are not ours to interpret.
keep run_dir {}
proc run-at {dir script} {
    catch {set dir [file tildeexpand $dir]}
    lappend ::run_dir $dir
    try {
        uplevel #0 $script
    } finally {
        set ::run_dir [lrange $::run_dir 0 end-1]
    }
}
proc Run {args} {
    set dir [lindex $::run_dir end]
    if {$dir ne ""} { set args [list env -C $dir {*}$args] }
    set via [lindex $::run_via end]
    if {$via eq ""} {
        puts "WM: Run $args"
        run-argv $args
        return
    }
    puts "WM: Run via [lindex $via 0]: $args"
    uplevel #0 [list {*}$via $args]
}

# Fire by NAME — run-or-raise, panel or no panel: the match's most
# recent window gets the focus (or the action's own activate hook),
# otherwise the launch runs under the action's env. Any panel that
# carries the action flashes its button, found by name. A waiting
# action says so instead of guessing.
#
# MODE IS THE CALLER'S, NOT THE DEED'S — and that is the whole reason
# it is an argument:
#
#   auto    consult the deed's `many` (this is what a CHORD does)
#   mru     the most recent window, whatever `many` says
#   choose  ask, when there is more than one
#   run     start another one, found window or not
#
# A button offers TWO of these on its own face — its main area is mru,
# its arrow is choose — so a knob read from inside the fire would take
# away the choice the mouse already has under its finger (the owner,
# 2026-08-03, correcting the first reading of `many`). The keyboard has
# no such face: it presses one chord and gets one answer, and `many` is
# the word that says which.
#
# PREFER names the panel the gesture came from, so an arrow opens its
# list off the button that was clicked rather than off whichever panel
# would have been picked for a chord.
# Reaching a window takes the desk with it — that IS what reaching
# means, and it is the same rule whether the window was found by a
# panel button, the window list or a chord. Sticky windows are here by
# definition and this never fires for them.
# The keyboard's own "send it there": the focused window, since the
# hand is on the keys and not on a titlebar.
proc desk-send-current {n} {
    set w [current-window]
    if {$w == 0} {
        puts "WM: desk send: no window"
        return
    }
    desk-send $w $n
}
proc desk-follow {w} {
    if {![info exists ::managed($w)] || [desk-here-p $w]} return
    desk-go [desk-of $w]
}
proc action-fire {name {mode auto} {prefer ""}} {
    if {![dict exists $::action_spec $name]} {
        puts "WM: action $name: unknown — nothing to fire"
        return
    }
    set spec [dict get $::action_spec $name]
    if {[dict get $spec state] ne "active"} {
        puts "WM: action $name: waiting on [dict get $spec needs] —\
 not firing"
        return
    }
    if {$mode eq "auto"} {
        set mode [expr {[dict exists $spec many] ? [dict get $spec many] : "mru"}]
    }
    # FORCE runs whatever it finds, so it asks nothing about windows.
    if {$mode eq "run"} {
        if {![dict exists $spec launch]} {
            puts "WM: action $name: nothing to run"
            policy-key-echo problem "«$name» has nothing to run"
            return
        }
        action-launch $name $spec
        return
    }
    set wins [panel-matches $name $spec]
    # Asking is only a question when there is something to ask about:
    # one window is reached, none is launched, exactly as ever. This is
    # also where the arrow's stale-zone case lands (the debounce window
    # between the strip's state and the living windows).
    if {$mode eq "choose" && [llength $wins] > 1} {
        action-choose $name $wins $prefer
        return
    }
    set hit [lindex $wins 0]
    if {$hit ne ""} {
        action-reach $name $spec $hit
    } elseif {[dict exists $spec launch]} {
        action-launch $name $spec
    } else {
        puts "WM: action $name: nothing matched, nothing to launch"
    }
}
# The launch half, lifted out so the forced run and the list's own «run
# another» row start a deed exactly the way an ordinary fire does —
# same env, same runvia, same flash, same memory of what was started.
proc action-launch {name spec} {
    puts "WM: action $name: launch"
    # WHAT THE DESK ITSELF STARTED AND HAS NOWHERE TO SHOW, which is a
    # fact and not a guess. "The last thing that appeared" would be the
    # guess: windows arrive on their own schedule and the answer would
    # change under the hand reaching for it (the owner, 2026-08-02 —
    # "appear happens dynamically, you could pin the wrong thing").
    #
    # Two things are stepped over, and for one reason: the question is
    # "what would you like to keep", and neither of them can answer it.
    # A press that merely FOUND an existing window started nothing —
    # which is why this lives in the launch word and not in the fire,
    # and why a FORCED run of a deed that has a window is still a
    # launch and still counts. And a deed that ALREADY HAS AN ICON is
    # not a candidate either: pinning it is a no-op, and letting it take
    # the slot would bury the thing you actually started a moment ago
    # behind an ordinary press of a button that is already there (the
    # owner, same day).
    if {[llength [action-panels $name]] == 0} { set ::last_started $name }
    action-flash $name firing
    set script [dict get $spec launch]
    if {[dict exists $spec env] || [dict exists $spec env-unset]} {
        set script [list with-env \
            [expr {[dict exists $spec env] ? [dict get $spec env] : {}}] \
            $script \
            [expr {[dict exists $spec env-unset]
                   ? [dict get $spec env-unset] : {}}]]
    }
    if {[dict exists $spec dir]} {
        set script [list run-at [dict get $spec dir] $script]
    }
    set via ""
    if {[dict exists $spec runvia]} { set via [dict get $spec runvia] }
    run-script "action $name" [list run-via $via $script]
}
keep last_started ""   ;# the last unpinned deed this desk launched

# ASK WHICH ONE — the filtered list of a deed's own windows, and the
# answer decided by whoever asked rather than by the list.
#
# WHERE it opens is a question only the KEYBOARD has: a click already
# said where it happened, and its arrow passes that panel as `prefer`.
# A chord has to be given a place, and the button is the one the eye
# already ties to the deed — so the list hangs off it when there is one
# to hang off, and stands in the middle of the screen when the deed has
# no face anywhere (the owner's rule, 2026-08-03).
#
# SHOWING, not merely referencing: a panel that names the deed in its
# config but has not built the button (the deed is waiting on its
# software, or resolve skipped it) would anchor the list against a
# button that is not on the screen. So the live item map answers, not
# the reference list.
proc action-shown-panels {name} {
    set out {}
    foreach pn [panel-names] {
        if {[info exists ::panel_items($pn)]
                && [dict exists $::panel_items($pn) $name]} { lappend out $pn }
    }
    return $out
}
proc action-where {name prefer} {
    set on [action-shown-panels $name]
    if {![llength $on]} { return center }
    if {$prefer ne "" && $prefer in $on} { return [list panel $prefer $name] }
    return [list panel [expr {"default" in $on ? "default" : [lindex $on 0]}] $name]
}
proc action-choose {name wins prefer} {
    # A WAIT NEEDS A COROUTINE, and a caller that is not one gets an
    # errand instead of an error: a chord already runs in one (run-script
    # wraps every key's payload), a panel click is a plain Tk binding.
    # Sending it round this way keeps `action-fire NAME choose` a thing
    # anybody may call from anywhere, which is what a verb in this
    # vocabulary has to be.
    if {[info coroutine] eq ""} {
        run-script "action $name" [list action-choose $name $wins $prefer]
        return
    }
    puts "WM: action $name: choose among [llength $wins] matches"
    set spec [dict get $::action_spec $name]
    # «Run another» is the visible door to what Ctrl does on a button,
    # and it is offered only where it is true: a deed with nothing to
    # launch cannot run another of anything.
    set more ""
    if {[dict exists $spec launch]} { set more "Run another $name" }
    set ans [winlist-choose $wins [action-where $name $prefer] $more]
    if {$ans eq ""} return
    # NOTHING TAKEN BEFORE THE WAIT IS TRUSTED AFTER IT. The list stood
    # open for as long as the person liked: the window can die, a reload
    # can take the deed out of the registry, the strip can be rebuilt.
    if {![dict exists $::action_spec $name]} {
        puts "WM: action $name: went away while the list was open"
        return
    }
    set spec [dict get $::action_spec $name]
    if {$ans eq "more"} {
        if {![dict exists $spec launch]} {
            puts "WM: action $name: nothing to run any more"
            return
        }
        action-launch $name $spec
        return
    }
    if {![info exists ::frameof($ans)]} {
        puts "WM: action $name: the picked window is gone"
        return
    }
    action-reach $name $spec $ans
}

# REACHING THE DEED'S WINDOW, in one place. The plain fire calls it
# with the most recent match; a filtered list calls it with the row the
# person picked — and that is why it had to become a word of its own.
# What «reach» means is the DEED's to say: an activate hook replaces
# the plain focus (the emacs door), and a list picking a window has no
# business skipping it. It used to be inlined in the fire, so the pick
# path went straight to the focus and the door was simply not opened.
#
# The hook is handed the window it is to act on. What it can do with
# that window is its own affair and not always much: the emacs door
# raises exactly this frame, but addresses its eval BY THE FRAME'S
# NAME, so two frames of one deed share an eval that lands on whichever
# the daemon picks. Naming the frame by its X window is possible
# (`outer-window-id`) and is a separate piece of work — see the plan.
proc action-reach {name spec w} {
    puts "WM: action $name: found 0x[format %x $w]"
    action-flash $name found
    if {[dict exists $spec activate]} {
        # in a coroutine, like every script that runs on a live desk: an
        # activate hook that waits (emacsclient, say) must not stop the
        # desk while it does
        run-script "action $name" [list {*}[dict get $spec activate] $w]
        return
    }
    panel-focus-hit $w
}

# Which panels carry a button for this deed — empty means nowhere, and
# nowhere is what makes a deed worth pinning.
proc action-panels {name} {
    set out {}
    foreach pn [panel-names] {
        if {[dict exists $::panels $pn refs $name]} { lappend out $pn }
    }
    return $out
}

# ---- Fire: run-or-raise as a word ------------------------------
# `Fire NAME ?mode?` is action-fire said out loud — the fire a chord
# or a button does, callable from any script. `Fire SPEC ?mode?` is
# the same fire over an INLINE spec, the action vocabulary without
# the registry: the whole derivation works — the terminal adapter,
# the match derived from the terminal's name — and nothing lands in
# the registry, the configurator or the bindings. It exists for the
# deed that is DATA rather than a declaration: a menu body listing
# twenty ssh targets or last week's projects would otherwise register
# twenty throwaway names for the configurator to show forever.
#
#     Fire mutt
#     Fire {terminal {name ssh_web} run {ssh web}}
#
# One word or a dict tells the two apart, the menu rows' own rule.
# The surface words — key, icon, badge, style — are refused on an
# inline spec: they dress a declared deed, and carrying them here
# would silently do nothing. An unmet `needs` is refused ALOUD rather
# than left waiting: there is no registry entry to wait in, and a
# fire that silently did nothing is the old mistyped-button bug in a
# new mouth. An inline emacs deed must say its frame name — it has no
# name of its own to lend (the rule a declared action's name covers).
proc Fire {what {mode auto}} {
    if {$mode ni {auto mru choose run}} {
        error "Fire: the mode is auto, mru, choose or run — not «$mode»"
    }
    if {[llength $what] == 1} {
        action-fire $what $mode
    } else {
        fire-spec $what $mode
    }
}
# The inline-spec gate Fire and the menu rows share — what a spec
# with no registry entry cannot carry, refused where it is written:
# the surface words dress a declared deed, and an emacs deed here has
# no name of its own to lend its frame.
proc fire-spec-gate {who raw} {
    foreach k {key icon badge style} {
        if {[dict exists $raw $k]} {
            error "$who: an inline deed cannot carry $k —\
 that word is for a declared action"
        }
    }
    spec-check $who action $raw
    if {[action-type $raw] eq "emacs" && ![dict exists $raw emacs frame]} {
        error "$who: an inline emacs deed needs a frame name —\
 it has no name of its own to lend (frame {} said on purpose is the\
 frameless pure eval)"
    }
}
proc fire-spec {raw mode} {
    fire-spec-gate Fire $raw
    if {[dict exists $raw needs]} {
        foreach c [dict get $raw needs] {
            array unset ::auto_execs $c
            if {[auto_execok $c] eq ""} {
                puts "WM: Fire: needs $c — not on this machine"
                policy-key-echo problem "«$c» is not on this machine"
                return
            }
        }
    }
    if {[action-type $raw] eq "terminal"
            && [lindex [terminal-resolve] 0] eq ""} {
        puts "WM: Fire: no terminal emulator on this machine"
        policy-key-echo problem "no terminal emulator on this machine"
        return
    }
    # the same desugar action-derive does, and it was MISSED at first:
    # the terminal leg then spawned its beast bare, the run words
    # quietly lost — found by the dir work, kept by the regression
    if {[dict exists $raw run]} {
        dict set raw launch [list Run {*}[dict get $raw run]]
    }
    set spec [spec-derive Fire $raw]
    if {$mode eq "auto"} {
        set mode [expr {[dict exists $spec many]
                        ? [dict get $spec many] : "mru"}]
    }
    if {$mode eq "run"} {
        if {![dict exists $spec launch]} {
            puts "WM: Fire: nothing to run"
            return
        }
        fire-spec-launch $spec
        return
    }
    set wins [panel-matches Fire $spec]
    if {$mode eq "choose" && [llength $wins] > 1} {
        fire-spec-choose $spec $wins
        return
    }
    set hit [lindex $wins 0]
    if {$hit ne ""} {
        fire-spec-reach $spec $hit
    } elseif {[dict exists $spec launch]} {
        fire-spec-launch $spec
    } else {
        puts "WM: Fire: nothing matched, nothing to launch"
    }
}
# The three limbs mirror action-launch/-reach/-choose minus what only
# a registered deed has: no button to flash, no panel to anchor the
# list to, no last-started slot to fill (pinning an inline deed would
# pin a name nobody declared), and no registry to re-read after the
# wait — the spec is in hand and cannot be swept out from under it.
proc fire-spec-launch {spec} {
    puts "WM: Fire: launch"
    set script [dict get $spec launch]
    if {[dict exists $spec env] || [dict exists $spec env-unset]} {
        set script [list with-env \
            [expr {[dict exists $spec env] ? [dict get $spec env] : {}}] \
            $script \
            [expr {[dict exists $spec env-unset]
                   ? [dict get $spec env-unset] : {}}]]
    }
    if {[dict exists $spec dir]} {
        set script [list run-at [dict get $spec dir] $script]
    }
    set via ""
    if {[dict exists $spec runvia]} { set via [dict get $spec runvia] }
    run-script Fire [list run-via $via $script]
}
proc fire-spec-reach {spec w} {
    puts "WM: Fire: found 0x[format %x $w]"
    if {[dict exists $spec activate]} {
        run-script Fire [list {*}[dict get $spec activate] $w]
        return
    }
    panel-focus-hit $w
}
proc fire-spec-choose {spec wins} {
    if {[info coroutine] eq ""} {
        run-script Fire [list fire-spec-choose $spec $wins]
        return
    }
    puts "WM: Fire: choose among [llength $wins] matches"
    set more ""
    if {[dict exists $spec launch]} { set more "Run another" }
    set ans [winlist-choose $wins center $more]
    if {$ans eq ""} return
    if {$ans eq "more"} {
        fire-spec-launch $spec
        return
    }
    if {![info exists ::frameof($ans)]} {
        puts "WM: Fire: the picked window is gone"
        return
    }
    fire-spec-reach $spec $ans
}

# ---- Window-Shot: the window, as the eye sees it ------------------
# `Window-Shot ?W? ?DIR?` — raise the window (group and desk, exactly
# as reaching it would), let it repaint what the raise uncovered, read
# its rectangle off the SCREEN — frame, titlebar and all — and write
# a PNG into DIR (unsaid: $HOME). Answers the file's path, or empty
# with a line saying why not.
#
# Off the screen and not off the window on purpose: an X11 window
# stores no pixels, so a shot is of what the eye sees and only that —
# which is why the raise and the settle are part of the word, not
# advice to the caller. The pixels come from the shim (one XGetImage,
# PNG-ready scanlines) and the PNG from rgba-png, the pure-Tcl
# assembler the client icons already ride — no ImageMagick, nothing
# external, the kit stays whole.
#
# It WAITS (the settle), so it wants the coroutine every script the
# desk runs already has — a binding, a menu row, a titlebar button.
proc Window-Shot {{w 0} {dir ""}} {
    if {[info coroutine] eq ""} {
        error "Window-Shot waits for the redraw — call it from a\
 script the desk runs (a binding, a menu row), not bare"
    }
    if {$w == 0} { set w $::focused }
    if {$w == 0 || ![info exists ::frameof($w)]} {
        puts "WM: Window-Shot: no window"
        return ""
    }
    if {$dir eq ""} { set dir $::env(HOME) }
    desk-follow $w
    raise-group $w
    x-sync 0
    fut::take [fut::after 200]
    if {![info exists ::frameof($w)]} {
        puts "WM: Window-Shot: the window went away while it settled"
        return ""
    }
    set t $::frameof($w)
    set X [winfo rootx $t]
    set Y [winfo rooty $t]
    set W [winfo width $t]
    set H [winfo height $t]
    set raw [x-shot $::root $X $Y $W $H]
    if {$raw eq ""} {
        puts "WM: Window-Shot: the server would not say —\
 is the window entirely on the screen?"
        return ""
    }
    file mkdir $dir
    set who [lindex [client-class $w] 0]
    if {$who eq ""} { set who window }
    set path [file join $dir [format %s-%s-%d.png \
        [clock format [clock seconds] -format %Y%m%d-%H%M%S] \
        [string map {/ _ { } _} $who] [incr ::shot_seq]]]
    set f [open $path wb]
    puts -nonewline $f [rgba-png $W $H $raw]
    close $f
    puts "WM: Window-Shot 0x[format %x $w] -> $path (${W}x${H})"
    return $path
}

# ---- Ask: a line of text from the person, dressed as the desk ----
# `Ask PROMPT ?-initial …? ?-place …?` — an undecorated one-line box:
# the prompt, then a field dressed exactly as the configurator's
# editors (ui-field, text-as-entry), no buttons — Enter answers,
# Escape answers the empty answer, and so does dismissal of any kind
# (the popup convention). It stands at the place-grammar point over
# the workarea (unsaid: center), sized to itself.
#
# The TYPING is the ui host's: this process takes no typed text by
# design (no input method, ever — the XIM post-mortem), so the word
# sends the question over the send bridge and parks on a future the
# host's answer fulfills. The host is spawned when it is not up, the
# applet door's own way. A reload yanks a standing ask exactly as it
# yanks a menu: the waiter dies with FUT CANCELLED under its own
# name, and the box is told to go.
#
# The material is deliberately the desk's own — the box for whatever
# command line this grows into later (the owner, 2026-08-05).
array set ask_fut {}   ;# id -> the future its asker parks on
keep ask_seq 0
keep ask_prev_gadget 0  ;# the last confirmed focus sat on a gadget
keep focus_by_policy 0  ;# the next confirmed focus is the POLICY's move

# The box is a HOST GADGET, told apart by class and dressed by this
# rule — the code's own word, snapshotted like any default: no frame
# (the desk must not frame its own question), and a layer above the
# fullscreen top, because a question must stay visible whatever
# raises meanwhile — a fresh xterm mapping over the box was the
# owner's case (2026-08-05). Below the WM's own windows and menus,
# which answer to nobody. Guarded for the Reread: a rule appended
# twice is the same rule said twice.
unless-already {[info exists ::gadget_rule_said]} {
    set ::gadget_rule_said 1
    wm-style {filter -class {* Tk9wmGadget}} {decor none layer 10}
}

# ...and LEAVING the box BY HAND cancels the ask: the person
# alt-tabbing away from a question is the person doing something
# else, which is an answer — the empty one (the dismissal rule).
# Three fences around that sentence, each one a measured case:
#
#  - CONFIRMED focus only (policy-paint-focus): the WM's own grabs —
#    a menu glanced at over the box — move nothing and cancel
#    nothing;
#  - the POLICY's own focus moves do not count as leaving: a refocus
#    after somebody else's window died is not the person going
#    anywhere (focus_by_policy, set at the two places the policy aims
#    focus — a newcomer's manage does not even take the focus while a
#    question holds it: it queues behind the box, see policy-managed);
#  - only a departure FROM the box counts: switching between other
#    windows while the box stands unfocused says nothing about it.
#
# The cost, accepted with the owner (2026-08-05): deliberately going
# elsewhere abandons the question — and the top layer is what makes
# that rare, the box floating above whatever one peeks at.
proc ask-focus-note {w} {
    set policy $::focus_by_policy
    set ::focus_by_policy 0
    set was $::ask_prev_gadget
    set now [expr {[lindex [client-class $w] 1] eq "Tk9wmGadget"}]
    set ::ask_prev_gadget $now
    if {![array size ::ask_fut]} return
    if {$now || $policy || !$was} return
    ask-yank "the focus left the ask"
}
proc Ask {prompt args} {
    if {[info coroutine] eq ""} {
        error "Ask waits for an answer — call it from a script the\
 desk runs (a binding, a menu row), not bare"
    }
    set initial ""
    set place center
    set width ""
    set over 0
    foreach {k v} $args {
        switch -- $k {
            -initial     { set initial $v }
            -place       { set place $v }
            -width       { set width $v }
            -over-window { set over $v }
            default  { error "Ask: unknown option «$k»\
 (-initial -place -width -over-window)" }
        }
    }
    # width is characters (the field's own unit) or a percent of the
    # workarea's width (the place grammar's spirit); unsaid, the box
    # sizes itself to its layout
    if {$width ne "" && ![regexp {^[0-9]+%?$} $width]} {
        error "Ask: -width is characters (48) or a percent of the\
 workarea (50%), not «$width»"
    }
    set anchor [anchor-of $place]
    set warect [workarea]
    # -over-window: the question is ABOUT a window, so the box stands
    # on it — the rect handed to the host is the frame below the
    # titlebar, anchored start/start, and an unsaid width becomes 100%
    # so the box spans the frame (a rename box reading as part of the
    # window it renames). The rect is pressed into the frame's own
    # monitor first: a window half off the screen still deserves a
    # reachable box, and for the bottom edge — the box's height being
    # the host's to know — two title strips stand in for it.
    if {$over != 0} {
        set fr [frame-rect $over]
        if {[llength $fr]} {
            lassign $fr fx fy fw fh
            set ct [lindex [chrome-of $over] 1]
            lassign [workarea-at $fr] wax way waw wah
            set bw [expr {min($fw, $waw)}]
            set bx [expr {max($wax, min($fx, $wax + $waw - $bw))}]
            set est [expr {2 * [look [look-of $over] titleh]}]
            set by [expr {max($way, min($fy + $ct, $way + $wah - $est))}]
            set warect [list $bx $by $bw [expr {max($fh - $ct, 1)}]]
            set anchor {start start}
            if {$width eq ""} { set width 100% }
        } else {
            puts "WM: Ask: -over-window 0x[format %x $over] wears no\
 frame — the box takes the workarea"
        }
    }
    if {![ask-host-ready]} {
        puts "WM: Ask: the ui host would not come up"
        return ""
    }
    # one box, one question: a newer ask DISPLACES a standing one —
    # its waiter is cancelled under its own name rather than left
    # parked forever behind a box that is no longer on the screen
    # (the owner's rule, 2026-08-05)
    foreach old [array names ::ask_fut] {
        puts "WM: ask $old: displaced by a newer ask — the wait is cancelled"
        set f $::ask_fut($old)
        unset ::ask_fut($old)
        fut::cancel $f "displaced by a newer ask"
    }
    set id [incr ::ask_seq]
    set ::ask_fut($id) [fut::new]
    send -async -- tk9wm-ui [list ui-ask [tk appname] $id \
        $prompt $initial $anchor $warect $width]
    puts "WM: Ask $id «$prompt»"
    return [fut::take $::ask_fut($id)]
}
# The ANSWER and the CANCEL are different facts (the owner's
# expectation, 2026-08-05): Enter delivers the text — the empty
# string included, an answer like any other — while Escape cancels
# the WAIT itself: the asking script stops at that line, quietly (the
# calm branch in run-script), exactly as a yank stops it. Collapsing
# the two into one empty string would make «answered nothing» and
# «did not answer» the same word, and a script acting on it could not
# tell a cleared field from a person who walked away.
proc ask-answer {id text} {
    if {![info exists ::ask_fut($id)]} {
        puts "WM: ask $id: nobody waits — dropped"
        return
    }
    set f $::ask_fut($id)
    unset ::ask_fut($id)
    puts "WM: ask $id: answered"
    fut::fulfill $f $text
}
proc ask-cancel {id} {
    if {![info exists ::ask_fut($id)]} {
        puts "WM: ask $id: nobody waits — dropped"
        return
    }
    set f $::ask_fut($id)
    unset ::ask_fut($id)
    puts "WM: ask $id: cancelled by the person"
    fut::cancel $f "the person cancelled the ask"
}
# The host, up — found on the registry or spawned the applet door's
# way and awaited (a fresh host loads a Tk and a theme before it can
# answer; the wait is a coroutine's, the desk does not stop).
proc ask-host-ready {} {
    if {"tk9wm-ui" in [winfo interps]} { return 1 }
    set head [ui-exec-head]
    if {![llength $head]} {
        puts "WM: Ask: no way to exec the ui host —\
 this image should set ::tk9wm_uiexec"
        return 0
    }
    set script [file join $::tk9wm_library ui host.tcl]
    puts "WM: Ask: spawning the ui host"
    policy-key-echo flash "ask: starting…"
    exec {*}$head $script [tk appname] &
    for {set i 0} {$i < 40} {incr i} {
        fut::take [fut::after 100]
        if {"tk9wm-ui" in [winfo interps]} { return 1 }
    }
    return 0
}

# ---- Rename: the person's word over the desk's --------------------
# The window command behind the winops `e` row: an ask under the
# window's own titlebar, primed with the TEMPLATE the desk currently
# speaks (visible-title-template) — the standing rename comes back
# exactly as typed, «[dev]: %t» and not the morning's expansion of
# it, and a style rule's template is met the same editable way (the
# owner, 2026-08-17). The answer is likewise kept as a template, not
# its expansion: type «ssh: %t» and the prefix keeps following the
# client's renames, type «%t» over a style-said title and the
# client's own words show through — the same grammar the style key
# speaks, one language in both mouths. The empty answer takes the
# hand rename OFF, back to whatever the style rules say (kitty's
# reading of an emptied field); Escape is not an answer at all — the
# wait is cancelled and this proc never resumes past the Ask line,
# so a walked-away-from box changes nothing.
#
# Interactive only: an Apply-To-Matching sweep reaching this verb
# would park one box per window, each displacing the last — a refusal
# with a line is the honest answer.
proc rename-command {w} {
    if {![interactive-p]} {
        puts "WM: Rename 0x[format %x $w]: an interactive command —\
 a sweep's boxes would only displace one another"
        return
    }
    set text [Ask Rename -initial [visible-title-template $w] -over-window $w]
    # the client can die while its question stands; the frame gone,
    # there is nothing left to name (unmanage swept ::renameof too)
    if {![info exists ::frameof($w)]} return
    if {$text eq ""} {
        unset -nocomplain ::renameof($w)
    } else {
        set ::renameof($w) $text
    }
    retitle $w
}

# PIN THE LAST THING I STARTED (the owner's own wording). The other
# half of populating a panel, and the half a keyboard can do: run
# something, decide you want it to stay, say so — without naming it,
# because the desk already knows what it just ran.
#
# It writes an ordinary `panel-button` into the custom layer, which is
# the same word the configurator writes and the same one a config
# would carry, so what it produces can be read, moved and taken back
# like anything else there. Something started by OTHER means is not
# ours to know about and is pinned with the mouse instead.
proc panel-pin-last {} {
    if {$::last_started eq ""} {
        policy-key-echo problem "nothing started from here yet — pin it\
 with the mouse instead"
        return
    }
    set name $::last_started
    # Still checked here, though the record now skips what was pinned
    # when it ran: a deed can be pinned BETWEEN starting it and asking
    # for it, and the second press of this chord is exactly that case.
    set on [action-panels $name]
    if {[llength $on]} {
        policy-key-echo problem "«$name» is already on the «[lindex $on 0]»\
 panel"
        return
    }
    # ...onto the panel that holds the furniture, which is the tray's
    # for want of a better answer while the ephemeral area has not
    # named one of its own.
    set pn [expr {[tray-panel] in [panel-names] ? [tray-panel]
                  : [lindex [concat [panel-names] default] 0]}]
    set was $::panel_target
    set ::panel_target $pn
    try {
        custom-write [list panel-button $name]
    } finally {
        set ::panel_target $was
    }
    puts "WM: pinned «$name» to the «$pn» panel"
    policy-key-echo keys "«$name» pinned to the panel"
}
proc action-flash {name state} {
    dict for {pname p} $::panels {
        panel-flash $pname $name $state
    }
}

# THE NAME IS THE ACTION'S NAME (the actions-first turn): a button
# holds no settings of its own any more — no match, no launch, no
# chord; all of that lives on the action it references, declared
# once and worn by any panel. What the reference CAN say is how it
# dresses here: `label` (display only — the key stays the name) and
# `icon` (over the action's own face). Saying panel-button Emacs
# twice does not make two buttons: the second call REFINES the
# first — overrides merge, an empty value un-says one ("the plain
# label after all") — and the button keeps the position its FIRST
# declaration gave it. Referencing an action nobody has declared
# yet, or one still waiting on its software, is LEGITIMATE: the
# strip skips it at resolve (panel-resolve says so in the log), and
# the button surfaces by itself on the reload that brings the
# action alive.
proc panel-button {name {overrides {}}} {
    if {[llength $overrides] % 2} {
        error "panel-button $name: overrides want key value pairs"
    }
    foreach k [dict keys $overrides] {
        if {$k ni {label icon}} {
            error "panel-button $name: unknown override \"$k\" — a\
 button is a reference to an action; label and icon are all it\
 overrides (the deed itself is `action $name`'s to describe)"
        }
    }
    set pn $::panel_target
    panel-ensure $pn
    set raw $overrides
    if {[dict exists $::panels $pn refs $name]} {
        set raw [dict merge [dict get $::panels $pn refs $name] $overrides]
    }
    foreach k [dict keys $raw] {
        if {[dict get $raw $k] eq ""
                && [node-empty-means [list panel @ $k]] eq "unsay"} {
            dict unset raw $k
        }
    }
    dict set ::panels $pn refs $name $raw
    panel-rebuild-soon
}
# What a strip SHOWS is resolved here, reference by reference,
# against the action registry — never at declaration: a config may
# reference an action it declares three lines later. An undeclared
# name and a waiting one are skipped; the rest come out as {name
# label spec}, the spec the action's own with the reference's icon
# over it. Two callers, two moods: the BUILD resolves once, stores
# the list for the fire/index machinery and SAYS (`say`) which
# references stand by; the geometry (panel-measure) resolves live
# and silently — the strip's thickness is asked about (the workarea,
# the bands) between declaration and build, and an answer read off a
# stale stored list made the workarea hop an extra time on every
# startup (measured — the reflow suite counts the hops).
proc panel-resolve {name {say 0}} {
    set shown {}
    dict for {aname over} [panel-cfg $name refs] {
        if {![dict exists $::action_spec $aname]} {
            if {$say} {
                puts "WM: panel $name: no action named $aname —\
 the button stands by"
            }
            continue
        }
        set spec [dict get $::action_spec $aname]
        if {[dict get $spec state] ne "active"} {
            if {$say} {
                puts "WM: panel $name: action $aname waits on\
 [dict get $spec needs] — the button stands by"
            }
            continue
        }
        set label $aname
        if {[dict exists $over label]} { set label [dict get $over label] }
        if {[dict exists $over icon]} {
            dict set spec icon [dict get $over icon]
        }
        lappend shown [list $aname $label $spec]
    }
    return $shown
}
# What the machinery RUNS ON is the derived form of an action's raw
# words. `terminal` is a PROVIDER of the two halves, not a third
# thing: it fills in match and launch (an explicit one beside it
# wins) and the machinery never hears of it. The derived match is
# STATIC — filter with a single pattern, so EITHER half of
# WM_CLASS answers: the instance on every beast that names, the
# class on the gnome-terminal factory. Deliberately not narrowed
# by the resolved beast, twice over: a verdict computed while the
# config is still speaking is the styleof lesson (see
# policy-apply), and the window found should be "my mutt", not
# "my mutt in the terminal I would launch today" — a desk that
# switched set-terminal keeps finding yesterday's window instead
# of launching a second mutt beside it. A beast that cannot name —
# every measured one turned out able to, but a registry entry with
# no name word stays possible — simply never matches, which IS the
# launch-only degradation, and spawn-terminal says so when it
# drops the name.
