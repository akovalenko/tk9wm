# The configurator — a RENDERER of the desk's own knob registry, and
# nothing more: every row comes from knob-table, fetched live, so this
# applet has no opinion about what knobs exist. treectrl (the owner's
# standing preference, and a tree of groups IS a tree), one row per
# knob under its group node. The COLLECTIONS below the knob groups
# are the same contract over collection-table: a node per family, an
# element per child, a field per grandchild, edited by the same
# kind-editors — see the treesync views and the field address.
#
# KEYBOARD-FIRST, by the owner's review of the first cut:
#   - the tree takes focus on open, and the focus is VISIBLE — a
#     highlight ring on the tree and the buttons, an outlined bar on
#     the selected row;
#   - arrows (and k/j, p/n, Ctrl+p/Ctrl+n) walk the rows; Return or
#     F2 ACTIVATES — a bool toggles, a choice drops a menu, the
#     free-form kinds open the overlay entry, color and font their
#     dialogs; Left/Right fold and unfold a group; F3 switches a
#     SLOT between its two spellings (an action's run and launch);
#   - the mouse follows the same grammar: a single click only SELECTS
#     (and focuses the tree); activation is the double click;
#   - Save and Revert wear Alt accelerators (ui-accel, the generic
#     support), and Tab reaches them with their rings showing.
#
# THE EDITOR INVARIANT: whenever the overlay entry is visible it HAS
# the focus (it is created after the click sequence finishes, and its
# Map claims focus); Return commits, Escape cancels, and the focus
# leaving is a commit attempt. Any scroll closes it the same way — an
# entry drifting apart from its row was the first cut's bug.
#
# A commit PREVIEWS immediately — the knob runs on the live desk over
# the send door — and marks the row pending (•). Save writes every
# pending knob through custom-write; Revert is a config reload, the
# desk's own undo. A row whose knob the CONFIG also sets wears a cfg
# badge — the loader's truth made visible.
ui-applet configurator {title "tk9wm configurator" build cfg-build}

set cfg_table {}     ;# knob-table, as last fetched
set cfg_coll {}      ;# collection-table, as last fetched
set cfg_pending {}   ;# name -> the command previewed but not saved
set cfg_item {}      ;# knob name -> tree item
set cfg_effect {}    ;# custom key -> pin | change (the desk's audit)
set cfg_node {}      ;# tree item -> collection descriptor (coll/elem/field)
set cfg_fitem {}     ;# field address -> tree item
set cfg_fresh {}     ;# elements born in this refresh — folded once attached
set cfg_T ""
set cfg_hint "Return or F4 opens the picker · F2 types · F3 switches a\
 slot's spelling · F8 what you have changed · Ins adds, Del drops ·\
 Alt+↑/↓ move a button · Ctrl+Enter takes · Save makes it stick"

# A REFUSAL MUST SAY WHY (the owner: a bad place value simply did not
# commit and explained nothing). Every rejection — ours by kind, or
# the desk's own error text coming back over the send door — lands on
# the status line, in the warn color, and the editor stays open on the
# offending text so it can be fixed rather than retyped.
proc cfg-status {msg {how note}} {
    set l [winfo toplevel $::cfg_T].b.note
    if {![winfo exists $l]} return
    $l configure -text [expr {$msg eq "" ? $::cfg_hint : $msg}] \
        -foreground [expr {$how eq "error" ? "#cc4040" : [ui-color link]}]
}
proc cfg-refuse {msg} {
    cfg-status $msg error
    bell
    return 0
}

proc cfg-build {W} {
    set ::cfg_T $W.t
    set ih [expr {[font metrics DeskFont -linespace] + 6}]
    # extended, for ONE gesture's sake: taking several of a bundle's
    # binds at once (decision 4). Everything else still works on the
    # first selected row, and plain clicks and arrows still select
    # singly — Ctrl+click is the way in.
    treectrl $W.t -showheader yes -showroot no -showbuttons yes \
        -selectmode extended -itemheight $ih \
        -background [ui-color field] -yscrollcommand [list cfg-yscroll $W.sb]
    ui-focusable $W.t
    # Out of the focus cycle: Tk's heuristic puts a scrollbar in it
    # (it has key bindings), and a stop with nothing to show for it —
    # the ring lands on something invisible — is worse than no stop
    # (the owner's review).
    ttk::scrollbar $W.sb -orient vertical -command [list $W.t yview] -takefocus 0
    set T $W.t
    $T column create -text knob         -resize yes -tags Cname
    $T column create -text value        -resize yes -tags Cval
    $T column create -text ""           -resize no  -tags Cflag
    $T column create -text "what it is" -squeeze yes -expand yes \
        -resize yes -tags Cdoc
    # THE HEADER WEARS THE THEME TOO (the owner): treectrl paints its
    # own, and left alone it is the toolkit's grey against a themed
    # desk. Its normal, active and pressed faces come from the same
    # palette the rest of the applet is dressed in.
    foreach c {Cname Cval Cflag Cdoc} {
        $T column configure $c -font TitleFont \
            -textcolor [ui-color fg] \
            -background [list [ui-color select] {active} \
                              [ui-color trough] {}] \
            -borderwidth 1 -arrowgravity right
    }
    $T configure -treecolumn Cname
    $T element create eTxt  text -fill [ui-color fg] -lines 1 -font DeskFont
    $T element create eVal  text -fill [ui-color link] -lines 1 -font DeskFont
    $T element create eDoc  text -fill [ui-color fg] -lines 1 -font DeskFont
    $T element create eFlag text -fill #cc7832 -lines 1 -font DeskFont
    $T element create eGrp  text -fill [ui-color fg] -lines 1 -font TitleFont
    $T element create eSel  rect -fill [list [ui-color select] selected] \
        -outline [list [ui-color link] selected] -outlinewidth 1
    foreach {st els} {
        sName {eSel eTxt} sVal {eSel eVal} sFlag {eSel eFlag}
        sDoc {eSel eDoc} sGrp {eSel eGrp}
    } {
        $T style create $st
        $T style elements $st $els
        $T style layout $st eSel -detach yes -iexpand xy
        $T style layout $st [lindex $els 1] -expand ns -padx 5 -squeeze x
    }
    # The tree says what it is, and its underline leads to it: Alt+k
    # from anywhere in this window puts the focus back on the knobs.
    ui-label $W.head "&Knobs — everything this desk can be told" $T \
        -foreground [ui-color link] -padx 6 -pady 4
    grid $W.head -row 0 -column 0 -columnspan 2 -sticky ew
    grid $T $W.sb -row 1 -sticky nsew
    grid rowconfigure $W 1 -weight 1
    grid columnconfigure $W 0 -weight 1
    frame $W.b -takefocus 0
    ttk::button $W.b.save   -text Save   -underline 0 -command cfg-save
    ttk::button $W.b.revert -text Revert -underline 0 -command cfg-revert
    ttk::button $W.b.erase  -text "Erase customization" -underline 0 \
        -command cfg-erase
    foreach b [list $W.b.save $W.b.revert $W.b.erase] {
        ui-focusable $b; ui-accel $b
    }
    # ANCHORED AT ITS TOP-LEFT, and filling what the box gives it: a
    # label centres its text in whatever space it has, so a hint one
    # line too tall for the box lost a slice off the TOP as well as
    # the bottom (the owner, 2026-08-01). The first line must always
    # be the one that stays.
    label  $W.b.note -takefocus 0 -anchor nw -justify left -text $::cfg_hint \
        -foreground [ui-color link]
    pack $W.b.save $W.b.revert $W.b.erase -side left -padx 4 -pady 4
    pack $W.b.note -side left -padx 12 -fill both -expand 1
    grid $W.b -row 2 -columnspan 2 -sticky ew
    # ...and the box stops propagating its children's appetite: a
    # longer or shorter status line used to resize the whole window
    # under the owner's hands as he typed (a short refusal SHRANK it).
    update idletasks
    # THREE lines' worth, always: a refusal is a sentence and
    # sometimes a long one, and the hint itself has grown to three as
    # the gestures did (the owner, 2026-08-01 — it was two, and the
    # third line had nowhere to be). The box keeps that height
    # whatever the text does, so the window walls still do not move;
    # the wrap length follows the window's width.
    $W.b configure -height [expr {max([winfo reqheight $W.b],
        3*[font metrics DeskFont -linespace] + 12)}]
    pack propagate $W.b 0
    bind $W <Configure> {cfg-note-wrap %W %w}

    # CONDITIONAL breaks: a plain `break` swallowed the class bindings
    # too, and with them treectrl's own header work — column drags and
    # resizes stopped (the owner's report). The helpers answer whether
    # the press was theirs; a press on the header is not.
    bind $T <ButtonPress-1>        {if {[cfg-click %x %y]} break}
    bind $T <Double-ButtonPress-1> {if {[cfg-doubleclick %x %y]} break}
    # Ctrl+click is NOT ours: the empty binding lets treectrl's own
    # class binding run, which in extended mode toggles the row into
    # the selection — the mouse half of the multi-take gesture.
    bind $T <Control-ButtonPress-1> {;}
    foreach k {Up k p} { bind $T <KeyPress-$k> {cfg-move above; break} }
    foreach k {Down j n} { bind $T <KeyPress-$k> {cfg-move below; break} }
    bind $T <Control-p> {cfg-move above; break}
    bind $T <Control-n> {cfg-move below; break}
    # ...and the ends of the list, in both dialects: Home/End as every
    # list has them, Alt+< and Alt+> as emacs hands expect (the marker
    # is a shifted key, so the binding names the key and the shift —
    # see the chord lesson in the WM's key layer).
    foreach k {<KeyPress-Home> <Alt-less> <Alt-Key-comma>} {
        bind $T $k {cfg-end first; break}
    }
    foreach k {<KeyPress-End> <Alt-greater> <Alt-Key-period>} {
        bind $T $k {cfg-end last; break}
    }
    bind $T <KeyPress-Return> {cfg-activate primary; break}
    bind $T <KeyPress-F4>     {cfg-activate primary; break}
    bind $T <KeyPress-F2>     {cfg-activate text; break}
    bind $T <KeyPress-F3>     {cfg-slot-menu; break}
    bind $T <KeyPress-F8>     {cfg-pins; break}
    # h/l fold and unfold beside the arrows, the way k/j walk beside
    # Up and Down (the owner's ask — vi hands)
    foreach k {Left h} { bind $T <KeyPress-$k> {cfg-fold collapse; break} }
    foreach k {Right l} { bind $T <KeyPress-$k> {cfg-fold expand; break} }
    # the composition gestures (plan step C): Insert adds an element,
    # Delete drops one, Alt moves a button through its set, and
    # Ctrl+Enter TAKES — the panel whole, or the selected binds out
    # of their bundle
    bind $T <KeyPress-Insert> {cfg-insert; break}
    bind $T <KeyPress-Delete> {cfg-delete; break}
    bind $T <Alt-Up>   {cfg-move-elem above; break}
    bind $T <Alt-Down> {cfg-move-elem below; break}
    bind $T <Control-Return> {cfg-take; break}
    cfg-refresh
    # ...and AGAIN once the window is really on the screen. Before
    # the first map a treectrl has no realized geometry to measure —
    # its column widths and the toplevel's requested height are both
    # provisional — so the first open after a fresh host came up
    # narrow AND too tall, while every later one, measured warm, was
    # right (the owner's report: "не ловится при перезапусках"). One
    # shot: the binding takes itself off.
    bind $W <Map> {cfg-fit-mapped %W}
    focus $T
}
proc cfg-fit-mapped {W} {
    if {$W ne [winfo toplevel $::cfg_T]} return
    bind $W <Map> {}
    cfg-fit
}

