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
    scrollbar $W.sb -orient vertical -command [list $W.t yview] -takefocus 0
    set T $W.t
    $T column create -text knob         -tags Cname
    $T column create -text value        -tags Cval
    $T column create -text ""           -tags Cflag
    $T column create -text "what it is" -squeeze yes -expand yes -tags Cdoc
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
    grid $T $W.sb -sticky nsew
    grid rowconfigure $W 0 -weight 1
    grid columnconfigure $W 0 -weight 1
    frame $W.b -takefocus 0
    button $W.b.save   -text Save   -underline 0 -command cfg-save
    button $W.b.revert -text Revert -underline 0 -command cfg-revert
    foreach b [list $W.b.save $W.b.revert] { ui-focusable $b; ui-accel $b }
    label  $W.b.note -takefocus 0 -text "Return/F2 edits · double-click too ·\
 a change previews at once · Save makes it stick" \
        -foreground [ui-color link]
    pack $W.b.save $W.b.revert -side left -padx 4 -pady 4
    pack $W.b.note -side left -padx 12
    grid $W.b -columnspan 2 -sticky ew

    bind $T <ButtonPress-1>        {cfg-click %x %y; break}
    bind $T <Double-ButtonPress-1> {cfg-doubleclick %x %y; break}
    foreach k {Up k p} { bind $T <KeyPress-$k> {cfg-move above; break} }
    foreach k {Down j n} { bind $T <KeyPress-$k> {cfg-move below; break} }
    bind $T <Control-p> {cfg-move above; break}
    bind $T <Control-n> {cfg-move below; break}
    bind $T <KeyPress-Return> {cfg-activate; break}
    bind $T <KeyPress-F2>     {cfg-activate; break}
    bind $T <KeyPress-Left>   {cfg-fold collapse; break}
    bind $T <KeyPress-Right>  {cfg-fold expand; break}
    cfg-refresh
    focus $T
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
    set ::cfg_cfgkeys [wm-call {layer-touched config}]
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
    set wname 0; set wval 0; set wdoc 0
    dict for {name meta} $::cfg_table {
        set wname [expr {max($wname, [font measure DeskFont $name])}]
        set wdoc  [expr {max($wdoc, [font measure DeskFont [dict get $meta doc]])}]
        set it [dict get $::cfg_item $name]
        set v [$T item element cget $it Cval eVal -text]
        set wval [expr {max($wval, [font measure DeskFont $v])}]
    }
    # room to type into, and a ceiling: one long value must not open
    # the column past reading width (a list already summarizes, but a
    # font name or a path can still run)
    set wval [expr {max(min($wval, [font measure DeskFont [string repeat 0 34]]), 140)}]
    $T column configure Cname -width [expr {$wname + 32}]
    $T column configure Cval  -width [expr {$wval + 16}]
    $T column configure Cflag -width [expr {[font measure DeskFont "•cfg"] + 12}]
    $T column configure Cdoc  -width [expr {$wdoc + 16}]
    set ih [expr {[font metrics DeskFont -linespace] + 6}]
    set rows [expr {[llength [dict keys $::cfg_item]]
                    + [llength [$T item children root]]}]
    set wall [expr {$wname + $wval + $wdoc + [font measure DeskFont "•cfg"] + 96}]
    set hall [expr {($rows + 2) * $ih}]
    $T configure \
        -width  [expr {min($wall, [winfo screenwidth $T] * 9 / 10)}] \
        -height [expr {min($hall, [winfo screenheight $T] * 4 / 5)}]
}

