# ---- the customization layer: the GUI's word, and whose word wins ----
# Three storeys, each overriding the one below: the CODE's defaults,
# the CONFIG (the user speaking deliberately, by hand), and the
# CUSTOMIZATIONS — the same user speaking by click, through the
# configurator applet or a desk button. The click is the LATER word
# and wins; were it the other way, a GUI whose knobs silently lose to
# a config line would be worse than no GUI (the owner's ruling,
# 2026-07-31). What keeps the shadowing lawful instead of mysterious
# is the loader's report: it knows which layer touched which knob and
# says so, one line per overlap.
#
# The bookkeeping: while a layer's file is being sourced, the config
# VOCABULARY is traced (armed for the load, removed after — nothing
# in the hot paths), and each call is recorded under a semantic key.
# The vocabulary is enumerated by hand and says so: a knob missing
# from the list still works, it just goes unreported — a soft edge,
# preferred over tracing every set-* including the substrate's
# internals.
# THE KNOB REGISTRY — the desk describing its own knobs, as data.
# This is what the configurator renders: it never knows the knobs, it
# ASKS the live WM for this table (knob-table, over the send door) and
# draws what it is told — so a ui host older or newer than the running
# desk still renders the running desk's truth. Each entry:
#   group  where the configurator files it
#   kind   how to render and validate: bool (on|off), {choice a b ...},
#          int, {float MIN MAX}, color, {font NAME}, text (free-form),
#          terminal (beast ?path?)
#   get    a script answering the CURRENT value
#   doc    one line for the UI; the long prose stays in
#          default-config.tcl and in the comments by the procs
# A knob missing here still works — it just does not appear in the
# configurator and goes unreported by the layer bookkeeping below,
# which derives its vocabulary from these keys. Soft edges, said out
# loud.
# A KNOB IS A LEAF, one storey under `knobs` — the plainest node
# there is, and the declaration says so exactly as it always did.
#
# `var` — WHERE THE WISH LIVES, and the first of the facets the
# lifecycle plan asks for (plans/tk9wm-config-lifecycle.md). It is not
# decoration: today the list a reload restores (config_vars) is kept by
# hand beside these declarations, so a knob whose variable is missing
# from it quietly survives a reload against the config's word, and
# nobody finds out until they do. Declared here, the list is DERIVABLE
# and the two can be compared — which is what knob-var-audit does at
# startup, once, out loud.
#
# Empty where the wish is not a plain global: a font object
# (set-desk-font), a font-kin entry (the two derived fonts), a key
# inside a collection (the panel trio lives in ::panels, per panel).
# Those need the collection half of the model — see the config-tree
# plan — and saying "" here is the honest statement of that, not a
# gap.
#
# `settle` — WHICH SETTLER MAKES IT REAL, by name from the ordered list
# below. Empty is legal and means exactly what it says: the value IS
# the state, read at the moment of use, and nothing has to be rebuilt
# for it (set-edge-resist is asked at the moment a window is carried;
# set-icon-path at the moment an icon is looked up).
#
# Today the setters still do their own work, so this facet DESCRIBES
# rather than drives — it is the mapping the next steps need, and
# declaring it now is what makes «осадить только изменившееся» a small
# change later rather than an archaeology exercise.
proc knob {name meta} {
    config-node [list knobs $name] [dict merge {node leaf} $meta]
}
proc knob-registry {} { config-nodes-under knobs }

# ---- the kind, as a CHECK — one implementation, both inputs -------
#
# A value arrives two ways: typed into the configurator, or written in
# a file. They were checked by two different pieces of code — the
# applet's own switch and whatever `if … error` the setter's author
# wrote — which is two answers to one question, drifting apart by
# construction (the lifecycle plan, step 2).
#
# It is one proc now, it lives here because the WM is what the value is
# FOR, and it asks the world rather than a rule of thumb (the owner,
# 2026-08-04: "она должна быть максимально по живому"). The display
# knows its colours; the keymap knows its keysyms; Tk knows what it
# will take for -cursor. A rule of thumb knows what somebody once
# believed.
#
# TWO KINDS OF ANSWER, and the difference is the plan's:
#   knob-check   ADMISSION — "" when the value may be said at all, a
#                complaint when the consumer could not use it ever;
#   knob-warn    WARNING — "" or a note about a value that is legal and
#                whose world is not ready (a directory that is not
#                there yet, a font family this display substitutes).
#                Never a refusal: the mount may appear, the font may be
#                installed, and dropping the value would change what
#                the config says behind the user's back.
proc knob-probe {} {
    if {![winfo exists .knobprobe]} {
        # never mapped, never packed, never read: a place to ask Tk
        # whether it would take a value, and nothing else
        label .knobprobe
    }
    return .knobprobe
}
proc knob-kind {name} {
    set r [knob-registry]
    if {![dict exists $r $name kind]} { return text }
    dict get $r $name kind
}
# THE KIND is what is checked, not the name — because names live in
# more places than the knob registry: a widget's type, a field of a
# collection, a member row in the tree. Delegating by NAME quietly lost
# every one of those (caught by the configurator suite the moment it
# was tried), so the pair travels instead and the caller supplies the
# kind it already knows.
proc knob-check {name value} { kind-check [knob-kind $name] $value $name }
proc kind-check {kind value {who ""}} {
    if {$who eq ""} { set who "this" }
    set name $who
    switch -- [lindex $kind 0] {
        int {
            if {![string is integer -strict $value]} {
                return "$name wants a whole number, not «$value»"
            }
            # ...and the bounds the setters used to check by hand:
            # `int` alone is any whole number, `int 0` is «not
            # negative», `int 1 9` is a range. Written in the kind, the
            # rule is one place and both inputs get it.
            lassign [lrange $kind 1 2] lo hi
            if {$lo ne "" && $value < $lo} {
                return "$name wants [expr {$hi eq {} ? "at least $lo" \
                                           : "a number from $lo to $hi"}]"
            }
            if {$hi ne "" && $value > $hi} {
                return "$name wants a number from $lo to $hi"
            }
        }
        float {
            lassign $kind - lo hi
            if {![string is double -strict $value]} {
                return "$name wants a number, not «$value»"
            }
            if {$value < $lo || $value > $hi} {
                return "$name wants a number between $lo and $hi"
            }
        }
        bool {
            if {![string is boolean -strict $value]} {
                return "$name is on or off, not «$value»"
            }
        }
        choice {
            if {$value ni [lrange $kind 1 end]} {
                return "$name is one of: [lrange $kind 1 end]"
            }
        }
        color {
            # THE DISPLAY's own answer, names from rgb.txt included
            if {[catch {winfo rgb . $value}]} {
                return "«$value» is not a colour this display knows"
            }
        }
        font {
            # THE CONSUMER, and not Tk. Our font grammar is WIDER than
            # Tk's -font: `DejaVu Sans 13 bold` with an unbraced
            # multi-word family is ours to parse and Tk's to refuse, so
            # asking Tk here rejected a spec the desk accepts (caught
            # by the configurator suite the moment this was written).
            # font-args is the code that will do the parsing, so it is
            # the code that answers.
            #
            # What it does NOT answer is whether the family exists: Tk
            # takes any family and substitutes silently (measured —
            # «!!!» resolves to the default). That is knob-warn's half.
            if {[catch {llength $value}]} {
                return "$name wants a list, and «$value» is not one"
            }
            if {[catch {font-args $name {*}$value} e]} { return $e }
        }
        list {
            if {[catch {llength $value}]} {
                return "$name wants a list, and «$value» is not one"
            }
        }
    }
    return ""
}
proc knob-warn {name value} { kind-warn [knob-kind $name] $value $name }
proc kind-warn {kind value {who ""}} {
    if {$who eq ""} { set who "this" }
    set name $who
    switch -- [lindex $kind 0] {
        list {
            # PATH SEMANTICS, and the owner said it in those words: a
            # directory that is not there is a note, never a reason to
            # drop the component. It may be mounted tomorrow, and a
            # config quietly shortened behind one's back is worse than
            # a line in the log.
            if {[lindex $kind 1] ne "directories"} { return "" }
            set gone {}
            foreach d $value {
                if {![file isdirectory $d]} { lappend gone $d }
            }
            if {[llength $gone]} {
                return "$name: not there (kept anyway, like PATH): [join $gone { }]"
            }
        }
        font {
            if {![llength $value]} { return "" }
            # ...through the same parser, so the family is the one the
            # desk will really ask for
            if {[catch {font-args $name {*}$value} opts]} { return "" }
            set want ""
            if {[dict exists $opts -family]} { set want [dict get $opts -family] }
            if {$want eq ""} { return "" }
            set got [font actual [list $want 10] -family]
            if {[string tolower $got] ne [string tolower $want]} {
                return "$name: no «$want» on this display — «$got» instead"
            }
        }
    }
    return ""
}
# The config word's own gate: refuse loudly, warn quietly, and let the
# word through in every other case. Called from the guard wrapper, so
# no setter has to remember it and none can forget.
proc knob-precheck {name value} {
    set bad [knob-check $name $value]
    if {$bad ne ""} { error $bad }
    set note [knob-warn $name $value]
    if {$note ne ""} { puts "WM: $note" }
}
# Every wish a knob declares — the derived form of what config_vars
# keeps by hand.
proc knob-vars {} {
    set out {}
    dict for {name meta} [knob-registry] {
        if {[dict exists $meta var] && [dict get $meta var] ne ""} {
            lappend out [dict get $meta var]
        }
    }
    return [lsort -unique $out]
}
# A SETTER ONE NEED NOT WRITE. With `var`, `settle` and `kind` all
# declared, a scalar knob's word is exactly: check (the gate does it),
# write the wish, ask for the deed. That is what this generates —
# which is the point of the facets, and the answer to «why declare
# them» (lifecycle plan, step 5).
#
# A hand-written word is never replaced: several are hand-written for
# real reasons (a font object rather than a variable, a value that
# normalizes, a wish spread over two variables), and the generator
# stepping over one would be the worst kind of clever.
proc knob-define {name} {
    set meta [dict get [knob-registry] $name]
    if {![dict exists $meta var] || [dict get $meta var] eq ""} { return 0 }
    if {[llength [info commands $name]]} { return 0 }
    set var [dict get $meta var]
    set kind [dict get $meta kind]
    set settle [expr {[dict exists $meta settle] ? [dict get $meta settle] : ""}]
    # BOOLEANS NORMALIZE. The wish is 0 or 1 whatever the config wrote
    # («on», «yes», «true»), because everything that reads it expects a
    # number — this is the one shape difference between the hand-written
    # words and the generated ones, and it is the kind that decides it.
    set write [expr {[lindex $kind 0] eq "bool"
                     ? "set ::$var \[expr {\$value ? 1 : 0}\]"
                     : "set ::$var \$value"}]
    set ask [expr {$settle eq "" ? "" : "; settle-soon $settle"}]
    proc $name {value} "$write$ask"
    return 1
}
proc knobs-define {} {
    set n 0
    dict for {name -} [knob-registry] { incr n [knob-define $name] }
    return $n
}
proc knob-settler {name} {
    set r [knob-registry]
    if {[dict exists $r $name settle]} { return [dict get $r $name settle] }
    return ""
}
# ...and the comparison, said once at startup. A knob whose variable a
# reload does not restore is a knob that outlives the config that set
# it; a name in the hand-kept list that no knob claims is either
# collection state (which is fine and expected) or a leftover. Both are
# worth one line rather than a surprise.
proc knob-var-audit {} {
    set declared [knob-vars]
    set kept $::config_vars
    set unrestored {}
    foreach v $declared {
        if {[lsearch -exact $kept $v] < 0} { lappend unrestored $v }
    }
    if {[llength $unrestored]} {
        puts "WM: knobs whose wish a reload does NOT restore:\
 [join $unrestored { }]"
    }
    set unclaimed 0
    foreach v $kept {
        if {[lsearch -exact $declared $v] < 0} { incr unclaimed }
    }
    # The rest of what a reload restores is collection state (panels,
    # widgets, actions, bindings) and derived memo — the config-tree
    # plan's half, and expected. Counted, not listed: a list of
    # twenty-seven names at every start is noise nobody reads twice.
    puts "WM: config wishes: [llength $declared] declared by knobs,\
 [llength $kept] restored on reload ($unclaimed of them collections and memo)"
    vocabulary-audit
    deed-audit
}
# THE INVARIANT, MADE ASKABLE: a config word only writes a wish, and
# nothing visible happens until a settler runs (lifecycle plan, step
# 4). A word that calls the desk directly is a DEED, and a deed cannot
# be said twice by two layers without the first one costing something —
# which is exactly how `set-desks 1` in a config flattened every window
# before the customization's `set-desks 2` was read.
#
# The check is a heuristic and says so: it looks for the settlers' own
# commands in a word's body. That catches the real cases (a setter
# calling panels-build, theme-apply, tray-recolor) and cannot catch a
# deed done through some name nobody thought of — which is fine. It is
# a hint that names names, not a proof.
set live_commands {
    panels-build tray-reconcile tray-recolor desk-window-build
    welcome-inject widgets-build retitle-frames root-cursor-apply
    publish-workarea panel-on-top theme-apply fonts-derive title-metrics
    restack-soon chord-hold-shadows panel-match-kick ui-restyle
}
proc deed-audit {} {
    set deeds {}
    dict for {name meta} [knob-registry] {
        if {![llength [info commands $name]]} continue
        if {[catch {info body $name} body]} continue
        foreach cmd $::live_commands {
            # NOT inside a longer name: `tray-reconcile-soon` is a
            # REQUEST and reads as the deed `tray-reconcile` to a
            # careless word boundary, since a dash is not a word
            # character. Asking that the next character is not one of
            # ours is what tells the two apart.
            # ${cmd} braced, and it matters: `$cmd(` reads as an ARRAY
            # reference to Tcl, so the pattern threw instead of matching
            # (measured — the whole audit died on it).
            if {[regexp "\\y${cmd}(?:\[^-a-zA-Z0-9\]|\$)" $body]} {
                lappend deeds $name
                break
            }
        }
    }
    if {[llength $deeds]} {
        puts "WM: words that still ACT rather than wish\
 ([llength $deeds]): [join [lsort $deeds] { }]"
    }
    return $deeds
}