# ONCE THE USER HAS SIZED IT, IT IS THEIR WINDOW (the owner). Our fit
# is a first guess at a size nobody has an opinion about yet; a hand
# on the border ends that, and every later refresh leaves the walls
# alone — the columns still re-measure, the tree still fills whatever
# it was given, but nothing asks for a new geometry.
#
# Telling the two apart: after a fit we remember the size we asked
# for, and a Configure that reports something else is somebody else's
# doing.
set cfg_user_sized 0
set cfg_fit_size {}
set cfg_col_fit {}    ;# column -> the -width the fit last set there
set cfg_col_user {}   ;# columns dragged by hand — theirs now
proc cfg-note-wrap {W w} {
    if {$W ne [winfo toplevel $::cfg_T]} return
    set l $W.b.note
    if {[winfo exists $l]} {
        # A FLOOR, not a threshold. It used to SKIP the rewrap when
        # the room fell under 80px — which is exactly the width at
        # which the hint most needs rewrapping, so a narrow window
        # kept the wrap (and the lines) of a wide one and the text
        # went out of the box sideways (the owner, 2026-08-01).
        set room [expr {max($w - [winfo x $l] - 12, 120)}]
        $l configure -wraplength $room
        cfg-note-room $W $l $room
    }
    if {!$::cfg_user_sized && [llength $::cfg_fit_size]} {
        lassign $::cfg_fit_size fw fh
        if {abs($w - $fw) > 2 || abs([winfo height $W] - $fh) > 2} {
            set ::cfg_user_sized 1
            puts "UI: configurator: sized by hand — the fit steps aside"
        }
    }
}

# HOW TALL THE BOX MUST BE AT THIS WIDTH. Narrow the window and the
# hint wraps onto more lines; there is usually slack going down and
# none going sideways, so the box takes the room it needs and the
# tree gives it up (the owner's ask, 2026-08-01).
#
# Measured on the HINT, never on what the status line happens to be
# saying — that was the old lesson and it still holds: a refusal is
# sometimes a long sentence, and the walls must not move as one
# arrives and goes. A refusal too long for the room runs off the
# bottom, which is what the label's top-left anchor is for.
proc cfg-note-room {W l room} {
    set m $W.b.measure
    if {![winfo exists $m]} {
        label $m -takefocus 0 -justify left       ;# never packed: a ruler
    }
    $m configure -font [$l cget -font] -wraplength $room -text $::cfg_hint
    set line [font metrics [$l cget -font] -linespace]
    set want [expr {max(3*$line, [winfo reqheight $m]) + 12}]
    if {[$W.b cget -height] != $want} { $W.b configure -height $want }
}

# Any scroll ends an open editor (as a commit attempt): the entry is
# placed at pixel coordinates and the rows move under it.
proc cfg-yscroll {sb a b} {
    if {[winfo exists $::cfg_T.edit]} { cfg-entry-done commit }
    $sb set $a $b
}

# A refresh RECONCILES the tree instead of rebuilding it: both
# tables are fetched first, then every level — the knob groups and
# family nodes under root, the knobs and elements under those, the
# fields under the live elements — is synced through treesync, each
# level under its own parent. What the user arranged — the
# selection, a folded group, an opened element — lives ON its item
# and survives because the item does; the save-and-restore dance
# this proc used to open with was the rebuild's tax, and it is gone
# with the rebuild.
proc cfg-owner {name} {
    expr {[dict exists $::cfg_table $name owner]
          ? [dict get $::cfg_table $name owner] : "code"}
}
# A REFRESH IS NOT RE-ENTRANT, though the event loop makes it look
# so: wm-call is a Tk send, and a send SPINS THE EVENT LOOP — so in
# the middle of a refresh (between the delete and the rebuild)
# another refresh can arrive: the desk answering a preview, a second
# gesture, a timer. Run at once it would read a half-built tree and
# build a second one over it. The guard folds every such arrival
# into ONE deferred re-run after the current pass — the late caller
# wanted the freshest tree, and the re-run is exactly that.
set cfg_refreshing 0
set cfg_refresh_again 0
proc cfg-refresh {} {
    if {$::cfg_refreshing} { set ::cfg_refresh_again 1; return }
    set ::cfg_refreshing 1
    set rc [catch cfg-refresh-body err opts]
    set ::cfg_refreshing 0
    set again $::cfg_refresh_again
    set ::cfg_refresh_again 0
    if {$rc} { return -options $opts $err }
    if {$again} cfg-refresh
}
proc cfg-refresh-body {} {
    set T $::cfg_T
    # BOTH tables are fetched before the tree is touched: a fetch is
    # a send, the loop spins, and a gesture landing in that window
    # now works over the still-intact old tree — reconcile has no
    # «the tree stands empty» phase for it to fall into.
    set ::cfg_table [wm-call knob-table]
    set ::cfg_coll [wm-call collection-table]
    # ...and what each of our own words DOES — pin or change, judged
    # by the desk at the one moment it can be (see custom-effect-judge)
    set ::cfg_effect [wm-call {set ::custom_effect}]
    # where to LAND if the selected row does not survive this pass —
    # a Delete is exactly that: beside where it stood, the previous
    # sibling, else the parent (the owner's ask, 2026-07-31 — being
    # thrown to the top of the tree is a lost place). Captured as
    # items: a survivor keeps its id, and cfg-select quietly skips a
    # candidate that died along with the selection.
    set fall {}
    set sel [cfg-selected]
    if {$sel ne ""} {
        foreach f [list [$T item prevsibling $sel] [$T item parent $sel]] {
            if {$f ne "" && $f != 0} { lappend fall $f }
        }
    }
    set ::cfg_item {}
    set ::cfg_node {}
    set ::cfg_fitem {}
    set ::cfg_fresh {}
    # the top storey — the knob groups (sorted), then the families in
    # the table's own order — reconciled as ONE list of root children
    set groups {}
    dict for {name meta} $::cfg_table {
        dict lappend groups [dict get $meta group] $name
    }
    set rows {}
    foreach group [lsort [dict keys $groups]] {
        lappend rows [list [list grp $group] {}]
    }
    dict for {cname cmeta} $::cfg_coll {
        lappend rows [list [list coll $cname] [dict get $cmeta doc]]
    }
    set top [treesync::sync $T \
                 {make cfg-top-make update cfg-top-update} $rows]
    # the knobs, one storey down, each group its own parent. cfg_item
    # is rebuilt in row order, group by group — cfg-end walks this
    # dict's order as the tree's reading order.
    foreach group [lsort [dict keys $groups]] {
        set rows [lmap name [lsort [dict get $groups $group]] {
            list $name [dict get $::cfg_table $name]
        }]
        set m [treesync::sync $T \
                   {make cfg-knob-make update cfg-knob-update} $rows \
                   [dict get $top [list grp $group]]]
        foreach row $rows {
            dict set ::cfg_item [lindex $row 0] \
                [dict get $m [lindex $row 0]]
        }
    }
    # the collections: elements under their family node, fields under
    # the live elements — the same engine, a parent per level, and
    # the descriptor maps rebuilt from what each sync returns
    dict for {cname cmeta} $::cfg_coll {
        set g [dict get $top [list coll $cname]]
        dict set ::cfg_node $g [dict create what coll coll $cname]
        set rows {}
        foreach e [dict get $cmeta elements] {
            lappend rows [list \
                [list [dict get $e key] [dict exists $e ineffectual]] \
                [list $cname $e]]
        }
        set m [treesync::sync $T \
                   {make cfg-elem-make update cfg-elem-update} $rows $g]
        foreach e [dict get $cmeta elements] {
            set key [dict get $e key]
            set dead [dict exists $e ineffectual]
            set it [dict get $m [list $key $dead]]
            set desc [dict create what elem coll $cname key $key]
            if {$dead} { dict set desc dead 1 }
            dict set ::cfg_node $it $desc
            if {$dead} continue
            set frows {}
            set said [cfg-elem-values $cname $key]
            set lint [expr {[dict exists $e lint] ? [dict get $e lint] : {}}]
            dict for {f fmeta} [dict get $cmeta fields] {
                if {![cfg-slot-shown? $f $fmeta $said]} continue
                lappend frows [list $f \
                    [list [list @field $cname $key $f] $fmeta \
                     [lsearch -all -inline -index 1 $lint $f]]]
            }
            # ...and after them, the words this one stands OVER:
            # same chord, another layer, not in force. They are rows,
            # not fields — nothing in them is edited here, and the
            # only gesture they answer is Delete on one of ours.
            if {[dict exists $e shadowed]} {
                foreach claim [dict get $e shadowed] {
                    lappend frows [list [list @over [dict get $claim owner]] \
                        [list shadow $claim]]
                }
            }
            set fm [treesync::sync $T \
                        {make cfg-field-make update cfg-field-update} \
                        $frows $it]
            dict for {f fit} $fm {
                if {[lindex $f 0] eq "@over"} {
                    dict set ::cfg_node $fit [dict create what shadow \
                        coll $cname key $key owner [lindex $f 1]]
                    continue
                }
                dict set ::cfg_node $fit [dict create what field \
                    coll $cname key $key field $f]
                dict set ::cfg_fitem [list @field $cname $key $f] $fit
            }
        }
    }
    # an element is BORN folded — the tree is an overview first; a
    # survivor keeps whatever the user made of it, which is the point
    foreach it $::cfg_fresh { $T collapse $it }
    cfg-fit
    # the selection rode its item; if its row is gone, land beside
    # where it stood (the fallbacks above, first survivor wins), and
    # only with nowhere at all to land — a first build — take the
    # first knob
    if {[cfg-selected] eq ""} {
        foreach f $fall {
            cfg-select $f
            if {[cfg-selected] ne ""} break
        }
    }
    if {[cfg-selected] eq ""} { cfg-select-first }
}
proc cfg-select-first {} {
    set first [lindex [dict values $::cfg_item] 0]
    if {$first ne ""} { cfg-select $first }
}

