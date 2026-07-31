# The configurator — a RENDERER of the desk's own knob registry, and
# nothing more: every row comes from knob-table, fetched live, so this
# applet has no opinion about what knobs exist. treectrl (the owner's
# standing preference, and a tree of groups IS a tree), one row per
# knob under its group node:
#
#     knob            value           what it is
#
# Editing is by KIND, in place: bool toggles on click, choice cycles,
# int/float/text/terminal get an overlay entry (Return commits,
# Escape cancels), color opens the chooser, font the font chooser.
# A commit PREVIEWS immediately — the knob runs on the live desk over
# the send door — and marks the row pending (•). Save writes every
# pending knob through custom-write (the customization layer's door,
# so the click persists and overlap is reported); Revert is a config
# reload, which is the desk's own undo. A row whose knob the CONFIG
# also sets wears a cfg badge — the shadowing made visible, same
# truth the loader logs.
ui-applet configurator {title "tk9wm configurator" build cfg-build}

set cfg_table {}     ;# knob-table, as last fetched
set cfg_pending {}   ;# name -> the command previewed but not saved
set cfg_item {}      ;# name -> tree item
set cfg_T ""

proc cfg-build {W} {
    set ::cfg_T $W.t
    set ih [expr {[font metrics DeskFont -linespace] + 6}]
    treectrl $W.t -showheader yes -showroot no -showbuttons yes \
        -selectmode single -itemheight $ih -width 660 -height 460 \
        -background [ui-color field] -yscrollcommand [list $W.sb set]
    scrollbar $W.sb -orient vertical -command [list $W.t yview]
    set T $W.t
    $T column create -text knob      -width 190 -tags Cname
    $T column create -text value     -width 210 -tags Cval
    $T column create -text ""        -width 44  -tags Cflag
    $T column create -text "what it is" -squeeze yes -expand yes -tags Cdoc
    $T configure -treecolumn Cname
    $T element create eTxt  text -fill [ui-color fg] -lines 1 -font DeskFont
    $T element create eVal  text -fill [ui-color link] -lines 1 -font DeskFont
    $T element create eDoc  text -fill [ui-color fg] -lines 1 -font DeskFont
    $T element create eFlag text -fill #cc7832 -lines 1 -font DeskFont
    $T element create eGrp  text -fill [ui-color fg] -lines 1 -font TitleFont
    $T element create eSel  rect -fill [list [ui-color select] selected]
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
    frame $W.b
    button $W.b.save   -text Save   -command cfg-save
    button $W.b.revert -text Revert -command cfg-revert
    label  $W.b.note -text "a change previews at once; Save makes it stick" \
        -foreground [ui-color link]
    pack $W.b.save $W.b.revert -side left -padx 4 -pady 4
    pack $W.b.note -side left -padx 12
    grid $W.b -columnspan 2 -sticky ew
    $T notify bind $T <ActiveItem> {}
    bind $T <ButtonPress-1> {cfg-click %x %y}
    cfg-refresh
}

proc cfg-refresh {} {
    set T $::cfg_T
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
    }
}
proc cfg-show-value {it name value} {
    set T $::cfg_T
    set kind [dict get $::cfg_table $name kind]
    if {[lindex $kind 0] eq "font"} {
        set value "[dict get $value -family] [dict get $value -size]\
 [dict get $value -weight]"
    }
    $T item element configure $it Cval eVal -text $value
    set flags {}
    if {[dict exists $::cfg_pending $name]} { lappend flags • }
    if {$name in $::cfg_cfgkeys} { lappend flags cfg }
    $T item element configure $it Cflag eFlag -text [join $flags ""]
}

proc cfg-click {x y} {
    set T $::cfg_T
    set id [$T identify $x $y]
    if {[lindex $id 0] ne "item"} return
    set it [lindex $id 1]
    set name ""
    dict for {n i} $::cfg_item { if {$i == $it} { set name $n; break } }
    if {$name eq ""} { $T toggle $it; return }   ;# a group header
    set kind [dict get $::cfg_table $name kind]
    switch -- [lindex $kind 0] {
        bool   { cfg-set $name [expr {[cfg-cur $name] eq "on" ? "off" : "on"}] }
        choice {
            set vals [lrange $kind 1 end]
            set i [lsearch -exact $vals [cfg-cur $name]]
            cfg-set $name [lindex $vals [expr {($i + 1) % [llength $vals]}]]
        }
        color {
            set c [tk_chooseColor -initialcolor [cfg-cur $name] \
                       -title "tk9wm: $name"]
            if {$c ne ""} { cfg-set $name $c }
        }
        font  { cfg-font-dialog $name }
        default { cfg-entry $it $name }
    }
}
proc cfg-cur {name} {
    expr {[dict exists $::cfg_pending $name]
          ? [lindex [dict get $::cfg_pending $name] end]
          : [dict get $::cfg_table $name value]}
}

# The overlay entry for the free-form kinds. Return commits, Escape
# cancels; a value the kind refuses rings the bell and stays put.
proc cfg-entry {it name} {
    set T $::cfg_T
    catch {destroy $T.edit}
    lassign [$T item bbox $it Cval] x1 y1 x2 y2
    entry $T.edit -font DeskFont -borderwidth 1 -highlightthickness 0
    $T.edit insert 0 [cfg-cur $name]
    $T.edit selection range 0 end
    place $T.edit -x $x1 -y $y1 -width [expr {$x2 - $x1}] \
        -height [expr {$y2 - $y1}]
    focus $T.edit
    bind $T.edit <Return> [list cfg-entry-commit $name]
    bind $T.edit <Escape> [list destroy $T.edit]
    bind $T.edit <FocusOut> [list destroy $T.edit]
}
proc cfg-entry-commit {name} {
    set v [$::cfg_T.edit get]
    if {[cfg-set $name $v]} { destroy $::cfg_T.edit }
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