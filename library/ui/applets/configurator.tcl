# The configurator — a RENDERER of the desk's own knob registry, and
# nothing more: every row comes from knob-table, fetched live, so this
# applet has no opinion about what knobs exist. treectrl (the owner's
# standing preference, and a tree of groups IS a tree), one row per
# knob under its group node.
#
# KEYBOARD-FIRST, by the owner's review of the first cut:
#   - the tree takes focus on open, and the focus is VISIBLE — a
#     highlight ring on the tree and the buttons, an outlined bar on
#     the selected row;
#   - arrows (and k/j, p/n, Ctrl+p/Ctrl+n) walk the rows; Return or
#     F2 ACTIVATES — a bool toggles, a choice drops a menu, the
#     free-form kinds open the overlay entry, color and font their
#     dialogs; Left/Right fold and unfold a group;
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
set cfg_pending {}   ;# name -> the command previewed but not saved
set cfg_item {}      ;# name -> tree item
set cfg_T ""
set cfg_hint "Return, F4 or double-click opens the picker · F2 types ·\
 Save makes it stick · Erase takes a saved click back"

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
    treectrl $W.t -showheader yes -showroot no -showbuttons yes \
        -selectmode single -itemheight $ih \
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
    label  $W.b.note -takefocus 0 -anchor w -justify left -text $::cfg_hint \
        -foreground [ui-color link]
    pack $W.b.save $W.b.revert $W.b.erase -side left -padx 4 -pady 4
    pack $W.b.note -side left -padx 12
    grid $W.b -row 2 -columnspan 2 -sticky ew
    # ...and the box stops propagating its children's appetite: a
    # longer or shorter status line used to resize the whole window
    # under the owner's hands as he typed (a short refusal SHRANK it).
    update idletasks
    # Two lines' worth, always: a refusal is a sentence and sometimes
    # a long one, and it was running off the end (the owner). The box
    # keeps that height whatever the text does, so the window walls
    # still do not move; the wrap length follows the window's width.
    $W.b configure -height [expr {max([winfo reqheight $W.b],
        2*[font metrics DeskFont -linespace] + 12)}]
    pack propagate $W.b 0
    bind $W <Configure> {cfg-note-wrap %W %w}

    # CONDITIONAL breaks: a plain `break` swallowed the class bindings
    # too, and with them treectrl's own header work — column drags and
    # resizes stopped (the owner's report). The helpers answer whether
    # the press was theirs; a press on the header is not.
    bind $T <ButtonPress-1>        {if {[cfg-click %x %y]} break}
    bind $T <Double-ButtonPress-1> {if {[cfg-doubleclick %x %y]} break}
    foreach k {Up k p} { bind $T <KeyPress-$k> {cfg-move above; break} }
    foreach k {Down j n} { bind $T <KeyPress-$k> {cfg-move below; break} }
    bind $T <Control-p> {cfg-move above; break}
    bind $T <Control-n> {cfg-move below; break}
    bind $T <KeyPress-Return> {cfg-activate primary; break}
    bind $T <KeyPress-F4>     {cfg-activate primary; break}
    bind $T <KeyPress-F2>     {cfg-activate text; break}
    # h/l fold and unfold beside the arrows, the way k/j walk beside
    # Up and Down (the owner's ask — vi hands)
    foreach k {Left h} { bind $T <KeyPress-$k> {cfg-fold collapse; break} }
    foreach k {Right l} { bind $T <KeyPress-$k> {cfg-fold expand; break} }
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
proc cfg-note-wrap {W w} {
    if {$W ne [winfo toplevel $::cfg_T]} return
    set l $W.b.note
    if {[winfo exists $l]} {
        set room [expr {$w - [winfo x $l] - 12}]
        if {$room > 80} { $l configure -wraplength $room }
    }
    if {!$::cfg_user_sized && [llength $::cfg_fit_size]} {
        lassign $::cfg_fit_size fw fh
        if {abs($w - $fw) > 2 || abs([winfo height $W] - $fh) > 2} {
            set ::cfg_user_sized 1
            puts "UI: configurator: sized by hand — the fit steps aside"
        }
    }
}

# Any scroll ends an open editor (as a commit attempt): the entry is
# placed at pixel coordinates and the rows move under it.
proc cfg-yscroll {sb a b} {
    if {[winfo exists $::cfg_T.edit]} { cfg-entry-done commit }
    $sb set $a $b
}