# ---- the treesync views: how each level dresses its items ----
# More top nodes — actions, panel, bindings, widgets, keys — served
# by collection-table exactly as the knobs are by knob-table. Every
# level is a make/update pair for treesync: make creates and
# dresses, update re-dresses a survivor — the same dresser both
# times, because what an item shows is ROW data, never item history
# (the strip's lesson). The engine attaches, positions and deletes;
# nothing here touches a sibling.
proc cfg-top-make {T parent key data} {
    lassign $key what name
    set item [$T item create -button yes]
    if {$what eq "grp"} {
        $T item style set $item Cname sGrp
    } else {
        # a family node wears its doc beside the name
        $T item style set $item Cname sGrp Cdoc sDoc
        $T item element configure $item Cdoc eDoc -text $data
    }
    $T item element configure $item Cname eGrp -text $name
    return $item
}
proc cfg-top-update {T item key data} {
    if {[lindex $key 0] eq "coll"} {
        $T item element configure $item Cdoc eDoc -text $data
    }
}
proc cfg-knob-dress {T item name meta} {
    $T item element configure $item Cdoc eDoc -text [dict get $meta doc]
    cfg-show-value $item $name [dict get $meta value]
    if {[dict exists $::cfg_effect $name]} {
        $T item element configure $item Cflag eFlag \
            -text [expr {[dict get $::cfg_effect $name] eq "pin" ? "pin" : ""}]
    }
}
proc cfg-knob-make {T parent key data} {
    set item [$T item create]
    $T item style set $item Cname sName Cval sVal Cflag sFlag Cdoc sDoc
    $T item element configure $item Cname eTxt -text $key
    cfg-knob-dress $T $item $key $data
    return $item
}
proc cfg-knob-update {T item key data} {
    cfg-knob-dress $T $item $key $data
}
# An ELEMENT: its key, a summary of what the layers said, and a flag
# with the owner badge — plus ✗ for a bind a later word buried
# (decision 5 made visible). dead rides IN THE SYNC KEY: a buried
# bind and the live one share a name, each must keep an item of its
# own, and a row changing sides is honestly a death and a birth.
proc cfg-elem-dress {T item cname e} {
    $T item element configure $item Cname eTxt -text [dict get $e key]
    $T item element configure $item Cval eVal \
        -text [cfg-elem-summary $cname $e]
    set flags {}
    if {[dict exists $e ineffectual]} { lappend flags ✗ }
    if {[dict exists $e waiting]} { lappend flags waiting }
    # the linter's remarks: a warn is louder than a note, and neither
    # is an error — the row works, somebody just has something to say
    # about it (the sentence itself is on the field it hangs off)
    if {[dict exists $e lint]} {
        set mark ""
        foreach v [dict get $e lint] {
            # nothing is said twice on one line: a WAITING element
            # already explains its needs, and the sentence naming the
            # missing command waits on that row for whoever opens it
            if {[dict exists $e waiting] && [dict get $v key] eq "needs"} continue
            if {[dict get $v level] eq "warn"} { set mark ⚠; break }
            set mark ·
        }
        if {$mark ne ""} { lappend flags $mark }
    }
    switch -- [dict get $e owner] {
        custom {
            # PIN or CHANGE — the same word wears both faces, and the
            # difference is invisible in the file: one alters what the
            # layers below give, the other holds what they already
            # gave (the owner's distinction, 2026-08-01). A `take` is
            # a pin ON PURPOSE, which is why nothing sweeps them by
            # itself.
            if {[dict exists $e effect] && [dict get $e effect] eq "pin"} {
                lappend flags pin
            } else {
                lappend flags custom
            }
        }
        config { lappend flags cfg }
    }
    $T item element configure $item Cflag eFlag -text [join $flags " "]
    $T item element configure $item Cdoc eDoc -text [cfg-elem-note $cname $e]
}
# What a row says about ITSELF in the doc column. For a binding that
# is whose word it is and where it was said — the question the tree
# could not answer before the origin rode along — and for a word that
# no longer answers, the reason, which used to be a silent ✗ on a row
# with nothing under it (the owner, 2026-08-01: «очень легко
# что-нибудь испортить и перекрыть»).
proc cfg-elem-note {cname e} {
    if {$cname ne "bindings"} { return "" }
    if {[dict exists $e why]} { return [dict get $e why] }
    set note "in force — [cfg-owner-words $e]"
    # what this word STANDS OVER — the claimants are rows under it
    # now, and the summary here says how many before one unfolds them
    if {[dict exists $e shadowed]} {
        set said {}
        foreach claim [dict get $e shadowed] {
            lappend said [cfg-owner-words $claim]
        }
        append note ", over [join $said { and }]"
    }
    if {[dict exists $e where]} {
        append note " · [file tail [dict get $e where]]"
    }
    return $note
}
proc cfg-owner-words {e} {
    if {[dict exists $e bundle]} { return "the [dict get $e bundle] family" }
    switch -- [dict get $e owner] {
        custom { return "yours" }
        config { return "the config's" }
    }
    return "the desk's own"
}
proc cfg-elem-make {T parent key data} {
    lassign $data cname e
    set item [$T item create -button [expr {![dict exists $e ineffectual]}]]
    $T item style set $item Cname sName Cval sVal Cflag sFlag Cdoc sDoc
    cfg-elem-dress $T $item $cname $e
    lappend ::cfg_fresh $item
    return $item
}
proc cfg-elem-update {T item key data} {
    lassign $data cname e
    cfg-elem-dress $T $item $cname $e
}
# An element's children are its FIELDS, edited by the same
# kind-editors the knobs use; a buried bind has no children at all —
# re-binding it is capture-chord's day, not a field edit here.
proc cfg-field-dress {T item addr fmeta {lint {}}} {
    # a claimant row: whose word it is, what it says, and that it is
    # not the one answering
    if {$addr eq "shadow"} {
        $T item element configure $item Cval eVal \
            -text [dict get $fmeta script]
        $T item element configure $item Cflag eFlag \
            -text [expr {[dict get $fmeta owner] eq "custom" ? "✗ yours" : "✗ cfg"}]
        $T item element configure $item Cdoc eDoc \
            -text "[cfg-owner-words $fmeta] word, not in force"
        return
    }
    $T item element configure $item Cval eVal \
        -text [cfg-value-text $addr [cfg-cur $addr]]
    set flag [expr {[dict exists $::cfg_pending $addr] ? "•" : ""}]
    set doc [dict get $fmeta doc]
    # A remark REPLACES the field's description while it stands: the
    # description says what the word is for, and one who has a
    # sentence about THIS word has the more useful thing to say.
    if {[llength $lint]} {
        set v [lindex $lint 0]
        append flag [expr {[dict get $v level] eq "warn" ? "⚠" : "·"}]
        set doc [dict get $v text]
    }
    $T item element configure $item Cflag eFlag -text $flag
    $T item element configure $item Cdoc eDoc -text $doc
}
proc cfg-field-make {T parent key data} {
    set item [$T item create]
    $T item style set $item Cname sName Cval sVal Cflag sFlag Cdoc sDoc
    $T item element configure $item Cname eTxt \
        -text [expr {[lindex $key 0] eq "@over" ? "…instead of" : $key}]
    cfg-field-dress $T $item {*}$data
    return $item
}
proc cfg-field-update {T item key data} {
    cfg-field-dress $T $item {*}$data
}
# What an element is AT A GLANCE, per family: a button says which
# fields speak, a binding shows its script, a bundle whether it
# stands, a widget its own words.
proc cfg-elem-summary {cname e} {
    set v [dict get $e values]
    switch -- $cname {
        actions - panel { return [join [dict keys $v] " "] }
        bindings { return [dict get $v script] }
        keys     { return [dict get $v state] }
    }
    return $v
}

# No wrapping anywhere, so everything MEASURES: each column asks the
# font how wide its widest text runs (the owner's review: the first
# cut opened at Tk's shrug of a default and nothing fit). The height
# wants every row; both are capped by the screen.
proc cfg-fit {} {
    set T $::cfg_T
    # THE TREE SIZES ITS OWN COLUMNS (the owner: its auto-width does
    # it right, and mine forgot the tree indent — the longest knob
    # name came out clipped). Ours is only the arithmetic it cannot
    # do: room to type into, a ceiling so one long value cannot open
    # the window past reading width, and the window's own size from
    # what the columns then ask for.
    set cap [font measure DeskFont [string repeat 0 34]]
    # Auto-width is right for the columns that hold their own text —
    # and blind for the two that do not. A SQUEEZED column asks for
    # almost nothing (measured: 24px against 374px of the longest
    # doc), and a column whose text appears only later (the flags)
    # asks for the width of the nothing it holds now. Both get an
    # honest minimum, measured from the content they WILL carry.
    set wdoc 0
    dict for {- meta} $::cfg_table {
        set wdoc [expr {max($wdoc, [font measure DeskFont [dict get $meta doc]])}]
    }
    # ONCE THE USER HAS DRAGGED A COLUMN, IT IS THEIR COLUMN (the
    # owner: the value column would not widen past the cap by hand,
    # and long values had nowhere to be read). The fit's ceiling is
    # imposed by MEASURING — auto-width first, then pinning whatever
    # runs past the cap — never by -maxwidth, which would clamp the
    # user's drag along with the fit's own arithmetic. A column whose
    # -width is not what the fit last set was dragged by hand, and
    # from then on the fit leaves it alone entirely.
    foreach c {Cname Cval Cflag Cdoc} {
        if {[dict exists $::cfg_col_fit $c]
                && ![dict exists $::cfg_col_user $c]
                && [$T column cget $c -width] ne [dict get $::cfg_col_fit $c]} {
            dict set ::cfg_col_user $c 1
            puts "UI: configurator: column $c sized by hand —\
 the fit steps aside"
        }
    }
    cfg-col-configure Cname -width {}
    cfg-col-configure Cval  -width {} -minwidth 140
    cfg-col-configure Cflag -width {} \
        -minwidth [expr {[font measure DeskFont "• custom"] + 12}]
    cfg-col-configure Cdoc  -width {} -minwidth [expr {$wdoc + 16}]
    update idletasks
    foreach c {Cname Cval} {
        if {![dict exists $::cfg_col_user $c]
                && [$T column width $c] > $cap} {
            $T column configure $c -width $cap
        }
    }
    foreach c {Cname Cval Cflag Cdoc} {
        if {![dict exists $::cfg_col_user $c]} {
            dict set ::cfg_col_fit $c [$T column cget $c -width]
        }
    }
    update idletasks
    # THE SUM MUST NOT CONTAIN ITS OWN ANSWER. Cdoc EXPANDS — its
    # current width is whatever was left over last time — so adding
    # that to the total and then handing the total back as the new
    # width grows the window by the slack on every refresh. On the
    # owner's desk each Alt+S walked the window a step wider, and
    # left, because it was against the right edge and the clamp kept
    # pulling it in. The expanding column contributes what it NEEDS
    # (its measured minimum), never what it currently occupies.
    set wall 0
    foreach c {Cname Cval Cflag} { incr wall [$T column width $c] }
    incr wall [$T column cget Cdoc -minwidth]
    set ih [expr {[font metrics DeskFont -linespace] + 6}]
    set rows [expr {[llength [dict keys $::cfg_item]]
                    + [llength [$T item children root]]}]
    # ...and the collection elements, visible under their open nodes
    # (their fields stand folded and do not count)
    dict for {- cmeta} $::cfg_coll {
        incr rows [llength [dict get $cmeta elements]]
    }
    # The ceiling is the WORKAREA minus what this window wears and
    # carries — the frame the desk will put around it and the button
    # box below the tree. Measured against the screen instead, the
    # window came up taller than the desk had room for and its bottom
    # went under the panel (the owner's report): a resize a client
    # asks for is honored as asked, and the WM's own clamp can only
    # move a window, not shrink it.
    set W [winfo toplevel $T]
    if {$::cfg_user_sized} return     ;# their window now, not ours
    lassign [ui-workarea] - - ww wh
    lassign [ui-chrome] B top
    set maxw [expr {$ww - 2*$B - [winfo reqwidth $W.sb] - 8}]
    # THE HINT WRAPS BEFORE THE ROOM FOR IT IS MEASURED. How many
    # lines that one line of gestures becomes depends on the width
    # the window is ABOUT to have; measured with the wrap the last
    # width left behind, the fit reserved two lines and the third
    # went under the desk (the owner, 2026-08-01 — the gesture list
    # had just grown). So: wrap to the width we are asking for, let
    # the box say how tall it is, and take the ceiling from that.
    set want [expr {min($wall + 24, $maxw)}]
    if {[winfo exists $W.b.note]} {
        set room [expr {$want - [winfo x $W.b.note] - 12}]
        if {$room > 80} { $W.b.note configure -wraplength $room }
        update idletasks
    }
    set maxh [expr {$wh - $top - $B - [winfo reqheight $W.b] - 8}]
    $T configure \
        -width  $want \
        -height [expr {min(($rows + 2) * $ih, $maxh)}]
    # ...and then ASK, because arithmetic about a widget's chrome is
    # a guess: a treectrl's -height buys the content, not the header
    # above it, and the difference put the window two pixels past the
    # workarea (measured). The whole toplevel says what it wants; the
    # tree gives back whatever hangs over.
    update idletasks
    set over [expr {[winfo reqheight $W] + $top + 2*$B - $wh}]
    if {$over > 0} { $T configure -height [expr {[$T cget -height] - $over}] }
    set over [expr {[winfo reqwidth $W] + 2*$B - $ww}]
    if {$over > 0} { $T configure -width [expr {[$T cget -width] - $over}] }
    update idletasks
    set ::cfg_fit_size [list [winfo reqwidth $W] [winfo reqheight $W]]
}

