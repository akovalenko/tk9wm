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
#     F2 EDITS — a bool toggles, a choice drops a menu, everything
#     else opens the overlay entry; F4 PICKS — color, font and list
#     dialogs, and the examples, where the cell has one (the owner,
#     2026-08-10: the keyboard's Enter is the typing gesture, the
#     dialogs answer to F4 and the mouse); Left/Right fold and unfold
#     a group; F3 switches a SLOT between its two spellings (a menu's
#     items and body — an action's run hides behind its face, launch,
#     and has no switch);
#   - the mouse follows the same grammar: a single click only SELECTS
#     (and focuses the tree); the double click is F4's gesture — the
#     picker where one stands, the editor elsewhere;
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
# the send door — and marks the row «* unsaved». Save writes every
# pending knob through custom-write; Revert is a config reload, the
# desk's own undo. A row whose knob the CONFIG also sets wears a cfg
# badge — the loader's truth made visible.
ui-applet configurator {title "tk9wm configurator" build cfg-build \
                            changed cfg-layer-changed}

set cfg_table {}     ;# knob-table, as last fetched
set cfg_coll {}      ;# collection-table, as last fetched
set cfg_pending {}   ;# name -> the command previewed but not saved
set cfg_item {}      ;# knob name -> tree item
set cfg_effect {}    ;# custom key -> pin | change (the desk's audit)
set cfg_node {}      ;# tree item -> collection descriptor (coll/elem/field)
set cfg_fitem {}     ;# field address -> tree item
set cfg_fresh {}     ;# elements born in this refresh — folded once attached
set cfg_member_into "" ;# which dict an Insert is about to grow
set cfg_cursor ""  ;# what the pointer is wearing over the tree
set cfg_T ""
set cfg_hint "Return or F2 types · F4 or a double click opens the\
 picker · F3 switches a slot's spelling · F8 what you have changed ·\
 F9 what went wrong · Ins adds, Del drops · Alt+↑/↓ move an item ·\
 Ctrl+Enter takes · m (or a click on the badge) opens the row's own\
 menu · Save makes it stick"

# A REFUSAL MUST SAY WHY (the owner: a bad place value simply did not
# commit and explained nothing). Every rejection — ours by kind, or
# the desk's own error text coming back over the send door — lands on
# the status line, in the warn color, and the editor stays open on the
# offending text so it can be fixed rather than retyped.
# The fill for a text element that may be drawn over the selection
# band: this colour normally, the selection's own ink when picked.
# Takes a palette KEY or a literal colour, because one of the five is
# a literal (the flag's orange) and it needs the same treatment.
proc cfg-ink {what} {
    set c [expr {[string index $what 0] eq "#" ? $what : [ui-color $what]}]
    list [ui-color selectfg] selected $c {}
}
# The badge's three inks: the selection's own on the band, the QUIET
# one on a `default` handle, the loud one on everything with news.
# A state rather than a per-item fill, so a theme flip repaints every
# badge through the element and leaves nothing wearing the old
# palette.
proc cfg-ink-flag {} {
    list [ui-color selectfg] selected [ui-color fg] quiet "#cc7832" {}
}
# PUTTING ON A PALETTE THAT MOVED — the applet's half of the desk's
# <<ThemeChanged>> (the owner, 2026-08-02: "the configurator does not
# repaint on the fly"). The option database dresses a widget once, at
# birth, so everything standing has to be told again by name.
#
# Told by NAME and not by walking the tree, which was the tempting
# version: a blind walk re-paints the things that are deliberately
# not the palette's colour — the flag's orange, a refusal's red on
# the status line — and a restyle that eats the error message is
# worse than one that misses a frame. The ttk half needs nothing
# here; `ttk::style theme use` repaints those where they stand.
proc cfg-restyle {} {
    if {![info exists ::cfg_T] || ![winfo exists $::cfg_T]} return
    set T $::cfg_T
    set W [winfo parent [winfo parent $T]]
    $T configure -background [ui-color field]
    foreach c {Cname Cval Cflag Cdoc} {
        $T column configure $c -textcolor [ui-color fg] \
            -background [list [ui-color hover] {active} \
                              [ui-color trough] {}]
    }
    foreach {el key} {eTxt fg eVal link eDoc fg eGrp fg} {
        $T element configure $el -fill [cfg-ink $key]
    }
    $T element configure eFlag -fill [cfg-ink-flag]
    $T element configure eSel -fill [list [ui-color select] selected] \
        -outline [list [ui-color link] selected]
    # ...and the plain-Tk furniture, which has no theme of its own.
    foreach w [list [winfo toplevel $T] $W $W.b] {
        if {[winfo exists $w]} { catch {$w configure -background [ui-color bg]} }
    }
    foreach w [list $W.head $W.b.note] {
        if {![winfo exists $w]} continue
        catch {$w configure -background [ui-color bg]}
    }
    # The heading is a link-coloured label, and so is the status line
    # — but only while it is saying something ordinary. A refusal is
    # red and stays red: the palette moved, the complaint did not.
    catch {$W.head configure -foreground [ui-color link]}
    if {[winfo exists $W.b.note]
            && [$W.b.note cget -foreground] ne "#cc4040"} {
        catch {$W.b.note configure -foreground [ui-color link]}
    }
    catch {ttk::style configure UiRing.TFrame -bordercolor [ui-color bg]}
    catch {ttk::style configure UiRingOn.TFrame -bordercolor [ui-color link]}
}
proc cfg-status {msg {how note}} {
    set l [winfo toplevel $::cfg_T].b.note
    if {![winfo exists $l]} return
    # Whatever replaces the hint says how to get it back (the owner,
    # 2026-08-10): every message ends in «F1 for help», and F1 is
    # bound to exactly this proc with nothing to say.
    $l configure -text [expr {$msg eq "" ? $::cfg_hint
                                         : "$msg · F1 for help"}] \
        -foreground [expr {$how eq "error" ? "#cc4040" : [ui-color link]}]
}
proc cfg-refuse {msg} {
    cfg-status $msg error
    bell
    return 0
}