# A refresh REBUILDS the tree, and the user's place in it must
# survive that (the owner: a Revert threw the navigation back to the
# top). What is remembered is what the user arranged — the selected
# knob and which groups stand folded — and it is restored by NAME,
# so it holds even if the registry itself changed underneath.
proc cfg-owner {name} {
    expr {[dict exists $::cfg_table $name owner]
          ? [dict get $::cfg_table $name owner] : "code"}
}
proc cfg-refresh {} {
    set T $::cfg_T
    set was_sel [expr {[cfg-selected] eq "" ? "" : [cfg-name-of [cfg-selected]]}]
    set was_folded {}
    # `open` is one of treectrl's built-in item states — the expanded
    # flag lives there, not in an option
    foreach g [$T item children root] {
        if {![$T item state get $g open]} {
            lappend was_folded [$T item element cget $g Cname eGrp -text]
        }
    }
    $T item delete all
    set ::cfg_table [wm-call knob-table]
    set ::cfg_item {}
    set groups {}
    dict for {name meta} $::cfg_table {
        dict lappend groups [dict get $meta group] $name
    }
    foreach group [lsort [dict keys $groups]] {
        set g [$T item create -button yes]
        $T item style set $g Cname sGrp
        $T item element configure $g Cname eGrp -text $group
        $T item lastchild root $g
        foreach name [lsort [dict get $groups $group]] {
            set meta [dict get $::cfg_table $name]
            set it [$T item create]
            $T item style set $it Cname sName Cval sVal Cflag sFlag Cdoc sDoc
            $T item element configure $it Cname eTxt -text $name
            $T item element configure $it Cdoc eDoc -text [dict get $meta doc]
            cfg-show-value $it $name [dict get $meta value]
            $T item lastchild $g $it
            dict set ::cfg_item $name $it
        }
        if {$group in $was_folded} { $T collapse $g }
    }
    cfg-fit
    if {$was_sel ne "" && [dict exists $::cfg_item $was_sel]} {
        cfg-select [dict get $::cfg_item $was_sel]
    } else {
        set first [lindex [dict values $::cfg_item] 0]
        if {$first ne ""} { cfg-select $first }
    }
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
    $T column configure Cname -width {} -maxwidth $cap
    $T column configure Cval  -width {} -minwidth 140 -maxwidth $cap
    $T column configure Cflag -width {} \
        -minwidth [expr {[font measure DeskFont "• custom"] + 12}]
    $T column configure Cdoc  -width {} -minwidth [expr {$wdoc + 16}]
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
    set maxh [expr {$wh - $top - $B - [winfo reqheight $W.b] - 8}]
    $T configure \
        -width  [expr {min($wall + 24, $maxw)}] \
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

# What a value LOOKS like in its cell. A list says how many it holds
# and of what — «[2 directories]» — rather than spelling itself out
# and blowing the column open (the owner's review); the whole of it
# lives in the sub-editor, one line per entry.
proc cfg-value-text {name value} {
    set kind [dict get $::cfg_table $name kind]
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
    if {[lindex [dict get $::cfg_table $name kind] 0] eq "font"
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
    if {$name eq ""} { $::cfg_T toggle $it; return }   ;# a group folds
    set kind [dict get $::cfg_table $name kind]
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
# Which kinds have a picker behind the ▾ — and what it is.
proc cfg-picker-of {name} {
    switch -- [lindex [dict get $::cfg_table $name kind] 0] {
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
    expr {[dict exists $::cfg_pending $name]
          ? [dict get $::cfg_pending $name value]
          : [dict get $::cfg_table $name value]}
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
proc cfg-list-dialog {name} {
    set w .cfg-list
    catch {destroy $w}
    toplevel $w -class Tk9wmUi
    wm title $w "tk9wm: $name"
    wm transient $w [winfo toplevel $::cfg_T]
    set noun [lindex [dict get $::cfg_table $name kind] 1]
    label $w.l -takefocus 0 -anchor w -text "$name — one [string range $noun 0 end-1] per line"
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
    if {![dict exists $::cfg_table $name computed]} {
        cfg-status "$name has no computed font to start a chooser from" error
        return
    }
    set seed [dict get $::cfg_table $name computed]
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
    set kind [dict get $::cfg_table $name kind]
    switch -- [lindex $kind 0] {
        int {
            if {![string is integer -strict $value]} {
                return [cfg-refuse "$name wants a whole number, not «$value»"]
            }
        }
        float {
            lassign $kind - lo hi
            if {![string is double -strict $value]} {
                return [cfg-refuse "$name wants a number, not «$value»"]
            }
            if {$value < $lo || $value > $hi} {
                return [cfg-refuse "$name wants a number between $lo and $hi"]
            }
        }
        color {
            if {[catch {winfo rgb . $value}]} {
                return [cfg-refuse "«$value» is not a color this display knows"]
            }
        }
    }
    # The kinds whose value is a LIST are spread into the command, and
    # a half-quoted line is not a list at all: asking Tcl to expand it
    # threw the parse error at the user as a stack trace (the owner
    # typed one into the terminal field). Ask FIRST, and say so.
    switch -- [lindex $kind 0] {
        font - terminal - list {
            if {[catch {llength $value}]} {
                return [cfg-refuse "$name wants a list —\
 «$value» has an unmatched quote or brace"]
            }
        }
    }
    set cmd [cfg-command $name $value]
    # And the DESK's own refusal is the user's to read: the knobs
    # validate (a bad place spec, an unknown terminal), and their
    # message says exactly what is wrong — far better than anything
    # this side could invent.
    if {[catch {wm-call $cmd} err]} {
        puts "UI: configurator: preview of «$cmd» refused: $err"
        return [cfg-refuse [cfg-brief $err]]
    }
    dict set ::cfg_pending $name [dict create cmd $cmd value $value]
    cfg-show-value [dict get $::cfg_item $name] $name $value
    cfg-status ""
    return 1
}
# How a knob's value becomes its command: the multi-argument kinds
# SPREAD (set-desk-font -family X -size N), a list travels whole as
# one argument, everything else is one word. The restore path builds
# the same way, which is what makes a saved value re-appliable.
proc cfg-command {name value} {
    switch -- [lindex [dict get $::cfg_table $name kind] 0] {
        font - terminal { return [list $name {*}$value] }
        default         { return [list $name $value] }
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
    dict for {name pend} $::cfg_pending {
        wm-call [list custom-write [dict get $pend cmd]]
    }
    set ::cfg_pending {}
    cfg-refresh
    puts "UI: configurator: saved"
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