# ---- the field address ----
# A collection element's field is addressed as {@field COLL KEY FIELD}
# — a list, where a knob is a bare name, and the first word is how
# every routing proc tells the two apart. The address is what
# cfg-set, cfg-cur and the pending dict carry; its kind comes from
# the collection registry's field meta instead of the knob table.
proc cfg-field? {name} { expr {[lindex $name 0] eq "@field"} }
# ---- one slot, two spellings ----
# Some keys are two ways of saying one thing and cannot be said
# together (the registry's `xor`: an action's command is `run` or
# `launch`, never both). A tree that showed both rows would be
# offering a mistake — so it shows ONE, the spelling in effect, with
# the switch behind its ▾. Unsaid on both, the first of the pair is
# the face: the plain one, which is what the sugar is for.
proc cfg-field-meta {name} {
    dict get $::cfg_coll [lindex $name 1] fields [lindex $name 3]
}
proc cfg-slot-shown? {f fmeta said} {
    if {![dict exists $fmeta xor] || [dict exists $said $f]} { return 1 }
    foreach other [dict get $fmeta xor] {
        if {[dict exists $said $other]} { return 0 }
    }
    return 1
}
proc cfg-kind-of {name} {
    if {[cfg-field? $name]} {
        return [dict get $::cfg_coll [lindex $name 1] \
                    fields [lindex $name 3] kind]
    }
    dict get $::cfg_table $name kind
}
# ...and how a sentence names it: the address minus its marker
proc cfg-pretty {name} {
    expr {[cfg-field? $name] ? [join [lrange $name 1 end] " "] : $name}
}
# What the layers' word holds for an element — and for one field of
# it, "" when unsaid (which is how a field is ADDED: editing the
# nothing it holds).
proc cfg-elem-values {coll key} {
    foreach e [dict get $::cfg_coll $coll elements] {
        if {[dict get $e key] eq $key && ![dict exists $e ineffectual]} {
            return [dict get $e values]
        }
    }
    return {}
}
proc cfg-field-stored {name} {
    set v [cfg-elem-values [lindex $name 1] [lindex $name 2]]
    set f [lindex $name 3]
    expr {[dict exists $v $f] ? [dict get $v $f] : ""}
}
proc cfg-node-addr {it} {
    set d [dict get $::cfg_node $it]
    list @field [dict get $d coll] [dict get $d key] [dict get $d field]
}
proc cfg-show-field {addr} {
    if {![dict exists $::cfg_fitem $addr]} return
    set it [dict get $::cfg_fitem $addr]
    $::cfg_T item element configure $it Cval eVal \
        -text [cfg-value-text $addr [cfg-cur $addr]]
    # keep whatever mark the linter left standing: this is the quick
    # redraw of ONE cell after an edit, and the remarks are re-read
    # with the rest of the table on the next refresh
    set mark ""
    regexp {[⚠·]$} [$::cfg_T item element cget $it Cflag eFlag -text] mark
    $::cfg_T item element configure $it Cflag eFlag \
        -text "[expr {[dict exists $::cfg_pending $addr] ? {•} : {}}]$mark"
}

# ...and the seam the ownership runs through: a hand-dragged column
# takes no configuration from the fit, none at all.
proc cfg-col-configure {c args} {
    if {[dict exists $::cfg_col_user $c]} return
    $::cfg_T column configure $c {*}$args
}

# What a value LOOKS like in its cell. A list says how many it holds
# and of what — «[2 directories]» — rather than spelling itself out
# and blowing the column open (the owner's review); the whole of it
# lives in the sub-editor, one line per entry.
proc cfg-value-text {name value} {
    set kind [cfg-kind-of $name]
    switch -- [lindex $kind 0] {
        font {
            # A font's value is whatever the config SAID, and that may
            # be the whole font or ANY SUBSET of it: «-weight bold» on
            # a derived font, «-family {Dejavu Sans}» on the desk font
            # (both are overrides, which is the point of both). Only a
            # spec carrying all three parts is summarized; anything
            # else shows itself, because a partial spec is exactly
            # what its author wrote and nothing is missing from it.
            # Reaching for -size in a spec that has none was a crash,
            # not a subtlety (the owner, on -family alone).
            set sum [cfg-font-summary $value]
            if {$sum ne ""} { return $sum }
            return [expr {$value eq "" ? "(derived, unchanged)" : $value}]
        }
        list {
            set noun [lindex $kind 1]
            if {$noun eq ""} { set noun entries }
            return "\[[llength $value] $noun\]"
        }
    }
    return $value
}
# What the EDITOR starts with — the value as one would type it. A
# font's actual dict is a mouthful of options; its family and size
# are what a hand wants to touch (and set-desk-font takes exactly
# that form back).
# Is this font spec the whole story — family, size and weight? Then
# it can be said in three words; anything less is its own answer.
proc cfg-font-summary {value} {
    if {[catch {dict size $value}]} { return "" }
    foreach k {-family -size -weight} {
        if {![dict exists $value $k]} { return "" }
    }
    return "[dict get $value -family] [dict get $value -size]\
 [dict get $value -weight]"
}
proc cfg-value-typed {name value} {
    if {[lindex [cfg-kind-of $name] 0] eq "font"
            && [cfg-font-summary $value] ne ""} {
        return "-family [list [dict get $value -family]]\
 -size [dict get $value -size] -weight [dict get $value -weight]"
    }
    return $value   ;# a partial spec is what its author wrote
}
proc cfg-show-value {it name value} {
    set T $::cfg_T
    $T item element configure $it Cval eVal -text [cfg-value-text $name $value]
    # WHOSE VALUE IS THIS, at a glance (the owner's ask): a dot for
    # changed-but-unsaved, then the layer that owns it — `custom` for
    # a click of yours that stuck (erasable), `cfg` for your
    # hand-written config, nothing at all for the desk's own default.
    set flags {}
    if {[dict exists $::cfg_pending $name]} { lappend flags • }
    switch -- [cfg-owner $name] {
        custom { lappend flags custom }
        config { lappend flags cfg }
    }
    $T item element configure $it Cflag eFlag -text [join $flags " "]
}

proc cfg-select {it} {
    set T $::cfg_T
    # an item id remembered across a refresh may name a corpse — the
    # rebuild is free to have deleted it, and the rememberer (a timer,
    # a gesture that slept through a reload) cannot know. Selecting
    # nothing quietly beats erroring out of whatever gesture this is.
    if {$it eq "" || [catch {$T item id $it} live] || $live eq ""} return
    $T selection clear all
    $T selection add $it
    $T activate $it
    $T see $it
}
proc cfg-selected {} { lindex [$::cfg_T selection get] 0 }
proc cfg-move {dir} {
    set cur [cfg-selected]
    if {$cur eq ""} return
    set next [$::cfg_T item id [list $cur $dir]]
    if {$next ne "" && $next != $cur} { cfg-select $next }
}
# The first and last KNOB, not the first and last row: a group header
# is a place to fold, not a place to be (and the tree may well open
# with one at the top).
proc cfg-end {which} {
    set names [dict keys $::cfg_item]
    if {![llength $names]} return
    set name [expr {$which eq "first" ? [lindex $names 0] : [lindex $names end]}]
    # ...and the group it lives in has to be open to be seen
    set it [dict get $::cfg_item $name]
    set parent [$::cfg_T item parent $it]
    if {$parent ne "" && ![$::cfg_T item state get $parent open]} {
        $::cfg_T expand $parent
    }
    cfg-select $it
}
proc cfg-name-of {it} {
    dict for {n i} $::cfg_item { if {$i == $it} { return $n } }
    return ""
}
proc cfg-fold {way} {
    set it [cfg-selected]
    if {$it ne "" && [cfg-name-of $it] eq ""} { $::cfg_T $way $it }
}

# A single click SELECTS and focuses the tree — nothing more; the
# double click and the keys activate.
# What identify answers, and who owns each answer:
#   {}                     empty space below the rows — nobody's
#   {header COLUMN ?side?} the header — treectrl's (drags, resizes)
#   {item I button}        the expander — treectrl's (folding)
#   {item I column C ...}  a CELL — ours
# Claiming anything but the last would swallow a class binding that
# does real work (the owner's review, twice over).
proc cfg-click {x y} {
    set id [$::cfg_T identify $x $y]
    if {[lindex $id 0] ne "item" || [lindex $id 2] ne "column"} { return 0 }
    focus $::cfg_T
    cfg-select [lindex $id 1]
    return 1
}
proc cfg-doubleclick {x y} {
    if {![cfg-click $x $y]} { return 0 }
    cfg-activate primary
    return 1
}
# ACTIVATION IS EDITING, and a picker is reachable FROM the editor
# (the owner's shape: F2 is text wherever text makes sense; a simple
# oneOf keeps its menu; everything else gets a combobox-like ▾ in the
# field that lands squarely in the dialog). So Return, F2 and the
# double click all mean the same thing — open the editor — except
# for the two kinds with no text to edit: a bool toggles, a choice
# drops its menu.
proc cfg-activate {{how primary}} {
    set it [cfg-selected]
    if {$it eq ""} return
    set name [cfg-name-of $it]
    if {$name eq ""} {
        # a collection FIELD edits; every other nameless row folds —
        # a group, a family node, an element, a buried bind
        if {[dict exists $::cfg_node $it]
                && [dict get $::cfg_node $it what] eq "shadow"} {
            cfg-status "this word is not the one answering — the row\
 above it is; Delete takes it back if it is yours"
            return
        }
        if {[dict exists $::cfg_node $it]
                && [dict get $::cfg_node $it what] eq "field"} {
            set name [cfg-node-addr $it]
        } else {
            $::cfg_T toggle $it
            return
        }
    }
    set kind [cfg-kind-of $name]
    switch -- [lindex $kind 0] {
        bool   { cfg-set $name [expr {[cfg-cur $name] eq "on" ? "off" : "on"}] }
        choice { cfg-choice-menu $it $name [lrange $kind 1 end] }
        default {
            set picker [cfg-picker-of $name]
            if {$how eq "primary" && $picker ne ""} {
                cfg-entry-pick $picker $name
                return
            }
            # after the event sequence, so nothing steals the focus
            # back from the entry (the invariant above)
            after idle [list cfg-entry $it $name]
        }
    }
}
# Which kinds have a picker behind the ▾ — and what it is. A slot's
# switch is NOT here on purpose: editing the command is the everyday
# thing and keeps the everyday gestures; changing which spelling the
# slot wears is rare and has a key of its own (F3).
proc cfg-picker-of {name} {
    switch -- [lindex [cfg-kind-of $name] 0] {
        color { return cfg-color-dialog }
        font  { return cfg-font-dialog }
        list  { return cfg-list-dialog }
    }
    return ""
}
# The pending value is kept AS A VALUE. It used to be dug back out
# of the command with `lindex ... end`, which is the last WORD — so a
# multi-word value came back mangled: «-weight bold» offered itself
# to the next edit as «bold» (the owner, on set-title-font). A command
# is not a value and cannot be read as one.
proc cfg-cur {name} {
    if {[dict exists $::cfg_pending $name]} {
        return [dict get $::cfg_pending $name value]
    }
    if {[cfg-field? $name]} { return [cfg-field-stored $name] }
    dict get $::cfg_table $name value
}