# What a value LOOKS like in its cell. A list says how many it holds
# and of what — «[2 directories]» — rather than spelling itself out
# and blowing the column open (the owner's review); the whole of it
# lives in the sub-editor, one line per entry.
proc cfg-value-text {name value} {
    set kind [dict get $::cfg_table $name kind]
    switch -- [lindex $kind 0] {
        font { return "[dict get $value -family] [dict get $value -size]\
 [dict get $value -weight]" }
        list {
            set noun [lindex $kind 1]
            if {$noun eq ""} { set noun entries }
            return "\[[llength $value] $noun\]"
        }
    }
    return $value
}
proc cfg-show-value {it name value} {
    set T $::cfg_T
    $T item element configure $it Cval eVal -text [cfg-value-text $name $value]
    set flags {}
    if {[dict exists $::cfg_pending $name]} { lappend flags • }
    if {$name in $::cfg_cfgkeys} { lappend flags cfg }
    $T item element configure $it Cflag eFlag -text [join $flags ""]
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
proc cfg-click {x y} {
    focus $::cfg_T
    set id [$::cfg_T identify $x $y]
    if {[lindex $id 0] eq "item"} { cfg-select [lindex $id 1] }
}
proc cfg-doubleclick {x y} {
    cfg-click $x $y
    cfg-activate
}
proc cfg-activate {} {
    set it [cfg-selected]
    if {$it eq ""} return
    set name [cfg-name-of $it]
    if {$name eq ""} { $::cfg_T toggle $it; return }   ;# a group folds
    set kind [dict get $::cfg_table $name kind]
    switch -- [lindex $kind 0] {
        bool   { cfg-set $name [expr {[cfg-cur $name] eq "on" ? "off" : "on"}] }
        choice { cfg-choice-menu $it $name [lrange $kind 1 end] }
        color {
            set c [tk_chooseColor -initialcolor [cfg-cur $name] \
                       -title "tk9wm: $name"]
            if {$c ne ""} { cfg-set $name $c }
        }
        font  { cfg-font-dialog $name }
        list  { cfg-list-dialog $name }
        default {
            # after the event sequence, so nothing steals the focus
            # back from the entry (the invariant above)
            after idle [list cfg-entry $it $name]
        }
    }
}
proc cfg-cur {name} {
    expr {[dict exists $::cfg_pending $name]
          ? [lindex [dict get $::cfg_pending $name] end]
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
    catch {destroy $T.edit}
    lassign [$T item bbox $it Cval] x1 y1 x2 y2
    if {$x1 eq ""} return
    entry $T.edit -font DeskFont -borderwidth 1 \
        -background [ui-color field] -foreground [ui-color fg] \
        -insertbackground [ui-color fg]
    ui-focusable $T.edit
    set ::cfg_editing $name
    $T.edit insert 0 [cfg-cur $name]
    $T.edit selection range 0 end
    place $T.edit -x $x1 -y $y1 -width [expr {$x2 - $x1}] \
        -height [expr {$y2 - $y1}]
    bind $T.edit <Map>      {focus %W}
    bind $T.edit <Return>   {cfg-entry-done commit; break}
    bind $T.edit <Escape>   {cfg-entry-done cancel; break}
    bind $T.edit <FocusOut> {cfg-entry-done commit}
    focus $T.edit
}
proc cfg-entry-done {how} {
    set T $::cfg_T
    if {![winfo exists $T.edit]} return
    set v [$T.edit get]
    set name $::cfg_editing
    bind $T.edit <FocusOut> {}
    destroy $T.edit
    if {$how eq "commit"} { cfg-set $name $v }
    focus $T
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
    button $w.b.ok     -text OK     -underline 0 \
        -command [list cfg-list-commit $name]
    button $w.b.cancel -text Cancel -underline 0 -command [list destroy $w]
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
    if {[cfg-set $name $out]} { destroy .cfg-list }
}
proc cfg-font-dialog {name} {
    tk fontchooser configure -font [list \
        [dict get $::cfg_table $name value -family] \
        [dict get $::cfg_table $name value -size]] \
        -command [list cfg-font-picked $name]
    tk fontchooser show
}
proc cfg-font-picked {name spec} {
    cfg-set $name [font actual $spec]
}

# cfg-set NAME VALUE — validate by kind, PREVIEW on the live desk,
# remember as pending. The programmatic door too (tests drive it by
# send), which is why it answers 1/0 instead of beeping alone.
proc cfg-set {name value} {
    set kind [dict get $::cfg_table $name kind]
    switch -- [lindex $kind 0] {
        int { if {![string is integer -strict $value]} { bell; return 0 } }
        float {
            lassign $kind - lo hi
            if {![string is double -strict $value]
                    || $value < $lo || $value > $hi} { bell; return 0 }
        }
        color { if {[catch {winfo rgb . $value}]} { bell; return 0 } }
    }
    switch -- [lindex $kind 0] {
        font     { set cmd [list $name {*}$value] }
        terminal { set cmd [list $name {*}$value] }
        default  { set cmd [list $name $value] }
    }
    # a list travels as ONE argument (set-icon-path takes the list)
    if {[catch {wm-call $cmd} err]} {
        puts "UI: configurator: preview of «$cmd» refused: $err"
        bell
        return 0
    }
    dict set ::cfg_pending $name $cmd
    cfg-show-value [dict get $::cfg_item $name] $name $value
    return 1
}
proc cfg-save {} {
    dict for {name cmd} $::cfg_pending {
        wm-call [list custom-write $cmd]
    }
    set ::cfg_pending {}
    cfg-refresh
    puts "UI: configurator: saved"
}
proc cfg-revert {} {
    set ::cfg_pending {}
    wm-call reload-config
    cfg-refresh
    puts "UI: configurator: reverted to the desk's own layers"
}