# WORDS OUTSIDE THE REGISTRY, which is the other gap the lifecycle plan
# names: instrumenting walks the registry, so a `set-*` that never got
# a descriptor is a word that kills the whole config file on a typo
# instead of recording a problem. It is also a word the configurator
# cannot show and nothing can type-check.
#
# What is DECLARED internal (config-internal) is not counted: that
# declaration is the descriptor settling the question. What is left is
# a real gap — a word one can say and nothing guards.
proc vocabulary-audit {} {
    set loose {}
    foreach name [lsort [info commands set-*]] {
        if {[dict exists $::verb_registry $name]} continue
        if {[dict exists $::config_internal $name]} continue
        lappend loose $name
    }
    if {[llength $loose]} {
        puts "WM: `set-*` outside the vocabulary registry\
 ([llength $loose]): [join $loose { }]"
    }
}
# THE DECLARATION ORDER IS THE DISPLAY ORDER: inside a group the
# configurator shows knobs as they are said here, the way the
# headings go in their said order (the owner, 2026-08-06 — the
# alphabet put set-root-cursor above set-theme, and could not put
# the edit door first). Declaring is curating: a group's first
# declaration is its first row.
knob set-desk-font   {var {} settle {titles} group fonts kind {font DeskFont}  get {font actual DeskFont}
                      doc {the font this desk is set in; everything derives from it}
                      examples {
                          {DejaVu Sans 13} {a whole spec — family and size, bare words welcome}
                          {-size 13} {one option alone — the rest of the font stays}
                          {-weight bold} {a bolder desk, family and size untouched}}}
knob set-title-font  {var {} settle {titles} group fonts kind {font TitleFont} get {font-kin-opts TitleFont}
                      doc {the titlebar font, as a delta from the desk font}
                      examples {
                          {-weight bold} {the classic delta — bold titles over the desk font}
                          {-size 10} {smaller titles, same family}}}