# A choice is a MENU at its cell, not a cycle to click blind through
# (the owner: four panel sides by repeated presses is cruel). The menu
# holds the keyboard natively; the current value is marked.
proc cfg-choice-menu {it name vals} {
    set T $::cfg_T
    catch {destroy $T.pop}
    menu $T.pop -tearoff 0 -font DeskFont
    set ::cfg_choice [cfg-cur $name]
    foreach v $vals {
        $T.pop add radiobutton -label $v -variable ::cfg_choice -value $v \
            -command [list cfg-set $name $v]
    }
    lassign [$T item bbox $it Cval] x1 y1 x2 y2
    tk_popup $T.pop [expr {[winfo rootx $T] + $x1}] \
                    [expr {[winfo rooty $T] + $y2}]
}

# The overlay entry. Created after idle (see cfg-activate) and its Map
# claims the focus: visible MEANS focused. Return commits, Escape
# cancels, losing the focus is a commit attempt.
proc cfg-entry {it name} {
    set T $::cfg_T
    cfg-entry-close
    lassign [$T item bbox $it Cval] x1 y1 x2 y2
    if {$x1 eq ""} return
    set ::cfg_editing $name
    set picker [cfg-picker-of $name]
    frame $T.edit -takefocus 0 -borderwidth 0
    entry $T.edit.e -font DeskFont -borderwidth 1 \
        -background [ui-color field] -foreground [ui-color fg] \
        -insertbackground [ui-color fg]
    ui-focusable $T.edit.e
    $T.edit.e insert 0 [cfg-value-typed $name [cfg-cur $name]]
    $T.edit.e selection range 0 end
    # GRID, and the button gets a column of its own: PACKED, the
    # entry (with -expand) claimed the whole cavity before the button
    # was packed at all — it existed, mapped 0, 1x1 in a corner,
    # which is why the owner could find no arrow anywhere (measured
    # on his live desk through the send door).
    grid $T.edit.e -row 0 -column 0 -sticky nsew
    grid rowconfigure $T.edit 0 -weight 1
    grid columnconfigure $T.edit 0 -weight 1
    if {$picker ne ""} {
        # the combobox-like way into the dialog: the button, or Down
        # from the keyboard — a gesture that costs nothing to guess
        ttk::button $T.edit.pick -text ▾ -takefocus 0 -width 2 \
            -command [list cfg-entry-pick $picker $name]
        grid $T.edit.pick -row 0 -column 1 -sticky ns
        # Down and F4 both — the gestures a combobox has taught
        # every pair of hands (the owner names F4 by its Windows
        # habit; Down is the X one)
        bind $T.edit.e <Down> [list cfg-entry-pick $picker $name]
        bind $T.edit.e <F4>   [list cfg-entry-pick $picker $name]
    }
    place $T.edit -x $x1 -y $y1 -width [expr {$x2 - $x1}] \
        -height [expr {$y2 - $y1}]
    bind $T.edit.e <Map>      {focus %W}
    bind $T.edit.e <Return>   {cfg-entry-done commit; break}
    bind $T.edit.e <Escape>   {cfg-entry-done cancel; break}
    bind $T.edit.e <FocusOut> {cfg-entry-focusout}
    focus $T.edit.e
}
# The focus leaving is a commit attempt — but not when it left FOR
# the picker button or the dialog it opened: that is one gesture, not
# an abandonment.
proc cfg-entry-focusout {} {
    if {[info exists ::cfg_picking] && $::cfg_picking} return
    cfg-entry-done commit
}
proc cfg-entry-pick {picker name} {
    set ::cfg_picking 1
    $picker $name
    set ::cfg_picking 0
}
proc cfg-entry-close {} {
    catch {bind $::cfg_T.edit.e <FocusOut> {}}
    catch {destroy $::cfg_T.edit}
}
proc cfg-entry-done {how} {
    set T $::cfg_T
    if {![winfo exists $T.edit]} return
    set v [$T.edit.e get]
    set name $::cfg_editing
    if {$how eq "commit"} {
        # a refusal KEEPS the editor open on the offending text — the
        # message says what is wrong, and the fix is a keystroke away
        if {![cfg-set $name $v]} { return }
    }
    cfg-entry-close
    focus $T
}
# A dialog's answer goes through the editor's own commit path, so one
# gesture ends in one committed value.
proc cfg-picked {name value} {
    cfg-entry-close
    cfg-set $name $value
    focus $::cfg_T
}
# The sub-editor a list deserves: one entry per line, which is the
# only shape in which a path list is readable and editable at all.
# Keyboard-first like the rest — the text has the focus from the
# start, Escape leaves, Alt+O and Alt+C are on the buttons; Return
# is a NEWLINE here (the list is multi-line by nature), so the
# commit is the button or its accelerator.
# The slot's ▾: which of the two spellings this row is, and the way
# across. One direction always works — a command is a script that
# says Run and nothing else. The other only when the script IS that
# and no more (run-words-of, which is strict on purpose): anything
# richer would have to be thrown away to fit a command field, so
# that entry stands DISABLED and says why in its own label rather
# than converting something it does not understand.
proc cfg-slot-menu {} {
    set it [cfg-selected]
    if {$it eq "" || ![dict exists $::cfg_node $it]
            || [dict get $::cfg_node $it what] ne "field"} {
        cfg-status "F3 switches how a slot is said — stand on one first" error
        return
    }
    set name [cfg-node-addr $it]
    if {![dict exists [cfg-field-meta $name] xor]} {
        cfg-status "[cfg-pretty $name] has only the one spelling" error
        return
    }
    set f [lindex $name 3]
    set T $::cfg_T
    catch {destroy $T.pop}
    menu $T.pop -tearoff 0 -font DeskFont
    set ::cfg_slot $f
    set value [cfg-cur $name]
    foreach other [concat [list $f] [dict get [cfg-field-meta $name] xor]] {
        if {$other eq $f} {
            $T.pop add radiobutton -label $other -variable ::cfg_slot \
                -value $other
            continue
        }
        # what the value would BECOME over there, and whether it can
        set to ""
        set why ""
        if {[lindex [cfg-kind-of $name] 0] eq "list"} {
            set to [list Run {*}$value]      ;# the command, said as a script
        } else {
            set to [wm-call [list run-words-of $value]]
            if {$to eq ""} { set why " (this script says more than a command can)" }
        }
        $T.pop add radiobutton -label "$other$why" -variable ::cfg_slot \
            -value $other -state [expr {$why eq "" ? "normal" : "disabled"}] \
            -command [list cfg-slot-switch $name $other $to]
    }
    lassign [$T item bbox [dict get $::cfg_fitem $name] Cval] x1 y1 x2 y2
    tk_popup $T.pop [expr {[winfo rootx $T] + $x1}] \
                    [expr {[winfo rooty $T] + $y2}]
}
# The switch itself: UN-SAY first and say after, because the two
# cannot stand together for even one command — the desk would refuse
# the pair, and rightly. A failure on the way leaves the field
# empty, which the field's own undo (a reload) puts back.
proc cfg-slot-switch {name to value} {
    lassign $name - coll key from
    if {![cfg-set $name {}]} return
    if {[cfg-set [list @field $coll $key $to] $value]} {
        cfg-status "$key: said as $to now"
    }
    cfg-refresh
}

proc cfg-list-dialog {name} {
    set w .cfg-list
    catch {destroy $w}
    toplevel $w -class Tk9wmUi
    wm title $w "tk9wm: [cfg-pretty $name]"
    wm transient $w [winfo toplevel $::cfg_T]
    set noun [lindex [cfg-kind-of $name] 1]
    if {$noun eq ""} { set noun entries }
    label $w.l -takefocus 0 -anchor w \
        -text "[cfg-pretty $name] — one [string range $noun 0 end-1] per line"
    text $w.t -font DeskFont -width 60 -height 10 -wrap none \
        -background [ui-color field] -foreground [ui-color fg] \
        -insertbackground [ui-color fg]
    ui-focusable $w.t
    foreach v [cfg-cur $name] { $w.t insert end "$v\n" }
    frame $w.b -takefocus 0
    ttk::button $w.b.ok     -text OK     -underline 0 \
        -command [list cfg-list-commit $name]
    ttk::button $w.b.cancel -text Cancel -underline 0 -command [list destroy $w]
    foreach b [list $w.b.ok $w.b.cancel] { ui-focusable $b; ui-accel $b }
    pack $w.b.ok $w.b.cancel -side left -padx 4 -pady 4
    pack $w.l -fill x -padx 6 -pady {6 2}
    pack $w.t -expand 1 -fill both -padx 6
    pack $w.b -fill x
    bind $w <Escape> [list destroy $w]
    focus $w.t
}
proc cfg-list-commit {name} {
    set out {}
    foreach line [split [string trim [.cfg-list.t get 1.0 end]] \n] {
        set line [string trim $line]
        if {$line ne ""} { lappend out $line }
    }
    destroy .cfg-list
    cfg-picked $name $out
}
# -parent, on both pickers: without it Tk's dialogs are neither
# transient nor grouped, and they sink behind the window that opened
# them (the owner watched both do it).
proc cfg-color-dialog {name} {
    set c [tk_chooseColor -parent [winfo toplevel $::cfg_T] \
        -initialcolor [cfg-cur $name] -title "tk9wm: $name"]
    if {$c ne ""} { cfg-picked $name $c }
}
# The dialog seeds from the COMPUTED font — what the desk actually
# draws with — even when the configured value is a two-word delta: a
# chooser has to start somewhere real.
proc cfg-font-dialog {name} {
    # ASKED NOW, not remembered: the table was fetched when the tree
    # was last built, and the desk font may have moved several times
    # since — the chooser opened on «Iosevka 11» long after the desk
    # had stopped being that (the owner). The kind names the font;
    # the desk knows what it currently IS.
    set which [lindex [dict get $::cfg_table $name kind] 1]
    if {[catch {wm-call [list font actual $which]} seed]} {
        cfg-status "$name: the desk did not answer what $which is now" error
        return
    }
    tk fontchooser configure \
        -parent [winfo toplevel $::cfg_T] \
        -title "tk9wm: $name" \
        -font [list [dict get $seed -family] [dict get $seed -size] \
                    [dict get $seed -weight]] \
        -command [list cfg-font-picked $name]
    tk fontchooser show
}
proc cfg-font-picked {name spec} {
    # picked by hand means stated whole — family, size and weight
    set a [font actual $spec]
    cfg-picked $name [list -family [dict get $a -family] \
        -size [dict get $a -size] -weight [dict get $a -weight]]
}

