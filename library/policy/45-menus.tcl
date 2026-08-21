# ---- window commands ------------------------------------------------
#
# An imperative over ONE window, named with a Capital. The rest of the
# config vocabulary is lowercase and DECLARATIVE — set-* knobs,
# wm-style, panel-button, filter, always: they describe a desk and say
# nothing about when. A Capital says the opposite, that this one acts
# the moment it is called; the case is the whole distinction, and it
# costs nothing to see.
#
# It also buys the names outright. Tcl and Tk already own `raise`,
# `lower`, `close` and `destroy`, so a lowercase vocabulary would have
# had to spell four of its ten verbs differently — `close-window` next
# to `minimize` — and a config author would have to remember which four.
# Raise and Close are ours; raise and close are still Tk's.
#
# Each takes the window as an OPTIONAL argument, and without one asks
# the context. That is what makes one definition serve two callers:
#
#   wm-bind {<Ctrl><Shift>z} Minimize          the active window
#   Apply-To-Matching always Minimize          each in turn
#
# and the winops menu, which acts on the window it was opened over. The
# context is a bound subject where there is one, and the focused client
# everywhere else.
keep subject_window 0
proc current-window {} {
    expr {$::subject_window != 0 ? $::subject_window : $::focused}
}
# Run a script with the subject bound. Restores on the way out however
# the script leaves — a window command can throw, and a subject left
# standing would silently retarget every later bare command.
proc with-window {w script} {
    set save $::subject_window
    set ::subject_window $w
    try {
        uplevel 1 $script
    } finally {
        set ::subject_window $save
    }
}

# Who is asking — the user, or a program? This is Emacs's
# called-interactively-p, kept for the same reason it exists there: one
# name should mean the obvious thing in both mouths, and the obvious
# thing differs.
#
# A USER toggles. Open the window menu over a maximized window and pick
# Maximize and you mean "the other way"; there is no other reading,
# because you are looking at the window while you say it. The same goes
# for a key you press yourself.
#
# A PROGRAM does not. `Apply-To-Matching always Maximize` means make
# this desk maximized, and a toggle would un-maximize precisely the
# windows that were already right — a sweep whose result depends on the
# state it found is not a sweep, it is a coin toss per window.
#
# So: interactive unless a program says otherwise, and the program that
# says so is the one driving other commands. Nothing needs to mark the
# menu or a key binding as "the user" — that is the default, and the
# default is the common case.
keep programmatic 0
proc programmatically {script} {
    set save $::programmatic
    set ::programmatic 1
    try {
        uplevel 1 $script
    } finally {
        set ::programmatic $save
    }
}
proc interactive-p {} { expr {!$::programmatic} }

# The commands that read it. Everything else in the table means one
# thing in either mouth — there is no toggling sense of Close, and
# Minimize has none either (a window you can pick the menu over is on
# the screen by definition). The axis pair are the same verb held to
# one axis: Maximize-V makes a window tall, Maximize-H makes it wide,
# and in a user's mouth each toggles its own axis alone.
proc maximize-command {w} {
    if {[interactive-p]} { maximize-toggle $w } else { maximize-client $w }
}
proc maximize-h-command {w} {
    if {[interactive-p]} { maximize-toggle $w h } else { maximize-client $w h }
}
proc maximize-v-command {w} {
    if {[interactive-p]} { maximize-toggle $w v } else { maximize-client $w v }
}
proc fullscreen-command {w} {
    if {[interactive-p]} { fullscreen-toggle $w } else { fullscreen-client $w }
}

# name -> the proc that does the work; every one of them takes a window.
# The Un- pair is unconditional in both mouths: a user who wants the way
# out and no guessing has it, and so does a sweep.
set window_commands {
    Maximize     maximize-command
    Maximize-H   maximize-h-command
    Maximize-V   maximize-v-command
    Unmaximize   unmaximize-client
    Fullscreen   fullscreen-command
    Unfullscreen unfullscreen-client
    Close        close-client
    Destroy      kill-client
    Raise        raise-group
    Lower        lower-group
    Above        layer-above-command
    Below        layer-below-command
    Unlayer      layer-clear-command
    Sticky       desk-sticky-toggle
    Bury         bury-group
    Move         move-keyboard
    Resize       resize-keyboard
    As-Usual     as-usual-command
    Minimize     policy-minimize-request
    Fade         fade-command
    Unfade       unfade-command
    Rename       rename-command
}
proc window-do {name {w 0}} {
    if {$w == 0} { set w [current-window] }
    if {$w == 0 || ![info exists ::frameof($w)]} {
        puts "WM: $name: no window"
        return 0
    }
    with-window $w [list [dict get $::window_commands $name] $w]
    invariants-soon   ;# a command is the other thing that can pull a rug
    return 1
}
# An alias apiece, so the name IS the command. The shadow check is not
# ceremony: a table entry that collided with a Tk command would replace
# it for the whole interpreter — `destroy` is how every decoration in
# this layer is torn down — and the damage would show up somewhere else
# entirely. Failing here, at load, is the cheap end of that.
foreach {_name _impl} $window_commands {
    # An alias of ours from a previous load is not a collision — it is
    # this very line, run before. Anything else that answers to the
    # name IS one, and failing here at load is the cheap end of that.
    if {[llength [info commands ::$_name]]
            && [interp alias {} ::$_name] eq ""} {
        error "window command $_name would shadow the existing command ::$_name"
    }
    interp alias {} ::$_name {} window-do $_name
}