knob set-panel-font  {var {} settle {panels} group fonts kind {font PanelFont} get {font-kin-opts PanelFont}
                      doc {the panel buttons' font, as a delta from the desk font}
                      examples {
                          {-size 10} {smaller buttons, same family}
                          {-family {DejaVu Sans Mono}} {a family of its own, the size still the desk's}}}
knob set-title-justify {var {titlejust} settle {titles} group fonts kind {choice left center right}
                      get {set ::titlejust} doc {where the title sits in its bar}}
knob set-border      {var {border} settle {titles} group frame kind {int 0} get {set ::border}
                      doc {the border's thickness, all four sides — it is the resize grip}}
knob set-grips       {var {gripz} settle {decor} group frame kind {int 0} get {set ::gripz}
                      doc {the corner grip arms' reach along the border}}
knob set-title-air   {var {titleair} settle {titles} group frame kind {int} get {set ::titleair}
                      doc {the strip's padding around the title's text line, each side;
 0 is exactly the linespace, negative clips into the line}
                      examples {
                          {0} {the tightest strip that still fits the whole font}
                          {-2} {tighter yet — eats the font's own leading, then the descenders}}}
knob set-button-gap  {var {btngap} settle {titles} group frame kind {int 0} get {set ::btngap}
                      derived {look default border}
                      doc {how much shorter than the strip a titlebar button is —
 the hole between the buttons and the client; unsaid, one border}
                      examples {
                          {2} {a tight 2px hole, whatever the border is}
                          {0} {full-height buttons, pressed right against the client}}}
knob set-minimize    {var {minimize} settle {} group windows kind {choice iconify refuse}
                      get {set ::minimize} doc {what an iconify request gets}}
knob set-maximize    {var {maximize} settle {} group windows kind {choice drop keep}
                      get {set ::maximize}
                      doc {what a hand resize does to the maximized mark}}
knob set-workarea-follow {var {workarea_follow} settle {} group windows kind {choice stick max off}
                      get {set ::workarea_follow}
                      doc {which windows follow a moving workarea}}
knob set-drag-modifier {var {drag_mods} settle {} group windows kind text get {mods-name $::drag_mods}
                      doc {the modifier that carries a window from anywhere}}
knob set-drag-slop   {var {drag_slop} settle {} group windows kind {int 0} get {set ::drag_slop}
                      doc {pixels a title press may travel and still be a click}}
knob set-edge-resist {var {edge_resist} settle {} group windows kind {int 0} get {set ::edge_resist}
                      doc {pixels a carried window sticks to a workarea edge}}
knob set-fade        {var {fade} settle {} group windows kind {float 0 1} get {set ::fade}
                      doc {how solid a faded window stays}}
knob set-edit-door   {var {edit_door} settle {} group desk kind {choice emacs terminal}
                      get {set ::edit_door}
                      derived {edit-door-derived}
                      doc {how a file opens to edit — emacs, or an editor in a terminal}}
knob set-theme       {var {theme} settle {theme} group desk kind {choice dark light} get {set ::theme}
                      doc {the desk's colours in one word; every colour derives from it}}
knob set-desks       {var {ndesks} settle {desks} group desk kind {int 1} get {set ::ndesks}
                      doc {how many virtual desks; 1 switches them off}}
knob set-desk-window {var {desk_window} settle {desk-window} group desk kind bool
                      get {expr {$::desk_window ? "on" : "off"}}
                      doc {the desk as one window of ours, or hands off the root}}
knob set-desk-background {var {desk_background_said} settle {desk-window} group desk kind color get {set ::desk_background_said}
                      derived {themed desk}
                      doc {the desk window's color}}
knob set-root-cursor {var {root_cursor} settle {cursor} group desk kind text get {set ::root_cursor}
                      doc {the cursor over the bare desk}}
knob set-welcome     {var {welcome} settle {welcome} group desk kind bool get {set ::welcome}
                      doc {the welcome note on the desk}}
knob set-panel-side  {var {} settle {panels} group panel kind {choice bottom top left right}
                      get {panel-cfg default side}
                      doc {which screen edge the default panel rides}}
knob set-panel-preset {var {} settle {panels} group panel kind {choice row stack icons}
                      get {panel-cfg default preset}
                      doc {buttons as a row, label-under-icon, or icons alone}}
knob set-panel-icon-size {var {} settle {panels} group panel kind {int 1}
                      get {panel-cfg default icon_size}
                      doc {the button face size when any face is iconic}}
knob set-icon-path   {var {icon_path} settle {} group panel kind {list directories} get {set ::icon_path}
                      doc {directories bare icon names are searched in}}
knob set-chord-hold  {var {chord_hold} settle {keys} group keys kind bool
                      get {expr {$::chord_hold ? "on" : "off"}}
                      doc {a chord answers with the modifier held down too}}
knob set-winlist-cycle {var {winlist_cycle_opt} settle {} group keys kind bool
                      get {expr {$::winlist_cycle_opt ? "on" : "off"}}
                      doc {alt-tab as the fvwm cycle, or a static menu}}
knob set-key-echo    {var {key_echo} settle {} group keys kind text get {set ::key_echo}
                      doc {ms of hesitation before a chord shows itself; off = never}}
knob set-key-echo-place {var {key_echo_place} settle {} group keys kind text get {set ::key_echo_place}
                      doc {where the chord echo sits, in place words}}
knob set-key-hold-warn {var {key_hold_warn} settle {} group keys kind {int 0} get {set ::key_hold_warn}
    doc {ms a binding may hold the desk before it is reported}}
knob set-tray        {var {tray_on} settle {tray} group tray kind bool
                      get {expr {$::tray_on ? "on" : "off"}}
                      doc {be the display's system tray}}
knob set-tray-panel  {var {tray_panel} settle {panels} group tray kind text get {set ::tray_panel}
                      doc {whose strip the tray is part of}}
knob set-tray-background {var {tray_bg_said} settle {tray} group tray kind color get {set ::tray_bg_said}
                      derived {themed ground}
                      doc {what shows through a transparent icon}}
knob set-tray-icon-size {var {tray_icon_size} settle {tray} group tray kind {int 1} get {set ::tray_icon_size}
                      doc {the tray cell's side, in pixels}}
knob set-tray-argb   {var {tray_argb} settle {tray} group tray kind bool
                      get {expr {$::tray_argb ? "on" : "off"}}
                      doc {offer an ARGB visual (needs a compositor)}}
knob set-terminal    {var {terminal_choice} settle {} group terminal kind terminal get {set ::terminal_choice}
                      derived {terminal-derived}
                      doc {which terminal emulator this desk favors}}
knob set-emacs-daemons {var {emacs_daemons} settle {} group emacs kind bool get {set ::emacs_daemons}
                      doc {daemons at all, or the plain lookup-or-run life}}
knob set-emacs-autodaemon {var {emacs_autodaemon} settle {} group emacs kind bool get {set ::emacs_autodaemon}
                      doc {start a missing daemon, or treat it as an error}}
knob set-emacs-frames {var {emacs_frames} settle {} group emacs kind {choice gui terminal}
                      get {set ::emacs_frames}
                      doc {what kind of frame an emacs button makes}}
knob set-emacs-keep-frame-name {var {emacs_keep_frame_name} settle {} group emacs kind bool
                      get {set ::emacs_keep_frame_name}
                      doc {leave the button's name in the frame's title}}
knob set-emacs-edit {var {emacs_edit} settle {} group emacs kind {choice reuse create}
                      get {set ::emacs_edit}
                      doc {where an edit lands — a frame one has, or a fresh one}}
knob set-emacs-edit-daemon {var {emacs_edit_daemon} settle {} group emacs kind text
                      get {set ::emacs_edit_daemon}
                      doc {which daemon opens an edit — unsaid is the default one}}
# knob-table — the send-facing answer: the registry plus each knob's
# current value, one dict. The configurator's whole worldview.
# What a DERIVED font's knob is really set to: the delta the config
# stated (-weight bold and nothing else), not the font that came out
# of applying it to the base. Deriving exists so a desk need not
# repeat the family; showing the computed font would invite exactly
# that repetition back (the owner, 2026-08-01).
proc font-kin-opts {name} {
    expr {[dict exists $::font_kin $name] ? [dict get $::font_kin $name opts] : {}}
}
# WHAT A KNOB IS SET TO is what the LAYERS SAID, when either of them
# said anything: the argument of the last command recorded for it.
# The `get` script answers what the desk COMPUTED from that, which is
# a different question and not the one an editor should show — save
# «-family {Dejavu Sans}» and the cell must still read that, not the
# whole font it resolved to (the owner, 2026-08-01). Nobody spoke:
# the computed value IS the answer, because the code's default is not
# written down anywhere else.
proc knob-said {name kind} {
    foreach layer {custom config} {
        if {![dict exists $::layer_knobs $layer $name]} continue
        set cmd [dict get $::layer_knobs $layer $name]
        # the multi-argument kinds spread their value into the
        # command; the rest carry it whole in one word
        if {[lindex $kind 0] in {font terminal}} {
            return [list 1 [lrange $cmd 1 end]]
        }
        return [list 1 [lindex $cmd 1]]
    }
    return [list 0 ""]
}
proc knob-table {} {
    set out {}
    dict for {name meta} [knob-registry] {
        set value ""
        lassign [knob-said $name [dict get $meta kind]] said value
        if {!$said} { catch {set value [uplevel #0 [dict get $meta get]]} }
        set extra [dict create value $value owner [knob-owner $name]]
        # WHAT IT AMOUNTS TO WITH NOBODY SAYING IT — and where that
        # answer came from. A knob whose default is DETECTED on this
        # machine is not making the same promise as one baked into the
        # code, and the difference is exactly what somebody deciding
        # whether to write a word of their own needs to see (the
        # owner, 2026-08-02, on the terminal). Only asked where the
        # knob offers an answer, and only while nothing is said.
        if {$value eq "" && [dict exists $meta derived]} {
            catch {dict set extra derived [uplevel #0 [dict get $meta derived]]}
        }
        # a font also answers what it COMPUTES to — the number a
        # chooser must start from, and the truth about what is drawn
        if {[lindex [dict get $meta kind] 0] eq "font"} {
            catch {dict set extra computed \
                [font actual [lindex [dict get $meta kind] 1]]}
        }
        dict set out $name [dict merge $meta $extra]
    }
    return $out
}
# WHOSE VALUE IS THIS — what a knob's row should answer at a glance
# (the owner: "did I override the default?"): `code` when neither
# layer has spoken, `config` when the hand-written file did, `custom`
# when a click did — which outranks the config, and says so.
proc knob-owner {name} {
    if {[dict exists $::layer_knobs custom $name]} { return custom }
    if {[dict exists $::layer_knobs config $name]} { return config }
    return code
}
# ERASE a customization — the click taken back. The entry leaves the
# custom layer and its file, and the desk re-reads its layers, so the
# knob falls back to whatever the config, or the code, says. The
# reload is what makes the erasure honest: nothing here has to know
# how to undo a knob, which is the same reason Revert is a reload.
proc custom-erase {name} {
    if {![dict exists $::layer_knobs custom $name]} { return 0 }
    dict unset ::layer_knobs custom $name
    custom-save
    puts "WM: custom: erased $name"
    reload-config
    return 1
}
# custom-reorder KEYS — the named entries take the order KEYS says:
# they are permuted among their own positions in the custom record,
# everything else stays where it stood. Order is meaning for the
# sectioned declarations (an owned panel IS its buttons' order), and
# the file is the only place that order lives — so this rewrites the
# file and leaves the LIVE order to the caller's reload: only a
# replay honors how the layers interleave.
proc custom-reorder {keys} {
    if {![dict exists $::layer_knobs custom]} {
        error "custom-reorder: the custom layer holds nothing"
    }
    set entries [dict get $::layer_knobs custom]
    set all [dict keys $entries]
    set slots [lmap k $all {expr {$k in $keys ? "yes" : "no"}}]
    if {[llength [lsearch -all $slots yes]] != [llength $keys]} {
        error "custom-reorder: keys and standing entries disagree:\
 $keys against [dict keys $entries]"
    }
    set i 0
    foreach here $slots {
        if {$here eq "yes"} {
            lset all $i [lindex $keys 0]
            set keys [lrange $keys 1 end]
        }
        incr i
    }
    set new {}
    foreach k $all { dict set new $k [dict get $entries $k] }
    dict set ::layer_knobs custom $new
    custom-save
    puts "WM: custom: reordered"
}

# ---- the collection registry ----
# The knobs' sibling: a COLLECTION is a configurable FAMILY — panel
# buttons, key bindings, widgets, key bundles — whose elements come
# and go, each addressed by a key of its own (a label, a chord, a
# name). The registry is the configurator's worldview of them, the
# exact counterpart of knob-table: what collections exist, what
# fields an element carries (kind + doc, editors picked by kind —
# `chord` validates through parse-chord and shows through chord-name,
# `dict` is a nested dictionary for a sub-editor), whether order is
# meaningful, and the elements themselves. Per element: its key, the
# values the layers SAID (the knob-said lesson holds here too — never
# the desk's expansion of them), and its OWNER — code, config or
# custom, read off the same per-key layer records the knobs use.
# A FAMILY IS A DICT OF ELEMENTS, and its fields are leaves inside
# every one of them — «actions @ launch» rather than a table of its
# own. What it serves the editor is unchanged; where it is kept is.
#
# Two words here are for the editor's tree rather than for the
# machinery. `insert {a button}` says a new element may be MADE and
# what to call one in a sentence — a family without it is fixed in
# code (the bundles). `topic {panel buttons}` says this family shares
# its subject with a group of knobs: `panel` was a heading of knobs
# AND a heading of buttons, standing twice in the tree and mattering
# once the addressing goes by subtree (the owner, 2026-08-02) — so
# the family hangs under that topic as a subsection called `buttons`.
proc collection {name meta} {
    config-node [list $name] [dict merge {node family} [dict remove $meta fields]]
    # THE ELEMENT ITSELF is a node too, and the one thing it has to
    # say is what a SECOND word about the same element does: refine
    # what stands (`merges` — then an empty value un-says a key) or
    # replace it. Families that have not been asked say nothing, and
    # nothing is claimed on their behalf.
    set el [list node dict]
    if {[dict exists $meta merge]} { lappend el merge [dict get $meta merge] }
    config-node [list $name @] $el
    dict for {f fmeta} [dict get $meta fields] {
        config-node [list $name @ $f] [dict merge {node leaf} $fmeta]
    }
}
proc collection-fields {name} { config-nodes-under [list $name @] }

# The one family whose fields are not written here: an action's keys
# ARE the spec registry's, and saying them again would be a second
# truth about the same language (spec-fields maps the language's
# kinds onto this tree's editors).
collection actions [list \
    key name ordered no insert {an action} \
    doc {named deeds — run-or-raise by name; a panel button is a reference to one} \
    list collection-actions \
    fields [spec-fields action]]
collection panel {
    key name ordered yes merge merges insert {a button}
    topic {panel buttons}
    doc {the default panel — references to actions, in strip order}
    list collection-panel
    fields {
        label {kind text doc {how the button reads — the action's name when unsaid}}
        icon  {kind text doc {a face for this panel — the action's own when unsaid}}
    }
}
collection bindings {
    key chord ordered no key-words yes insert {a binding}
    topic {keys bindings}
    doc {every chord this desk answers to, and what it runs}
    list collection-bindings
    fields {
        script {kind text lint script doc {what the chord runs}}
        name   {kind text doc {how the key-help overlay names it — display only}}
    }
}
collection widgets {
    key name ordered yes insert {a widget}
    doc {the desk's widgets, sharing their areas in declaration order}
    list collection-widgets
    fields {
        -type    {kind choice choices-from types
                  doc {what the widget IS — see wm-widget-type}}
        -on      {kind text doc {which surface hosts it — workarea, screen, or a panel's name}}
        -place   {kind text doc {where on its surface — [SIZE]EDGE words: 50%right, center, top left}}
        -padding {kind int  doc {air inside the container, px}}
    }
}
collection keys {
    key bundle ordered no topic {keys bundles}
    doc {families of bindings that come and go together — members fixed in code}
    list collection-keys
    fields {
        state  {kind {choice on off} doc {the whole family, present or not}}
        params {kind dict members fixed
                doc {the bundle's own parameters — the rows under this one name them}}
    }
}
# The menus' fields are the spec registry's, exactly as the actions':
# one language, one table, two readers.
collection menus [list \
    key name ordered no insert {a menu} \
    doc {the config's own menus — rows of deeds under a chord} \
    list collection-menus \
    fields [spec-fields menu]]

# A list script answers a DICT — elements, plus whatever meta only
# the live state knows: the panel says whether the custom layer OWNS
# the set (the adoption gate the editing rules turn on), and each
# element carries `said` — the custom layer's own word for it, which
# is what a save must accumulate onto so a standing delta survives
# the next edit.
proc collection-actions {} {
    set out {}
    # A REMOVAL IS A WORD TOO, and a word one must be able to take
    # back: an action removed by the custom layer is gone from the
    # registry, so without this line the tree would show nothing at
    # all where it stood — an invisible customization, undoable only
    # by editing the file this applet exists to spare people.
    foreach layer {custom config} {
        if {![dict exists $::layer_knobs $layer]} continue
        dict for {k cmd} [dict get $::layer_knobs $layer] {
            if {[lindex $cmd 0] ne "action-remove"} continue
            set name [lindex $cmd 1]
            if {[dict exists $::action_raw $name]} continue
            lappend out [dict create key $name values {} owner $layer \
                lkey $k ineffectual 1 \
                why "removed by you — Delete takes the removal back"]
        }
    }
    dict for {name raw} $::action_raw {
        set e [dict create key $name values $raw \
                   owner [knob-owner "action $name"]]
        # THE TYPE IS FIRST-CLASS IN THE TREE even when nobody said
        # it: unsaid, the row shows what the settings amount to, and
        # says that it was derived rather than written.
        if {![dict exists $raw type]} {
            dict set e derived [dict create type [action-type $raw]]
        }
        # A WRITTEN `run` SHOWS THROUGH ITS FACE: the tree keeps one
        # row for the slot — launch — so the launch this run desugars
        # to rides as derived, giving that row an honest value to
        # show and to seed an edit with.
        if {[dict exists $raw run]} {
            dict set e derived launch [list Run {*}[dict get $raw run]]
        }
        if {[dict exists $::custom_effect "action $name"]} {
            dict set e effect [dict get $::custom_effect "action $name"]
        }
        # waiting — declared, not alive: the tree gets to say why a
        # deed is not answering (and the panels not showing it)
        if {[dict exists $::action_spec $name state]
                && [dict get $::action_spec $name state] ne "active"} {
            dict set e waiting 1
        }
        # the linter's remarks ride along, so the tree can flag the
        # very row they are about (they are ADVICE — an element
        # wearing one is not broken, and nothing here is refused)
        if {[dict exists $::action_lint $name]
                && [llength [dict get $::action_lint $name]]} {
            dict set e lint [dict get $::action_lint $name]
        }
        if {[dict exists $::layer_knobs custom "action $name"]} {
            set cmd [dict get $::layer_knobs custom "action $name"]
            if {[lindex $cmd 0] eq "action"} {
                dict set e said [lindex $cmd 2]
            }
        }
        lappend out $e
    }
    dict create elements $out
}
# The panel family is REFERENCES: each element an action's name with
# its display overrides, `waiting` flagging one the strip is not
# showing — its action undeclared still, or gated on software the
# machine lacks; the reference stays VISIBLE here either way, since
# a customization must never need the file dug out by hand. The
# CARDS are the registry's other half: every action NOT on the
# panel, which is exactly what Insert can bring in — the catalogue
# was the buttons' raw memory once, and is the action registry
# itself now.
proc collection-panel {} {
    set out {}
    dict for {aname over} [panel-cfg default refs] {
        set e [dict create key $aname values $over \
                   owner [knob-owner "panel-button $aname"]]
        if {![dict exists $::action_spec $aname]
                || [dict get $::action_spec $aname state] ne "active"} {
            dict set e waiting 1
        }
        if {[dict exists $::layer_knobs custom "panel-button $aname"]} {
            set cmd [dict get $::layer_knobs custom "panel-button $aname"]
            if {[lindex $cmd 0] eq "panel-button"} {
                dict set e said [lindex $cmd 2]
            }
        }
        lappend out $e
    }
    set cards {}
    dict for {aname -} $::action_raw {
        if {![dict exists $::panels default refs $aname]} {
            lappend cards $aname
        }
    }
    dict create elements $out cards $cards owned [expr {[dict exists \
        $::layer_knobs custom "panel-buttons-own default"] ? "yes" : "no"}]
}
proc collection-widgets {} {
    set out {}
    dict for {name opts} $::widgets {
        set values $opts
        # what the layer SAID, when one did: the call's own words, not
        # the stored merge of defaults over them. The code's widgets
        # never spoke sparsely — the stored options ARE its word.
        foreach layer {custom config} {
            if {[dict exists $::layer_knobs $layer "wm-widget $name"]} {
                set values [lrange \
                    [dict get $::layer_knobs $layer "wm-widget $name"] 2 end]
                break
            }
        }
        # ...AND WHAT THE UNSAID FIELDS AMOUNT TO. A widget that never
        # said where it goes is not «nowhere»: it is at the workarea's
        # right, which is what the merged options hold — and the tree
        # has a way to show exactly that (a derived value, marked as
        # not written). The owner, 2026-08-02: «placement виджета по
        # умолчанию нигде, на самом деле на workarea справа». The
        # type's param defaults are the same kind of answer and ride
        # the same key.
        #
        # `fields` is the element's OWN half of the schema — the words
        # of its type (params, and -every where the type ticks) — which
        # the family's static table cannot carry: what rows an element
        # grows depends on what it IS.
        set type [dict get $opts -type]
        lappend out [dict create key $name values $values \
                         derived [dict merge [widget-type-defaults $type] $opts] \
                         fields [widget-type-fields $type] \
                         owner [knob-owner "wm-widget $name"]]
    }
    # ...and the TYPES: what a new widget can be — the Insert dialog's
    # catalogue, which for widgets has existed all along
    dict create elements $out types [dict keys $::widget_types]
}
# WHOSE is a widget's SEAT in the row — not whose are its options.
# The order is first-declaration order: a custom override of a config
# widget keeps the config's seat, and the code's own mat (the
# welcome) takes its injected place only when no layer sat it first —
# welcome-inject fills absence, it never moves what stands. So the
# seat is the custom layer's exactly when custom declared the widget
# and config did not; that is what the editor's Alt-move may permute
# (the light model — the owner, 2026-08-11).
proc widget-seat-custom? {name} {
    expr {[dict exists $::layer_knobs custom "wm-widget $name"]
          && ![dict exists $::layer_knobs config "wm-widget $name"]}
}
proc collection-keys {} {
    set out {}
    dict for {name def} $::key_bundle_defs {
        set on [dict exists $::key_bundles $name]
        # the parameters the family RUNS ON when it is up; the
        # declaration's defaults when it is off
        set params [expr {$on ? [dict get $::key_bundles $name params]
                              : [dict get $def params]}]
        lappend out [dict create key $name \
            values [dict create state [expr {$on ? "on" : "off"}] \
                        params $params] \
            owner [knob-owner "wm-keys $name"]]
    }
    dict create elements $out
}
proc collection-menus {} {
    set out {}
    # a removal is a word too — the actions' rule, verbatim
    foreach layer {custom config} {
        if {![dict exists $::layer_knobs $layer]} continue
        dict for {k cmd} [dict get $::layer_knobs $layer] {
            if {[lindex $cmd 0] ne "wm-menu-remove"} continue
            set name [lindex $cmd 1]
            if {[dict exists $::menus $name]} continue
            lappend out [dict create key $name values {} owner $layer \
                lkey $k ineffectual 1 \
                why "removed by you — Delete takes the removal back"]
        }
    }
    dict for {name raw} $::menus {
        set e [dict create key $name values $raw \
                   owner [knob-owner "wm-menu $name"]]
        if {[dict exists $::layer_knobs custom "wm-menu $name"]} {
            set cmd [dict get $::layer_knobs custom "wm-menu $name"]
            if {[lindex $cmd 0] eq "wm-menu"} {
                dict set e said [lindex $cmd 2]
            }
        }
        lappend out $e
    }
    dict create elements $out
}
# The bindings are TWO lists in one: the keymap walked live — every
# chord the desk actually answers to — and then the layer words a
# LATER word buried (the owner's decision 5: last wins, custom over
# config). A buried wm-bind is not in the keymap at all, but the
# user's file still says it, so the table serves it flagged
# `ineffectual` — the tree gets to mark the bind that does nothing
# instead of pretending it was never written.
# WHO ANSWERS this chord sequence now, and everything one would need
# to say so to a human before taking it: the deed itself, whose word
# it is, the file and line it was said on when it came from a file,
# and — for a family's chord — the parameters that family stands on,
# which is what tells «chords» from «chords under another prefix»
# (the owner's ask, 2026-08-01). Empty when the chord is free, which
# is the answer that needs no dialog.
proc chord-holder {spec} {
    if {[catch {lmap tok $spec {join [parse-chord $tok] ,}} pk]} { return "" }
    set live [keymap-payload $::keymap $pk]
    if {$live eq ""} { return "" }
    set origin [keymap-origin $::keymap $pk]
    set out [dict create script [lindex $live 0] name [lindex $live 1] \
                 who $origin]
    set where [keymap-where $::keymap $pk]
    if {$where ne ""} { dict set out where $where }
    if {[lindex $origin 0] eq "bundle"
            && [dict exists $::key_bundles [lindex $origin 1]]} {
        dict set out params \
            [dict get $::key_bundles [lindex $origin 1] params]
    }
    return $out
}
proc keymap-where {node keys} {
    set k [lindex $keys 0]
    if {![dict exists $node $k]} { return "" }
    set entry [dict get $node $k]
    if {[llength $keys] == 1} {
        return [expr {[lindex $entry 0] eq "map" ? "" : [lindex $entry 4]}]
    }
    if {[lindex $entry 0] ne "map"} { return "" }
    return [keymap-where [lindex $entry 1] [lrange $keys 1 end]]
}

proc collection-bindings {} {
    set out [keymap-elements $::keymap {} {}]
    # ONE ROW PER CHORD, and the losers hang UNDER it. A layer word
    # that does not answer used to be an element of its own, so a
    # chord two layers had spoken about wore two rows with the same
    # name and no relation between them — «как-то не очень понятно
    # всё в целом» (the owner, 2026-08-01). Now the live word carries
    # its claimants: same information, one story.
    #
    # A word whose chord answers NOTHING keeps a row of its own —
    # there is no live row to hang it on, and it must still be
    # visible to be taken back.
    set orphans {}
    foreach layer {custom config} {
        if {![dict exists $::layer_knobs $layer]} continue
        dict for {k cmd} [dict get $::layer_knobs $layer] {
            if {[lindex $k 0] ne "wm-bind"} continue
            # A SILENCE IS A WORD TOO (the owner, 2026-08-02): an
            # unbind that buried somebody's bind used to leave no row
            # at all — so the promise Delete makes, «Delete on that
            # takes it back and the chord returns», had nothing to
            # land on. The silence stands as a row of its own, owner
            # and lkey riding it so Delete and «Erase my word» work
            # unchanged; what it silenced hangs under it, the same
            # way a live word carries its claimants.
            if {[lindex $cmd 0] eq "wm-unbind"} {
                if {[catch {lmap tok [lindex $cmd 1] \
                                {join [parse-chord $tok] ,}} pk]} continue
                if {[keymap-payload $::keymap $pk] ne ""} continue
                set chord [join [lmap c $pk {chord-name {*}[split $c ,]}] " "]
                lappend out [dict create key $chord \
                    values [dict create script "" name ""] \
                    owner $layer lkey $k ineffectual 1 \
                    why "your silence — what it covers hangs under it;\
 Delete takes the silence back and the chord returns"]
                continue
            }
            if {[lindex $cmd 0] ne "wm-bind"} continue
            if {[catch {lmap tok [lindex $cmd 1] \
                            {join [parse-chord $tok] ,}} pk]} continue
            # WHOSE the chord is now is the leaf's own word, not a
            # guess from matching script texts
            if {[keymap-origin $::keymap $pk] eq $layer} continue
            set chord [join [lmap c $pk {chord-name {*}[split $c ,]}] " "]
            set claim [dict create owner $layer lkey $k \
                script [lindex $cmd 2] name [lindex $cmd 3]]
            # a row with this chord — live, or a silence made above —
            # takes the buried word as its claimant; only a chord no
            # row shows at all is an orphan row of its own
            set attached 0
            set out [lmap e $out {
                if {[dict get $e key] ne $chord} { set e } else {
                    set attached 1
                    dict lappend e shadowed $claim
                }
            }]
            if {!$attached} {
                lappend orphans [dict create key $chord \
                    values [dict create script [lindex $cmd 2] \
                                name [lindex $cmd 3]] \
                    owner $layer lkey $k ineffectual 1 \
                    why "not in force — nothing answers this chord now"]
            }
        }
    }
    # ...AND THE CODE'S OWN WORD under whoever took its chord: the
    # desk's defaults and the bundles' binds are not layer words, so
    # the scan above cannot see them — the «would say» table
    # (code_binds) can. A chord whose live word IS the record's owner
    # needs no claimant; anything else — a layer's bind, a layer's
    # silence — stands over the code's word and says so.
    set claimed {}
    foreach e $out {
        if {![catch {lmap tok [split [dict get $e key] " "] \
                         {join [parse-chord $tok] ,}} pk]
                && [dict exists $::code_binds $pk]
                && [keymap-origin $::keymap $pk] \
                       ne [dict get $::code_binds $pk origin]} {
            set rec [dict get $::code_binds $pk]
            set claim [dict create owner code \
                script [dict get $rec script] name [dict get $rec name]]
            if {[lindex [dict get $rec origin] 0] eq "bundle"} {
                dict set claim bundle [lindex [dict get $rec origin] 1]
            }
            dict lappend e shadowed $claim
        }
        lappend claimed $e
    }
    dict create elements [concat $claimed $orphans]
}
# Whose, in words a sentence can carry.
proc owner-words {origin} {
    if {[lindex $origin 0] eq "bundle"} { return "the [lindex $origin 1] family's" }
    switch -- $origin {
        custom { return "your" }
        config { return "the config's" }
    }
    return "the desk's own"
}
proc keymap-elements {node path disp} {
    set out {}
    dict for {k entry} $node {
        lassign [split $k ,] mods ks
        set p2 [concat $path [list $k]]
        set d2 [concat $disp [list [chord-name $mods $ks]]]
        lassign $entry kind payload
        if {$kind eq "map"} {
            lappend out {*}[keymap-elements $payload $p2 $d2]
        } else {
            # a leaf is {action SCRIPT NAME ORIGIN}, and the origin is
            # the answer to «whose word is this» — asked of the binding
            # itself instead of reconstructed from the layers
            lassign $entry - script bname origin where
            set owner $origin
            if {[lindex $origin 0] eq "bundle"} { set owner code }
            set e [dict create key [join $d2 " "] \
                values [dict create script $script name $bname] \
                owner $owner]
            # the layer's own key — spelled as the writer spelled the
            # chords, which is what an erase must be addressed by
            set lkey [binding-key $owner $p2]
            if {$lkey ne ""} { dict set e lkey $lkey }
            if {$lkey ne "" && [dict exists $::custom_effect $lkey]} {
                dict set e effect [dict get $::custom_effect $lkey]
            }
            # ...and the line it was said on, for whoever has to be
            # told WHERE the word they are fighting with lives
            if {$where ne ""} { dict set e where $where }
            if {[lindex $origin 0] eq "bundle"} {
                dict set e bundle [lindex $origin 1]
            }
            lappend out $e
        }
    }
    return $out
}
# UNDER WHICH KEY the owning layer holds this binding — the address an
# erase has to be given. Only the address: whose the binding is, the
# leaf now says itself. Parsed chords, not spec spellings: <Super>9
# and <super>9 are one chord, while the layer key holds whichever
# spelling the writer used, which is exactly why it is handed back
# rather than reconstructed.
proc binding-key {layer keys} {
    if {$layer ni {custom config}} { return "" }
    if {![dict exists $::layer_knobs $layer]} { return "" }
    dict for {k cmd} [dict get $::layer_knobs $layer] {
        if {[lindex $k 0] ne "wm-bind"} continue
        if {[lindex $cmd 0] ne "wm-bind"} continue
        if {[catch {lmap tok [lindex $cmd 1] \
                        {join [parse-chord $tok] ,}} pk]} continue
        if {$pk eq $keys} { return $k }
    }
    return ""
}
# The keymap's word at a chord sequence: {SCRIPT ?NAME?} with the
# action tag stripped, or empty — absent, pruned, or a map where a
# binding was asked for.
proc keymap-payload {node keys} {
    set k [lindex $keys 0]
    if {![dict exists $node $k]} { return {} }
    set entry [dict get $node $k]
    lassign $entry kind payload
    if {[llength $keys] == 1} {
        # {SCRIPT NAME} — the origin is the leaf's fourth word and has
        # its own reader (keymap-origin)
        return [expr {$kind eq "map" ? {} : [lrange $entry 1 2]}]
    }
    if {$kind ne "map"} { return {} }
    return [keymap-payload $payload [lrange $keys 1 end]]
}
# collection-table — the send-facing answer, the configurator's whole
# view of the families: the registry, and whatever each collection's
# list script serves — the elements, plus the meta only the live
# state knows (a button set's `owned`).
proc collection-table {} {
    set out {}
    dict for {name meta} [config-families] {
        dict set out $name [dict merge $meta [collection-verb $name] \
                                [uplevel #0 [dict get $meta list]]]
    }
    return $out
}
# WHICH WORD SAYS THIS FAMILY, AND IN WHAT SHAPE — read off the verb
# registry rather than written down a second time. A family is a
# node; the word that says it is the one whose `at` lands there and
# which is not a denial or a sweep. The SHAPE is what an editor needs
# to build a call without knowing the family by name (config-tree,
# step 3): `spec` and `overrides` take a delta dict, `options` a whole
# option dict spread into the call, `pair` positional values, and
# `params` dashed ones.
proc collection-verb {name} {
    dict for {verb meta} $::verb_registry {
        if {[lindex [dict get $meta at] 0] ne $name} continue
        if {[dict exists $meta denies] || [dict exists $meta sweep]} continue
        return [dict create verb $verb \
            layer-key [dict get $meta key] \
            shape [expr {[dict exists $meta value]
                         ? [dict get $meta value] : "spec"}]]
    }
    return {}
}

# The traced vocabulary derives from the registry — one list, not two
# — plus the named declarations, which are traced per name rather
# than rendered as knobs.
# ---- the verb registry: what a word of the config TOUCHES ----
# Three tables described this desk's configuration and none of them
# described the same thing: the knobs (what a knob IS and how to show
# it), the collections (what a family serves the editor), the specs
# (what an action may carry). The one fact none of them held is the
# one everything else is derived from — WHERE IN THE CONFIGURATION a
# word lands, and what shape the thing it leaves there has.
#
# So: a verb, the node it touches, and how its arguments make that
# node's address and value. `at` is the path with @1 standing for the
# verb's first argument; `key` is the name the layers file it under
# (a negative word files under the word it denies, which is what
# makes «my last word about this» a single entry); `section` marks
# the words whose DECLARATION ORDER is meaning rather than noise, and
# its number is the order the sections go out in.
#
# What this replaces so far: the hand-written switch in knob-key and
# the hand-written list of ordered sections in custom-save. What it
# is FOR is the tree — see plans/tk9wm-config-tree.md.
proc config-verb {name meta} { dict set ::verb_registry $name $meta }
set verb_registry {}
# NOT VOCABULARY, and said so. This layer's own primitives are spelled
# `set-*` like the words a config uses (set-prop-longs, set-wm-state),
# and so are one or two words that exist but are nobody's business to
# say out loud yet. Without a declaration the audit below cannot tell
# them apart from a word somebody forgot to register — and telling them
# apart is exactly what a descriptor is for (the lifecycle plan's step
# two; the owner, 2026-08-04: "panel live colors на данный момент
# внутрянка").
set config_internal {}
proc config-internal {args} {
    foreach name $args { dict set ::config_internal $name 1 }
}
config-internal set-prop-longs set-prop-utf8 set-wm-state set-net-wm-state
config-internal set-key-help set-panel-live-colors
config-verb wm-bind           {at {bindings @1} key wm-bind      value pair}
config-verb wm-unbind         {at {bindings @1} key wm-bind      denies 1}
config-verb action            {at {actions @1}  key action       spec action}
config-verb action-remove     {at {actions @1}  key action       denies 1}
config-verb wm-widget         {at {widgets @1}  key wm-widget    value options section 2}
config-verb wm-widget-remove  {at {widgets @1}  key wm-widget    denies 1}
config-verb panel-button      {at {panel @1}    key panel-button value overrides section 4}
config-verb panel-buttons-own {at {panel @1}    key panel-buttons-own sweep 1 section 3}
config-verb wm-font           {at {fonts @1}    key wm-font      value options section 1}
config-verb wm-look           {at {looks @1}    key wm-look      value spec}
config-verb wm-keys           {at {keys @1}     key wm-keys      value params}
config-verb wm-menu           {at {menus @1}    key wm-menu      spec menu}
config-verb wm-menu-remove    {at {menus @1}    key wm-menu      denies 1}
config-verb winops-item        {at {winops @1}   key winops-item  value options}
config-verb winops-item-remove {at {winops @1}   key winops-item  denies 1}
config-verb command-state      {at {states @1}   key command-state value word}
# A word without a knob: sayable, and therefore guarded, but with no
# row in the configurator — its value is a list of six-word monitor
# rectangles, which is a repair tool and a test seam rather than
# something to turn.
config-verb set-monitors {at {knobs set-monitors} key set-monitors value word}
# ...and every knob, which is the plain case: no address of its own
# beyond its name, one value, and the type the knob registry states.
dict for {name meta} [knob-registry] {
    config-verb $name [list at [list knobs $name] key $name value word \
        kind [dict get $meta kind]]
}
# GENERATED HERE, where the registry is finally complete and before
# anything can be said: sixteen words that were sixteen bodies saying
# the same three things (check, write the wish, ask for the deed).
# What is left hand-written is hand-written for a reason, and each
# reason is now visible instead of buried in a body that looked like
# all the others.
puts "WM: knob words generated: [knobs-define]"
set knob_vocab [dict keys $verb_registry]
set knob_layer ""
keep layer_knobs {}    ;# layer -> key -> the full command, per load cycle
# The key is semantic: a plain knob is one key however often it is
# called (the last call wins in Tcl exactly as in the file), a named
# declaration is one key PER NAME.
# ---- a word that fails does not take the file down with it ----
# A config used to die where a word threw: the line was reported and
# everything BELOW it never ran. One mistyped chord cost the owner his
# whole panel section, and nothing about the missing panel pointed at
# the typo three sections up (2026-08-01).
#
# So every verb carries a guard, and the guard is the Common Lisp
# shape the owner asked for — `handler-bind` with a `continue`
# restart: while a LAYER is being read, a failure is recorded and the
# word simply returns, so the file goes on; anywhere else it is
# re-thrown, because an interactive caller (the applet, custom-write)
# must see what it did.
#
# Two ways to wear it, and the measurement (whale9, 2026-08-01) says
# which is for what. `config-proc` puts the guard in at the point of
# definition and keeps the body's file and line. Instrumenting an
# EXISTING proc rewrites its body — no extra stack level, `uplevel 1`
# still means the caller, the arg spec and defaults survive — but the
# body loses its binding to the file it was written in. For OUR
# vocabulary that costs nothing (the provenance walk skips our own
# files anyway), which is why the whole registry is instrumented in
# one loop instead of thirty definitions being rewritten by hand.
proc config-word-failed {verb err opts} {
    if {![info exists ::knob_layer] || $::knob_layer eq ""} {
        return -options $opts $err
    }
    problem-record "config word $verb" $err [said-where]
    return ""
}
proc config-guarded-body {verb body {arg ""}} {
    # the body starts on the SAME LINE as the opening of try, so a
    # body that still has line information keeps its numbering — and
    # the precheck rides on that same line for the same reason
    set gate ""
    if {$arg ne ""} { set gate "knob-precheck [list $verb] \$$arg; " }
    return "try {$gate$body} on error {e o} {config-word-failed [list $verb] \$e \$o}"
}
# WHICH WORDS THE GATE FITS: a knob whose word takes exactly one
# argument, which is the plain scalar case. The rest — option lists,
# collections, words with a path of their own — are the config-tree
# plan's half and check themselves for now.
proc config-gate-arg {name} {
    if {![dict exists [knob-registry] $name]} { return "" }
    if {[catch {info args $name} as] || [llength $as] != 1} { return "" }
    return [lindex $as 0]
}
proc config-proc {name spec body} {
    proc $name $spec [config-guarded-body $name $body]
}
proc config-instrument {name} {
    if {![llength [info commands $name]]} { return 0 }
    if {[catch {info body $name} body]} { return 0 }   ;# not a proc: a C command
    # ...already wearing one? Asked by SUBSTRING rather than by a glob
    # of the whole wrapper — which would have to carry an unbalanced
    # brace, and Tcl counts braces inside a proc body whatever they
    # are quoted with. (A backslash IS enough where one is really
    # wanted — `set x "\{"` parses fine — but a substring says the
    # same thing without the escape, and this line cost a load once
    # already, 2026-08-01.)
    if {[string first "config-word-failed" $body] >= 0} { return 0 }
    set spec {}
    foreach a [info args $name] {
        if {[info default $name $a def]} {
            lappend spec [list $a $def]
        } else {
            lappend spec $a
        }
    }
    proc $name $spec [config-guarded-body $name $body [config-gate-arg $name]]
    return 1
}
proc config-instrument-vocabulary {} {
    set n 0
    dict for {verb -} $::verb_registry { incr n [config-instrument $verb] }
    return $n
}

proc knob-key {words} {
    set p [lindex $words 0]
    if {![dict exists $::verb_registry $p]} { return $p }
    set meta [dict get $::verb_registry $p]
    set key [dict get $meta key]
    # a verb whose node is addressed by its first argument is filed
    # per address; one that is not is filed under itself
    if {"@1" in [dict get $meta at]} { return "$key [lindex $words 1]" }
    return $key
}
proc knob-touched {cmd op} {
    if {$::knob_layer eq ""} return
    # Only the file's OWN calls: a knob calling another knob inside
    # (set-title-font is wm-font TitleFont) fires the trace too, and
    # recording it would double every overlap line. The callback runs
    # in the traced command's caller — level 1 here means "called
    # from the sourced file's top level".
    if {[info level] != 1} return
    if {[catch {knob-key $cmd} key]} return
    # THE SAME WORD IN TWO OF YOUR FILES is possible now that the
    # custom layer comes in pieces, so it is reported rather than
    # silently resolved: the later one wins, exactly as within a file.
    if {[dict exists $::layer_knobs $::knob_layer $key]
            && [info exists ::layer_where]
            && [dict exists $::layer_where $::knob_layer $key]} {
        set was [lindex [dict get $::layer_where $::knob_layer $key] 0]
        set now [lindex [said-where] 0]
        if {$was ne "" && $now ne ""
                && [file dirname $was] ne ""
                && [lindex [split $was :] 0] ne [lindex [split $now :] 0]} {
            problem-record "$::knob_layer layer" "«$key» is said in two of\
 your files — $was and $now. The later one wins; the earlier is dead\
 weight." [said-where]
        }
    }
    dict set ::layer_knobs $::knob_layer $key $cmd
    # ...AND WHERE IT WAS SAID. A binding has carried its chain since
    # the provenance step; a knob had nowhere to keep one, so «open
    # the line that sets this» had nothing to open. The trace runs
    # under the statement itself, so the chain here is the same one
    # said-where gives a binding: the config's line first, then
    # whoever called it.
    dict set ::layer_where $::knob_layer $key [said-where]
}
# Where a knob was set, as a chain of file:line — by default the word
# IN FORCE, which is what a row is asking when it asks where its value
# comes from. It used to answer for the CONFIG whatever the row's own
# word was, on the reasoning that the custom file is written by click
# and nobody edits it by hand (2026-08-02) — and that made two rows of
# one tree answer differently: a BINDING of yours named the custom file
# it was written in (its chain is recorded where the bind happened,
# whatever layer that was), while a KNOB of yours said the config does
# not mention it, which is true and useless (the owner, 2026-08-03).
# Naming the file is not an invitation to edit it — that file says what
# it is in its own first line — and it is the honest answer to where
# the value is written down. Ask for a layer by name to see what a
# word STANDS ON.
#
# Empty when that layer never said it, or when the word came from
# somewhere provenance skips: the desk's own library (so the default
# config, which lives there, has no line to point at), the entry
# script, or a click that no file has caught up with yet.
proc knob-where {name {layer ""}} {
    if {![info exists ::layer_where]} { return "" }
    if {$layer eq ""} { set layer [knob-owner $name] }
    if {![dict exists $::layer_where $layer $name]} { return "" }
    return [dict get $::layer_where $layer $name]
}
proc layer-source {layer path} {
    foreach p $::knob_vocab {
        if {[llength [info commands $p]]} {
            trace add execution $p enter knob-touched
        }
    }
    set ::knob_layer $layer
    set code [catch {uplevel #0 [list source $path]} err opts]
    set ::knob_layer ""
    foreach p $::knob_vocab {
        catch {trace remove execution $p enter knob-touched}
    }
    # ...and the WHERE along with the what: the stack's tail names the
    # file and line of the statement that threw, which is what a
    # failed load must put in the log (see load-config).
    list $code $err [expr {$code ? [dict get $opts -errorinfo] : ""}]
}
proc layer-touched {layer} {
    expr {[dict exists $::layer_knobs $layer]
          ? [dict keys [dict get $::layer_knobs $layer]] : {}}
}
proc layer-overlaps {} {
    set out {}
    if {![dict exists $::layer_knobs config]
            || ![dict exists $::layer_knobs custom]} { return $out }
    foreach key [dict keys [dict get $::layer_knobs custom]] {
        if {[dict exists $::layer_knobs config $key]} { lappend out $key }
    }
    return $out
}
# ---- what a customization actually DOES ----
# Two kinds of word live in the custom layer, and they look identical
# in it (the owner's distinction, 2026-08-01): one CHANGES a setting
# against what the layers below would have given, the other PINS what
# is already so — «let this stop depending on the config or on the
# code». A `take` out of a bundle is the second kind on purpose, so
# nothing here may go dropping them by itself.
#
# Telling them apart needs the state as it would be WITHOUT the custom
# layer, and there is exactly one moment when that state really
# exists: the reload, between the config and the custom layer. So the
# judgement is made there and remembered, rather than guessed at
# afterwards from values that already have the custom word in them.
keep custom_effect {}   ;# custom key -> pin | change
keep custom_floor {}    ;# the state the layers below left, at the snapshot

proc custom-floor-snapshot {} {
    set knobs {}
    dict for {name meta} [knob-registry] {
        catch {dict set knobs $name [uplevel #0 [dict get $meta get]]}
    }
    set ::custom_floor [dict create knobs $knobs actions $::action_raw \
        keymap $::keymap widgets $::widgets bundles $::key_bundles]
}
# ...and afterwards, key by key: does what we said differ from what
# stood there without us? The comparison is per VERB, because each
# knows where its subject lives.
proc custom-effect-judge {} {
    set ::custom_effect {}
    if {![dict exists $::layer_knobs custom]} return
    set floor $::custom_floor
    dict for {key cmd} [dict get $::layer_knobs custom] {
        set verb [lindex $cmd 0]
        set name [lindex $cmd 1]
        set same 0
        switch -- $verb {
            wm-bind {
                if {![catch {lmap t $name {join [parse-chord $t] ,}} pk]} {
                    set was [keymap-payload [dict get $floor keymap] $pk]
                    set now [keymap-payload $::keymap $pk]
                    set same [expr {$was ne "" && [lindex $was 0] eq [lindex $now 0]}]
                }
            }
            action {
                set was [expr {[dict exists $floor actions $name]
                               ? [dict get $floor actions $name] : ""}]
                set now [expr {[dict exists $::action_raw $name]
                               ? [dict get $::action_raw $name] : ""}]
                set same [expr {$was eq $now}]
            }
            wm-widget {
                set was [expr {[dict exists $floor widgets $name]
                               ? [dict get $floor widgets $name] : ""}]
                set now [expr {[dict exists $::widgets $name]
                               ? [dict get $::widgets $name] : ""}]
                set same [expr {$was eq $now}]
            }
            wm-keys {
                set was [expr {[dict exists $floor bundles $name]
                               ? [dict get $floor bundles $name] : ""}]
                set now [expr {[dict exists $::key_bundles $name]
                               ? [dict get $::key_bundles $name] : ""}]
                set same [expr {$was eq $now}]
            }
            default {
                # a plain knob answers what it holds; the floor kept
                # what it held before we spoke
                if {[config-node-of [list knobs $verb]] ne ""
                        && [dict exists $floor knobs $verb]} {
                    catch {
                        set now [uplevel #0 \
                            [dict get [config-node-of [list knobs $verb]] get]]
                        set same [expr {$now eq [dict get $floor knobs $verb]}]
                    }
                }
            }
        }
        dict set ::custom_effect $key [expr {$same ? "pin" : "change"}]
    }
}
# The overview: what we have said, sorted into the two kinds. A pin is
# not a mistake — this only counts them and hands the list over.
proc custom-audit {} {
    set changes {}
    set pins {}
    dict for {key what} $::custom_effect {
        if {$what eq "pin"} { lappend pins $key } else { lappend changes $key }
    }
    dict create changes $changes pins $pins
}
# ...and the sweep, which takes NAMED keys and nothing else: the
# caller shows the list and asks, because «this says what the layer
# below says» and «I meant it to stop depending on that layer» are
# the same word seen from two sides (see take).
proc custom-drop {keys} {
    set gone 0
    foreach key $keys {
        if {![dict exists $::layer_knobs custom $key]} continue
        dict unset ::layer_knobs custom $key
        incr gone
    }
    if {$gone} {
        custom-save
        puts "WM: custom: dropped $gone word(s) that changed nothing"
        reload-config
    }
    return $gone
}

# custom-write COMMAND — a customization is born: recorded under its
# key, persisted, and run on the live desk in the same breath. The
# file is rewritten WHOLE in a canonical style (one call per line,
# sorted by key) and moved into place atomically — it is machine-owned
# and says so in its header, which is what makes rewriting it safe.
# ---- THE CUSTOM LAYER IN PIECES (the owner, 2026-08-02) -----------
# «Главный кастом-файл соурсит дополнительные, настройка приземляется
# туда, где она определена. Юз кейс — а эту панель буду хранить у себя
# в гите.» So: one verb, sourced in place, and the includes go at the
# TOP of the main file — the main file's own words are written after
# them and therefore win, which keeps «custom is the last word» true
# inside the layer as well as outside it.
#
# A word's HOME is the file that says it, which the provenance already
# knows (layer_where, from the same said-where the tree shows). A word
# said for the first time by a click has no home yet and lands in the
# main file.
keep custom_includes {}   ;# paths the main file pulls in, in order
keep custom_home {}       ;# key -> the file of the custom layer that says it
proc custom-include {path} {
    catch {set path [file tildeexpand $path]}
    set path [file normalize $path]
    if {$path ni $::custom_includes} { lappend ::custom_includes $path }
    if {![file exists $path]} {
        puts "WM: custom-include $path — not there yet; it will be\
 written when something lands in it"
        return
    }
    uplevel #0 [list source $path]
}
# Read off the provenance once a layer has been read: the first link
# of a word's chain is the file it stands in.
proc custom-homes {} {
    set ::custom_home {}
    if {![dict exists $::layer_knobs custom]} return
    dict for {key -} [dict get $::layer_knobs custom] {
        set chain [knob-where $key custom]
        if {![llength $chain]} continue
        set place [lindex $chain 0]
        if {![regexp {^(.*):\d+$} $place -> file]} continue
        dict set ::custom_home $key $file
    }
}
# WHAT THE CUSTOM FILE ALREADY SAYS about this command's key — «» when
# it says nothing. The editor asks before it records a change: a line
# that would write the file exactly as it already stands is not an
# edit, whatever it does to the desk. Note this is the FILE's word,
# not the desk's live state: a preview runs in the custom layer's name
# but is not filed under it (only a layer being loaded records here),
# which is what makes the comparison honest.
proc custom-word {command} {
    if {[catch {knob-key $command} key]} { return "" }
    if {![dict exists $::layer_knobs custom $key]} { return "" }
    return [dict get $::layer_knobs custom $key]
}
proc custom-write {command {by desk}} {
    if {[catch {knob-key $command} key]} {
        error "custom-write: not a command list: $command"
    }
    # SAID BEFORE IT IS WRITTEN DOWN. It used to be recorded and
    # saved first and run after, so a word the desk REFUSES still
    # landed in the file — and a file with a word that throws stops
    # loading THERE, taking every line under it with it. The owner
    # typed one chord wrong (`super+t r w`, and the desk spells its
    # modifiers Super) and lost his whole panel section on the next
    # load: the strip stopped reordering and flickered, and nothing
    # about that pointed at a typo three sections up (2026-08-01).
    #
    # Said IN THE CUSTOM LAYER'S NAME, because a live edit is the
    # custom layer's word exactly as the replay of it will be (say-as).
    say-as custom { uplevel #0 $command }
    dict set ::layer_knobs custom $key $command
    custom-save
    if {[dict exists $::layer_knobs config $key]} {
        puts "WM: custom overrides the config: $key"
    }
    puts "WM: custom: $command"
    ui-layer-push $key $by
}
# ...AND WHOEVER IS LOOKING AT THE LAYER IS TOLD. There is one writer
# for the custom layer and always was — the configurator's edits come
# here over the send door, the desk's own words (the welcome mat
# retiring itself) call it directly — but only the writer knew. So an
# applet standing open showed the layer as it was BEFORE: the owner
# hid the mat from the desk and the configurator went on offering him
# `set-welcome on` (2026-08-02). This is the other half, and it is
# what the desk's own future words need — «pin this window by
# WM_CLASS to where it stands» writes custom from a keystroke, with
# the editor open beside it.
#
# Asynchronous on purpose: the writer must not wait on a window, and
# a host that is not there is not an error.
proc ui-layer-push {key by} {
    if {"tk9wm-ui" ni [winfo interps]} return
    catch {send -async -- tk9wm-ui [list ui-layer-changed custom $key $by]}
}
# The verbs whose declaration order is meaning, in the order their
# sections go out — the registry says both (see config-verb).
proc config-ordered-verbs {} {
    set by {}
    dict for {name meta} $::verb_registry {
        if {[dict exists $meta section]} {
            dict set by [dict get $meta section] $name
        }
    }
    set out {}
    foreach n [lsort -integer [dict keys $by]] { lappend out [dict get $by $n] }
    return $out
}
proc custom-save {} {
    set entries {}
    if {[dict exists $::layer_knobs custom]} {
        set entries [dict get $::layer_knobs custom]
    }
    # EACH FILE GETS ITS OWN WORDS. A word written by a click has no
    # home and lands in the main file; a word that came out of an
    # included file goes back to it, which is what «эту панель буду
    # хранить у себя в гите» means in practice.
    set main [custom-path]
    set byfile [dict create $main {}]
    foreach path $::custom_includes { dict set byfile $path {} }
    dict for {key cmd} $entries {
        set home $main
        if {[dict exists $::custom_home $key]
                && [dict get $::custom_home $key] in $::custom_includes} {
            set home [dict get $::custom_home $key]
        }
        dict set byfile $home [dict merge \
            [dict get $byfile $home] [dict create $key $cmd]]
    }
    dict for {path part} $byfile {
        custom-emit $path $part [expr {$path eq $main}]
    }
}
proc custom-emit {path entries main} {
    file mkdir [file dirname $path]
    set tmp $path.tmp
    set ch [open $tmp w]
    puts $ch "# tk9wm customizations — MACHINE-WRITTEN, do not edit by hand:"
    puts $ch "# the configurator rewrites this file whole. Hand-written"
    puts $ch "# configuration belongs in tk9wm.tcl, which loads BEFORE this"
    puts $ch "# file; on overlap the desk says so in its log."
    # the includes go FIRST, so this file's own words are the later
    # ones and win — and so a file kept elsewhere (a panel in one's
    # own git) is pulled in before anything here refines it
    if {$main && [llength $::custom_includes]} {
        puts $ch ""
        foreach inc $::custom_includes { puts $ch [list custom-include $inc] }
        puts $ch ""
    }
    # Which entries keep their DECLARATION ORDER, and which are
    # sorted for a stable diff (the owner's call): fonts derive from
    # one another, widgets share an area in order, and an owned
    # panel IS its buttons' order. Those go out in SECTIONS, kind by
    # kind, with panel-buttons-own directly above the buttons —
    # replayed, the sweep must come before what it would otherwise
    # sweep, whenever either was written. Bindings are a map keyed
    # by chord, plain knobs a map keyed by name — nothing about
    # their order means anything, so they sort.
    set sorted {}
    foreach kind [config-ordered-verbs] { set section($kind) {} }
    dict for {key cmd} $entries {
        set p [lindex $key 0]
        if {[info exists section($p)]} {
            lappend section($p) $cmd
        } else {
            lappend sorted $key
        }
    }
    # A BUNDLE FALLS SILENT BEFORE SINGLE WORDS SPEAK: a disassembled
    # family (decision 4) is `wm-keys B off` plus the kept binds as
    # plain wm-bind — and replayed alphabetically the binds landed
    # first and the off then swept their chords away with the family's
    # (an off unbinds whatever the previous instance bound). So the
    # wm-keys words go out ahead of everything else in the map.
    foreach key [lsort $sorted] {
        if {[lindex $key 0] eq "wm-keys"} { puts $ch [dict get $entries $key] }
    }
    foreach key [lsort $sorted] {
        if {[lindex $key 0] ne "wm-keys"} { puts $ch [dict get $entries $key] }
    }
    set ordered {}
    foreach kind [config-ordered-verbs] { lappend ordered {*}$section($kind) }
    if {[llength $ordered]} {
        puts $ch ""
        puts $ch "# ...and the ordered declarations, in the order they were made:"
        puts $ch "# fonts derive, buttons lay out and widgets share an area BY ORDER."
        foreach cmd $ordered { puts $ch $cmd }
    }
    close $ch
    file rename -force $tmp $path
}

# Readable ink for a given background — the two-way fork only (light
# ink on dark ground, dark ink on light), decided by relative
# luminance. What it exists for is anything drawn ON the user's own
# colors: the welcome text sits directly on set-desk-background, and
# black-on-black is the failure this refuses to have.
proc contrast-fg {bg} {
    lassign [winfo rgb . $bg] r g b
    expr {(0.2126*$r + 0.7152*$g + 0.0722*$b) / 65535.0 > 0.5
          ? "#1c1c1c" : "#eeeeec"}
}
proc contrast-link {bg} {
    lassign [winfo rgb . $bg] r g b
    expr {(0.2126*$r + 0.7152*$g + 0.0722*$b) / 65535.0 > 0.5
          ? "#1a4a8a" : "#8ab4f8"}
}

# The welcome mat: the desk invites its user to the configurator, in
# plain text on the desk itself — config or no config (the owner's
# call: the note is about the configurator existing, not about the
# desk being fresh). It stays until "hide forever", whose click
# writes a customization (set-welcome off) — for a fresh user, their
# very first: the invitation dogfoods the layer it invites you to
# use. A config may also just say set-welcome off.
keep welcome on
# The mat's widget is named `welcome`, plainly: it used to be
# __welcome, and the underscores read as machinery for no reason a
# reader could find (the owner, 2026-08-11) — the widgets tree is
# where the mat shows, and it should show under the name one would
# say. The off-path checks the TYPE before it unsets: a user's own
# widget that happens to be called welcome is not the mat, and
# set-welcome off must not swallow it (welcome-inject already yields
# the name — its guard is existence, not type).
proc set-welcome {mode} {
    if {$mode ni {on off}} { error "set-welcome: on or off" }
    set ::welcome $mode
    if {$mode eq "off" && [dict exists $::widgets welcome]
            && [dict get $::widgets welcome -type] eq "welcome"} {
        dict unset ::widgets welcome
    }
    # ...and ON puts the mat back, through the settler that does it —
    # which also rebuilds the widgets it lives among.
    settle-soon welcome
    settle-soon widgets
}
proc welcome-inject {} {
    if {$::welcome ne "on"} return
    if {[dict exists $::widgets welcome]} return
    # No colours in the DECLARATION: they would be frozen at the
    # moment of injection, and the mat then kept the old ground while
    # the desk changed under it (the owner, mid-experiment with
    # set-desk-background). The build reads the desk's colour when it
    # runs, and a rebuild is what every colour change already does.
    wm-widget welcome -type welcome -on workarea -place center
}

# ---- applets: the ui host and the door to it ----
# One host process, one Tk, every applet a toplevel — see
# library/ui/host.tcl for the host's own contract (disposable
# resident: survives a WM restart on purpose, holds nothing durable).
#
# HOW THE HOST IS EXEC'D reuses the self-exec machinery's answer
# (the owner's instruction): reexec-head already knows what
# interpreter this desk runs on, in the form the four measured
# startup shapes require — and whatever whale carries the WM
# certainly carries the ui. The interpreter+script form hands us the
# interpreter; a bare-executable form (starpack, zipfs image) re-runs
# its own baked script and cannot run ours — such an image provides
# ::tk9wm_uiexec, the mirror of ::tk9wm_reexec, same contract: a
# wrapper that KNOWS says so.
proc ui-exec-head {} {
    if {[info exists ::tk9wm_uiexec]} { return $::tk9wm_uiexec }
    set head [reexec-head]
    if {[llength $head] == 1} { return {} }
    list [lindex $head 0]
}
# ...AND THE BRIDGE IS PUSHED, not only pulled. The host syncs when
# it opens an applet, which is enough for what it opens NEXT and
# nothing at all for what is already on the screen: the owner changed
# the desk font four times over and the configurator kept the type it
# was born with. So every change that alters ui-style tells the host
# to re-read it — asynchronously, because a WM that waits on an
# applet is a desk that stops.
proc ui-restyle {} {
    if {"tk9wm-ui" ni [winfo interps]} return
    catch {send -async -- tk9wm-ui ui-style-sync}
}
# ...and FRESHNESS is pushed beside the style, for the applets
# already on the screen: a Reread and a WM start both mean «the ui
# code on disk may have moved under the resident host», and the pull
# half of the stale check (ui-open) is a door no OPEN applet passes
# through — the owner's Alt-Up case. Async for the same reason
# ui-restyle is; a current host shrugs the nudge off, a stale one
# hands its open applets to a successor (ui-freshen in the host).
proc ui-freshen-push {} {
    if {"tk9wm-ui" ni [winfo interps]} return
    catch {send -async -- tk9wm-ui ui-freshen}
}
# ui-style — the bridge from the desk's look to the applets' (the
# owner's ask: the fonts must ARRIVE; and at least one light scheme).
# The host asks over the send door and applies what it is told, so an
# applet is set in the desk's own fonts, and dressed in the desk's own
# THEME. It used to guess the scheme from the luminance of
# set-desk-background, which was the honest stopgap while the WM's own
# chrome had no theme to speak of; now that it has one the guess is
# gone, and an applet wears whatever set-theme says — including when
# somebody overrides the desk colour alone, where the guess used to
# flip the configurator out from under a desk that had not changed.
proc ui-style {} {
    set palette {}
    foreach {key role} {bg ground fg ink field field link link
                        select select trough trough
                        modal modal edge edge} {
        lappend palette $key [themed $role]
    }
    dict create \
        deskfont  [font actual DeskFont] \
        titlefont [font actual TitleFont] \
        scheme    $::theme \
        generation [ui-generation] \
        workarea  [workarea] \
        chrome    [list [look default border] [look default decotop]] \
        {*}$palette
}
# The ui world's cache key: an MTIME FINGERPRINT of everything under
# library/ui — the host included, which is the point (the owner: a
# changed host.tcl had no way to arrive; a re-source counter could
# never cover the host's own code) — plus treesync.tcl one storey up,
# because the host sources that too. The host learns it for free
# riding ui-style, answers "stale" at the next open when it differs,
# and the WM respawns — so any edit under ui/ is one close-and-open
# away, no Reread involved, while a WM restart (mtimes untouched)
# leaves the resident host in peace. For the applets already OPEN the
# check is also PUSHED — ui-freshen-push above, on a Reread and at
# start — and a stale host hands them to a successor itself.
#
# Mtimes are the CHECKOUT's truth and only that (the owner's caveat):
# a kit or archive built deterministically pins them on purpose, and
# worse, an UPDATED kit with pinned mtimes would be indistinguishable
# from the old one. So the family rule applies once more — a wrapper
# that KNOWS says so: a packaged build sets ::tk9wm_uigen to its own
# build id (a git rev, a version — anything that changes with the
# build), next to the ::tk9wm_reexec/::tk9wm_uiexec it already
# carries, and the fingerprint is simply that.
proc ui-generation {} {
    if {[info exists ::tk9wm_uigen]} { return $::tk9wm_uigen }
    set g 0
    set n 0
    foreach f [glob -nocomplain \
            [file join $::tk9wm_library ui *.tcl] \
            [file join $::tk9wm_library ui applets *.tcl] \
            [file join $::tk9wm_library treesync.tcl]] {
        incr n
        catch {set g [expr {max($g, [file mtime $f])}]}
    }
    return "$n:$g"
}

# The welcome mat's first QUICK KNOBS (the owner's order): all the
# desk's type bigger or smaller in one press. What it really turns is
# the ONE font everything derives from — set-desk-font — and it
# persists like any click: through custom-write, one standing entry
# rewritten per press. The sign is the unit (Tk: points positive,
# pixels negative), so "bigger" grows the magnitude whichever unit
# the desk measures in.
proc welcome-font-bump {dir} {
    set size [font actual DeskFont -size]
    set step [expr {$dir eq "up" ? 1 : -1}]
    set mag [expr {max(6, abs($size) + $step)}]
    set new [expr {$size < 0 ? -$mag : $mag}]
    custom-write [list set-desk-font {*}[knob-merge-opts set-desk-font \
        [list -size $new]]]
    if {[llength [info commands widgets-build]]} { widgets-build }
}
# FURNISHING A DESK IN ONE CLICK — the mat's other offer, and the
# answer to "somebody who just wants to LOOK at this thing" (the
# owner, 2026-08-02: a wizard is a fine idea and «I want to look at
# tk9wm» is the wrong place for one). A set is a list of ordinary
# config words written into the custom layer, so it is exactly what a
# person would have typed and can be read, edited and taken back the
# same way. No new mechanism, and nothing the layer has not seen.
#
# EVERY BUTTON CARRIES ITS OWN `needs`, which is what lets one set
# serve every machine: a deed whose software is missing stands by and
# is not drawn, so the same six lines give a tmux desk three buttons
# and a bare one, one. Nothing here has to ask what is installed —
# that question is already answered, once, by the thing that answers
# it for hand-written configs too.
#
# THE SET OWNS THE PANEL (panel-buttons-own): applying it twice gives
# the same desk rather than six buttons, and the ownership rule is the
# custom layer's own — the whole set or nothing, no deltas over a
# config's line-up.
#
# A PANEL MEANS A PANEL WITH ITS FURNITURE IN IT — the tray AND a clock
# (the owner, 2026-08-03). The clock names its panel outright because a
# widget's default place is the workarea, which is the desk and not the
# strip, and what is being offered here is a strip with something on
# it. It costs the band very little now that a widget is told which way
# its strip runs and how much thickness the buttons already paid for
# (widget-band-opts): the clock lays itself out in one line or two and
# does not push the bar deeper on its own account.
keep welcome_presets {
    minimal {
        {panel-buttons-own default}
        {set-tray on}
        {wm-widget clock -type clock -on {panel default} -place {right vcenter}}
        {action terminal {terminal {name terminal} key {<Super>t t}}}
        {action emacs {emacs {frame tk9wm-frame} needs emacs key {<Super>t e}}}
        {action tmux {terminal {name tmux title tmux}
                      run {sh -c {tmux attach || tmux new}}
                      badge t needs tmux key {<Super>t m}}}
        {panel-button terminal}
        {panel-button emacs}
        {panel-button tmux}
    }
}
# The chords all hang under the desk's OWN prefix rather than taking
# top-level keys: <Super>t t, <Super>t e, <Super>t m. That costs the
# global namespace nothing — a prefix is exactly what one is for —
# and each is guessable from the first letter of what it opens.
#
# The emacs button is bound to a CONSTANT FRAME NAME and so is
# create-or-raise rather than always-new (the owner's call): a frame's
# name is its WM_CLASS instance, so the match derives itself and the
# second press finds the first press's window. No eval — the button
# opens emacs, it does not tell emacs what to think.
#
# The terminal button says a NAME (the owner, 2026-08-06): nameless,
# its match is the any-emulator predicate, and a button meant to be
# «my shell» would light up for a tmux in a plain xterm, an ssh
# window — every terminal-shaped thing on the desk. Named, the
# emulator is spawned wearing `terminal` as its WM_CLASS instance and
# the match narrows to exactly the windows this button opened. It is
# also the better example to copy — what the desk WRITES for somebody
# is the idiom they will read and reuse, and the name idiom is the
# one that keeps buttons from swallowing each other. The catch-all
# `terminal {}` stays a legal word for whoever wants exactly that.
#
# The tmux button says a TITLE as well as a name, because the two are
# different marks and only one of them derives itself. A terminal
# left to title its own window names it after the command's first
# word, and this command is `sh -c "tmux attach || tmux new"` — so a
# window whose whole point is tmux introduced itself, in the taskbar
# and to the eye, as «sh» (the owner, 2026-08-02).
proc welcome-preset {name} {
    if {![dict exists $::welcome_presets $name]} {
        error "welcome-preset: no such set «$name»"
    }
    foreach cmd [dict get $::welcome_presets $name] { custom-write $cmd }
    puts "WM: welcome: the «$name» set applied\
 ([llength [dict get $::welcome_presets $name]] words)"
}

# THE THEME, FROM THE MAT — one click, and the whole desk changes
# colour (the owner, 2026-08-02, asking for the switch to be right
# there on the welcome note). It writes a customization like every
# other link on the mat: the invitation goes on dogfooding the layer
# it invites you to use, and the choice survives a restart because it
# is written down rather than merely done.
proc welcome-theme-flip {} {
    set to [expr {$::theme eq "light" ? "dark" : "light"}]
    custom-write [list set-theme $to]
}
# A PROGRAMMATIC WRITER MUST MERGE, not replace. The custom layer's
# record for a knob IS its command, so writing «set-desk-font -size
# 11» throws away the -family that stood beside it — the owner lost
# his Iosevka to the mat's font buttons that way, and did not see it
# because the LIVE font keeps what it is not told to change; only the
# record was poorer. So a writer of one option asks what the layers
# already say and hands back the whole word.
proc knob-merge-opts {name opts} {
    set base {}
    foreach layer {custom config} {
        if {![dict exists $::layer_knobs $layer $name]} continue
        set said [lrange [dict get $::layer_knobs $layer $name] 1 end]
        if {[catch {font-args $name {*}$said} said]} { set said {} }
        set base $said
        break
    }
    return [dict merge $base $opts]
}

# applet NAME — the panel button's idempotent semantics one storey
# up, three questions in order:
#   is the applet's WINDOW on the desk?  focus it (the window wears
#     {tk9wm-NAME Tk9wmUi} — a match, not a memory: it survives a WM
#     restart because adoption re-finds it);
#   is the HOST alive?  ask it to open the applet (Tk send — a stale
#     registry entry fails the send and falls through to the spawn);
#   else  spawn the host with the applet's name on its command line.
proc applet {name} {
    set pred [list filter -class [list tk9wm-$name Tk9wmUi]]
    set hit [lindex [panel-matches "applet $name" \
        [dict create match $pred]] 0]
    if {$hit ne ""} {
        puts "WM: applet $name: found 0x[format %x $hit]"
        panel-focus-hit $hit
        return
    }
    if {"tk9wm-ui" in [winfo interps]} {
        # ASYNC, and that is the whole of the latency story: the host
        # answers a ui-open by asking US for ui-style, and a
        # synchronous send here left the WM waiting inside its own
        # send while the host waited inside its reply. Tk survives
        # that — by TIMERS — which is why a deiconify cost as much as
        # a cold start (the owner, measured on his desk). Nothing here
        # wants an answer: a stale host now takes itself off the
        # registry and asks the WM for a fresh one, so even that
        # decision needs no round trip.
        if {![catch {send -async -- tk9wm-ui [list ui-open $name]}]} {
            puts "WM: applet $name: asked the running host"
            return
        }
        # a corpse in the registry: fall through and spawn
    }
    set head [ui-exec-head]
    if {![llength $head]} {
        puts "WM: applet $name: no way to exec the ui host —\
 this image should set ::tk9wm_uiexec"
        return
    }
    set script [file join $::tk9wm_library ui host.tcl]
    puts "WM: applet $name: spawning the ui host"
    # A WORD WHILE IT COMES UP: a fresh host has a Tk, a treectrl and
    # a theme to load before anything can be on the screen, and a
    # desk that says nothing for two seconds looks broken (the
    # owner). The desk's own echo box is exactly the right size for
    # this — no new machinery, and it fades on its own.
    policy-key-echo flash "$name: starting…"
    exec {*}$head $script [tk appname] $name &
}