# cfg-set NAME VALUE — validate by kind, PREVIEW on the live desk,
# remember as pending. The programmatic door too (tests drive it by
# send), which is why it answers 1/0 instead of beeping alone.
# THE BOUNDARY. A refusal is an answer (0 and a sentence); an
# unexpected ERROR is something else — the knob may have run halfway
# before it threw, and a half-applied setting is a desk nobody asked
# for (the owner). So the whole apply path is fenced: anything that
# escapes puts the desk BACK to what its layers say — a reload, the
# same undo Revert uses — drops the pending previews with it, and
# says so on the status line instead of throwing a dialog at
# somebody who was only typing.
set cfg_broken 0     ;# the give-up state: we have stopped touching things
proc cfg-set {name value} {
    if {$::cfg_broken} {
        cfg-status "this configurator has given up — Revert, or restart\
 the desk; nothing here will touch the desk until then" error
        return 0
    }
    if {[catch {cfg-apply $name $value} r opts]} {
        cfg-recover $name $r $opts
        return 0
    }
    return $r
}
# THE NARROW UNDO FIRST. A knob that threw mid-apply is put back to
# what it is SAVED as — that one knob, not the whole desk, and the
# other pending previews are none of this accident's business (the
# owner's refinement). Only a knob whose value is the CODE's default
# needs the wide one: a default is not written down anywhere and a
# reload is the only way to re-state it.
proc cfg-restore {name} {
    # a FIELD's narrow undo is the wide one: only the layers know
    # what the element said before the preview touched it
    if {[cfg-field? $name]} {
        wm-call reload-config
        cfg-refresh
        return
    }
    set meta [dict get $::cfg_table $name]
    if {[dict get $meta owner] eq "code"} {
        wm-call reload-config
    } else {
        wm-call [cfg-command $name [dict get $meta value]]
    }
    cfg-refresh
}
# ...AND IF THE UNDO ITSELF FAILS, WE STOP. There is nothing left to
# try that would not be guessing with the user's live desk, so the
# configurator says exactly that and touches nothing further: no
# previews, no writes. Revert stays available — it is the user
# ASKING for the wide undo, which is a different thing from us
# reaching for it.
proc cfg-recover {name err {opts {}}} {
    puts "UI: configurator: setting $name FAILED: $err"
    if {[dict exists $opts -errorinfo]} { puts [dict get $opts -errorinfo] }
    catch {cfg-entry-close}
    dict unset ::cfg_pending $name
    if {[catch {cfg-restore $name} err2 opts2]} {
        set ::cfg_broken 1
        puts "UI: configurator: PUTTING $name BACK ALSO FAILED: $err2"
        if {[dict exists $opts2 -errorinfo]} { puts [dict get $opts2 -errorinfo] }
        catch {cfg-status "$name broke ([cfg-brief $err]) and could not be\
 put back either ([cfg-brief $err2]). The desk's live configuration may\
 be inconsistent and we have stopped touching it — Revert to re-read\
 the saved layers, or restart the desk." error}
        return
    }
    cfg-status "$name went wrong ([cfg-brief $err]) — that knob is back\
 on its saved value; anything else you had pending is untouched" error
}
proc cfg-apply {name value} {
    set kind [cfg-kind-of $name]
    set who [cfg-pretty $name]
    switch -- [lindex $kind 0] {
        int {
            if {![string is integer -strict $value]} {
                return [cfg-refuse "$who wants a whole number, not «$value»"]
            }
        }
        float {
            lassign $kind - lo hi
            if {![string is double -strict $value]} {
                return [cfg-refuse "$who wants a number, not «$value»"]
            }
            if {$value < $lo || $value > $hi} {
                return [cfg-refuse "$who wants a number between $lo and $hi"]
            }
        }
        color {
            if {[catch {winfo rgb . $value}]} {
                return [cfg-refuse "«$value» is not a color this display knows"]
            }
        }
        choice {
            if {$value ni [lrange $kind 1 end]} {
                return [cfg-refuse "$who is one of: [lrange $kind 1 end]"]
            }
        }
    }
    # The kinds whose value is a LIST are spread into the command, and
    # a half-quoted line is not a list at all: asking Tcl to expand it
    # threw the parse error at the user as a stack trace (the owner
    # typed one into the terminal field). Ask FIRST, and say so.
    switch -- [lindex $kind 0] {
        font - terminal - list - chord - dict {
            if {[catch {llength $value}]} {
                return [cfg-refuse "$who wants a list —\
 «$value» has an unmatched quote or brace"]
            }
        }
    }
    # A bundle that stands OFF has nowhere to hold new parameters —
    # wm-keys can only speak them while declaring the family up.
    if {[cfg-field? $name] && [lindex $name 1] eq "keys"
            && [lindex $name 3] eq "params"
            && [cfg-cur [list @field keys [lindex $name 2] state]] eq "off"} {
        return [cfg-refuse "$who: turn the bundle on first — off, it\
 keeps only its declaration defaults"]
    }
    set cmd [cfg-command $name $value]
    # And the DESK's own refusal is the user's to read: the knobs
    # validate (a bad place spec, an unknown terminal), and their
    # message says exactly what is wrong — far better than anything
    # this side could invent.
    # ...and it is said IN THE CUSTOM LAYER'S NAME. A preview is the
    # custom word arriving early — Save only writes down what the desk
    # is already doing — so anything that records WHOSE a thing is (a
    # binding's origin) must hear the same answer now as after the
    # save, or the tree would show the code's own word wearing an edit
    # nobody in the code ever made.
    if {[catch {wm-call [list say-as custom $cmd]} err]} {
        puts "UI: configurator: preview of «$cmd» refused: $err"
        return [cfg-refuse [cfg-brief $err]]
    }
    dict set ::cfg_pending $name [dict create cmd $cmd value $value]
    if {[cfg-field? $name]} {
        cfg-show-field $name
    } else {
        cfg-show-value [dict get $::cfg_item $name] $name $value
    }
    # A needs the machine cannot meet yet is a LEGITIMATE word (the
    # owner, 2026-07-31): declaring a button ahead of its software is
    # the point — the desk skips it quietly and the button appears by
    # itself when the command does. The applet accepts, and only SAYS
    # what will happen, so a vanished button is never a surprise.
    if {[cfg-field? $name] && [lindex $name 1] eq "actions"
            && [lindex $name 3] eq "needs"} {
        foreach c $value {
            if {[wm-call [list auto_execok $c]] eq ""} {
                cfg-status "«$c» is not on this machine — it will\
 stand by, visible here, until the command appears"
                return 1
            }
        }
    }
    cfg-status ""
    return 1
}
# How a knob's value becomes its command: the multi-argument kinds
# SPREAD (set-desk-font -family X -size N), a list travels whole as
# one argument, everything else is one word. The restore path builds
# the same way, which is what makes a saved value re-appliable.
proc cfg-command {name value} {
    if {[cfg-field? $name]} { return [cfg-field-command $name $value] }
    switch -- [lindex [dict get $::cfg_table $name kind] 0] {
        font - terminal { return [list $name {*}$value] }
        default         { return [list $name $value] }
    }
}
# ...and how a FIELD edit becomes one — per family, because each verb
# has its own grammar:
#   actions  — action KEY {FIELD V}: the verb MERGES by name, so the
#              delta alone is the whole edit — and panel likewise,
#              panel-button KEY {FIELD V} merging the overrides;
#   bindings — wm-bind re-states the pair, the other half riding
#              along from the element;
#   widgets  — wm-widget replaces WHOLE: the element's standing
#              options, its other pendings, then this edit;
#   keys     — off is a word of its own; anything else re-declares
#              the bundle from its params.
proc cfg-field-command {name value} {
    lassign $name - coll key f
    switch -- $coll {
        actions { return [list action $key [list $f $value]] }
        panel   { return [list panel-button $key [list $f $value]] }
        bindings {
            set script [expr {$f eq "script" ? $value
                : [cfg-cur [list @field bindings $key script]]}]
            set bname [expr {$f eq "name" ? $value
                : [cfg-cur [list @field bindings $key name]]}]
            return [list wm-bind [split $key " "] $script $bname]
        }
        widgets {
            set opts [cfg-elem-values widgets $key]
            dict for {a p} $::cfg_pending {
                if {[cfg-field? $a] && [lindex $a 1] eq "widgets"
                        && [lindex $a 2] eq $key} {
                    dict set opts [lindex $a 3] [dict get $p value]
                }
            }
            dict set opts $f $value
            return [list wm-widget $key {*}$opts]
        }
        keys {
            if {$f eq "state" && $value eq "off"} {
                return [list wm-keys $key off]
            }
            set params [expr {$f eq "params" ? $value
                : [cfg-cur [list @field keys $key params]]}]
            set cmd [list wm-keys $key]
            dict for {k v} $params { lappend cmd -$k $v }
            return $cmd
        }
    }
}
# The desk answers with an error, sometimes a multi-line one; the
# status line wants its first sentence.
proc cfg-brief {err} {
    set one [string trim [regsub -all {\s+} [lindex [split $err \n] 0] " "]]
    if {[string length $one] > 90} { set one "[string range $one 0 87]…" }
    return $one
}
proc cfg-save {} {
    # The PANEL fields do not write their preview commands: the panel
    # set is custom's whole or not custom's at all (the owner's
    # decision 2), so their pendings fold into one adoption below.
    # Everything else persists its own preview command — for a
    # binding, widget or bundle that command already re-states the
    # whole element.
    set deltas {}
    set adeltas {}
    dict for {name pend} $::cfg_pending {
        if {[cfg-field? $name] && [lindex $name 1] eq "panel"} {
            dict set deltas [lindex $name 2] [lindex $name 3] \
                [dict get $pend value]
        } elseif {[cfg-field? $name] && [lindex $name 1] eq "actions"} {
            dict set adeltas [lindex $name 2] [lindex $name 3] \
                [dict get $pend value]
        } else {
            wm-call [list custom-write [dict get $pend cmd]]
        }
    }
    if {[dict size $adeltas]} { cfg-save-actions $adeltas }
    if {[dict size $deltas]} { cfg-save-panel $deltas }
    set ::cfg_pending {}
    cfg-refresh
    puts "UI: configurator: saved"
}
# An action's custom word is ONE entry keyed by name, so a save must
# accumulate onto what custom already said — the panel set's
# said+delta rule, without the adoption (no set here to own).
proc cfg-save-actions {deltas} {
    dict for {key delta} $deltas {
        set e [cfg-elem-rec actions $key]
        set said ""
        if {$e ne "" && [dict exists $e said]} { set said [dict get $e said] }
        wm-call [list custom-write \
                     [list action $key [dict merge $said $delta]]]
    }
}
# ADOPTION (the owner's decision 2). A set custom already owns takes
# the touched references as said+delta — the standing custom word
# with the edits over it, so an older delta survives this one. A set
# it does not yet own is taken WHOLE — cfg-adopt-panel below.
proc cfg-save-panel {deltas} {
    set c [dict get $::cfg_coll panel]
    if {[dict get $c owned] ne "yes"} {
        cfg-adopt-panel $deltas
        return
    }
    foreach e [dict get $c elements] {
        set key [dict get $e key]
        if {![dict exists $deltas $key]} continue
        set said [expr {[dict exists $e said] ? [dict get $e said] : ""}]
        wm-call [list custom-write [list panel-button $key \
            [dict merge $said [dict get $deltas $key]]]]
    }
}
# Taking the set whole: own the panel, then every reference in panel
# order — a touched one as said+delta, an untouched one by its
# standing word (usually {}: the bare name, which IS the whole
# reference — the description lives on the action), and a skipped
# one not at all — which is what a Delete is.
proc cfg-adopt-panel {deltas {skip {}}} {
    set c [dict get $::cfg_coll panel]
    wm-call [list custom-write {panel-buttons-own default}]
    foreach e [dict get $c elements] {
        set key [dict get $e key]
        if {$skip ne "" && $key eq $skip} continue
        set said [expr {[dict exists $e said] ? [dict get $e said] : ""}]
        if {[dict exists $deltas $key]} {
            set said [dict merge $said [dict get $deltas $key]]
        }
        wm-call [list custom-write [list panel-button $key $said]]
    }
}
# Erase the selected knob's customization: the click taken back, the
# file rewritten without it, and the desk reloaded so the knob falls
# back to the config's word or the code's. Also drops a pending
# preview for that knob — it is the same "never mind".
proc cfg-erase {} {
    set it [cfg-selected]
    if {$it eq ""} return
    set name [cfg-name-of $it]
    if {$name eq ""} return
    dict unset ::cfg_pending $name
    if {[cfg-owner $name] ne "custom"} {
        cfg-status "$name carries no customization to erase"
        return
    }
    wm-call [list custom-erase $name]
    cfg-refresh
    cfg-status "$name is back to [cfg-owner $name]'s word"
}
proc cfg-revert {} {
    set ::cfg_pending {}
    wm-call reload-config
    cfg-refresh
    if {$::cfg_broken} {
        set ::cfg_broken 0
        cfg-status "the layers were re-read and this configurator is\
 working again"
    }
    puts "UI: configurator: reverted to the desk's own layers"
}