# ---- what a verb READS: the state behind a marked menu row ----
# The marker is a fact about the VERB, not about a row: a row firing
# Maximize-V is marked because of what Maximize-V means, wherever the
# row lives — the same rule that keeps the winops menu a SELECTION
# from the table above rather than a copy that drifts. Keyed by the
# command prefix exactly as a row spells it; absence means a stateless
# verb (Close, Move) — no marker, not an error.
#
# Each predicate MIRRORS ITS VERB'S TOGGLE: marked means firing takes
# the state off. Maximize marks only when every axis is held, which is
# the toggle's own reading (any axis free means maximize) — a tall
# window marks Maximize-V alone, and the axis rows are where the
# partial truth shows.
set window_states {
    Maximize    {maximized-p {h v}}
    Maximize-H  {maximized-p h}
    Maximize-V  {maximized-p v}
    Fullscreen  fullscreen-p
    Minimize    iconic-p
    Above       {layer-at-p above}
    Below       {layer-at-p below}
    Sticky      desk-sticky-p
}
proc maximized-p {axes w} {
    set have [expr {[info exists ::maxaxes($w)] ? $::maxaxes($w) : {}}]
    foreach a [max-axes $axes] {
        if {$a ni $have} { return 0 }
    }
    return 1
}
proc fullscreen-p {w} { info exists ::fullscreen($w) }
proc iconic-p {w} { info exists ::iconic($w) }
proc layer-at-p {name w} {
    expr {[layer-declared $w] == [layer-number $name]}
}
# desk-sticky-p is the substrate's own; the sticky row reads it as is.