proc cfg-build {W} {
    # THE RING GOES ROUND THE BOX: the tree and its scrollbar are one
    # thing on the screen, and an editor opened over the tree has not
    # left it (the owner, 2026-08-01). ui-ring-box keeps the ring lit
    # for anything focused inside itself, which is exactly what an
    # overlay editor is.
    ui-ring-box $W.box
    set ::cfg_T $W.box.t
    set ih [expr {[font metrics DeskFont -linespace] + 6}]
    # extended, for ONE gesture's sake: taking several of a bundle's
    # binds at once (decision 4). Everything else still works on the
    # first selected row, and plain clicks and arrows still select
    # singly — Ctrl+click is the way in.
    treectrl $W.box.t -showheader yes -showroot no -showbuttons yes \
        -selectmode extended -itemheight $ih -highlightthickness 0 \
        -borderwidth 0 \
        -background [ui-color field] -yscrollcommand [list cfg-yscroll $W.box.sb]
    # Out of the focus cycle: Tk's heuristic puts a scrollbar in it
    # (it has key bindings), and a stop with nothing to show for it —
    # the ring lands on something invisible — is worse than no stop
    # (the owner's review).
    ttk::scrollbar $W.box.sb -orient vertical -command [list cfg-scroll-request $W.box.t yview] \
        -takefocus 0
    set T $W.box.t
    $T column create -text knob         -resize yes -tags Cname
    $T column create -text value        -resize yes -tags Cval
    $T column create -text ""           -resize no  -tags Cflag
    $T column create -text "what it is" -squeeze yes -expand yes \
        -resize yes -tags Cdoc
    # THE HEADER WEARS THE THEME TOO (the owner): treectrl paints its
    # own, and left alone it is the toolkit's grey against a themed
    # desk. Its normal, active and pressed faces come from the same
    # palette the rest of the applet is dressed in.
    #
    # Under the pointer it is the HOVER ground and not the selection
    # band: the header's letters are one colour whatever state it is
    # in, so a ground that needs the selection's own ink would black
    # them out (the owner, 2026-08-02 — the light theme's dark blue
    # under unchanged black). ui-tint keeps the hue and the ink both.
    foreach c {Cname Cval Cflag Cdoc} {
        $T column configure $c -font TitleFont \
            -textcolor [ui-color fg] \
            -background [list [ui-color hover] {active} \
                              [ui-color trough] {}] \
            -borderwidth 1 -arrowgravity right
    }
    $T configure -treecolumn Cname
    # EVERY TEXT ELEMENT ANSWERS THE SELECTION, because the band under
    # it is a colour of its own and one ink cannot serve both grounds:
    # awlight selects with a dark blue, and the row's ordinary black
    # went invisible the moment it was picked (the owner, 2026-08-02).
    # cfg-ink is the two-state fill, and every element that draws
    # letters over eSel takes it.
    # `quiet` marks a row whose badge is an affordance rather than an
    # alarm (the «default» handle): same element, its own ink.
    $T state define quiet
    $T element create eTxt  text -fill [cfg-ink fg]   -lines 1 -font DeskFont
    $T element create eVal  text -fill [cfg-ink link] -lines 1 -font DeskFont
    $T element create eDoc  text -fill [cfg-ink fg]   -lines 1 -font DeskFont
    $T element create eFlag text -fill [cfg-ink-flag] -lines 1 -font DeskFont
    $T element create eGrp  text -fill [cfg-ink fg]   -lines 1 -font TitleFont
    $T element create eImg  image
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
    # the icon field's value cell carries a PICTURE beside the words:
    # the resolved thumbnail is the found/not-found answer at a glance
    $T style create sValImg
    $T style elements sValImg {eSel eImg eVal}
    $T style layout sValImg eSel -detach yes -iexpand xy
    $T style layout sValImg eImg -expand ns -padx {5 0}
    $T style layout sValImg eVal -expand ns -padx 5 -squeeze x
    # The tree says what it is, and its underline leads to it: Alt+k
    # from anywhere in this window puts the focus back on the knobs.
    ui-label $W.head "&Knobs — everything this desk can be told" $T \
        -foreground [ui-color link] -padx 6 -pady 4
    grid $W.head -row 0 -column 0 -columnspan 2 -sticky ew
    grid $T $W.box.sb -row 0 -in $W.box -sticky nsew
    grid rowconfigure $W.box 0 -weight 1
    grid columnconfigure $W.box 0 -weight 1
    grid $W.box -row 1 -column 0 -columnspan 2 -sticky nsew
    grid rowconfigure $W 1 -weight 1
    grid columnconfigure $W 0 -weight 1
    frame $W.b -takefocus 0
    # Save, Revert — and the config file. «Erase customization» stood
    # here too, and a button in the WINDOW'S OWN row read as «all of
    # it» while it worked on the selected row (the owner, 2026-08-02).
    # The gesture lives where its subject is — «Erase my word» in the
    # row's menu; cfg-erase stays as its engine. «Edit config…» passes
    # that same ruling the other way: its subject IS the whole file —
    # the knobs are half the story, and the annotated config in the
    # user's own path (first run copies it there) is the other half,
    # one press away instead of a path to remember (the owner,
    # 2026-08-06).
    ttk::button $W.b.save   -text Save   -underline 0 -command cfg-save
    ttk::button $W.b.revert -text Revert -underline 0 -command cfg-revert
    ttk::button $W.b.edit   -text "Edit config…" -underline 0 \
        -command cfg-edit-config
    foreach b [list $W.b.save $W.b.revert $W.b.edit] {
        ui-focusable $b; ui-accel $b
    }
    # ANCHORED AT ITS TOP-LEFT, and filling what the box gives it: a
    # label centres its text in whatever space it has, so a hint one
    # line too tall for the box lost a slice off the TOP as well as
    # the bottom (the owner, 2026-08-01). The first line must always
    # be the one that stays.
    label  $W.b.note -takefocus 0 -anchor nw -justify left -text $::cfg_hint \
        -foreground [ui-color link]
    pack $W.b.save $W.b.revert $W.b.edit -side left -padx 4 -pady 4
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
    # The desk's own <<ThemeChanged>> (ui-style-announce): the palette
    # under us moved, put it on.
    bind [winfo toplevel $W] <<DeskStyle>> cfg-restyle

    # CONDITIONAL breaks: a plain `break` swallowed the class bindings
    # too, and with them treectrl's own header work — column drags and
    # resizes stopped (the owner's report). The helpers answer whether
    # the press was theirs; a press on the header is not.
    # the wheel asks what the scrollbar asks, and before the tree's
    # own class binding gets the event
    foreach ev {<MouseWheel> <Button-4> <Button-5>} {
        bind $T $ev {if {![cfg-editing-guard scroll]} break}
    }
    # «select none» (the listbox's Ctrl+backslash, which treectrl
    # inherits) leaves the selection on the INVISIBLE root, and no
    # key navigates from there — so it picks the first real row
    # instead. Bound to the gesture rather than to <<Selection>>: a
    # rebuild empties the selection too, for an instant, and a guard
    # watching every change moved the selection out from under every
    # refresh (measured, 2026-08-02).
    bind $T <Control-backslash> {cfg-selection-guard; break}
    bind $T <Motion>               {cfg-motion %x %y}
    bind $T <ButtonPress-1>        {if {[cfg-click %x %y]} break}
    bind $T <Double-ButtonPress-1> {if {[cfg-doubleclick %x %y]} break}
    # Ctrl+click is NOT ours: the empty binding lets treectrl's own
    # class binding run, which in extended mode toggles the row into
    # the selection — the mouse half of the multi-take gesture.
    bind $T <Control-ButtonPress-1> {;}
    # A PLAIN LETTER IS A LETTER. Tk's <KeyPress-k> matches Alt+k as
    # well, so the tree's vi-style navigation was eating the Knobs
    # label's own Alt+k (the owner, 2026-08-02). These answer only
    # when no modifier is down; anything else falls through to
    # whoever meant it.
    foreach k {Up k p} {
        bind $T <KeyPress-$k> {if {[cfg-plain-key %s]} {cfg-move above; break}}
    }
    foreach k {Down j n} {
        bind $T <KeyPress-$k> {if {[cfg-plain-key %s]} {cfg-move below; break}}
    }
    bind $T <Control-p> {cfg-move above; break}
    bind $T <Control-n> {cfg-move below; break}
    bind $T <Shift-Up>   {cfg-extend above; break}
    bind $T <Shift-Down> {cfg-extend below; break}
    bind $T <Control-space> {cfg-mark; break}
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
    # F1 is the way back to the crib: the status line opens on the
    # key hint, anything the applet says replaces it — and says «F1
    # for help» on the way (cfg-status), so the way back is written
    # on whatever covered it.
    bind $T <KeyPress-F1>     {cfg-status ""; break}
    # RETURN TYPES (the owner, 2026-08-10): the keyboard's activation
    # is the editor, exactly as F2 — a bool still toggles and a choice
    # still drops its menu, but a picker dialog no longer stands
    # between the hand and the text. The dialogs keep their own
    # doors: F4, and the mouse's double click.
    bind $T <KeyPress-Return> {cfg-activate text; break}
    bind $T <KeyPress-F4>     {cfg-activate primary; break}
    bind $T <KeyPress-F2>     {cfg-activate text; break}
    bind $T <KeyPress-F3>     {cfg-slot-menu; break}
    bind $T <KeyPress-F8>     {cfg-pins; break}
    # THE ROW MENU, for a keyboard: `m` because his machine has no Menu
    # key and Shift+F10 is nobody's first guess (the owner, 2026-08-02)
    # — and Menu and Shift+F10 anyway, for the machines that do.
    bind $T <KeyPress-m>      {if {[cfg-plain-key %s]} {cfg-row-menu; break}}
    bind $T <KeyPress-Menu>   {cfg-row-menu; break}
    bind $T <Shift-KeyPress-F10> {cfg-row-menu; break}
    bind $T <KeyPress-F9>     {cfg-problems; break}
    # h/l fold and unfold beside the arrows, the way k/j walk beside
    # Up and Down (the owner's ask — vi hands)
    foreach k {Left h} {
        bind $T <KeyPress-$k> {if {[cfg-plain-key %s]} {cfg-fold collapse; break}}
    }
    foreach k {Right l} {
        bind $T <KeyPress-$k> {if {[cfg-plain-key %s]} {cfg-fold expand; break}}
    }
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
set cfg_fit_done 0    ;# the walls are set once and then left alone
set cfg_fit_size {}   ;# EVERY size the fit has asked for, see cfg-note-wrap
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
    # A HAND ON THE BORDER IS A SIZE WE NEVER ASKED FOR — and «we»
    # means any of our asks, not just the last one. A resize is
    # granted by the desk asynchronously, so the Configure for the
    # size the window had BEFORE a fit can still be in flight when
    # that fit ends; compared against the newest number alone it read
    # as a hand on the border, and the window declared itself
    # user-sized while it was still opening (measured, 2026-08-02).
    if {$::cfg_fit_done && !$::cfg_user_sized && [llength $::cfg_fit_size]} {
        set h [winfo height $W]
        set ours 0
        foreach s $::cfg_fit_size {
            lassign $s fw fh
            if {abs($w - $fw) <= 2 && abs($h - $fh) <= 2} { set ours 1 ; break }
        }
        if {!$ours} {
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
    # THE BOX MAY NOT SWALLOW THE WINDOW. «The hint takes the lines
    # it needs» stood on slack going down; a third button in the row
    # (less room for the note) times a narrow window broke it — the
    # wrapped hint asked for more height than the whole window had,
    # the grid starved the tree's row and UNMAPPED it, and every
    # overlay editor placed in that tree was unviewable: focus
    # refused quietly, keys went to the tree, nothing grew. The
    # box's ceiling is half the window — the workarea's half while
    # the window has no height yet — and past it the hint runs off
    # the bottom, which is what the top-left anchor has always been
    # for.
    set wh [winfo height $W]
    if {$wh <= 1} { set wh [lindex [ui-workarea] 3] }
    set want [expr {min($want, max(3*$line + 12, $wh / 2))}]
    if {[$W.b cget -height] != $want} { $W.b configure -height $want }
}

# Any scroll ends an open editor (as a commit attempt): the entry is
# placed at pixel coordinates and the rows move under it.
# Control, Alt/Meta and Super — the three a letter must not be
# wearing for the tree to claim it (Shift is fine: it is part of what
# letter was typed, and Lock/Num are noise).
proc cfg-plain-key {state} { expr {!($state & 0x4c)} }
# ---- the selection never lands where one cannot stand ----
# treectrl inherits the listbox's Ctrl+backslash — «select none» —
# and with -showroot no that left the selection on the INVISIBLE root
# item, from which no key navigates anywhere (the owner, 2026-08-02).
# Unbinding that one key would fix that one key; this fixes the shape
# of the problem: a selection that is empty, or is the root, is not a
# place, so it becomes the first row that is.
proc cfg-selection-guard {} {
    set T $::cfg_T
    if {![winfo exists $T]} return
    set it [cfg-selected]
    if {$it eq ""} { set it [lindex [$T item children root] 0] }
    if {$it ne ""} { catch {cfg-select $it} }
}
proc cfg-yscroll {sb a b} { $sb set $a $b }
# ---- what may happen while a value is half-typed ----
# The owner's rule, and it turns on ONE question — has anything been
# typed (2026-08-01)? That half is mechanical and lives with the
# editor (ui-cell-guard); THIS half is the policy, which is ours to
# have: work in progress is neither thrown away nor silently
# committed by a wheel, so the answer is no — to the scroll, to the
# erase, to the focus walking off — and the tree stays put while the
# value stays under the hand that typed it.
proc cfg-editing-guard {what} { ui-cell-guard $::cfg_T $what }
proc cfg-may-i {what} { return 0 }
proc cfg-scroll-request {w args} {
    if {[cfg-editing-guard scroll]} { $w {*}$args }
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
# THE DESK MOVED A LAYER WITHOUT BEING ASKED BY THIS WINDOW — a word
# it said for itself (the welcome mat retiring), or one said from a
# keystroke while the editor stood open. Reconcile, which is all a
# refresh ever does; a value under the hand keeps the hand's own word,
# because a preview outranks what the layers say until it is dropped.
proc cfg-layer-changed {layer key by} {
    if {$by eq "configurator" || ![winfo exists $::cfg_T]} return
    cfg-refresh
    cfg-status "the desk said «$key» itself — this list has caught up"
}
# EVERY WORD OF OURS GOES OUT UNDER OUR NAME, so the desk's word back
# to us can be told from the echo of our own (see cfg-layer-changed).
# One writer for the layer, and it has always been the desk's — this
# only tells it who is speaking.
proc cfg-write {command} {
    wm-call [list custom-write $command configurator]
}
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
    ui-tree-render $T "" [cfg-nodes] {make cfg-row-make \
        update cfg-row-update register cfg-row-register}
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
# ---- ONE WALK, NODE-DRIVEN (config-tree, step 3) -----------------
# The tree used to be built by hand, one storey at a time: a loop for
# the knob groups, a loop for the knobs, a loop for the families, a
# loop for the elements, a loop for the fields — five loops and four
# make/update pairs, so every level was its own code and a new level
# meant more of it.
#
# It is one walk now. cfg-nodes says what the tree IS — a list of
# records, each with its children — and the host's ui-tree-render puts
# any such list under any parent, registering the maps as it goes (the
# walk is nobody's family and lives there). What a row LOOKS
# like is still the dressers below, chosen by the node's own `what`:
# the rendering generalised, the appearance did not move.
#
# A node: what (its nature), key (unique among siblings — treesync's
# identity), label, button, children, plus whatever its dresser and
# the gestures want (addr for the editable ones, coll/key/field for
# the family rows).
proc cfg-nodes {} {
    set out {}
    # the knobs, gathered into their groups, knobs in SAID order
    # inside a group: the registry keeps its declaration order, and
    # the declarations are curated to read — the same ruling the
    # headings got (the owner, 2026-08-06), one storey down. The
    # alphabet put set-root-cursor above set-theme and could not put
    # the edit door first, which is where the owner wants it.
    set groups {}
    dict for {name meta} $::cfg_table {
        dict lappend groups [dict get $meta group] $name
    }
    # ONE SUBJECT, ONE HEADING. A group of knobs and a family can be
    # the same subject: `panel` was a heading of knobs and a heading
    # of buttons, standing twice in the tree — confusing to read now
    # and wrong once a subtree is something one addresses (the owner,
    # 2026-08-02). A family that named a topic hangs UNDER it as a
    # subsection of its own; one that named none is a topic itself and
    # stands among the headings.
    set under {}
    dict for {cname cmeta} $::cfg_coll {
        if {[dict exists $cmeta topic]} {
            dict lappend under [lindex [dict get $cmeta topic] 0] $cname
        }
    }
    # The headings' order is SAID, not sorted: the desk and its fonts
    # first, then actions before the keys and panel that lean on them
    # (a button is a reference to an action, a chord is what an action
    # carries), then the terminal and emacs integrations those actions
    # launch through, then the remaining furniture. Alphabet put
    # actions last of all — backwards to how the subjects depend on
    # each other (the owner, 2026-08-06). A subject the list never
    # heard of goes after the named ones, in name order — a new group
    # surfaces rather than vanishes.
    set said {desk fonts actions keys panel terminal emacs \
        windows tray widgets menus}
    set subjects [dict keys $groups]
    foreach t [dict keys $under] {
        if {$t ni $subjects} { lappend subjects $t }
    }
    dict for {cname cmeta} $::cfg_coll {
        if {![dict exists $cmeta topic]} { lappend subjects $cname }
    }
    set ordered {}
    foreach s $said { if {$s in $subjects} { lappend ordered $s } }
    foreach s [lsort $subjects] {
        if {$s ni $ordered} { lappend ordered $s }
    }
    foreach topic $ordered {
        if {![dict exists $groups $topic] && ![dict exists $under $topic]} {
            # a family that is a subject in its own right
            lappend out [cfg-coll-node $topic $topic]
            continue
        }
        set kids {}
        if {[dict exists $groups $topic]} {
            foreach name [dict get $groups $topic] {
                lappend kids [dict create what knob key $name label $name \
                    addr $name meta [dict get $::cfg_table $name]]
            }
        }
        foreach cname [dict getdef $under $topic {}] {
            lappend kids [cfg-coll-node $cname \
                [lindex [dict get $::cfg_coll $cname topic] 1]]
        }
        lappend out [dict create what grp key [list grp $topic] \
            label $topic button 1 children $kids]
    }
    return $out
}
proc cfg-coll-node {cname label} {
    set cmeta [dict get $::cfg_coll $cname]
    dict create what coll key [list coll $cname] \
        label $label button 1 coll $cname doc [dict get $cmeta doc] \
        children [cfg-element-nodes $cname $cmeta]
}
proc cfg-element-nodes {cname cmeta} {
    set out {}
    foreach e [dict get $cmeta elements] {
        set key [dict get $e key]
        set dead [dict exists $e ineffectual]
        set node [dict create what elem key [list $key $dead] label $key \
            button [expr {!$dead}] coll $cname elkey $key rec $e]
        if {$dead} {
            dict set node dead 1
        } else {
            dict set node children [cfg-field-nodes $cname $key $e]
        }
        lappend out $node
    }
    # ...AND A LAST ROW THAT MAKES ONE MORE. A family one may add to
    # ends in «Add a button…», which is both the plus every list of
    # this shape has and the answer to an empty family: a subtree with
    # nothing in it showed neither what it held nor whether it was
    # open at all (the owner, 2026-08-02, on actions, panel and env).
    # The row is where the new element will stand, so standing on it
    # and typing is the whole gesture where a name is all that is
    # needed; the families that need more than a name open their
    # dialog from the same row.
    if {[dict exists $cmeta insert]} {
        lappend out [dict create what add key {@add} \
            label "Add [dict get $cmeta insert]…" coll $cname \
            addr [list @add $cname]]
    }
    return $out
}
proc cfg-field-nodes {cname key e} {
    set out {}
    set said [cfg-elem-values $cname $key]
    set lint [expr {[dict exists $e lint] ? [dict get $e lint] : {}}]
    set fields [dict get $::cfg_coll $cname fields]
    # ...and the element's OWN half of the schema, after the family's:
    # a widget's rows depend on what it IS (its type's params), which a
    # static family table cannot say.
    if {[dict exists $e fields]} {
        set fields [dict merge $fields [dict get $e fields]]
    }
    dict for {f fmeta} $fields {
        if {![cfg-slot-shown? $f $fmeta $said $fields]} continue
        set addr [list @field $cname $key $f]
        # A CLOSED DICT WITH NO KEYS IS NO ROW AT ALL. `members fixed`
        # already withholds the «Add a key…» row — the schema is the
        # declaration's and a hand adds nothing to it — so a bundle
        # that declares no parameters (windows) hung an openable
        # branch with nothing inside: nothing to read, nothing to do
        # (the owner, 2026-08-10). No keys standing, none pending,
        # none derived — no row.
        if {[dict getdef $fmeta members {}] eq "fixed"
                && ![catch {dict size [cfg-cur $addr]} mn] && $mn == 0
                && [cfg-field-derived $addr] eq ""} continue
        set node [dict create what field key $f label $f \
            addr $addr coll $cname elkey $key \
            field $f meta $fmeta \
            lint [lsearch -all -inline -index 1 $lint $f]]
        if {[dict exists $fmeta members]} {
            dict set node button 1
            dict set node children [cfg-member-nodes $cname $key $f $addr]
        }
        lappend out $node
    }
    # ...and after them, the words this one stands OVER: same chord,
    # another layer, not in force. They are rows, not fields — nothing
    # in them is edited here, and the only gesture they answer is
    # Delete on one of ours.
    if {[dict exists $e shadowed]} {
        foreach claim [dict get $e shadowed] {
            lappend out [dict create what shadow \
                key [list @over [dict get $claim owner]] label "…instead of" \
                coll $cname elkey $key owner [dict get $claim owner] \
                claim $claim]
        }
    }
    return $out
}
proc cfg-member-nodes {cname key f addr} {
    set out {}
    set d [cfg-cur $addr]
    if {[catch {dict size $d}]} { return {} }   ;# half-typed, not a dict yet
    dict for {m v} $d {
        lappend out [dict create what member key $m label $m \
            addr [list @member $cname $key $f $m] \
            coll $cname elkey $key field $f member $m]
    }
    # ...and the same last row a family has: a dict of one's own keys
    # is the case the owner named for typing the name in the tree
    # itself («для env так очень уместно»), and an empty env used to
    # be a node one could not tell open from shut. NOT for a dict
    # whose schema is FIXED (`members fixed` — a bundle's params):
    # offering «Add a key…» against a closed schema was an invitation
    # to a refusal (the owner, 2026-08-03) — the declared keys are
    # already rows, and there is nothing else a hand could add.
    if {[dict get [cfg-field-meta $addr] members] ne "fixed"} {
        lappend out [dict create what add key {@add} label "Add a key…" \
            coll $cname elkey $key field $f addr [list @add-member {*}$addr]]
    }
    return $out
}
# WHAT A ROW CAN BE FOUND BY afterwards: an editable row by its
# address, a family row by its descriptor. Rebuilt every pass, in the
# walk's own order.
proc cfg-row-register {item n} {
    switch -- [dict get $n what] {
        knob { dict set ::cfg_item [dict get $n addr] $item }
        coll {
            dict set ::cfg_node $item \
                [dict create what coll coll [dict get $n coll]]
        }
        elem {
            set desc [dict create what elem coll [dict get $n coll] \
                          key [dict get $n elkey]]
            if {[dict exists $n dead]} { dict set desc dead 1 }
            dict set ::cfg_node $item $desc
        }
        field {
            dict set ::cfg_node $item [dict create what field \
                coll [dict get $n coll] key [dict get $n elkey] \
                field [dict get $n field]]
            dict set ::cfg_fitem [dict get $n addr] $item
        }
        member {
            dict set ::cfg_node $item [dict create what member \
                coll [dict get $n coll] key [dict get $n elkey] \
                field [dict get $n field] member [dict get $n member]]
            dict set ::cfg_fitem [dict get $n addr] $item
        }
        shadow {
            dict set ::cfg_node $item [dict create what shadow \
                coll [dict get $n coll] key [dict get $n elkey] \
                owner [dict get $n owner]]
        }
        add {
            # `key` empty, and present: every row that names a family
            # names a key too, and this one belongs to no element yet
            dict set ::cfg_node $item [dict create what add key {} \
                coll [dict get $n coll] addr [dict get $n addr]]
        }
    }
}
proc cfg-row-make {T parent key node} {
    set button [expr {[dict exists $node button] ? [dict get $node button] : 0}]
    set item [$T item create -button $button]
    switch -- [dict get $node what] {
        grp  { $T item style set $item Cname sGrp }
        coll { $T item style set $item Cname sGrp Cdoc sDoc }
        elem { lappend ::cfg_fresh $item }
    }
    if {[dict get $node what] ni {grp coll}} {
        set sval sVal
        if {[dict exists $node meta kind]
                && [lindex [dict get $node meta kind] 0] eq "icon"} {
            set sval sValImg
        }
        $T item style set $item Cname sName Cval $sval Cflag sFlag Cdoc sDoc
    }
    $T item element configure $item Cname \
        [expr {[dict get $node what] in {grp coll} ? "eGrp" : "eTxt"}] \
        -text [dict get $node label]
    cfg-row-update $T $item $key $node
    return $item
}
proc cfg-row-update {T item key node} {
    switch -- [dict get $node what] {
        grp {}
        coll {
            $T item element configure $item Cdoc eDoc -text [dict get $node doc]
        }
        knob {
            cfg-knob-dress $T $item [dict get $node addr] [dict get $node meta]
        }
        elem {
            cfg-elem-dress $T $item [dict get $node coll] [dict get $node rec]
        }
        field {
            cfg-field-dress $T $item [dict get $node addr] \
                [dict get $node meta] [dict get $node lint]
        }
        shadow {
            cfg-field-dress $T $item shadow [dict get $node claim]
        }
        member {
            set addr [dict get $node addr]
            $T item element configure $item Cval eVal \
                -text [cfg-value-text $addr [cfg-cur $addr]]
            cfg-flag-set $item {}
            $T item element configure $item Cdoc eDoc \
                -text "one of [dict get $node field] — empty here is a\
 value, and Del takes it away"
        }
        add {
            $T item element configure $item Cval eVal -text ""
            cfg-flag-set $item {}
            $T item element configure $item Cdoc eDoc \
                -text "type a name here — or Insert, which is the same row"
        }
    }
}
# THE BADGE IS A HANDLE. What the flag cell says — whose word the row
# wears, and a dot when an unsaved edit stands on it — is also where
# everything ABOUT THAT ROW hangs (the owner, 2026-08-02: Save is
# about everything, Revert is about everything, and Erase is about
# the row one stands on, with nowhere to say so). So a cell with
# something in it is underlined like the link it now is, and a click
# opens the row's menu.
proc cfg-flag-set {it flags} {
    set text [join $flags " "]
    $::cfg_T item element configure $it Cflag eFlag -text $text \
        -font [expr {$text eq "" ? "DeskFont" : "LinkFont"}]
    $::cfg_T item state set $it \
        [expr {$text eq "default" ? "quiet" : "!quiet"}]
}
proc cfg-knob-dress {T item name meta} {
    $T item element configure $item Cdoc eDoc -text [dict get $meta doc]
    cfg-show-value $item $name [dict get $meta value]
    # A KNOB NOBODY SAID CAN STILL HAVE AN ANSWER, and hiding it left
    # the row blank where the desk in fact knew what it was doing (the
    # owner, 2026-08-02: the terminal is worked out and not shown).
    # Said as a field's derived value is said, and for the same
    # reason: it is not written anywhere, and the row must not read as
    # if it were.
    if {[dict get $meta value] ne "" || ![dict exists $meta derived]
            || [dict get $meta derived] eq ""
            || [dict exists $::cfg_pending $name]} return
    $T item element configure $item Cval eVal -text [dict get $meta derived]
    cfg-flag-set $item derived
    $T item element configure $item Cdoc eDoc \
        -text "worked out, not written — [dict get $meta doc]"
}
# An ELEMENT: its key, a summary of what the layers said, and a flag
# with the owner badge — plus ✗ for a bind a later word buried
# (decision 5 made visible). dead rides IN THE SYNC KEY: a buried
# bind and the live one share a name, each must keep an item of its
# own, and a row changing sides is honestly a death and a birth.
proc cfg-elem-dress {T item cname e} {
    $T item element configure $item Cname eTxt -text [dict get $e key]
    $T item element configure $item Cval eVal \
        -text [cfg-inline-text [cfg-elem-summary $cname $e]]
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
            if {[dict get $v level] eq "warn"} { set mark warn; break }
            set mark note
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
    cfg-flag-set $item $flags
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
        append note " · [cfg-where-brief [dict get $e where]]"
    }
    return $note
}
# The chain, short enough for a cell: where it was WRITTEN, and how
# many hands it passed through on the way (a config that declares a
# proc and calls it is two links, and the second one is the one a
# reader is usually looking for).
proc cfg-where-brief {chain} {
    if {![llength $chain]} { return "" }
    set brief [file tail [lindex $chain 0]]
    if {[llength $chain] > 1} { append brief " ←[llength [lrange $chain 1 end]]" }
    return $brief
}
proc cfg-owner-words {e} {
    if {[dict exists $e bundle]} { return "the [dict get $e bundle] family" }
    switch -- [dict get $e owner] {
        custom { return "yours" }
        config { return "the config's" }
    }
    return "the desk's own"
}
# An element's children are its FIELDS, edited by the same
# kind-editors the knobs use; a buried bind has no children at all —
# re-binding it is capture-chord's day, not a field edit here.
proc cfg-field-dress {T item addr fmeta {lint {}}} {
    # a claimant row: whose word it is, what it says, and that it is
    # not the one answering
    if {$addr eq "shadow"} {
        $T item element configure $item Cval eVal \
            -text [cfg-inline-text [dict get $fmeta script]]
        $T item element configure $item Cflag eFlag \
            -text [expr {[dict get $fmeta owner] eq "custom" ? "✗ yours"
                         : [dict get $fmeta owner] eq "config" ? "✗ cfg"
                         : "✗ default"}]
        $T item element configure $item Cdoc eDoc \
            -text "[cfg-owner-words $fmeta] word, not in force"
        return
    }
    $T item element configure $item Cval eVal \
        -text [cfg-value-text $addr [cfg-cur $addr]]
    set flags {}
    if {[dict exists $::cfg_pending $addr]} { lappend flags "* unsaved" }
    set doc [dict get $fmeta doc]
    # SAID, AND EMPTY — a state the tree could not show, and one that
    # changes what a deed IS (the owner, 2026-08-02: «по поводу
    # terminal в редакторе толком не видно, отсутствует ли он или
    # присутствует пустой»). An empty cell meant either «nobody said
    # this» or «said, with nothing in it», and only the second one
    # puts the deed in a terminal. Where empty is a legal value the
    # row says so in words; where it is not, the state cannot arise —
    # an empty value there takes the key away.
    if {[cfg-field-said? $addr] && [cfg-cur $addr] eq ""} {
        lappend flags "said empty"
        set doc "said with nothing in it — $doc"
    } elseif {![cfg-field-said? $addr]} {
        set derived [cfg-field-derived $addr]
        if {$derived ne ""} {
            $T item element configure $item Cval eVal -text $derived
            lappend flags derived
            set doc "derived from the words below, not written — $doc"
        }
    }
    # AN ICON ANSWERS AS A PICTURE (the owner, 2026-08-06): the row
    # resolves the value the way the panel will — the thumbnail says
    # «found», the path in this column says WHERE, and «path found,
    # no picture» is the broken-svg diagnosis neither half could give
    # alone. A miss names the search that failed.
    if {[lindex [cfg-kind-of $addr] 0] eq "icon"} {
        lassign [cfg-icon-dress $addr] img note bad
        catch {$T item element configure $item Cval eImg -image $img}
        if {$note ne ""} { set doc $note }
        if {$bad} { lappend flags ✗ }
    }
    # A remark REPLACES the field's description while it stands: the
    # description says what the word is for, and one who has a
    # sentence about THIS word has the more useful thing to say.
    if {[llength $lint]} {
        set v [lindex $lint 0]
        lappend flags [expr {[dict get $v level] eq "warn" ? "warn" : "note"}]
        set doc [dict get $v text]
    }
    cfg-flag-set $item $flags
    $T item element configure $item Cdoc eDoc -text $doc
}
# What the icon VALUE amounts to on this machine: the desk resolves
# it exactly as a panel would (icon-file-of — path, ~, or a name
# searched through icon-path), and the thumbnail is made HERE, in the
# ui process, since an image cannot cross the send door. Returns
# {image doc-note bad}: a found file shows its picture and its path,
# a file no image comes out of says so, a miss names the search.
proc cfg-icon-dress {addr} {
    set spec [cfg-cur $addr]
    if {$spec eq "" || [ui-standalone?]} { return {{} {} 0} }
    set path ""
    catch {set path [wm-call [list icon-file-of $spec]]}
    if {$path eq ""} {
        return [list {} "no $spec.png or $spec.svg in icon-path —\
 the button would wear its badge" 1]
    }
    set img [cfg-icon-thumb $path]
    if {$img eq ""} {
        return [list {} "found $path — but no image comes out of it" 1]
    }
    return [list $img $path 0]
}
# One thumbnail per resolved file, made once and kept: a row-height
# rendering for svg (the core reads it), an integer subsample for
# anything bigger than the row (a panel-size png shrunk to a stamp —
# rough is fine, it is a presence mark, not a preview).
set cfg_icon_imgs {}
proc cfg-icon-thumb {path} {
    set h [expr {[font metrics DeskFont -linespace] + 2}]
    set key [list $path $h]
    if {[dict exists $::cfg_icon_imgs $key]} {
        return [dict get $::cfg_icon_imgs $key]
    }
    set img ""
    if {[string match -nocase *.svg $path]} {
        catch {set img [image create photo -file $path \
                            -format [list svg -scaletoheight $h]]}
    } else {
        catch {
            set src [image create photo -file $path]
            if {[image height $src] > $h} {
                set f [expr {([image height $src] + $h - 1) / $h}]
                set img [image create photo]
                $img copy $src -subsample $f $f
                image delete $src
            } else {
                set img $src
            }
        }
    }
    dict set ::cfg_icon_imgs $key $img
    return $img
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
        -minwidth [expr {[font measure DeskFont "* unsaved custom"] + 12}]
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
    # ...AND ONCE IS ENOUGH — once the window has been SEEN. The fit
    # is a first guess at a size nobody has an opinion about yet;
    # re-measuring on every refresh meant a window that resized itself
    # when one pressed Erase, or anything else that reloads (the
    # owner, 2026-08-02: «даже если геометрия не от юзера —
    # перемеривать на ходу не стоит»). The columns still re-measure
    # above; only the walls stand still.
    #
    # WHICH fit gets to set them is the whole of the two-row bug (the
    # owner, same day): the build's own refresh fits too, and it fits
    # a tree the toplevel has never laid out — provisional column
    # widths, a row count that is barely anything — so as a one-shot
    # it won the race and the window opened at two rows' height. So
    # the walls are open while the window is out of sight (the host
    # builds it withdrawn, and it may re-measure as often as it likes
    # there); the first fit with the window actually on the screen is
    # the one that closes them.
    if {$::cfg_fit_done} return
    set closes [winfo ismapped $W]
    lassign [ui-workarea] - - ww wh
    lassign [ui-chrome] B top
    set maxw [expr {$ww - 2*$B - [winfo reqwidth $W.box.sb] - 8}]
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
        if {$room > 80} {
            $W.b.note configure -wraplength $room
            # ...AND THE BOX'S OWN HEIGHT WITH IT. The ceiling below is
            # the workarea minus what this window carries, and the box
            # is the biggest part of that. Its height is set by the
            # Configure handler — that is, for whatever width the
            # window last HAD — so a fit that reads it is subtracting a
            # box belonging to another window: with a tall enough one,
            # nothing is left and the tree opens with room for two rows
            # (the owner, 2026-08-02). Ask for the height that goes
            # with the width we are about to ask for.
            cfg-note-room $W $W.b.note $room
        }
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
    lappend ::cfg_fit_size [list [winfo reqwidth $W] [winfo reqheight $W]]
    # ...AND ONLY NOW ARE THE WALLS CLOSED. Until they are, every
    # Configure this window sees is our own doing or the desk's answer
    # to it (a clamp into the workarea, a frame settling) — never a
    # hand on the border, because there is nothing to take hold of
    # yet. See cfg-note-wrap, which is what this gates.
    if {$closes} { set ::cfg_fit_done 1 }
}

# ---- the field address ----
# A collection element's field is addressed as {@field COLL KEY FIELD}
# — a list, where a knob is a bare name, and the first word is how
# every routing proc tells the two apart. The address is what
# cfg-set, cfg-cur and the pending dict carry; its kind comes from
# the collection registry's field meta instead of the knob table.
proc cfg-field? {name} { expr {[lindex $name 0] eq "@field"} }
# ---- a dict is a SUBTREE, not a cell -----------------------------
# The renderer walks nodes now, so a dict inside a field costs
# children rather than code (config-tree, step 3 — and the owner's
# own example, «actions.Firefox.env.GTK_IM_MODULE»). A member is
# addressed one storey deeper than its field:
#
#   {@field  actions Firefox env}                  the dict
#   {@member actions Firefox env GTK_IM_MODULE}    one variable in it
#
# It is EDITED as itself and SAID as its parent: the dict is a
# replacing node, so the word that carries one member carries all of
# them. That also means one pending, on the parent — two members
# edited in a row cannot race each other to be saved.
proc cfg-member? {name} { expr {[lindex $name 0] eq "@member"} }
proc cfg-member-parent {name} {
    lassign $name - coll key f -
    return [list @field $coll $key $f]
}
proc cfg-member-of {name} { lindex $name 4 }
# Taking a member away is legal HERE, where saying it empty is legal
# too: the dict is rewritten whole, so absence and emptiness are both
# expressible — which is exactly the shape the plan asks empty-valued
# leaves to live in.
proc cfg-member-drop {name} {
    set parent [cfg-member-parent $name]
    set d [cfg-cur $parent]
    dict unset d [cfg-member-of $name]
    if {[cfg-set $parent $d]} {
        after idle cfg-refresh
        cfg-status "[cfg-member-of $name] is gone from [cfg-pretty $parent] — Save writes that down"
    }
}
# ---- one slot, two spellings ----
# Some keys are two ways of saying one thing and cannot be said
# together (the registry's `xor`: an action's command is `run` or
# `launch`, never both). A tree that showed both rows would be
# offering a mistake — so it shows ONE. A pair whose sugar named a
# FACE (run's is launch) keeps the face on screen always: the sugar
# is for WRITING, and a config that says `run {mutt}` shows as the
# derived `Run mutt` it desugars to — one spelling in the UI, two in
# the file (the owner, 2026-08-06). A pair without a face (a menu's
# items/body) shows the spelling in effect, with the switch on F3.
proc cfg-field-meta {name} {
    set fields [dict get $::cfg_coll [lindex $name 1] fields]
    set f [lindex $name 3]
    if {[dict exists $fields $f]} { return [dict get $fields $f] }
    # the element's own words — a widget type's params live on the
    # element rather than on the family
    set rec [cfg-elem-rec [lindex $name 1] [lindex $name 2]]
    if {$rec ne "" && [dict exists $rec fields $f]} {
        return [dict get $rec fields $f]
    }
    return {}
}
proc cfg-slot-shown? {f fmeta said fields} {
    if {[dict exists $fmeta face]} { return 0 }
    if {![dict exists $fmeta xor] || [dict exists $said $f]} { return 1 }
    foreach other [dict get $fmeta xor] {
        if {![dict exists $said $other]} continue
        # a said sibling whose face THIS row is does not hide it:
        # the row stands, showing the derived spelling
        if {[dict getdef [dict getdef $fields $other {}] face {}] eq $f} continue
        return 0
    }
    return 1
}
proc cfg-kind-of {name} {
    if {[cfg-member? $name]} { return text }
    if {[cfg-field? $name]} {
        set coll [lindex $name 1]
        set fmeta [cfg-field-meta $name]
        # A CATALOGUE IS THE FAMILY'S OWN. Some choices are known only
        # to the live desk — what a widget may BE is whatever
        # wm-widget-type has declared by now — so the field says WHERE
        # its values live rather than listing them in a registry that
        # would go stale. A free-text type was how «bogusgadget» got
        # committed and stood there as a widget that cannot be built
        # (the owner, 2026-08-02).
        if {[dict exists $fmeta choices-from]} {
            set src [dict get $fmeta choices-from]
            if {[dict exists $::cfg_coll $coll $src]} {
                return [list choice {*}[dict get $::cfg_coll $coll $src]]
            }
        }
        return [dict get $fmeta kind]
    }
    dict get $::cfg_table $name kind
}
# ...and how a sentence names it: the address minus its marker
proc cfg-pretty {name} {
    if {[cfg-field? $name] || [cfg-member? $name]} {
        return [join [lrange $name 1 end] " "]
    }
    return $name
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
# What the ELEMENT says this field amounts to when nobody has said
# it. The type of a deed is the case this exists for (the owner,
# 2026-08-02: «в конфигураторе тип должен быть first-class citizen»)
# — it is a real word one can write, and until one does, the settings
# below amount to an answer, which the row shows rather than hides.
proc cfg-field-derived {addr} {
    set rec [cfg-elem-rec [lindex $addr 1] [lindex $addr 2]]
    if {$rec eq "" || ![dict exists $rec derived [lindex $addr 3]]} { return "" }
    return [dict get $rec derived [lindex $addr 3]]
}
# Is this key PRESENT in the element's merged word? The values dict
# holds what the layers said; absence and emptiness are two different
# answers in it, and the tree has to keep them two.
proc cfg-field-said? {name} {
    # A PREVIEW IS THE WORD ARRIVING EARLY, here as everywhere else:
    # a value typed and not yet saved makes the key said, and an
    # empty one means whatever empty means at this node. Asking the
    # desk alone left the badge and the menu a refresh behind what
    # the user had just typed.
    if {[dict exists $::cfg_pending $name]} {
        if {[dict get $::cfg_pending $name value] ne ""} { return 1 }
        return [expr {[cfg-field-empty-means $name] eq "value"}]
    }
    set v [cfg-elem-values [lindex $name 1] [lindex $name 2]]
    return [dict exists $v [lindex $name 3]]
}
# What an empty value at this field MEANS — the node's own word,
# carried out of the registry by the family's field table.
proc cfg-field-empty-means {name} {
    set meta [cfg-field-meta $name]
    if {[dict exists $meta empty]} { return [dict get $meta empty] }
    return unsay
}
proc cfg-field-stored {name} {
    set v [cfg-elem-values [lindex $name 1] [lindex $name 2]]
    set f [lindex $name 3]
    expr {[dict exists $v $f] ? [dict get $v $f] : ""}
}
proc cfg-node-addr {it} {
    set d [dict get $::cfg_node $it]
    if {[dict get $d what] eq "member"} {
        return [list @member [dict get $d coll] [dict get $d key] \
                    [dict get $d field] [dict get $d member]]
    }
    list @field [dict get $d coll] [dict get $d key] [dict get $d field]
}
proc cfg-show-field {addr} {
    if {![dict exists $::cfg_fitem $addr]} return
    set it [dict get $::cfg_fitem $addr]
    # an icon cell re-dresses WHOLE: the thumbnail and the resolved
    # path answer the value just typed, not only its text
    if {[cfg-field? $addr] && [lindex [cfg-kind-of $addr] 0] eq "icon"} {
        cfg-field-dress $::cfg_T $it $addr [cfg-field-meta $addr]
        return
    }
    $::cfg_T item element configure $it Cval eVal \
        -text [cfg-value-text $addr [cfg-cur $addr]]
    # keep whatever mark the linter left standing: this is the quick
    # redraw of ONE cell after an edit, and the remarks are re-read
    # with the rest of the table on the next refresh
    set mark ""
    regexp {(warn|note)$} [$::cfg_T item element cget $it Cflag eFlag -text] mark
    set flags {}
    if {[dict exists $::cfg_pending $addr]} { lappend flags "* unsaved" }
    if {$mark ne ""} { lappend flags $mark }
    cfg-flag-set $it $flags
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
    return [cfg-inline-text $value]
}
# A NEWLINE IS DRAWN, NOT PRINTED. A three-line script in a one-line
# cell put treectrl's control-character box on the screen — «vt»,
# which is a thing to decipher rather than read (the owner,
# 2026-08-02). The value itself is untouched: this is the CELL'S
# rendering of it, and the editor still opens on the real text.
# (Trimming it first was the other half of his thought, and the
# answer there is no: a trailing backslash means something.) One
# renderer for every one-line cell — the element's own header row and
# a shadowed claimant showed the box where their field rows did not
# (the owner, 2026-08-02, second look).
proc cfg-inline-text {value} { string map [list \n " ⏎ "] $value }
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
    # hand-written config. The desk's own value says `default` — not
    # news, a HANDLE: the row's menu was undiscoverable exactly where
    # its best offer lives («Pin this value as mine» — the owner,
    # 2026-08-02), so the badge is always there to click, wearing the
    # quiet ink so a fresh desk is not a column of alarms.
    set flags {}
    if {[dict exists $::cfg_pending $name]} { lappend flags "* unsaved" }
    switch -- [cfg-owner $name] {
        custom {
            # PIN or CHANGE, the same distinction the elements wear:
            # one holds what the layers below already give, the other
            # alters it. (It used to be said a line later, and said
            # it by REPLACING the badge — so a changed word of ours
            # showed no badge at all, and with it no handle.)
            if {[dict exists $::cfg_effect $name]
                    && [dict get $::cfg_effect $name] eq "pin"} {
                lappend flags pin
            } else {
                lappend flags custom
            }
        }
        config { lappend flags cfg }
    }
    if {![llength $flags]} { lappend flags default }
    cfg-flag-set $it $flags
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
# WHICH ROW ONE IS ON is the ACTIVE item, not the selection — they
# are two different marks in a treectrl and the owner was right to
# doubt they were one (2026-08-02). The active item is the keyboard's
# cursor: it survives «select none», it is what the arrows move, and
# it is the row every single-row gesture here means. The selection is
# what is MARKED, which matters only where more than one row can be
# acted on at once (Ctrl+Enter's take).
#
# The root can be active or selected and is neither a row nor a
# place: it answers as nothing at all.
proc cfg-selected {} {
    set T $::cfg_T
    set it [$T item id active]
    if {$it eq "" || $it == [$T item id root]} { return "" }
    return $it
}
# MARKING MORE THAN ONE ROW IS A KEYBOARD GESTURE TOO. The tree takes
# several rows (Ctrl+Enter's take works on them) and the only way to
# mark them was the mouse — on a desk that is keyboard-first
# everywhere else (the owner, 2026-08-02). Shift+arrow walks and marks
# as it goes; Ctrl+space marks the row one stands on, or unmarks it.
# The ACTIVE row — the keyboard's cursor — moves either way, because
# that is what every single-row gesture is about.
proc cfg-extend {dir} {
    set T $::cfg_T
    set cur [cfg-selected]
    if {$cur eq ""} return
    set next [$T item id [list $cur $dir]]
    if {$next eq "" || $next == $cur || $next == [$T item id root]} return
    $T selection add $cur      ;# the row one started from is marked too
    $T selection add $next
    $T activate $next
    $T see $next
}
proc cfg-mark {} {
    set T $::cfg_T
    set it [cfg-selected]
    if {$it eq ""} return
    if {[lsearch -exact [$T selection get] $it] >= 0} {
        $T selection clear $it
    } else {
        $T selection add $it
    }
}
proc cfg-move {dir} {
    set cur [cfg-selected]
    if {$cur eq ""} return
    set next [$::cfg_T item id [list $cur $dir]]
    if {$next ne "" && $next != $cur} { cfg-select $next }
}
# THE ENDS OF THE TREE, not the ends of the knob table. End walked the
# knobs, so it landed wherever the knobs stopped — in front of the
# families, with rows still below it (the owner, 2026-08-02: «как-то
# неаккуратно»). The last row of a tree is the last open descendant of
# the last top node, and the first is simply the first.
proc cfg-end {which} {
    set T $::cfg_T
    set kids [$T item children root]
    if {![llength $kids]} return
    if {$which eq "first"} {
        cfg-select [lindex $kids 0]
        return
    }
    set it [lindex $kids end]
    while {[$T item state get $it open] && [llength [$T item children $it]]} {
        set it [lindex [$T item children $it] end]
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
    # ...and a click ON THE BADGE is the badge's own gesture
    if {[cfg-flag-hit $id]} { cfg-row-menu }
    return 1
}
# Is this identify's answer the flag cell of a row that HAS a badge?
# An empty cell is not a link and must not pretend to be one.
proc cfg-flag-hit {id} {
    if {[lindex $id 0] ne "item" || [lindex $id 2] ne "column"} { return 0 }
    set T $::cfg_T
    if {[catch {$T column id [lindex $id 3]} c]} { return 0 }
    if {$c ne [$T column id Cflag]} { return 0 }
    if {[catch {$T item element cget [lindex $id 1] Cflag eFlag -text} t]} {
        return 0
    }
    return [expr {$t ne ""}]
}
# The pointer says what the underline says. Kept on the tree rather
# than on the cell (treectrl has no per-element cursor), and changed
# only when it actually changes — a cursor reset on every motion event
# is a flicker on some X servers.
proc cfg-motion {x y} {
    set want [expr {[cfg-flag-hit [$::cfg_T identify $x $y]] ? "hand2" : ""}]
    if {$want eq $::cfg_cursor} return
    set ::cfg_cursor $want
    $::cfg_T configure -cursor $want
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
        # ...and the «Add…» row IS the gesture: where a name is all
        # that is needed, one types it in the row itself (the owner:
        # «прикольно было бы вставлять путём редактирования new name
        # прямо в дереве, для env так очень уместно») — and the name
        # is typed in the NAME column, because that is what is being
        # said. What needs more than a name opens its dialog instead.
        if {[dict exists $::cfg_node $it]
                && [dict get $::cfg_node $it what] eq "add"} {
            set addr [dict get $::cfg_node $it addr]
            if {![cfg-add-inline? $addr]} {
                cfg-insert
                return
            }
            ui-cell-edit $::cfg_T $it Cname $addr \
                [dict create how $how kind text value "" element eTxt \
                     commit cfg-add-commit refuse cfg-refuse may-i cfg-may-i]
            return
        }
        # ...a MEMBER edits as itself too: the whole write still goes
        # through its parent's word (cfg-apply merges the dict and
        # re-states it), but the GESTURE used to stop at fields — on
        # a bundle's prefix the Enter only folded the leaf (the
        # owner, 2026-08-03: «элементы prefix и help в поддереве не
        # редактируются»).
        if {[dict exists $::cfg_node $it]
                && [dict get $::cfg_node $it what] in {field member}} {
            set name [cfg-node-addr $it]
        } else {
            $::cfg_T toggle $it
            return
        }
    }
    ui-cell-edit $::cfg_T $it Cval $name [cfg-cell-opts $name $how]
}
# WHICH «Add…» ROWS TAKE A NAME AND NOTHING ELSE. A key in a dict of
# one's own and a named deed are made out of a name; a button needs
# the action it points at, a widget its type, a binding its chord —
# those keep their dialog, which is where those answers are given.
proc cfg-add-inline? {addr} {
    if {[lindex $addr 0] eq "@add-member"} { return 1 }
    return [expr {[lindex $addr 1] eq "actions"}]
}
# The commit half: what the typed name MAKES. Answers 1/0 like every
# other commit, so a refusal leaves the name under the hand that
# typed it.
proc cfg-add-commit {addr name} {
    set name [string trim $name]
    if {$name eq ""} { return 1 }        ;# typed nothing: nothing made
    if {[lindex $addr 0] eq "@add-member"} {
        return [cfg-add-member [lrange $addr 1 end] $name]
    }
    return [cfg-insert-action "" $name]
}
# WHAT THE EDITOR NEEDS TO KNOW ABOUT A CELL — and the three answers
# it cannot have on its own. The data is this applet's reading of the
# address: the value as one would type it (a font's dict is a
# mouthful; its three words are what a hand touches), the kind that
# decides the gesture, the dialog behind the ▾. The three callbacks
# are the seam the editor left the applet through:
#
#   commit  cfg-set     — validate by kind, preview on the live desk,
#                         remember as pending; 0 and a sentence when
#                         the value is refused
#   refuse  cfg-refuse  — the status line, and the bell that goes
#                         with it
#   may-i   cfg-may-i   — the rule above
proc cfg-cell-opts {name {how primary}} {
    set v [cfg-cur $name]
    # an unsaid slot showing a derived value EDITS as that value: the
    # row says «Run true» and opening it offers those words to work
    # from, not an empty cell
    if {$v eq "" && [cfg-field? $name] && ![cfg-field-said? $name]} {
        set v [cfg-field-derived $name]
    }
    dict create how $how kind [cfg-kind-of $name] \
        value [cfg-value-typed $name $v] element eVal \
        pick [cfg-picker-of $name] \
        commit cfg-set refuse cfg-refuse may-i cfg-may-i
}
# Which kinds have a picker behind the ▾ — and what it is. A slot's
# switch is NOT here on purpose: editing the command is the everyday
# thing and keeps the everyday gestures; changing which spelling the
# slot wears is rare and has a key of its own (F3). A row that
# declared EXAMPLES opens on them, and a kind whose editor is a real
# dialog keeps it one press away — the Chooser… button on the
# examples dialog itself. It used to be the other way around (the
# dialog won), and the fonts are why it flipped (the owner,
# 2026-08-11): the chooser can only say a whole font, and «-weight
# bold» over a derived font — a partial spec, the thing one actually
# writes — is exactly what examples are for.
proc cfg-picker-of {name} {
    if {[dict size [cfg-examples-of $name]]} { return cfg-examples-dialog }
    return [cfg-kind-dialog-of $name]
}
proc cfg-kind-dialog-of {name} {
    switch -- [lindex [cfg-kind-of $name] 0] {
        color { return cfg-color-dialog }
        font  { return cfg-font-dialog }
        list  { return cfg-list-dialog }
    }
    return ""
}
# The declared examples of this row, wherever its meta lives: a
# field's come off the registry through spec-fields, a knob's off the
# knob table. Empty when nobody offered any.
proc cfg-examples-of {name} {
    if {[cfg-field? $name]} {
        set meta [cfg-field-meta $name]
        if {[dict exists $meta examples]} { return [dict get $meta examples] }
        return {}
    }
    if {![cfg-member? $name] && [dict exists $::cfg_table $name examples]} {
        return [dict get $::cfg_table $name examples]
    }
    return {}
}
# The ▾ of a field with examples (the owner, 2026-08-06): not
# abstract help but words to take and bend — picking a row puts its
# value into the entry ready for editing, the entry is what commits,
# and an untouched pick commits as itself.
proc cfg-examples-dialog {name} {
    set w .cfg-examples
    set rows {}
    set ::cfg_example_vals {}
    dict for {v hint} [cfg-examples-of $name] {
        set row [expr {$hint eq "" ? $v : "$v   — $hint"}]
        lappend rows $row
        dict set ::cfg_example_vals $row $v
    }
    ui-pick-dialog $w [winfo toplevel $::cfg_T] \
        "tk9wm: [cfg-pretty $name]" \
        "examples — pick one and bend it to your need" \
        $rows "as it will be said" \
        [list cfg-example-picked $name]
    bind $w.list <<ListboxSelect>> [list cfg-example-fill $w]
    # ...and the kind's own instrument one press away, where there is
    # one: the examples are words to bend, the chooser is the whole
    # keyboard — its pick commits down the same road, so which door
    # was taken makes no difference to what lands.
    set dlg [cfg-kind-dialog-of $name]
    if {$dlg ne ""} {
        ttk::button $w.b.chooser -text "C&hooser…" \
            -command [list cfg-example-chooser $w $dlg $name]
        ui-focusable $w.b.chooser
        ui-accel $w.b.chooser
        pack $w.b.chooser -side left -padx 4 -pady 4
    }
    cfg-dialog-homing $w
}
proc cfg-example-chooser {w dlg name} {
    destroy $w
    {*}$dlg $name
}
proc cfg-example-fill {w} {
    if {![llength [$w.list curselection]]} return
    set row [$w.list get [lindex [$w.list curselection] 0]]
    $w.e delete 0 end
    $w.e insert 0 [dict get $::cfg_example_vals $row]
}
proc cfg-example-picked {name choice typed} {
    if {$typed eq "" && $choice ne ""} {
        set typed [dict get $::cfg_example_vals $choice]
    }
    if {$typed eq ""} return
    cfg-picked $name $typed
}
# The pending value is kept AS A VALUE. It used to be dug back out
# of the command with `lindex ... end`, which is the last WORD — so a
# multi-word value came back mangled: «-weight bold» offered itself
# to the next edit as «bold» (the owner, on set-title-font). A command
# is not a value and cannot be read as one.
proc cfg-cur {name} {
    if {[cfg-member? $name]} {
        set d [cfg-cur [cfg-member-parent $name]]
        if {[catch {dict get $d [cfg-member-of $name]} v]} { return "" }
        return $v
    }
    if {[dict exists $::cfg_pending $name]} {
        return [dict get $::cfg_pending $name value]
    }
    if {[cfg-field? $name]} { return [cfg-field-stored $name] }
    dict get $::cfg_table $name value
}

# ---- THE CELL EDITOR IS THE LIBRARY'S NOW (config-tree, step 4) ---
# What opens on a cell, what Tab and Return and a stray click mean
# there, where the ▾ leads — none of that was ever about knobs or
# actions, so it lives in the host (ui-cell-edit and kin) and every
# tree-shaped applet gets it. What stayed is what only we know: the
# address, the value, the kind, the dialogs, and the three answers
# cfg-cell-opts hands over. These three lines are what our own
# callers — and the suite — go on reading.
proc cfg-entry {it name} {
    ui-cell-open $::cfg_T $it Cval $name [cfg-cell-opts $name]
}
proc cfg-entry-done {how} { ui-cell-done $::cfg_T $how }
proc cfg-entry-close {} { ui-cell-close $::cfg_T }
# A dialog's answer goes through the editor's own commit path, so one
# gesture ends in one committed value.
proc cfg-picked {name value} {
    cfg-entry-close
    cfg-set $name $value
    focus $::cfg_T
}
# ---- one road home from every dialog ----
# A dialog that COMMITS lands the focus (cfg-picked above); the ones
# that merely close — Escape, Cancel, the font chooser's own Done —
# left it nowhere: the widget the toplevel's focus memory pointed at
# was the overlay editor, and it died when the dialog opened, so the
# keys went to the toplevel itself until Alt+K or Tab (the owner,
# 2026-08-11, off the F2 → ▾ → Chooser… road). The way back rides the
# dialog's own Destroy, whatever road closes it: the editor when one
# still stands, the tree otherwise. after idle, so a commit's own
# focusing (or the next dialog on a Chooser… hop) is not fought over.
proc cfg-refocus {} {
    if {![info exists ::cfg_T] || ![winfo exists $::cfg_T]} return
    focus [expr {[winfo exists $::cfg_T.edit.t] ? "$::cfg_T.edit.t"
                                                : $::cfg_T}]
}
proc cfg-dialog-gone {who w} {
    if {$who ne $w} return
    after idle cfg-refocus
}
proc cfg-dialog-homing {w} {
    bind $w <Destroy> +[list cfg-dialog-gone %W $w]
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
    set f [lindex $name 3]
    # a sibling that made this row its face is not on offer: the
    # pair has one UI spelling, and F3 has nothing to switch
    set others {}
    if {[dict exists [cfg-field-meta $name] xor]} {
        set fields [dict get $::cfg_coll [lindex $name 1] fields]
        foreach other [dict get [cfg-field-meta $name] xor] {
            if {[dict getdef [dict getdef $fields $other {}] face {}] eq $f} {
                continue
            }
            lappend others $other
        }
    }
    if {![llength $others]} {
        cfg-status "[cfg-pretty $name] has only the one spelling" error
        return
    }
    set T $::cfg_T
    ui-menu $T.pop
    set ::cfg_slot $f
    set value [cfg-cur $name]
    foreach other [concat [list $f] $others] {
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
    cfg-dialog-homing $w
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
# WHAT THE COLOR CHOOSER OPENS ON: the said word when there is one,
# the DERIVED color when there is none. An unsaid color knob is not
# colorless — it is wearing the theme's answer — and handing the
# dialog the empty value threw before anything mapped: the ▾ on a
# themed set-desk-background silently did nothing, the error sank in
# bgerror (the owner, 2026-08-02).
proc cfg-color-seed {name} {
    set v [cfg-cur $name]
    if {$v ne ""} { return $v }
    if {[dict exists $::cfg_table $name derived]} {
        return [dict get $::cfg_table $name derived]
    }
    return ""
}
proc cfg-color-dialog {name} {
    set seed [cfg-color-seed $name]
    set c [tk_chooseColor -parent [winfo toplevel $::cfg_T] \
        {*}[expr {$seed ne "" ? [list -initialcolor $seed] : {}}] \
        -title "tk9wm: $name"]
    # modal, so the road home is simply after the wait: a cancel used
    # to leave the focus on the toplevel (see cfg-refocus)
    if {$c ne ""} { cfg-picked $name $c } else { cfg-refocus }
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
    after idle cfg-font-dressed
}
# ...and dressed for today, once it stands: the chooser is built
# lazily by the show, its plain-Tk lists off the option database of
# that moment — the walk (ui-redress-tk-dialogs) tells them the
# palette that stands now, whichever theme this desk has been through
# since. The Destroy hook is the road home (cfg-refocus): Tk destroys
# the chooser on OK and Cancel alike, and only OK speaks back through
# the command — a cancel left the focus on the toplevel. Guarded, so
# an Apply-then-show on the same standing dialog does not stack the
# binding twice.
proc cfg-font-dressed {} {
    ui-redress-tk-dialogs
    set fc [winfo toplevel $::cfg_T].__tk__fontchooser
    if {[winfo exists $fc]
            && ![string match *cfg-dialog-gone* [bind $fc <Destroy>]]} {
        cfg-dialog-homing $fc
    }
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
    if {[cfg-member? $name]} {
        set parent [cfg-member-parent $name]
        set d [cfg-cur $parent]
        dict set d [cfg-member-of $name] $value
        set r [cfg-apply $parent $d]
        # the member rows are drawn from the parent's value, and the
        # walk is what draws them — after the editor has closed
        if {$r} { after idle cfg-refresh }
        return $r
    }
    set kind [cfg-kind-of $name]
    set who [cfg-pretty $name]
    # THE DESK'S OWN CHECK, not a second one of ours. A value typed
    # here and a value written in a config file are the same value, and
    # they used to meet two different judges — this switch, and
    # whatever the setter's author wrote. One judge now, living where
    # the value is FOR (knob-check in policy/80-custom.tcl), asked over the same
    # wire everything else here is asked over.
    #
    # Standalone — no desk to ask — keeps a thin local copy: better a
    # second implementation in the one mode that cannot consult the
    # first than an applet that accepts anything when run alone.
    if {![ui-standalone?]} {
        set bad [wm-call [list kind-check $kind $value $who]]
        if {$bad ne ""} { return [cfg-refuse $bad] }
    } else {
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
    # A WORD THAT WOULD WRITE THE SAME LINE IS NOT AN EDIT. Typing
    # back what our own layer already says — Enter, Enter on a value
    # that is already ours — left the row wearing «* unsaved» for a
    # save that would rewrite the file identically (the owner,
    # 2026-08-02: «не приносит ничего полезного»). Saying our own word
    # over the CODE's or the CONFIG's is a different thing entirely —
    # that is a pin, it holds what the layers below give, and it keeps
    # its mark.
    if {[wm-call [list custom-word $cmd]] eq $cmd} {
        dict unset ::cfg_pending $name
    } else {
        dict set ::cfg_pending $name [dict create cmd $cmd value $value]
    }
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
    # THE LINTER, AT THE MOMENT ONE WRITES (the owner: this is the
    # moment that matters — the typo is fresh and the person is
    # standing here). Advice, never a refusal: the value is already
    # committed above, and what comes back is a sentence to read.
    set say [cfg-lint-note $name $value]
    if {$say ne ""} {
        cfg-status $say
        return 1
    }
    cfg-status ""
    return 1
}
proc cfg-lint-note {name value} {
    if {![cfg-field? $name]} { return "" }
    set meta [cfg-field-meta $name]
    if {![dict exists $meta lint] || [dict get $meta lint] ne "script"} {
        return ""
    }
    set v [lindex [wm-call [list script-lint $value]] 0]
    if {$v eq ""} { return "" }
    return "[dict get $v text]"
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
# THE CALL A FIELD EDIT MAKES, built from the family's SHAPE and not
# from its name (config-tree, step 3). The registry says which word
# says a family and what its arguments look like; this switch is on
# that shape, so a new family whose word has a shape already known
# needs nothing here at all.
proc cfg-field-command {name value} {
    lassign $name - coll key f
    set fam [dict get $::cfg_coll $coll]
    set verb [dict get $fam verb]
    set el [expr {[dict exists $fam key-words] ? [split $key " "] : $key}]
    switch -- [dict get $fam shape] {
        spec - overrides {
            # a merging word: the delta is this one field — and when
            # this field is the FACE of a spelling still said (launch
            # over a written run), the same word un-says that
            # spelling: the pair may not stand together, and the desk
            # would refuse a merge that kept both
            set delta [list $f $value]
            set said [cfg-elem-values $coll $key]
            dict for {other ometa} [dict get $fam fields] {
                if {[dict getdef $ometa face {}] eq $f
                        && [dict exists $said $other]} {
                    set delta [linsert $delta 0 $other {}]
                }
            }
            return [list $verb $el $delta]
        }
        options {
            # a replacing word: everything it holds goes out again,
            # this field's new value among it (previews included —
            # they are the word arriving early)
            set opts [cfg-elem-values $coll $key]
            dict for {a p} $::cfg_pending {
                if {[cfg-field? $a] && [lindex $a 1] eq $coll
                        && [lindex $a 2] eq $key} {
                    dict set opts [lindex $a 3] [dict get $p value]
                }
            }
            dict set opts $f $value
            return [list $verb $el {*}$opts]
        }
        pair {
            # positional values, in the family's own field order
            set cmd [list $verb $el]
            foreach ff [dict keys [dict get $fam fields]] {
                lappend cmd [expr {$ff eq $f ? $value
                    : [cfg-cur [list @field $coll $key $ff]]}]
            }
            return $cmd
        }
        params {
            # dashed values, plus the one bare word this shape has:
            # a family turned off is said by turning it off, not by
            # handing it an empty parameter list
            if {$f eq "state" && $value eq "off"} {
                return [list $verb $el off]
            }
            set params [expr {$f eq "params" ? $value
                : [cfg-cur [list @field $coll $key params]]}]
            set cmd [list $verb $el]
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
    # an open editor is part of what one means by «save»
    if {![cfg-entry-done commit]} return
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
            cfg-write [dict get $pend cmd]
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
        set word [dict merge $said $delta]
        # the face's un-say rides into the FILE too: a written run may
        # stand in the config layer under the launch saved here (the
        # preview's un-say does not survive a reload), and the replay
        # would meet the pair refused — so a word that says a face
        # un-says the spelling behind it (a no-op when nothing stands)
        set fields [dict get $::cfg_coll actions fields]
        dict for {f v} $word {
            dict for {other ometa} $fields {
                if {[dict getdef $ometa face {}] eq $f
                        && ![dict exists $word $other]} {
                    set word [linsert $word 0 $other {}]
                }
            }
        }
        cfg-write [list action $key $word]
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
        cfg-write [list panel-button $key \
            [dict merge $said [dict get $deltas $key]]]
    }
}
# Taking the set whole: own the panel, then every reference in panel
# order — a touched one as said+delta, an untouched one by its
# standing word (usually {}: the bare name, which IS the whole
# reference — the description lives on the action), and a skipped
# one not at all — which is what a Delete is.
proc cfg-adopt-panel {deltas {skip {}}} {
    set c [dict get $::cfg_coll panel]
    cfg-write {panel-buttons-own default}
    foreach e [dict get $c elements] {
        set key [dict get $e key]
        if {$skip ne "" && $key eq $skip} continue
        set said [expr {[dict exists $e said] ? [dict get $e said] : ""}]
        if {[dict exists $deltas $key]} {
            set said [dict merge $said [dict get $deltas $key]]
        }
        cfg-write [list panel-button $key $said]
    }
}
# Erase the selected knob's customization: the click taken back, the
# file rewritten without it, and the desk reloaded so the knob falls
# back to the config's word or the code's. Also drops a pending
# preview for that knob — it is the same "never mind".
proc cfg-erase {} {
    if {![cfg-editing-guard erase]} return
    set it [cfg-selected]
    if {$it eq ""} return
    set name [cfg-name-of $it]
    if {$name eq ""} return
    dict unset ::cfg_pending $name
    if {[cfg-owner $name] ne "custom"} {
        cfg-status "$name carries no customization to erase"
        return
    }
    # ERASING ONE WORD MUST NOT COST THE OTHERS. The erase reloads —
    # that is what makes it honest, since nothing here has to know
    # how to undo a knob — but a reload puts the desk back to what
    # the LAYERS say, and every preview standing on another row goes
    # with it. The owner erased one thing and watched an unsaved edit
    # elsewhere roll back (2026-08-01). So the previews are taken up
    # again afterwards: they are commands, and re-running them is
    # exactly what a preview is.
    set kept [cfg-reload-keeping [list $name] \
                  [list wm-call [list custom-erase $name]]]
    cfg-refresh
    cfg-status "$name is back to [cfg-owner $name]'s word[cfg-kept-note $kept]"
}
# ...and it is the same door every row-scoped undo goes through. The
# layers are the truth, so re-reading them is how anything here is
# taken back — but a preview is by definition what they do not say
# yet, and the ones this act is not about are re-run on the other
# side. They are commands; re-running one is exactly what a preview
# is.
proc cfg-reload-keeping {drop script} {
    set keep $::cfg_pending
    foreach n $drop { dict unset keep $n }
    uplevel #0 $script
    dict for {n pend} $keep {
        if {[catch {wm-call [dict get $pend cmd]} err]} {
            puts "UI: configurator: preview of «[dict get $pend cmd]» did not\
 survive: $err"
            dict unset keep $n
        }
    }
    set ::cfg_pending $keep
    return [dict size $keep]
}
proc cfg-kept-note {n} {
    if {!$n} { return "" }
    return " — $n unsaved change(s) elsewhere kept"
}
# ---- the row menu (the owner's shape, 2026-08-02) ----
# What the menu is ABOUT, said the same way for every kind of row: the
# word's address, whose it is, what unsaved work stands on it, and
# where the CONFIG mentions it. A field or a shadowed claimant is part
# of its element's word, so the question climbs to the element — the
# same climb Delete makes.
proc cfg-row-subject {it} {
    set T $::cfg_T
    if {$it eq ""} { return "" }
    # A MEMBER is its own subject too, and the one place where both
    # acts are legal: its dict is rewritten whole, so saying it empty
    # and taking it away are two different words one can actually say.
    if {[dict exists $::cfg_node $it]
            && [dict get $::cfg_node $it what] eq "member"} {
        set addr [cfg-node-addr $it]
        set parent [cfg-member-parent $addr]
        set pend {}
        if {[dict exists $::cfg_pending $parent]} { lappend pend $parent }
        set up [cfg-row-subject [$T item parent $it]]
        return [dict create kind member item $it addr $addr \
            pretty [cfg-pretty $addr] said 1 means value pending $pend \
            owner [expr {$up eq "" ? "code" : [dict get $up owner]}] \
            parent $up \
            where [expr {$up eq "" ? "" : [dict get $up where]}] \
            under [expr {$up eq "" ? "" : [cfg-dict-get $up under]}]]
    }
    # A FIELD IS ITS OWN SUBJECT now: saying a key empty and taking it
    # back are the field's business, and they are the two acts a
    # tree of merging layers cannot express by typing (the owner's
    # question about `terminal`). A shadowed claimant still belongs
    # to the element that buried it.
    if {[dict exists $::cfg_node $it]
            && [dict get $::cfg_node $it what] eq "field"} {
        set d [dict get $::cfg_node $it]
        set addr [list @field [dict get $d coll] [dict get $d key] \
                      [dict get $d field]]
        set pend {}
        if {[dict exists $::cfg_pending $addr]} { lappend pend $addr }
        set parent [cfg-row-subject [$T item parent $it]]
        return [dict create kind field item $it addr $addr \
            pretty [cfg-pretty $addr] said [cfg-field-said? $addr] \
            means [cfg-field-empty-means $addr] pending $pend \
            owner [expr {$parent eq "" ? "code" : [dict get $parent owner]}] \
            parent $parent \
            where [expr {$parent eq "" ? "" : [dict get $parent where]}] \
            under [expr {$parent eq "" ? "" : [cfg-dict-get $parent under]}]]
    }
    while {[dict exists $::cfg_node $it]
           && [dict get $::cfg_node $it what] in {field shadow}} {
        set it [$T item parent $it]
    }
    if {[dict exists $::cfg_node $it]} {
        set d [dict get $::cfg_node $it]
        if {[dict get $d what] ne "elem"} { return "" }
        set coll [dict get $d coll]
        set key [dict get $d key]
        set rec [cfg-elem-rec $coll $key [dict exists $d dead]]
        if {$rec eq ""} { return "" }
        set lkey [cfg-layer-key $coll $key $rec]
        # a binding carries its own chain (it was recorded where the
        # bind happened, which is exact); anything else asks the layer
        set where {}
        if {[dict exists $rec where]} { set where [dict get $rec where] }
        if {![llength $where]} {
            set where [wm-call [list knob-where $lkey]]
        }
        set pend {}
        dict for {n -} $::cfg_pending {
            if {[lrange $n 0 2] eq [list @field $coll $key]} { lappend pend $n }
        }
        return [dict create kind elem item $it coll $coll key $key rec $rec \
            pretty $key owner [dict get $rec owner] lkey $lkey \
            pending $pend where $where \
            under [cfg-under [dict get $rec owner] $lkey]]
    }
    set name [cfg-name-of $it]
    if {$name eq ""} { return "" }
    set pend {}
    if {[dict exists $::cfg_pending $name]} { lappend pend $name }
    return [dict create kind knob item $it name $name \
        pretty [cfg-pretty $name] owner [cfg-owner $name] lkey $name \
        pending $pend where [wm-call [list knob-where $name]] \
        under [cfg-under [cfg-owner $name] $name]]
}
# What a word of OURS stands on: the config's line for the same key,
# when there is one. That line is where the value would come from if
# this word were erased, so it is the one a reader wants next — and
# a binding has shown its buried claimants in the tree all along
# (cfg-elem-note), which is the shape this borrows for the rows that
# have no children to show them in.
proc cfg-under {owner lkey} {
    if {$owner ne "custom"} { return "" }
    return [wm-call [list knob-where $lkey config]]
}
proc cfg-row-menu {} {
    set m [cfg-row-menu-build]
    if {$m eq ""} return
    set T $::cfg_T
    lassign [$T item bbox [dict get [cfg-row-subject [cfg-selected]] item] \
                 Cflag] x1 y1 x2 y2
    tk_popup $m [expr {[winfo rootx $T] + $x1}] [expr {[winfo rooty $T] + $y2}]
}
# Built and posted apart, so a test can read what the menu OFFERS
# without a grab standing over the rest of the suite.
proc cfg-row-menu-build {} {
    set T $::cfg_T
    set s [cfg-row-subject [cfg-selected]]
    if {$s eq ""} {
        cfg-status "the row menu is about one word — stand on a knob or\
 on a family's element" error
        return ""
    }
    ui-menu $T.rowpop
    # WHICH ROW THIS IS ABOUT, said out loud when more than one is
    # marked: the menu has always been about the row one STANDS on,
    # and with five rows highlighted that was anybody's guess (the
    # owner, 2026-08-02). Marking several stays legal — «take these
    # five out into a file of their own» is a thing one will want to
    # say — so the menu names its subject instead of unmarking them.
    set marked [llength [$T selection get]]
    $T.rowpop add command -state disabled \
        -label [expr {$marked > 1
                      ? "[dict get $s pretty] (of $marked marked)"
                      : [dict get $s pretty]}]
    $T.rowpop add separator
    set mine [expr {[dict get $s owner] eq "custom"}]
    if {[dict get $s kind] eq "member"} {
        $T.rowpop add command -label "Say it empty" \
            -state [expr {[cfg-cur [dict get $s addr]] eq ""
                          ? "disabled" : "normal"}] \
            -command [list cfg-row-do say-empty $s]
        $T.rowpop add command -label "Take it out of the dict" \
            -command [list cfg-row-do drop $s]
        $T.rowpop add command -label "Reset to saved" \
            -state [expr {[llength [dict get $s pending]] ? "normal" : "disabled"}] \
            -command [list cfg-row-do reset $s]
        cfg-row-menu-where $s
        return $T.rowpop
    }
    if {[dict get $s kind] eq "field"} {
        # THE TWO ACTS THAT TYPING CANNOT SAY APART. An empty field
        # means one thing or the other depending on the node, so the
        # menu names the consequence instead of leaving it to a
        # convention: where empty is a word, saying it empty is an
        # act; where it is not, the same keystroke takes the key back.
        if {[dict get $s means] eq "value"} {
            $T.rowpop add command -label "Say it empty" \
                -state [expr {[dict get $s said] && [cfg-cur [dict get $s addr]] eq ""
                              ? "disabled" : "normal"}] \
                -command [list cfg-row-do say-empty $s]
            $T.rowpop add command -label "Unsay this key" -state disabled \
                -command {}
        } else {
            $T.rowpop add command -label "Unsay this key" \
                -state [expr {[dict get $s said] ? "normal" : "disabled"}] \
                -command [list cfg-row-do unsay $s]
        }
        $T.rowpop add command -label "Reset to saved" \
            -state [expr {[llength [dict get $s pending]] ? "normal" : "disabled"}] \
            -command [list cfg-row-do reset $s]
        if {[dict get $s parent] ne ""} {
            $T.rowpop add command -label "Erase this element's word" \
                -state [expr {$mine ? "normal" : "disabled"}] \
                -command [list cfg-row-do erase [dict get $s parent]]
        }
        cfg-row-menu-where $s
        return $T.rowpop
    }
    $T.rowpop add command -label "Erase my word" \
        -state [expr {$mine ? "normal" : "disabled"}] \
        -command [list cfg-row-do erase $s]
    $T.rowpop add command -label "Reset to saved" \
        -state [expr {[llength [dict get $s pending]] ? "normal" : "disabled"}] \
        -command [list cfg-row-do reset $s]
    # ...and what Del would do here, under its own name: the keyboard
    # gesture existed and nothing on the screen offered it (the
    # owner, 2026-08-02). Only where Del genuinely acts — dropping
    # somebody else's element; our own already reads «Erase my word»
    # above, which is the same engine Del reaches.
    set del [cfg-del-offer $s]
    if {$del ne ""} {
        $T.rowpop add command -label $del -command cfg-delete
    }
    if {[dict get $s kind] eq "knob"} {
        # PINNING is the Enter-on-the-same-value gesture, said out
        # loud: a word of ours that holds what the layers below
        # already give, so a later config cannot move it.
        $T.rowpop add command -label "Pin this value as mine" \
            -state [expr {$mine ? "disabled" : "normal"}] \
            -command [list cfg-row-do pin $s]
        # ...and the edit-door knob carries its own proof: the same
        # act as the window's «Edit config…», right where the door
        # is being chosen — set it, press, walk through it.
        if {[dict get $s name] eq "set-edit-door"} {
            $T.rowpop add command -label "Open the config through this door" \
                -command cfg-edit-config
        }
    }
    cfg-row-menu-where $s
    return $T.rowpop
}
# The contextual name of the Del gesture on this row, or empty where
# Del would only explain itself (a knob, a bundle, our own word, a
# word already out of force). The act is cfg-delete itself — one
# engine for the key and the menu, confirmations included.
proc cfg-del-offer {s} {
    if {[dict get $s kind] ne "elem"} { return "" }
    set rec [dict get $s rec]
    if {[dict get $rec owner] eq "custom"} { return "" }
    if {[dict exists $rec ineffectual]} { return "" }
    switch -- [dict get $s coll] {
        bindings { return "Silence this chord" }
        widgets  { return "Remove this widget" }
        actions  { return "Remove this deed" }
        panel    { return "Drop this button" }
    }
    return ""
}
proc cfg-row-menu-where {s} {
    set T $::cfg_T
    $T.rowpop add separator
    set i 0
    foreach place [dict get $s where] {
        incr i
        cfg-where-item $place [expr {$i == 1
            ? "Said at [cfg-place-brief $place]"
            : "…called from [cfg-place-brief $place]"}]
    }
    # ...and the word underneath, if a click of ours covers one: only
    # its head, because what a reader wants there is the line, not the
    # buried word's own call chain.
    foreach place [cfg-dict-get $s under] {
        incr i
        cfg-where-item $place "…over the config's [cfg-place-brief $place]"
        break
    }
    if {!$i} {
        $T.rowpop add command -state disabled -label [cfg-where-none $s]
    }
}
# A place opens THROUGH THE DOOR, and only through it (the owner,
# 2026-08-10). Each of these rows used to be a cascade asking «which
# way in — the door, emacs by name, the terminal editor by name?»,
# and that ask was the set-edit-door knob asked again, one storey
# deeper and on every line. The knob has already answered; a hand
# that means another door for once flips the knob, which is one
# gesture where the cascades were one question each.
proc cfg-where-item {place label} {
    $::cfg_T.rowpop add command -label $label \
        -command [list cfg-open-place door $place]
}
# NO FILE POINTS AT IT — and there are three different reasons for
# that, which "the config does not mention it" said as one. A click
# that no re-read has caught up with has no line yet; the desk's own
# default config has none to give (provenance skips our own library);
# and a value nobody has said at all is the code's.
proc cfg-where-none {s} {
    switch -- [cfg-dict-get $s owner] {
        custom { return "said by a click of yours — no line to open" }
        config { return "the desk's own default config says it" }
    }
    return "nobody has said it — this is the desk's own answer"
}
proc cfg-dict-get {d key} {
    expr {[dict exists $d $key] ? [dict get $d $key] : ""}
}
proc cfg-place-brief {place} {
    if {![regexp {^(.*):(\d+)$} $place -> file line]} { return $place }
    return "[file tail $file]:$line"
}
proc cfg-open-place {how place} {
    if {![regexp {^(.*):(\d+)$} $place -> file line]} {
        cfg-status "«$place» does not name a file and a line" error
        return
    }
    if {[catch {wm-call [list edit-place $how $file $line]} err]} {
        cfg-status [cfg-brief $err] error
        return
    }
    cfg-status "opening [cfg-place-brief $place]"
}
# THE CONFIG FILE, ONE PRESS AWAY. The first run copies the annotated
# sample into the user's own path exactly so there is something to
# edit — this is the door to it, and it doubles as the edit-door
# knob's try-me: set the door, press, walk through it. Line 1 on
# purpose: the file opens on its own preamble, which is the map.
proc cfg-edit-config {} {
    if {[catch {wm-call {edit-place door [config-path] 1}} err]} {
        cfg-status [cfg-brief $err] error
        return
    }
    cfg-status "opening the config —\
 [wm-call {edit-door-name [edit-door-resolve]}]"
}
proc cfg-row-do {how s} {
    if {![cfg-editing-guard [dict get $s pretty]]} return
    switch -- $how {
        erase {
            if {[dict get $s kind] eq "knob"} {
                cfg-select [dict get $s item]
                cfg-erase
                return
            }
            set kept [cfg-reload-keeping [dict get $s pending] \
                [list cfg-erase-word [dict get $s coll] [dict get $s key] \
                     [dict get $s rec]]]
            cfg-refresh
            cfg-status "[dict get $s pretty]: your word is taken\
 back[cfg-kept-note $kept]"
        }
        reset {
            set kept [cfg-reload-keeping [dict get $s pending] \
                          {wm-call reload-config}]
            cfg-refresh
            cfg-status "[dict get $s pretty] is back to what is\
 saved[cfg-kept-note $kept]"
        }
        drop { cfg-member-drop [dict get $s addr] }
        say-empty - unsay {
            # ONE WRITE, TWO MEANINGS, and the node decides which: in
            # a merging word an empty value is «take this back», and
            # where the registry declares empty a value it is «said,
            # with nothing in it». The menu already named which one
            # this row does.
            set addr [dict get $s addr]
            if {[cfg-set $addr ""]} {
                cfg-refresh
                if {$how eq "unsay"} {
                    cfg-status "[dict get $s pretty] is unsaid — Save writes\
 that down"
                } else {
                    cfg-status "[dict get $s pretty] is said with nothing in\
 it — Save writes that down"
                }
            }
        }
        pin {
            set name [dict get $s name]
            set v [cfg-cur $name]
            if {[cfg-set $name $v]} {
                cfg-refresh
                cfg-status "[dict get $s pretty] will be held at «$v» —\
 Save writes it down"
            }
        }
    }
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
        member { cfg-member-drop [cfg-node-addr $it]; return }
        coll  { cfg-delete-family [dict get $d coll]; return }
        shadow {
            if {[dict get $d owner] eq "config"} {
                cfg-status "that is the config's own word, kept here\
 because yours stands over it — the file that says it is yours to\
 edit, not this applet's"
                return
            }
            if {[dict get $d owner] ne "custom"} {
                cfg-status "that is the desk's own word — it stands\
 back up by itself when the word over it goes"
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
            cfg-write [list wm-unbind [split $key " "]]
        }
        widgets {
            if {![cfg-confirm "«$key» is not your widget. Dropping it\
 writes a removal of your own over it, which is itself a\
 customization — Delete on that takes it back. Remove it?"]} return
            cfg-write [list wm-widget-remove $key]
        }
        actions {
            if {![cfg-confirm "«$key» is the [dict get $e owner]'s deed.\
 Dropping it writes a removal of your own over it, which is itself a\
 customization — Delete on that takes it back. Remove it?"]} return
            cfg-write [list action-remove $key]
        }
    }
    cfg-refresh
    cfg-status "$key dropped from $coll — Insert brings elements back"
}
# The word we hold about ONE element, whatever family it is in.
proc cfg-erase-word {coll key e} {
    wm-call [list custom-erase [cfg-layer-key $coll $key $e]]
}
# WHERE A WORD IS FILED IN A LAYER — the address the erase uses, and
# the one the provenance is keyed by, said in one place so the two can
# never drift apart.
proc cfg-layer-key {coll key e} {
    if {[dict exists $e lkey]} { return [dict get $e lkey] }
    if {[dict exists $::cfg_coll $coll layer-key]} {
        return "[dict get $::cfg_coll $coll layer-key] $key"
    }
    return "$coll $key"
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
    switch -- [dict get $d coll] {
        panel   { cfg-move-button $d $dir }
        widgets { cfg-move-widget $d $dir }
        default {
            cfg-status "the panel's buttons and the widgets move today:\
 everything else follows the layers' declaration order"
        }
    }
}
proc cfg-move-button {d dir} {
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
# The widgets' move is the LIGHT model, on purpose (the owner,
# 2026-08-11: the panel-style takeover of the whole set is a design
# still cooking — widgets are half a panel editor already, and what
# happens when the room runs out is unanswered). A widget the custom
# layer both declared and SEATED (no config word under it — a custom
# override of a config widget keeps the config's seat, and the code's
# mat takes its own only when no layer sat it first) moves among its
# custom neighbours by permuting the file's lines; anything else says
# whose declaration holds its place.
proc cfg-move-widget {d dir} {
    set key [dict get $d key]
    if {![wm-call [list widget-seat-custom? $key]]} {
        cfg-status "«$key» sits where its declaration put it — only\
 widgets added by you move today"
        return
    }
    set order [lmap e [dict get $::cfg_coll widgets elements] \
                   {dict get $e key}]
    set i [lsearch -exact $order $key]
    if {$i < 0} return
    # THE PARTNER IS THE NEXT CUSTOM SEAT, NOT THE NEXT ROW. A config
    # widget — or the injected mat — standing between two of yours
    # holds a seat no permutation of the custom file can move, and
    # demanding plain adjacency made it a wall: the owner re-added
    # his widgets just to get them side by side of it (2026-08-11).
    # So the move steps over what it could never move — the two
    # custom lines trade places, the foreign seat stays its own — and
    # the reload below parks the mat after the layers' words anyway.
    set step [expr {$dir eq "above" ? -1 : 1}]
    set other ""
    for {set j [expr {$i + $step}]} {$j >= 0 && $j < [llength $order]} \
        {incr j $step} {
        if {[wm-call [list widget-seat-custom? [lindex $order $j]]]} {
            set other [lindex $order $j]
            break
        }
    }
    if {$other eq ""} return          ;# the edge of what is yours
    set pair [expr {$dir eq "above" ? [list $key $other]
                                    : [list $other $key]}]
    wm-call [list custom-reorder \
                 [lmap l $pair {string cat "wm-widget " $l}]]
    wm-call reload-config
    cfg-refresh
    cfg-status "$key moved — the order of your widgets is the custom\
 layer's word"
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
                cfg-write [list wm-keys $b off]
            }
            foreach e $taken {
                cfg-write [list wm-bind \
                    [split [dict get $e key] " "] \
                    [dict get $e values script] \
                    [dict get $e values name]]
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
    set what [dict get $::cfg_node $it what]
    # standing ON the «Add…» row: it says where the new one lands, so
    # Insert here is the same gesture the row itself performs (typing
    # the name), for the hands that reach for the key
    if {$what eq "add"} {
        set addr [dict get $::cfg_node $it addr]
        if {[lindex $addr 0] eq "@add-member"} {
            set ::cfg_member_into [lrange $addr 1 end]
            cfg-pick-dialog "another one in the dict" {} \
                "name for the new member" cfg-insert-member \
                cfg-member-trouble
            return
        }
        cfg-insert-into [dict get $::cfg_node $it coll]
        return
    }
    # standing IN a dict — on it or on one of its members — Insert
    # means «another member», which is the only sensible reading
    if {$what eq "member"
            || ($what eq "field" && [dict exists $::cfg_node $it field]
                && [dict exists [cfg-field-meta [list @field \
                        [dict get $::cfg_node $it coll] \
                        [dict get $::cfg_node $it key] \
                        [dict get $::cfg_node $it field]]] members])} {
        set ::cfg_member_into [cfg-node-addr $it]
        cfg-pick-dialog "another one in the dict" {} \
            "name for the new member" cfg-insert-member \
            cfg-member-trouble
        return
    }
    cfg-insert-into [dict get $::cfg_node $it coll]
}
proc cfg-insert-into {coll} {
    switch -- $coll {
        actions  { cfg-pick-dialog "new action" {} \
                       "name for the new action" cfg-insert-action \
                       cfg-action-trouble }
        panel    { cfg-insert-panel-dialog }
        widgets  { cfg-insert-widgets-dialog }
        bindings { cfg-insert-binding-dialog }
        keys     { cfg-status "the bundles are fixed in code — turn\
 them on and off, or take their binds" }
    }
}
# A fresh action is born empty and edited into shape — the same road
# a fresh button label walks.
proc cfg-insert-member {choice typed} {
    if {$typed eq ""} { return }
    cfg-add-member $::cfg_member_into $typed
}
# One key into a dict — from the dialog above, or typed straight into
# the tree's own «Add a key…» row. Answers 1/0 like a commit.
proc cfg-add-member {into name} {
    if {[cfg-member? $into]} { set into [cfg-member-parent $into] }
    set d [cfg-cur $into]
    if {[catch {dict size $d}]} { set d {} }
    if {[dict exists $d $name]} {
        return [cfg-refuse "[cfg-pretty $into] already has $name"]
    }
    dict set d $name ""
    if {![cfg-set $into $d]} { return 0 }
    after idle cfg-refresh
    cfg-status "$name is in [cfg-pretty $into], empty — type its value,\
 or Del takes it out again"
    return 1
}
proc cfg-insert-action {choice typed} {
    set name [expr {$choice ne "" ? $choice : $typed}]
    if {$name eq ""} { return 0 }
    if {[cfg-elem-rec actions $name] ne ""} {
        return [cfg-refuse "an action named $name already stands —\
 pick another name"]
    }
    if {[catch {cfg-write [list action $name {}]} err]} {
        return [cfg-refuse [cfg-brief $err]]
    }
    cfg-refresh
    cfg-status "$name is declared — fill its fields in"
    return 1
}

# The commit half of each Insert, dialogless — the programmatic door
# the tests drive, like cfg-set beside the editors.
# PICKED WINS, and what was typed is the road to a button whose label
# is fresh — the rule the picker used to know about this one caller.
proc cfg-insert-button-picked {choice typed} {
    cfg-insert-button [expr {$choice ne "" ? $choice : $typed}]
}
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
    if {[catch {cfg-write [list panel-button $name {}]} err]} {
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
    if {[catch {cfg-write [list wm-widget $name -type $type]} err]} {
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
    if {[catch {cfg-write [list wm-bind [split $spec " "] $script]} err]} {
        return [cfg-refuse [cfg-brief $err]]
    }
    cfg-refresh
    cfg-status "[join $spec " "] is bound"
    return 1
}

# ---- what went wrong, where one can read it ----
# The echo box says a failure happened and fades; this is the other
# half — the store, laid out so the whole message and the lines that
# led to it can be read at leisure (the owner's doubt about a popup
# with no natural end, 2026-08-01: the popup need not be the place
# one reads it).
proc cfg-problems {} {
    set all [wm-call problems]
    if {![llength $all]} {
        cfg-status "nothing has gone wrong since the desk came up"
        return
    }
    cfg-problems-show $all
}
# ...the window itself, apart from the question of whether there is
# anything to put in it — which is what lets a test build it cold
# (ui-lazy below) instead of waiting for something to go wrong.
proc cfg-problems-show {all} {
    set w .cfg-problems
    catch {destroy $w}
    toplevel $w -class Tk9wmUi
    wm title $w "tk9wm: what went wrong"
    wm transient $w [winfo toplevel $::cfg_T]
    label $w.l -takefocus 0 -anchor w \
        -text "[llength $all] since the desk came up, newest first"
    listbox $w.list -font DeskFont -height [expr {max(3, min(12, [llength $all]))}] \
        -exportselection 0 \
        -background [ui-color field] -foreground [ui-color fg] \
        -selectbackground [ui-color select] \
        -selectforeground [ui-color selectfg]
    ui-focusable $w.list
    foreach p $all {
        $w.list insert end "[dict get $p what] — [problem-one-line [dict get $p text]]"
    }
    # the details of the selected one: the whole message, and every
    # line of the reader's own that led to it (the frame chain)
    label $w.detail -takefocus 0 -anchor nw -justify left -height 4 \
        -foreground [ui-color link] -text "" -wraplength 560
    frame $w.b -takefocus 0
    ttk::button $w.b.close -text "&Close" -command [list destroy $w]
    ttk::button $w.b.clear -text "Clear the &list" \
        -command [list cfg-problems-clear $w]
    foreach b [list $w.b.close $w.b.clear] { ui-focusable $b; ui-accel $b }
    pack $w.b.close $w.b.clear -side left -padx 4 -pady 4
    pack $w.l -fill x -padx 6 -pady {6 2}
    pack $w.list -expand 1 -fill both -padx 6
    pack $w.detail -fill x -padx 6 -pady {6 2}
    pack $w.b -fill x
    bind $w <Escape> [list destroy $w]
    bind $w.list <<ListboxSelect>> [list cfg-problem-detail $w $all]
    $w.list selection set 0
    cfg-problem-detail $w $all
    # placement is the DESK's: a transient is centred on its parent by
    # the same policy every dialog on this desk gets (run-dialog-test)
    focus $w.list
}
proc problem-one-line {text} {
    set one [string trim [regsub -all {\s+} $text " "]]
    if {[string length $one] > 60} { set one "[string range $one 0 57]…" }
    return $one
}
proc cfg-problem-detail {w all} {
    set sel [$w.list curselection]
    if {![llength $sel]} return
    set p [lindex $all [lindex $sel 0]]
    set detail [dict get $p text]
    if {[llength [dict get $p where]]} {
        append detail "\n\nsaid at [join [dict get $p where] " ← "]"
    }
    $w.detail configure -text $detail
}
proc cfg-problems-clear {w} {
    wm-call problems-clear
    destroy $w
    cfg-status "the list is empty again — what is on the desk is unchanged"
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
# stands on, because «chords» and «chords under another prefix» are
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
        "or an action's name" cfg-insert-button-picked cfg-button-trouble
}
proc cfg-insert-widgets-dialog {} {
    set types [dict get $::cfg_coll widgets types]
    cfg-pick-dialog "new widget — pick its type" $types \
        "name for the new widget" cfg-insert-widget-picked \
        cfg-widget-trouble
}
proc cfg-insert-widget-picked {choice entry} {
    # for widgets the LIST is the type and the ENTRY is the name
    cfg-insert-widget $entry $choice
}
# WHAT VALID MEANS, dialog by dialog — the checks ui-pick-dialog asks
# before it lets a commit through. A widget with no name used to fall
# through in silence: the commit proc returned 0 to a dialog that had
# already closed (the owner, 2026-08-02). The commit procs keep their
# own guards — they are the backstop for programmatic callers — but
# the sentence a person needs lands here, in the dialog, on the line
# that needs fixing.
proc cfg-widget-trouble {choice typed} {
    if {$typed eq ""} { return "name the widget first" }
    if {$choice eq ""} { return "pick a type from the list" }
    if {[cfg-elem-rec widgets $typed] ne ""} {
        return "a widget named $typed already stands — pick another name"
    }
    return ""
}
proc cfg-action-trouble {choice typed} {
    set name [expr {$choice ne "" ? $choice : $typed}]
    if {$name eq ""} { return "name the action first" }
    if {[cfg-elem-rec actions $name] ne ""} {
        return "an action named $name already stands — pick another name"
    }
    return ""
}
proc cfg-member-trouble {choice typed} {
    expr {$typed eq "" ? "name the key first" : ""}
}
proc cfg-button-trouble {choice typed} {
    set name [expr {$choice ne "" ? $choice : $typed}]
    if {$name eq ""} { return "pick an action, or name one" }
    if {[cfg-elem-rec panel $name] ne ""} {
        return "$name is already on the panel"
    }
    return ""
}
# One shape serves buttons and widgets: a list to pick from, an entry
# beside it. The commit callback gets what was picked and what was
# typed; buttons use one of the two, widgets need both.
# The picker lives in the host now (ui-pick-dialog): a list to choose
# from, a name to type, and a commit — nothing about it was ever this
# applet's, and the next one gets it for free.
proc cfg-pick-dialog {title choices entrylabel commit {check {}}} {
    ui-pick-dialog .cfg-insert [winfo toplevel $::cfg_T] \
        "tk9wm: $title" $title $choices $entrylabel $commit $check
    cfg-dialog-homing .cfg-insert
}
# THE LAZILY BUILT THINGS, DECLARED. A run with ui-build-all behind it
# opens every one of them once — which is how a clash or a typo in a
# window nobody visits in the suite gets caught by the suite.
ui-lazy "problems view" {
    cfg-problems-show {{what probe text {a probe} where {}}}
} {destroy .cfg-problems}
ui-lazy "insert dialog" {
    cfg-pick-dialog "probe" {one two} "name" {}
} {destroy .cfg-insert}
ui-lazy "examples dialog" {
    cfg-examples-dialog {@field actions example key}
} {destroy .cfg-examples}
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
    cfg-dialog-homing $w
    focus $w.chord
}
# REFUSED WHERE IT WAS TYPED. The commit used to close the dialog
# first and complain after — into the main window's status line, from
# where the dialog had stood a bad chord read as swallowed silence
# (the owner, 2026-08-02: Alt+f4). The dialog keeps the floor until
# its words are good: the refusal appears under the entries, and the
# hand is still on the line that needs fixing.
proc cfg-bind-commit {w} {
    set spec [string trim [$w.chord get]]
    set script [string trim [$w.script get]]
    if {[cfg-bind-trouble $spec $script err]} {
        ui-dialog-say $w $err
        return
    }
    destroy $w
    cfg-insert-bind $spec $script
}
# What is wrong with the dialog's words, before anything runs: an
# empty half, or a chord token the desk cannot parse. The DESK is the
# parser — asking it keeps one grammar (case-forgiving keysyms
# included) serving the file and the dialog alike.
proc cfg-bind-trouble {spec script varname} {
    upvar 1 $varname err
    if {$spec eq ""}   { set err "name a chord first" ; return 1 }
    if {$script eq ""} { set err "say what it runs"   ; return 1 }
    if {[catch {wm-call \
            [list lmap tok [split $spec " "] {parse-chord $tok}]} e]} {
        set err [cfg-brief $e]
        return 1
    }
    return 0
}