# ---- the composition gestures (plan step C) ----
# What a knob never needed: elements COME AND GO and change places.
# Delete drops one out of its family, Insert brings one in (from a
# card, a type, or thin air), Alt moves a button through its owned
# set, Ctrl+Enter TAKES — the panel whole (decision 2) or chosen
# binds out of their bundle (decision 4).

# One question, one honest dialog — and a seam the tests stub out.
proc cfg-confirm {msg} {
    expr {[tk_messageBox -type yesno -icon question -default no \
               -parent [winfo toplevel $::cfg_T] \
               -title "tk9wm configurator" -message $msg] eq "yes"}
}
# The element the gesture is aimed at, or "" with a sentence.
proc cfg-elem-of {it} {
    if {$it eq "" || ![dict exists $::cfg_node $it]} { return "" }
    set d [dict get $::cfg_node $it]
    expr {[dict get $d what] eq "elem" ? $d : ""}
}
# The element's record as the table served it. The dead flag picks
# between a buried bind and the live one on the same chord — two
# rows, one key.
proc cfg-elem-rec {coll key {dead 0}} {
    foreach e [dict get $::cfg_coll $coll elements] {
        if {[dict get $e key] eq $key
                && [dict exists $e ineffectual] == $dead} { return $e }
    }
    return ""
}

# ---- Delete: take back what WE said ----
# It used to mean two different things chosen silently by who owned
# the row — erase a customization here, write a suppressing word
# there — and the owner walked straight into the seam (2026-08-01:
# «во многих случаях del вроде работает как erase customization на
# поддереве, может это узаконить?»). So: Delete ERASES OUR WORD, and
# nothing else. On a family node it erases every word of ours in that
# family, which is the subtree reading of the same sentence.
#
# Taking something the CONFIG (or the code) declared is a different
# act — it needs a word of our own that says «not this one», and for
# a panel it needs the whole set to become ours. That still happens,
# but only through a question that says exactly what will follow (his
# decision, same day), because the consequence outlives the click:
# an owned set stops following the config.
proc cfg-delete {} {
    set it [cfg-selected]
    if {$it eq "" || ![dict exists $::cfg_node $it]} return
    set d [dict get $::cfg_node $it]
    switch -- [dict get $d what] {
        coll  { cfg-delete-family [dict get $d coll]; return }
        shadow {
            if {[dict get $d owner] ne "custom"} {
                cfg-status "that is the config's own word, kept here\
 because yours stands over it — the file that says it is yours to\
 edit, not this applet's"
                return
            }
            set e [cfg-elem-rec bindings [dict get $d key]]
            foreach claim [dict get $e shadowed] {
                if {[dict get $claim owner] ne "custom"} continue
                wm-call [list custom-erase [dict get $claim lkey]]
            }
            cfg-refresh
            cfg-status "[dict get $d key]: your word that was not in\
 force is taken back"
            return
        }
        field {
            cfg-status "a field is part of its element's word — Delete\
 on the element takes the whole of it back, or edit this to {} to\
 unsay just this one"
            return
        }
    }
    set coll [dict get $d coll]
    set key [dict get $d key]
    set e [cfg-elem-rec $coll $key [dict exists $d dead]]
    if {$coll eq "keys"} {
        cfg-status "a bundle is not deleted — turn its state off, or\
 take the binds you want and the rest goes with it"
        return
    }
    # OURS: the plain case, and the only one that needs no question.
    if {[dict get $e owner] eq "custom"} {
        cfg-erase-word $coll $key $e
        cfg-refresh
        cfg-status "$key: your word here is taken back"
        return
    }
    if {[dict exists $e ineffectual]} {
        cfg-status "$key is the config's buried word — the file that\
 says it is yours to edit, not this applet's"
        return
    }
    # NOT OURS: say what it will cost before doing it.
    switch -- $coll {
        panel {
            if {![cfg-confirm "«$key» is the config's button. Dropping\
 it makes THE WHOLE SET yours: buttons the config adds later will not\
 appear here any more. Take the panel over and drop it?"]} return
            cfg-adopt-panel {} $key
        }
        bindings {
            if {![cfg-confirm "«$key» is not your binding. Dropping it\
 writes a silence of your own over it, which is itself a\
 customization — Delete on that takes it back and the chord returns.\
 Silence it?"]} return
            wm-call [list custom-write [list wm-unbind [split $key " "]]]
        }
        widgets {
            if {![cfg-confirm "«$key» is not your widget. Dropping it\
 writes a removal of your own over it, which is itself a\
 customization — Delete on that takes it back. Remove it?"]} return
            wm-call [list custom-write [list wm-widget-remove $key]]
        }
        actions {
            if {![cfg-confirm "«$key» is the [dict get $e owner]'s deed.\
 Dropping it writes a removal of your own over it, which is itself a\
 customization — Delete on that takes it back. Remove it?"]} return
            wm-call [list custom-write [list action-remove $key]]
        }
    }
    cfg-refresh
    cfg-status "$key dropped from $coll — Insert brings elements back"
}
# The word we hold about ONE element, whatever family it is in.
proc cfg-erase-word {coll key e} {
    if {[dict exists $e lkey]} {
        wm-call [list custom-erase [dict get $e lkey]]
        return
    }
    switch -- $coll {
        panel   { wm-call [list custom-erase "panel-button $key"] }
        actions { wm-call [list custom-erase "action $key"] }
        widgets { wm-call [list custom-erase "wm-widget $key"] }
        default { wm-call [list custom-erase "$coll $key"] }
    }
}
# ...and the subtree reading: everything of ours in one family. The
# desk answers what our words ARE (layer-touched), so this needs no
# list of families of its own — and one reload lands them all.
proc cfg-delete-family {coll} {
    set verbs [dict get {actions {action action-remove} panel
        {panel-button panel-buttons-own} bindings {wm-bind}
        widgets {wm-widget} keys {wm-keys}} $coll]
    set mine {}
    foreach k [wm-call {layer-touched custom}] {
        if {[lindex $k 0] in $verbs} { lappend mine $k }
    }
    if {![llength $mine]} {
        cfg-status "nothing of yours in $coll — this family is the\
 config's and the code's as it stands"
        return
    }
    if {![cfg-confirm "Take back everything you have said about\
 $coll — [llength $mine] word(s)? What the config and the code say\
 stays and comes back into force."]} return
    foreach k $mine { wm-call [list custom-erase $k] }
    cfg-refresh
    cfg-status "$coll: [llength $mine] word(s) of yours taken back"
}

# Alt+Up / Alt+Down — the owned set's order is the custom file's
# order (decision 2), so a move is: own the set if config still
# rules it, permute the entries (custom-reorder), and replay — only
# a reload honors how the layers interleave.
proc cfg-move-elem {dir} {
    set d [cfg-elem-of [cfg-selected]]
    if {$d eq ""} return
    if {[dict get $d coll] ne "panel"} {
        cfg-status "only the panel's buttons move today: a widget's\
 place follows the layers' declaration order"
        return
    }
    set key [dict get $d key]
    set order [lmap e [dict get $::cfg_coll panel elements] \
                   {dict get $e key}]
    set i [lsearch -exact $order $key]
    set j [expr {$dir eq "above" ? $i - 1 : $i + 1}]
    if {$i < 0 || $j < 0 || $j >= [llength $order]} return   ;# the edge
    if {[dict get $::cfg_coll panel owned] ne "yes"} {
        cfg-adopt-panel {}
    }
    set order [linsert [lreplace $order $i $i] $j $key]
    wm-call [list custom-reorder \
                 [lmap l $order {string cat "panel-button " $l}]]
    wm-call reload-config
    cfg-refresh
    cfg-status "$key moved — the set's order is the custom layer's now"
}

# Ctrl+Enter. On the panel family (its node or any element): take
# the panel set whole — decision 2's one action. On bindings: take
# the selected binds into the custom layer as plain wm-bind; any
# bundle they came out of falls silent (decision 4), the off written
# FIRST so the replay cannot sweep the kept binds.
proc cfg-take {} {
    set items [$::cfg_T selection get]
    if {![llength $items]} return
    set what ""
    foreach it $items {
        if {![dict exists $::cfg_node $it]} continue
        set d [dict get $::cfg_node $it]
        if {[dict get $d coll] eq "panel"} { set what panel; break }
        if {[dict get $d what] eq "elem"
                && [dict get $d coll] eq "bindings"} {
            set what bindings
            break
        }
    }
    switch -- $what {
        panel {
            if {[dict get $::cfg_coll panel owned] eq "yes"} {
                cfg-status "the panel set is already yours"
                return
            }
            cfg-adopt-panel {}
            cfg-refresh
            cfg-status "the panel set is yours now — its order and\
 members are the custom layer's word"
        }
        bindings {
            set taken {}
            set bundles {}
            foreach it $items {
                if {![dict exists $::cfg_node $it]} continue
                set d [dict get $::cfg_node $it]
                if {[dict get $d what] ne "elem"
                        || [dict get $d coll] ne "bindings"} continue
                set e [cfg-elem-rec bindings [dict get $d key]]
                if {[dict get $e owner] eq "custom"} continue
                if {[dict exists $e ineffectual]} continue
                lappend taken $e
                if {[dict exists $e bundle]} {
                    dict set bundles [dict get $e bundle] 1
                }
            }
            if {![llength $taken]} {
                cfg-status "nothing here to take: select the binds\
 you want as your own (Ctrl+click adds to the selection)"
                return
            }
            foreach b [dict keys $bundles] {
                wm-call [list custom-write [list wm-keys $b off]]
            }
            foreach e $taken {
                wm-call [list custom-write [list wm-bind \
                    [split [dict get $e key] " "] \
                    [dict get $e values script] \
                    [dict get $e values name]]]
            }
            cfg-refresh
            if {[dict size $bundles]} {
                cfg-status "[llength $taken] binds are yours; the\
 [join [dict keys $bundles] {, }] bundle went off with the rest"
            } else {
                cfg-status "[llength $taken] binds are yours now"
            }
        }
        default {
            cfg-status "Ctrl+Enter takes: the panel set whole, or\
 selected binds out of their bundle"
        }
    }
}