# The config's door for its own verbs: declare what a command reads,
# and every surface showing a row that fires it can mark the row —
# winops today, whatever grows rows tomorrow. The key is the exact
# command prefix as the row spells it: a verb with an argument baked
# in ({my-thing --tall}) is its own verb, exactly as the stock axis
# pair is two names over one implementation.
proc command-state {name pred} {
    if {![llength $pred]} {
        error "command-state $name: a state that reads nothing is a typo"
    }
    dict set ::window_states $name $pred
}
# Marked (1), unmarked (0), or stateless ("") — the one question a
# surface asks about a row. A predicate that throws is LOGGED and
# reads unmarked: a bad line in a config must not cost the menu.
proc command-marked-p {cmd w} {
    if {![dict exists $::window_states $cmd]} { return "" }
    if {[catch {uplevel #0 [list {*}[dict get $::window_states $cmd] $w]} m]} {
        puts "WM: command-state «$cmd»: predicate error: $m"
        return 0
    }
    expr {$m ? 1 : 0}
}

# Commands about the DESK rather than a window — same Capital, nothing
# to resolve. The lowercase originals stay: they are the implementations
# (as close-client is the implementation behind Close), the substrate
# and this layer call them by those names, and a config written before
# the vocabulary existed keeps working.
# Quit asks first — but only when a PERSON asked. The same rule as
# Maximize: a program that says Quit means it, and a modal question put
# to a script is a hang rather than a safeguard.
# The question warns rather than reassures, and deliberately does not
# try to work out which it should do.
#
# What the window manager can promise is only its own half: it RELEASES
# every client instead of destroying it, so nothing dies by our hand.
# What happens next is the session's business, and in nearly every real
# setup the session ends with us — .Xsession finishes with `exec wm`,
# or with `wm & … wait`, and either way our exit is the end of the
# script and every window goes with it. Only a window manager started
# by hand inside an existing session leaves its clients standing.
#
# It said "Windows stay open" for one commit, which was true of the
# case almost nobody is in. Detecting the difference was the obvious
# next thought and is a trap (owner, 2026-07-29): pid == session id
# catches `exec wm` and misses `wm & wait` completely — where we are
# NOT the leader and the session ends anyway — so the heuristic would
# print the reassuring line in precisely the case that must not be
# reassured. A guess that fails toward "it's fine" is worse than no
# guess, so: no guess, and the pessimistic wording, which is also the
# true one nearly always.
proc quit-command {} {
    if {![interactive-p]} { quit-wm; return }
    confirm "tk9wm" "Quit? The X session normally ends with the\
        window manager." Quit quit-wm
}
set desk_commands {
    Restart restart-wm
    Reload  reload-config
    Reread  reread-layers
    Quit    quit-command
}
foreach {_name _impl} $desk_commands {
    if {[llength [info commands ::$_name]]
            && [interp alias {} ::$_name] eq ""} {
        error "desk command $_name would shadow the existing command ::$_name"
    }
    # reload-config lives in main.tcl, which is sourced after this file;
    # an alias resolves at call time, so declaring it here is fine.
    interp alias {} ::$_name {} $_impl
}
unset _name _impl

# Run a window command over every window a predicate accepts — the
# sweep behind "minimize everything", and behind anything else worth
# doing to a whole desk at once:
#
#   wm-bind {<Super>d} {Apply-To-Matching always Minimize}
#
# The predicate is the one wm-style and a panel button's match already
# take (`always`, `{filter -class ...}`, a proc of your own), so there
# is one matching language here, not two.
#
# The target list is a SNAPSHOT taken before anything runs. These
# commands unmap, close and unmanage windows — iterating the live set
# would be iterating a list the body is editing — and a window that
# dies mid-sweep is skipped rather than mourned. Order is
# most-recently-focused first, the window list's order: a hash order
# would land differently on every run, which is no way to write a
# regression, and MRU means the focus walks down the history as each
# window leaves rather than jumping about.
#
# Nothing here is allowed to abort the sweep. A predicate that throws
# on one window, or a command that does, costs that window and no
# other: "as many as possible" is the contract, and a desk half swept
# because window three had a bad style rule is not it.
proc Apply-To-Matching {pred command} {
    programmatically { Apply-To-Matching-1 $pred $command }
}
proc Apply-To-Matching-1 {pred command} {
    set targets {}
    foreach w $::focus_hist {
        if {[info exists ::managed($w)]} { lappend targets $w }
    }
    foreach w [array names ::managed] {
        if {$w ni $targets} { lappend targets $w }
    }
    set matched 0
    foreach w $targets {
        if {![info exists ::managed($w)]} continue   ;# gone since the snapshot
        if {[catch {uplevel #0 [list {*}$pred $w]} verdict]} {
            puts "WM: Apply-To-Matching: predicate error on 0x[format %x $w]: $verdict"
            continue
        }
        if {!$verdict} continue
        incr matched
        if {[catch {$command $w} err]} {
            puts "WM: Apply-To-Matching: $command failed on\
                  0x[format %x $w]: $err"
        }
    }
    # Counted as MATCHED and tried, not as succeeded — a window command
    # does not report back, and it should not have to: whether this
    # particular window took the operation is between it and the
    # command (a style that refuses minimization says so in its own
    # line). Claiming a success count here would be inventing one.
    puts "WM: Apply-To-Matching $command: $matched of [llength $targets] matched"
    return $matched
}

# ---- the window ops menu ----
# Actions on ONE window — the fvwm-style dropdown: from the titlebar's
# left button, or on the focused window by key. Anchored at the
# window's top-left corner, right below the titlebar. Every action
# carries a hotkey letter (shown right-aligned, fvwm menus underline
# theirs — a column reads better in a treectrl); a bare letter press
# fires it, and the navigation letters yield to hotkeys while
# Ctrl+P/Ctrl+N always navigate (popup-nav).
#
# fullscreen is on the list and not only on the clients' own keys for a
# plain reason: a fullscreen window has no titlebar and no border, so
# if the client that asked for the state will not take it back — or
# never had a key for it — this menu is the only way out. Alt+Space
# reaches it through the WM's own grab, over the fullscreen window.
# The menu is a SELECTION from the window commands plus a hotkey letter
# apiece — it does not carry its own copy of what each one does. It used
# to, and two lists meaning the same thing is how a menu entry and a key
# binding drift into doing different things.
set winops_actions {
    Maximize   x
    Maximize-V v
    Maximize-H h
    Fullscreen f
    Close      c
    Destroy    d
    Raise      r
    Lower      l
    Bury       b
    Move       m
    Resize     s
    As-Usual   u
    Minimize   i
    Above      a
    Sticky     y
    Rename     e
}
# The rows this window's menu shows: the stock commands, then the
# config's own items (winops-item below) — each gated by its needs
# (the machine) and its when (this window), judged at open. `marked`
# is the row's state marker, read off the command it fires
# (command-marked-p) at the same moment — open is when the menu
# looks, for the marker as for the when.
proc winops-rows {w} {
    set rows {}
    foreach {label key} $::winops_actions {
        # Resize on a fixed-size window is a refusal at every door
        # (resize-keyboard); a row that could only say no is not shown.
        if {$label eq "Resize" && [client-fixed-size-p $w]} continue
        # ...and As-Usual re-places by the style's place rule, so a
        # window whose style has none loses the row the same way.
        if {$label eq "As-Usual" && ![style-place-p $w]} continue
        lappend rows [dict create label $label key $key command $label \
            marked [command-marked-p $label $w]]
    }
    dict for {name item} $::winops_items {
        if {[dict exists $item needs]
                && ![needs-met [dict get $item needs]]} {
            puts "WM: winops: «$name» waits on [dict get $item needs]\
 — not shown"
            continue
        }
        if {[dict exists $item when]} {
            if {[catch {uplevel #0 \
                    [list {*}[dict get $item when] $w]} m]} {
                puts "WM: winops «$name»: when predicate error: $m"
                continue
            }
            if {!$m} continue
        }
        lappend rows [dict create label [dict get $item label] \
            key [expr {[dict exists $item key]
                       ? [dict get $item key] : ""}] \
            command [dict get $item command] \
            marked [command-marked-p [dict get $item command] $w]]
    }
    return $rows
}
proc winops {{w 0}} {
    if {$w == 0} { set w $::focused }
    if {$w == 0 || ![info exists ::frameof($w)]} {
        popups-close
        puts "WM: winops: no window"
        return
    }
    set ::winops_win $w
    set ::winops_rows [winops-rows $w]
    set n [llength $::winops_rows]
    set ih [expr {[font metrics TitleFont -linespace] + 6}]
    set T [popup-shell .winops $ih winops-click]
    # The state marker: a bullet rather than a check because the
    # bullet is in every font a spartan X setup has — a marker that
    # renders as tofu marks nothing.
    set markw [expr {[font measure TitleFont "•"] + 8}]
    $T column create -width $markw -tags Cmark
    $T column create -squeeze yes -expand yes -tags C0
    $T column create -width [expr {$ih + 4}] -tags Ckey
    $T configure -treecolumn C0
    $T element create eKey text -fill [themed dim] -lines 1 \
        -font [popup-hover-font]
    $T element create eMark text -fill [themed ink] -lines 1 \
        -font [popup-hover-font]
    $T style create sAct
    $T style elements sAct {eSel eTxt}
    $T style layout sAct eSel -detach yes -iexpand xy
    $T style layout sAct eTxt -expand ns -padx 8
    $T style create sKey
    $T style elements sKey {eSel eKey}
    $T style layout sKey eSel -detach yes -iexpand xy
    $T style layout sKey eKey -expand wns -padx 6
    $T style create sMark
    $T style elements sMark {eSel eMark}
    $T style layout sMark eSel -detach yes -iexpand xy
    $T style layout sMark eMark -expand wens
    set maxw 0
    foreach row $::winops_rows {
        set label [dict get $row label]
        set maxw [expr {max($maxw, [font measure TitleFont $label])}]
        set item [$T item create]
        $T item style set $item Cmark sMark C0 sAct Ckey sKey
        $T item element configure $item Cmark eMark \
            -text [expr {[dict get $row marked] eq "1" ? "•" : ""}]
        $T item element configure $item C0 eTxt -text $label
        $T item element configure $item Ckey eKey -text [dict get $row key]
        $T item lastchild root $item
    }
    $T selection add 1
    set t $::frameof($w)
    lassign [frame-chrome $t] B top
    set X [expr {[winfo rootx $t] + $B}]
    set Y [expr {[winfo rooty $t] + $top}]
    # THE MENU GOES WHERE THE HAND IS. Called up by a key it has no
    # hand and stays at the window's own corner, which is where it
    # always was; called up by the mouse it follows the hand —
    # gesture-menu-at, the rule this menu measured out and the
    # config's own menus now share.
    set at [gesture-menu-at $w]
    if {[llength $at]} { lassign $at X Y }
    set W [expr {max($maxw + $ih + 40, 160) + $markw}]
    set H [popup-fit .winops $n $ih $X $Y]
    lassign [popup-show .winops $W $H $X $Y] X Y
    if {![grab-keys-to winops-key]} {
        puts "WM: winops: keyboard not grabbed — mouse only"
    }
    # Where it LANDED, clamping and all — the menu is an
    # override-redirect window of our own and nothing else on the
    # display reports its geometry.
    puts "WM: winops open 0x[format %x $w] ${W}x${H}+$X+$Y"
}
proc winops-key {kind name mods} {
    if {$kind eq "release"} return
    if {$mods == 0} {
        set i 0
        foreach row $::winops_rows {
            incr i
            if {[dict get $row key] ne "" && $name eq [dict get $row key]} {
                winops-fire $i
                return
            }
        }
    }
    set d [popup-nav $name $mods]
    if {$d != 0} {
        popup-move .winops.t [llength $::winops_rows] $d
        return
    }
    switch -- $name {
        Return - KP_Enter { winops-fire [lindex [.winops.t selection get] 0] }
        Escape            { popups-close }
    }
}
proc winops-fire {i} {
    if {$i eq "" || $i < 1} { popups-close; return }
    set w $::winops_win
    set row [lindex $::winops_rows [expr {$i - 1}]]
    popups-close
    if {![info exists ::frameof($w)]} return
    puts "WM: winops 0x[format %x $w] [dict get $row label]"
    # in a coroutine, as every fired script here: a stock command
    # returns at once and costs nothing, and a config's own item may
    # legitimately wait (Choose, a launch) — and its error becomes a
    # problem instead of a throw up the binding
    run-script "winops [dict get $row label]" \
        [list {*}[dict get $row command] $w]
}
proc winops-click {x y {s 0}} {
    set T .winops.t
    if {[catch {$T identify -array A $x $y}] || $A(where) ne "item"} return
    winops-fire $A(item)
}

# ---- the window menu grows rows of the config's own ----
# winops-item NAME {label … command … ?key …? ?needs …? ?when …?} —
# a row under the stock commands, shown per window: `command` is a
# prefix the window is appended to (the titlebar-bind convention, so
# a window command or the config's own proc both fit), `needs` gates
# on the machine, `when` on the window (a predicate as wm-style takes
# them). The name is the primary key and a second word refines; the
# label reads on the row (the name, unsaid); a key is one character
# and the stock letters are looked up first.
keep winops_items {}   ;# NAME -> the merged raw words
proc winops-item {name settings} {
    set raw $settings
    if {[dict exists $::winops_items $name]} {
        set raw [dict merge [dict get $::winops_items $name] $settings]
    }
    foreach k [dict keys $raw] {
        if {[dict get $raw $k] eq ""} { dict unset raw $k }
    }
    foreach k [dict keys $raw] {
        if {$k ni {label key command needs when}} {
            error "winops-item $name: unknown word «$k»\
 (label key command needs when)"
        }
    }
    if {![dict exists $raw command]} {
        error "winops-item $name: an item needs a command —\
 a row that does nothing is a typo"
    }
    if {[dict exists $raw key]
            && [string length [dict get $raw key]] != 1} {
        error "winops-item $name: a key is one character,\
 not «[dict get $raw key]»"
    }
    if {![dict exists $raw label]} { dict set raw label $name }
    dict set ::winops_items $name $raw
}
proc winops-item-remove {name} {
    dict unset ::winops_items $name
    puts "WM: winops item $name: removed"
}

# Where a GESTURE wants a menu: the hand's point — except that a hand
# on the window's own titlebar hangs the menu from the strip's bottom
# edge instead: it drops out of the bar the way a menubar's does, the
# title and its buttons stay readable above it, and the release of a
# press that meant to leave the menu STANDING lands clear of it (the
# owner, 2026-08-03). The x follows the pointer either way — the eye
# is there, and a drag still in progress has the shortest way into
# the first row. Empty when there is no gesture: a key has no hand.
# One code path, so winops and the config's menus cannot drift.
proc gesture-menu-at {w} {
    set at [gesture-point]
    if {![llength $at]} { return "" }
    lassign $at hx hy
    if {$w != 0 && [info exists ::frameof($w)]} {
        set t $::frameof($w)
        if {[winfo exists $t.title] && $hy >= [winfo rooty $t.title]
                && $hy < [winfo rooty $t.title] + [winfo height $t.title]} {
            lassign [frame-chrome $t] B top
            set hy [expr {[winfo rooty $t] + $top}]
        }
    }
    list $hx $hy
}

# ---- the config's own menus ----
# A menu is another SURFACE for actions, the way the panel is: the
# panel lays references out in a strip, a menu lays them out in a
# transient list under a chord. The word is declarative, and a row is
# a reference to an action — or a bare label+do pair, for the piece
# that is genuinely the config's own:
#
#     wm-menu ssh {
#         key   {<Super>t s}
#         items {
#             {action ssh_web key w}
#             ssh_db
#             {label "log here" do {Run xterm -e tail -f /var/log/syslog}}
#         }
#     }
#
# `items` is the static half; `body` is the dynamic one — a script
# ASKED FOR THE ROWS AT OPEN TIME (a list of recent projects is stale
# the moment it is written down), answering the same grammar. One of
# the two, never both: the run ⊕ launch rule, for the same reason —
# one slot, two spellings.
#
# A menu with NO explicit keys is numbered by position — the shared
# popup alphabet (popup-autokeys: 1-9, then A-Z minus the motion
# letters j/k/n/p). One explicit key anywhere turns the numbering
# off: the author took the naming into their own hands, and the rows
# they left bare stay bare rather than wearing gap numbers. A
# reference to a waiting action is not shown (the panel's rule), and
# one to a deed nobody declared is skipped with a log line: a menu is
# a view, and a view does not refuse to open over one bad row.
#
# What a pick MEANS follows the winlist's rule exactly: nobody
# waiting — the row fires (an action by name, a do-script in its own
# coroutine); a waiter parked on the popup (Choose below) — the row
# is the answer and the caller decides.
keep menus {}   ;# NAME -> the merged raw words (what the layers SAID)
keep menu_griped {}   ;# {menu action} -> the typo already went to problems

proc wm-menu {name settings} {
    set raw $settings
    if {[dict exists $::menus $name]} {
        set raw [dict merge [dict get $::menus $name] $settings]
    }
    foreach k [dict keys $raw] {
        if {[dict get $raw $k] eq ""
                && [node-empty-means [list @spec menu $k]] eq "unsay"} {
            dict unset raw $k
        }
    }
    spec-check "wm-menu $name" menu $raw
    if {[dict exists $raw items]} {
        foreach item [dict get $raw items] {
            menu-item-check "wm-menu $name" $item
        }
    }
    if {[dict exists $raw place]} { anchor-of [dict get $raw place] }
    # checked first, changed second: a word that is refused above must
    # leave the standing menu — chord and all — exactly as it was
    if {[dict exists $::menus $name key]} {
        catch {wm-unbind [dict get $::menus $name key]}
    }
    # a fresh word re-judges the gripes: the reference the problems
    # store named may well be what this declaration just fixed
    foreach k [dict keys $::menu_griped] {
        if {[lindex $k 0] eq $name} { dict unset ::menu_griped $k }
    }
    dict set ::menus $name $raw
    if {[dict exists $raw key]} {
        wm-bind [dict get $raw key] [list menu-open $name] $name
    }
}
proc wm-menu-remove {name} {
    if {[dict exists $::menus $name key]} {
        catch {wm-unbind [dict get $::menus $name key]}
    }
    dict unset ::menus $name
    puts "WM: menu $name: removed"
}
# One row's grammar, shared by the declaration (checked when said) and
# the body (checked when it answers): a bare word is an action's name,
# anything longer says what it is. `action` takes a NAME or an inline
# SPEC — one word or a dict, Fire's own rule (the owner's ask,
# 2026-08-05: a menu row should not need a registry entry for a deed
# said once) — and an inline one is read by Fire's gate where it is
# written, and needs a label, having no name to read as one.
proc menu-item-check {who item} {
    if {[llength $item] == 1} return   ;# a bare action name
    if {[llength $item] % 2} {
        error "$who: an item is a bare action name or key-value words,\
 not «$item»"
    }
    foreach k [dict keys $item] {
        if {$k ni {action label do key shift-action shift-do}} {
            error "$who: unknown item word «$k»\
 (action label do key shift-action shift-do)"
        }
    }
    if {[dict exists $item action] && [dict exists $item do]} {
        error "$who: an item is an action reference or a do-script, not both"
    }
    if {![dict exists $item action] && ![dict exists $item do]} {
        error "$who: an item names an action or carries a do-script"
    }
    if {[dict exists $item action]
            && [llength [dict get $item action]] > 1} {
        fire-spec-gate "$who: inline action" [dict get $item action]
        if {![dict exists $item label]} {
            error "$who: an inline action needs a label —\
 it has no name to read as one"
        }
    }
    if {[dict exists $item do] && ![dict exists $item label]} {
        error "$who: a do item needs a label"
    }
    # The shift half is the row's OTHER reading — same two shapes as
    # the plain one, at most one of them, and never on its own: a
    # modifier modifies something. It borrows the row's label, so an
    # inline shift-action needs none of its own.
    if {[dict exists $item shift-action] && [dict exists $item shift-do]} {
        error "$who: the shift half is an action reference or a\
 do-script, not both"
    }
    if {[dict exists $item shift-action]
            && [llength [dict get $item shift-action]] > 1} {
        fire-spec-gate "$who: inline shift-action" \
            [dict get $item shift-action]
    }
    if {[dict exists $item key]
            && [string length [dict get $item key]] != 1} {
        error "$who: an item key is one character,\
 not «[dict get $item key]»"
    }
}
# Open by name — what the menu's chord is bound to. The optional
# trailing argument is the window a titlebar or winops gesture appends;
# a menu is not about a window, so it is accepted and ignored, and the
# gesture's POINT is what such a caller contributes (gesture-point).
proc menu-open {name {w 0}} {
    if {![dict exists $::menus $name]} {
        puts "WM: menu $name: unknown — nothing to open"
        return
    }
    set raw [dict get $::menus $name]
    set items {}
    if {[dict exists $raw body]} {
        if {[catch {uplevel #0 [dict get $raw body]} items]} {
            problem-record "menu $name" $items
            return
        }
        # the body's rows are checked as the config's were — at the
        # moment they exist, which for a body is now
        foreach item $items {
            if {[catch {menu-item-check "menu $name" $item} err]} {
                problem-record "menu $name" $err
                return
            }
        }
    } elseif {[dict exists $raw items]} {
        set items [dict get $raw items]
    }
    set rows {}
    foreach item $items {
        if {[llength $item] == 1} { set item [list action [lindex $item 0]] }
        if {[dict exists $item action]
                && [llength [dict get $item action]] > 1} {
            # an INLINE spec, fired through Fire's own door; hidden
            # while its needs are unmet or a terminal deed has no
            # emulator — the same waiting judgement a declared action
            # gets, made on the spot
            set a [dict get $item action]
            if {[dict exists $a needs] && ![needs-met [dict get $a needs]]} {
                puts "WM: menu $name: «[dict get $item label]» waits on\
 [dict get $a needs] — not shown"
                continue
            }
            if {[action-type $a] eq "terminal"
                    && [lindex [terminal-resolve] 0] eq ""} {
                puts "WM: menu $name: «[dict get $item label]» waits on\
 a terminal emulator — not shown"
                continue
            }
            set label [dict get $item label]
            set fire [list Fire $a]
        } elseif {[dict exists $item action]} {
            set a [dict get $item action]
            if {![dict exists $::action_spec $a]} {
                # a reference nobody declared is a DEFECT, not a state:
                # it goes to the problems store — once per declaration
                # cycle, a reload re-judges — while the log line says
                # it at every open
                if {![dict exists $::menu_griped [list $name $a]]} {
                    dict set ::menu_griped [list $name $a] 1
                    problem-record "menu $name" \
                        "«$a» is not a deed this desk knows — skipped"
                } else {
                    puts "WM: menu $name: «$a» is not a deed this desk\
 knows — skipped"
                }
                continue
            }
            if {[dict get $::action_spec $a state] ne "active"} {
                puts "WM: menu $name: «$a» is waiting — not shown"
                continue
            }
            set label [expr {[dict exists $item label]
                             ? [dict get $item label] : $a}]
            set fire [list action-fire $a]
        } else {
            set label [dict get $item label]
            set fire [list run-script "menu $name «$label»" \
                          [dict get $item do]]
        }
        # The SHIFT half — the same two shapes, judged the same way,
        # with one difference in consequence: the plain half's refusal
        # hides the row, the shift half's only takes the other reading
        # away (the row is alive by the plain half's judgement, and a
        # shifted pick then reads plain). A reference nobody declared
        # is still a defect and still gripes, once per cycle.
        set sfire ""
        if {[dict exists $item shift-action]} {
            set sa [dict get $item shift-action]
            if {[llength $sa] > 1} {
                if {([dict exists $sa needs]
                        && ![needs-met [dict get $sa needs]])
                        || ([action-type $sa] eq "terminal"
                            && [lindex [terminal-resolve] 0] eq "")} {
                    puts "WM: menu $name: «$label» shift half waits —\
 Shift reads plain"
                } else {
                    set sfire [list Fire $sa]
                }
            } elseif {![dict exists $::action_spec $sa]} {
                if {![dict exists $::menu_griped [list $name $sa]]} {
                    dict set ::menu_griped [list $name $sa] 1
                    problem-record "menu $name" \
                        "shift half «$sa» is not a deed this desk knows —\
 Shift reads plain"
                } else {
                    puts "WM: menu $name: shift half «$sa» is not a deed\
 this desk knows — Shift reads plain"
                }
            } elseif {[dict get $::action_spec $sa state] ne "active"} {
                puts "WM: menu $name: «$label» shift half «$sa» is\
 waiting — Shift reads plain"
            } else {
                set sfire [list action-fire $sa]
            }
        } elseif {[dict exists $item shift-do]} {
            set sfire [list run-script "menu $name «$label» (shift)" \
                           [dict get $item shift-do]]
        }
        set row [dict create label $label fire $fire key \
            [expr {[dict exists $item key] ? [dict get $item key] : ""}]]
        if {$sfire ne ""} { dict set row sfire $sfire }
        lappend rows $row
    }
    if {![llength $rows]} {
        puts "WM: menu $name: nothing to show"
        return
    }
    set ::menu_name $name
    set geo [menu-post $rows [expr {[dict exists $raw place]
                                    ? [dict get $raw place] : ""}] $w]
    puts "WM: menu $name open ([llength $rows] items) $geo"
}

# ---- Choose: the list that answers, as a word --------------------
# The functional half, factored from what winlist-choose proved out:
# put THESE rows up, wait, answer the picked row's value — its label
# when no value is said — or empty when the person did something
# else. A row is a bare word (label and value both) or `{label L
# ?value V? ?key K? ?shift-value V?}` — shift-value is what a SHIFTED
# pick answers, for a caller whose rows have a second reading; a row
# without one answers `value` however it was picked, so the modifier
# never invents a difference the caller did not declare. It WAITS, so
# it wants the coroutine every
# script the desk runs already has (run-script wraps a binding's
# payload and a launch alike); called bare it says so instead of
# wedging the caller.
proc Choose {items {place ""}} {
    if {[info coroutine] eq ""} {
        error "Choose waits for an answer — call it from a script the\
 desk runs (a binding, a launch), not bare"
    }
    set rows {}
    foreach item $items {
        if {[llength $item] == 1} {
            set item [list label [lindex $item 0]]
        }
        if {[llength $item] % 2} {
            error "Choose: a row is a bare word or key-value words,\
 not «$item»"
        }
        foreach k [dict keys $item] {
            if {$k ni {label value key shift-value}} {
                error "Choose: unknown row word «$k»\
 (label value key shift-value)"
            }
        }
        if {![dict exists $item label]} {
            error "Choose: a row needs a label"
        }
        if {[dict exists $item key]
                && [string length [dict get $item key]] != 1} {
            error "Choose: a row key is one character,\
 not «[dict get $item key]»"
        }
        set row [dict create \
            label [dict get $item label] \
            value [expr {[dict exists $item value]
                         ? [dict get $item value]
                         : [dict get $item label]}] \
            key [expr {[dict exists $item key]
                       ? [dict get $item key] : ""}]]
        if {[dict exists $item shift-value]} {
            dict set row svalue [dict get $item shift-value]
        }
        lappend rows $row
    }
    if {![llength $rows]} { return "" }
    set geo [menu-post $rows $place]
    puts "WM: menu chooser open ([llength $rows] items) $geo"
    return [popup-await .menu]
}

# The builder both doors share: hand out the hotkeys, build the
# winops-shaped two columns, post, take the keyboard, answer the
# geometry it landed at. The rows land in ::menu_rows with their keys
# resolved; what a row CARRIES (fire or value) is the door's
# business, read back in menu-pick.
proc menu-post {rows {place ""} {w 0}} {
    # A FULLY unkeyed menu is numbered by position with the shared
    # popup alphabet (popup-autokeys); one explicit key anywhere
    # turns the numbering off — the author took the naming into
    # their own hands, and rows they left bare stay bare. (Gap
    # numbers used to be handed out around the claimed keys, and a
    # mnemonic menu grew digits nobody asked for — the owner,
    # 2026-08-17.)
    set keyed 0
    foreach row $rows {
        if {[dict get $row key] ne ""} { set keyed 1; break }
    }
    set out {}
    if {$keyed} {
        set out $rows
    } else {
        foreach row $rows key [popup-autokeys [llength $rows]] {
            dict set row key $key
            lappend out $row
        }
    }
    set ::menu_rows $out
    set n [llength $out]
    set ih [expr {[font metrics TitleFont -linespace] + 6}]
    set T [popup-shell .menu $ih menu-click]
    $T column create -squeeze yes -expand yes -tags C0
    $T column create -width [expr {$ih + 4}] -tags Ckey
    $T configure -treecolumn C0
    $T element create eKey text -fill [themed dim] -lines 1 \
        -font [popup-hover-font]
    $T style create sAct
    $T style elements sAct {eSel eTxt}
    $T style layout sAct eSel -detach yes -iexpand xy
    $T style layout sAct eTxt -expand ns -padx 8 -squeeze x
    $T style create sKey
    $T style elements sKey {eSel eKey}
    $T style layout sKey eSel -detach yes -iexpand xy
    $T style layout sKey eKey -expand wns -padx 6
    set maxw 0
    foreach row $out {
        set maxw [expr {max($maxw, [font measure TitleFont \
                                        [dict get $row label]])}]
        set item [$T item create]
        $T item style set $item C0 sAct Ckey sKey
        $T item element configure $item C0 eTxt -text [dict get $row label]
        $T item element configure $item Ckey eKey -text [dict get $row key]
        $T item lastchild root $item
    }
    $T selection add 1
    # WHERE IT OPENS is worked out, and a said `place` overrules the
    # working-out: edge words, sizeless, over the workarea — the key
    # echo's own grammar. Unsaid: a gesture puts it under the hand
    # (hanging from the titlebar's bottom edge when the hand is on
    # the strip — gesture-menu-at, the winops rule), and a chord gets
    # the winlist's spot on the monitor under the pointer. Clamped to
    # the glass either way (popup-show).
    lassign [pointer-monitor] mx my sw sh
    set W [expr {min(max($maxw + $ih + 40, 160), $sw * 3 / 5)}]
    # The height goes through the scroll gate FIRST (popup-fit): a Y
    # computed from an unclipped height would anchor a bottom-placed —
    # or centred — menu off the glass. The gate's anchor point only
    # picks the monitor: the workarea's own corner for a said `place`
    # (the no-arg workarea is the primary's), the pointer's monitor
    # otherwise — the same glass the placement below works on.
    if {$place ne ""} {
        lassign [anchor-of $place] halign valign
        lassign [workarea] wax way ww wh
        set H [popup-fit .menu $n $ih $wax $way]
        set X [place-axis $wax $ww $W $halign]
        set Y [place-axis $way $wh $H $valign]
    } else {
        set H [popup-fit .menu $n $ih $mx $my]
        set at [gesture-menu-at $w]
        if {[llength $at]} {
            lassign $at X Y
        } else {
            set X [expr {$mx + ($sw - $W) / 2}]
            set Y [expr {$my + ($sh - $H) / 3}]
        }
    }
    lassign [popup-show .menu $W $H $X $Y] X Y
    if {![grab-keys-to menu-key \
              [list popup-yank "the keyboard went to another mode"]]} {
        puts "WM: menu: keyboard not grabbed — mouse only"
    }
    return ${W}x${H}+$X+$Y
}
# Shift on any way of picking — Return, a hotkey letter, a click — is
# the row's OTHER reading; a row without one reads plain, so the
# modifier never surprises. A hotkey letter fires bare or with Shift
# alone (a shifted LETTER arrives as its own uppercase keysym, which
# the -nocase match already takes; a shifted DIGIT arrives as the
# layout's symbol — «!», «@» — and honestly is not that hotkey any
# more, so the shift reading of a digit row goes through Return).
proc menu-key {kind name mods} {
    if {$kind eq "release"} return
    set shifted [expr {($mods & 1) != 0}]
    if {($mods & ~1) == 0 && [string length $name] == 1} {
        set i 0
        foreach row $::menu_rows {
            incr i
            set k [dict get $row key]
            if {$k ne "" && [string equal -nocase $k $name]} {
                menu-pick $i $shifted
                return
            }
        }
    }
    set d [popup-nav $name $mods]
    if {$d != 0} {
        popup-move .menu.t [llength $::menu_rows] $d
        return
    }
    switch -- $name {
        Return - KP_Enter { menu-pick [lindex [.menu.t selection get] 0] \
                                $shifted }
        Escape            { popups-close }
    }
}
proc menu-pick {i {shifted 0}} {
    if {$i eq "" || $i < 1} { popups-close; return }
    set row [lindex $::menu_rows [expr {$i - 1}]]
    # a list that answers does not act — the winlist's rule, verbatim
    if {[info exists ::popup_fut(.menu)]} {
        set which [expr {$shifted && [dict exists $row svalue]
                         ? "svalue" : "value"}]
        puts "WM: menu answers «[dict get $row $which]»"
        popup-answer .menu [dict get $row $which]
        return
    }
    popups-close
    set which [expr {$shifted && [dict exists $row sfire]
                     ? "sfire" : "fire"}]
    puts "WM: menu $::menu_name pick «[dict get $row label]»[expr\
 {$which eq "sfire" ? " (shift)" : ""}]"
    uplevel #0 [dict get $row $which]
}
proc menu-click {x y {s 0}} {
    set T .menu.t
    if {[catch {$T identify -array A $x $y}] || $A(where) ne "item"} return
    menu-pick $A(item) [expr {($s & 1) != 0}]
}