# Insert — what CAN come in, per family: a panel button from the
# card list (every action not on the panel — this is where a deleted
# button comes back) or by a typed name the actions may not know
# yet; a widget from its type catalogue; a binding from a chord and
# a script. The keys family is closed — its members are fixed in
# code.
proc cfg-insert {} {
    set it [cfg-selected]
    if {$it eq "" || ![dict exists $::cfg_node $it]} {
        cfg-status "Insert works inside a collection — stand on a\
 family or one of its elements"
        return
    }
    switch -- [dict get $::cfg_node $it coll] {
        actions  { cfg-pick-dialog "new action" {} \
                       "name for the new action" cfg-insert-action }
        panel    { cfg-insert-panel-dialog }
        widgets  { cfg-insert-widgets-dialog }
        bindings { cfg-insert-binding-dialog }
        keys     { cfg-status "the bundles are fixed in code — turn\
 them on and off, or take their binds" }
    }
}
# A fresh action is born empty and edited into shape — the same road
# a fresh button label walks.
proc cfg-insert-action {choice typed} {
    set name [expr {$choice ne "" ? $choice : $typed}]
    if {$name eq ""} { return 0 }
    if {[cfg-elem-rec actions $name] ne ""} {
        return [cfg-refuse "an action named $name already stands —\
 pick another name"]
    }
    if {[catch {wm-call [list custom-write [list action $name {}]]} err]} {
        return [cfg-refuse [cfg-brief $err]]
    }
    cfg-refresh
    cfg-status "$name is declared — fill its fields in"
    return 1
}

# The commit half of each Insert, dialogless — the programmatic door
# the tests drive, like cfg-set beside the editors.
proc cfg-insert-button {name} {
    if {$name eq ""} { return 0 }
    if {[cfg-elem-rec panel $name] ne ""} {
        cfg-status "$name is already on the panel"
        return 1
    }
    if {[dict get $::cfg_coll panel owned] ne "yes"} {
        cfg-adopt-panel {}
    }
    # the bare name IS the whole reference — the description lives on
    # the action. Referencing a waiting or still-undeclared action is
    # legitimate (the button waits with it), so no name is refused;
    # the status only says what will show when.
    if {[catch {wm-call [list custom-write \
                             [list panel-button $name {}]]} err]} {
        return [cfg-refuse [cfg-brief $err]]
    }
    cfg-refresh
    set a [cfg-elem-rec actions $name]
    if {$a eq ""} {
        cfg-status "$name is on the panel — no action of that name\
 yet, so the button stands by until one is declared"
    } elseif {[dict exists $a waiting]} {
        cfg-status "$name is on the panel — it stands by until what\
 its action needs appears on this machine"
    } else {
        cfg-status "$name is on the panel"
    }
    return 1
}
proc cfg-insert-widget {name type} {
    if {$name eq "" || $type eq ""} { return 0 }
    if {[cfg-elem-rec widgets $name] ne ""} {
        return [cfg-refuse "a widget named $name already stands —\
 pick another name"]
    }
    if {[catch {wm-call [list custom-write \
                             [list wm-widget $name -type $type]]} err]} {
        return [cfg-refuse [cfg-brief $err]]
    }
    cfg-refresh
    cfg-status "$name is up — place it with its fields"
    return 1
}
proc cfg-insert-bind {spec script} {
    if {$spec eq "" || $script eq ""} { return 0 }
    # WHO IS ALREADY THERE. Binding over somebody else's chord is
    # allowed — that is how one takes a deed out of a family — but it
    # is never a thing to discover afterwards, which is exactly what
    # the owner walked into (2026-08-01). The desk knows the holder
    # and where it was said; this asks with both in the sentence.
    set held ""
    catch {wm-call [list chord-holder [split $spec " "]]} held
    if {[dict exists $held who]} {
        if {![cfg-confirm "[join $spec { }] already answers —\
 [cfg-holder-sentence $held]. Binding here takes the chord while both\
 stand; the other word comes back when yours goes."]} { return 0 }
    }
    if {[catch {wm-call [list custom-write \
                             [list wm-bind [split $spec " "] $script]]} err]} {
        return [cfg-refuse [cfg-brief $err]]
    }
    cfg-refresh
    cfg-status "[join $spec " "] is bound"
    return 1
}

# ---- what have I actually changed? ----
# The two kinds of customization counted, and the pins offered up for
# dropping — offered, never taken: a word that says what the layer
# below says may be exactly what its author meant (that is what
# taking a bind out of a bundle IS). So this shows the list and asks,
# and a no leaves everything standing.
proc cfg-pins {} {
    set audit [wm-call custom-audit]
    set changes [llength [dict get $audit changes]]
    set pins [dict get $audit pins]
    if {![llength $pins]} {
        cfg-status "$changes word(s) of yours, and every one of them\
 changes something — nothing here is holding what the layers below\
 already say"
        return
    }
    set names {}
    foreach k $pins { lappend names [join $k " "] }
    if {![cfg-confirm "You have $changes word(s) that change something\
 and [llength $pins] that hold what the config or the code already\
 says:\n\n  [join $names "\n  "]\n\nHolding one may be the whole\
 point — a bind taken out of a family is a hold on purpose. Drop all\
 [llength $pins] of them?"]} {
        cfg-status "$changes change(s), [llength $pins] hold(s) —\
 nothing dropped"
        return
    }
    set gone [wm-call [list custom-drop $pins]]
    cfg-refresh
    cfg-status "$gone word(s) that changed nothing are gone; the\
 layers below say the same thing without them"
}

# The holder of a chord, in one sentence: the deed, whose word it is,
# on which line it was said, and — for a family — the parameters it
# stands on, because «accords» and «accords under another prefix» are
# different answers to «where did this come from».
proc cfg-holder-sentence {held} {
    set who [dict get $held who]
    if {[lindex $who 0] eq "bundle"} {
        set s "«[dict get $held script]» from the [lindex $who 1] family"
        if {[dict exists $held params] && [dict size [dict get $held params]]} {
            set bits {}
            dict for {k v} [dict get $held params] { lappend bits "$k $v" }
            append s " ([join $bits {, }])"
        }
    } else {
        set s "«[dict get $held script]», [cfg-owner-words \
                   [dict create owner $who]]"
    }
    if {[dict exists $held where]} {
        append s ", said at [file tail [dict get $held where]]"
    }
    return $s
}

# The dialogs: keyboard-first like the list sub-editor — a listbox
# of what there is, an entry for what there is not, OK and Cancel
# with their accelerators.
proc cfg-insert-panel-dialog {} {
    set cards [dict get $::cfg_coll panel cards]
    cfg-pick-dialog "new panel button — an action" $cards \
        "or an action's name" cfg-insert-button
}
proc cfg-insert-widgets-dialog {} {
    set types [dict get $::cfg_coll widgets types]
    cfg-pick-dialog "new widget — pick its type" $types \
        "name for the new widget" cfg-insert-widget-picked
}
proc cfg-insert-widget-picked {choice entry} {
    # for widgets the LIST is the type and the ENTRY is the name
    cfg-insert-widget $entry $choice
}
# One shape serves buttons and widgets: a list to pick from, an entry
# beside it. The commit callback gets what was picked and what was
# typed; buttons use one of the two, widgets need both.
proc cfg-pick-dialog {title choices entrylabel commit} {
    set w .cfg-insert
    catch {destroy $w}
    toplevel $w -class Tk9wmUi
    wm title $w "tk9wm: $title"
    wm transient $w [winfo toplevel $::cfg_T]
    label $w.l -takefocus 0 -anchor w -text $title
    listbox $w.list -font DeskFont -height [expr {max(3, min(10,
        [llength $choices]))}] \
        -background [ui-color field] -foreground [ui-color fg] \
        -selectbackground [ui-color select]
    ui-focusable $w.list
    foreach c $choices { $w.list insert end $c }
    label $w.el -takefocus 0 -anchor w -text $entrylabel
    entry $w.e -font DeskFont -background [ui-color field] \
        -foreground [ui-color fg] -insertbackground [ui-color fg]
    ui-focusable $w.e
    frame $w.b -takefocus 0
    ttk::button $w.b.ok -text OK -underline 0 \
        -command [list cfg-pick-commit $w $commit]
    ttk::button $w.b.cancel -text Cancel -underline 0 \
        -command [list destroy $w]
    foreach b [list $w.b.ok $w.b.cancel] { ui-focusable $b; ui-accel $b }
    pack $w.b.ok $w.b.cancel -side left -padx 4 -pady 4
    pack $w.l -fill x -padx 6 -pady {6 2}
    pack $w.list -expand 1 -fill both -padx 6
    pack $w.el -fill x -padx 6 -pady {6 2}
    pack $w.e -fill x -padx 6
    pack $w.b -fill x
    bind $w <Escape> [list destroy $w]
    bind $w.list <Double-ButtonPress-1> [list cfg-pick-commit $w $commit]
    bind $w.list <Return> [list cfg-pick-commit $w $commit]
    bind $w.e <Return> [list cfg-pick-commit $w $commit]
    focus [expr {[llength $choices] ? "$w.list" : "$w.e"}]
}
proc cfg-pick-commit {w commit} {
    set choice ""
    if {[llength [$w.list curselection]]} {
        set choice [$w.list get [lindex [$w.list curselection] 0]]
    }
    set typed [string trim [$w.e get]]
    destroy $w
    if {$commit eq "cfg-insert-button"} {
        # picked wins; typed is the fresh-label road
        cfg-insert-button [expr {$choice ne "" ? $choice : $typed}]
    } else {
        $commit $choice $typed
    }
}
proc cfg-insert-binding-dialog {} {
    set w .cfg-insert
    catch {destroy $w}
    toplevel $w -class Tk9wmUi
    wm title $w "tk9wm: new binding"
    wm transient $w [winfo toplevel $::cfg_T]
    label $w.cl -takefocus 0 -anchor w \
        -text "chord sequence — as the desk shows them: <Super>j, Super+t w"
    entry $w.chord -font DeskFont -background [ui-color field] \
        -foreground [ui-color fg] -insertbackground [ui-color fg]
    label $w.sl -takefocus 0 -anchor w -text "what it runs"
    entry $w.script -font DeskFont -background [ui-color field] \
        -foreground [ui-color fg] -insertbackground [ui-color fg]
    ui-focusable $w.chord
    ui-focusable $w.script
    frame $w.b -takefocus 0
    ttk::button $w.b.ok -text OK -underline 0 -command [list cfg-bind-commit $w]
    ttk::button $w.b.cancel -text Cancel -underline 0 \
        -command [list destroy $w]
    foreach b [list $w.b.ok $w.b.cancel] { ui-focusable $b; ui-accel $b }
    pack $w.b.ok $w.b.cancel -side left -padx 4 -pady 4
    foreach x {cl chord sl script} { pack $w.$x -fill x -padx 6 -pady 2 }
    pack $w.b -fill x
    bind $w <Escape> [list destroy $w]
    bind $w.script <Return> [list cfg-bind-commit $w]
    focus $w.chord
}
proc cfg-bind-commit {w} {
    set spec [string trim [$w.chord get]]
    set script [string trim [$w.script get]]
    destroy $w
    cfg-insert-bind $spec $script
}