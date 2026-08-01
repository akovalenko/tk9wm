#!/bin/sh
# Regression for the configurator: it renders the live knob-table
# (rows exist), an edit PREVIEWS on the desk at once, Save persists
# through custom-write, Revert is the desk's own reload — and the
# welcome mat's font buttons turn the one font everything derives
# from, persistently. The style bridge is asserted by the host
# wearing the desk's DeskFont. Below the knob groups, the COLLECTIONS
# (collection-table): field edits preview per family's own verb, and
# Save adopts the panel set whole (own + buttons in order).
. "$(dirname "$0")/common.sh"
export DISPLAY=:94
rm -f /tmp/.X94-lock /tmp/.X11-unix/X94
Xvfb :94 -screen 0 1024x768x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/cfg-config"
mkdir -p "$HERE/cfg-config"
cat > "$HERE/cfg-config/tk9wm.tcl" <<'EOF'
set-edge-resist 3
action dummy {launch {exec true &}}
panel-button dummy
wm-bind {<Super>5} {list config-five}
wm-widget часы -type clock
action probe {run {true} icon P}
action w8x {run {true} needs /no/such/thing}
EOF

XDG_CONFIG_HOME="$HERE/cfg-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-cfg.log" 2>&1 &
WM=$!
sleep 1.5

q()  { printf '%s\n' "$1" > "$HERE/cfg-config/q.tcl"
       "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/cfg-config/q.tcl"; }
qu() { printf '%s\n' "$1" > "$HERE/cfg-config/qu.tcl"
       "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm-ui "$HERE/cfg-config/qu.tcl"; }

q 'applet configurator' >/dev/null
sleep 3
ROWS=$(qu 'llength [dict keys $::cfg_item]')
HOSTFONT=$(qu 'font actual DeskFont -size')
WMFONT=$(q 'font actual DeskFont -size')
CFGBADGE=$(qu 'cfg-owner set-edge-resist')
# the linter's remark, where the eye is: a mark on the element and
# the sentence itself in place of the field's description
LINTFLAG=$(qu 'set r none
    dict for {i d} $::cfg_node {
        if {[dict get $d what] eq "elem" && [dict get $d coll] eq "actions"
                && [dict get $d key] eq "dummy"} {
            set r [$::cfg_T item element cget $i Cflag eFlag -text]
        }
    }
    set r')
LINTDOC=$(qu 'set i [dict get $::cfg_fitem {@field actions dummy launch}]
    $::cfg_T item element cget $i Cdoc eDoc -text')
# THE LINTER'S MARK IS NOT A MODIFICATION MARK. They were a dot each
# and looked alike, and the owner read his own untouched actions as
# changed (2026-08-02). Words now, and this says the untouched one
# wears the remark and nothing about saving.
LINTNOTMOD=$(qu 'set i [dict get $::cfg_fitem {@field actions dummy launch}]
    set t [$::cfg_T item element cget $i Cflag eFlag -text]
    list flag [list $t] unsaved [expr {[string match "*unsaved*" $t]}]')

# ONCE THE USER HAS SIZED IT, the fit steps aside — asserted early,
# before the scenes that deliberately break procs, and undone right
# after so the later size checks still measure the fit.
qu 'wm geometry [winfo toplevel $::cfg_T] 700x400; list asked' >/dev/null
sleep 1
qu 'cfg-refresh; list refreshed' >/dev/null
sleep 0.5
HANDSIZED=$(qu 'list sized $::cfg_user_sized \
                     geom [wm geometry [winfo toplevel $::cfg_T]]')
qu 'set ::cfg_user_sized 0; cfg-fit; list refitted' >/dev/null
sleep 0.5

qu 'cfg-set set-fade 0.42' >/dev/null
sleep 0.5
PREVIEW=$(q 'set ::fade')
SAVED0=$(grep -c 'set-fade' "$HERE/cfg-config/tk9wm.custom.tcl" 2>/dev/null)
qu 'cfg-save' >/dev/null
sleep 0.5
SAVED1=$(grep -c 'set-fade 0.42' "$HERE/cfg-config/tk9wm.custom.tcl" 2>/dev/null)

qu 'cfg-set set-drag-slop 9' >/dev/null
sleep 0.3
qu 'cfg-revert' >/dev/null
sleep 1
REVERTED=$(q 'set ::drag_slop')

BAD=$(qu 'cfg-set set-fade 7')

# the list kind: summarized in its cell, edited whole in the sub-editor
LISTCELL=$(qu 'cfg-value-text set-icon-path {/a /b}')
qu 'cfg-set set-icon-path {/tmp/one /tmp/two /tmp/three}' >/dev/null
sleep 0.3
LISTLIVE=$(q 'llength $::icon_path')
# navigation survives a refresh: pick a knob deep in the tree, fold a
# group, then Revert
qu 'cfg-select [dict get $::cfg_item set-tray-icon-size]' >/dev/null
qu 'set g [$::cfg_T item id {root child 0}]; $::cfg_T collapse $g; list folded' >/dev/null
qu 'cfg-revert' >/dev/null
sleep 1
KEPT=$(qu 'cfg-name-of [cfg-selected]')
FOLD=$(qu 'expr {[$::cfg_T item state get [$::cfg_T item id {root child 0}] open] ? 0 : 1}')
# ...and not by restaging: a refresh RECONCILES, so the rows
# themselves survive it — the same item ids, knob and field alike —
# which is what the selection and the fold above actually rode on
SAMEID=$(qu 'set k0 [dict get $::cfg_item set-edge-resist]
    set f0 [dict get $::cfg_fitem {@field panel dummy label}]
    cfg-refresh
    list knob [expr {[dict get $::cfg_item set-edge-resist] == $k0}] \
         field [expr {[dict get $::cfg_fitem {@field panel dummy label}] == $f0}]')
THEME=$(qu 'ttk::style theme use')
# a derived font is shown AS CONFIGURED — a delta, not the computed font
qu 'cfg-set set-title-font {-weight bold}' >/dev/null
qu 'cfg-save' >/dev/null
sleep 0.5
# a PENDING multi-word value must offer itself back whole to the next
# edit (it used to come back as its last word)
PENDBACK=$(qu 'cfg-set set-title-font {-weight bold}; cfg-cur set-title-font')
# a PARTIAL font spec — one option, no size — must render and apply
PARTIAL=$(qu 'cfg-set set-desk-font {-family {DejaVu Sans}}')
PARTIALCELL=$(qu 'cfg-value-text set-desk-font {-family {DejaVu Sans}}')
PARTIALLIVE=$(q 'font actual DeskFont -family')
# THE OTHER FORM: a Tk font spec, which is what a non-Tcl hand writes
SPECFORM=$(q 'set-desk-font {DejaVu Sans 13 bold}
              list [font actual DeskFont -family] [font actual DeskFont -size] \
                   [font actual DeskFont -weight]')
SPECWORDS=$(q 'set-desk-font DejaVu Sans 11
               list [font actual DeskFont -family] [font actual DeskFont -size]')
SPECDELTA=$(q 'set-title-font {Liberation Serif}
               list [font actual TitleFont -family] \
                    [expr {[font actual TitleFont -size]
                           eq [font actual DeskFont -size]}]')
SPECBAD=$(q 'catch {set-desk-font { }} e; set e')
# every knob that touches something VISIBLE must act at once, not at
# the next apply — the desk window was the last one that did not
DESKWIN=$(qu 'cfg-set set-desk-window off
              list gone [wm-call {expr {[winfo exists .desk] ? 1 : 0}}] \
                   back [wm-call {set-desk-window on; expr {[winfo exists .desk] ? 1 : 0}}]')
# ...and SAVED, it must still read as what was said, not as what the
# desk computed from it
qu 'cfg-save' >/dev/null
sleep 0.5
SAVEDSPEC=$(qu 'cfg-refresh; dict get $::cfg_table set-desk-font value')
FONTCELL=$(qu 'cfg-value-text set-title-font [dict get $::cfg_table set-title-font value]')
FONTOWNER=$(qu 'cfg-owner set-title-font')
FONTLIVE=$(q 'font actual TitleFont -weight')
FONTFAM=$(q 'expr {[font actual TitleFont -family] eq [font actual DeskFont -family]}')
# ...and the customization can be taken back
qu 'cfg-select [dict get $::cfg_item set-title-font]; cfg-erase' >/dev/null
sleep 1
ERASEDOWNER=$(qu 'cfg-owner set-title-font')
ERASEDLIVE=$(q 'font actual TitleFont -weight')
ERASEDFILE=$(grep -c 'set-title-font' "$HERE/cfg-config/tk9wm.custom.tcl" 2>/dev/null)
THEME=$(qu 'ttk::style theme use')
# a refusal must SAY why — and must not throw: an unmatched quote in a
# list-shaped kind, and a place spec the desk itself rejects
BADLIST=$(qu 'cfg-set set-terminal {kitty "unclosed}')
BADLISTMSG=$(qu 'set l [winfo toplevel $::cfg_T].b.note; $l cget -text')
BADCURSOR=$(qu 'cfg-set set-root-cursor no-such-cursor')
BADCURSORMSG=$(qu 'set l [winfo toplevel $::cfg_T].b.note; $l cget -text')
GOODCURSOR=$(qu 'cfg-set set-root-cursor watch')
CURSORLIVE=$(q 'set ::root_cursor')
BADPLACE=$(qu 'cfg-set set-key-echo-place {bla bla bla}')
BADPLACEMSG=$(qu 'set l [winfo toplevel $::cfg_T].b.note; $l cget -text')
GOODMSG=$(qu 'cfg-set set-drag-slop 5; set l [winfo toplevel $::cfg_T].b.note; $l cget -text')
# the scrollbar lives beside the tree INSIDE the ring box now
SBFOCUS=$(qu 'set w [winfo parent $::cfg_T].sb; $w cget -takefocus')
# the heading names the tree, underlines its letter, and Alt+k leads
# there — the host's facility, not this applet's flourish
# the desk font MOVES and the applet follows — it used to keep the
# type it was born with — and the chooser seeds from what the font is
# NOW, not from the table's snapshot
q 'set-desk-font {DejaVu Sans 14}' >/dev/null
sleep 1
FOLLOW=$(qu 'list host [font actual DeskFont -size] \
                  seed [wm-call {font actual DeskFont -size}]')

# the ends of the list, in both dialects
ENDS=$(qu 'set T $::cfg_T
           focus $T
           event generate $T <KeyPress-End>
           set last [cfg-name-of [cfg-selected]]
           event generate $T <KeyPress-Home>
           set first [cfg-name-of [cfg-selected]]
           event generate $T <Alt-greater>
           set lastalt [cfg-name-of [cfg-selected]]
           event generate $T <Alt-less>
           set firstalt [cfg-name-of [cfg-selected]]
           list $first $last [expr {$first eq $firstalt && $last eq $lastalt}]')

# a modifier mask is not a value for a human: it reads back as it is
# written, and what it writes is legal input
MODS=$(qu 'set t [wm-call knob-table]
           set shown [dict get $t set-drag-modifier value]
           list shown $shown \
                round [wm-call [list set-drag-modifier $shown]] \
                same [wm-call {expr {$::drag_mods == 64}}] \
                refused [wm-call {catch {set-drag-modifier zzz}}]')

HEAD=$(qu 'set W [winfo toplevel $::cfg_T]
           focus $W.b.save
           event generate $W <Alt-Key-k>
           list text [$W.head cget -text] under [$W.head cget -underline] \
                focus [focus]')
# a refresh must not GROW the window: the fit fed on its own leftover
# once, and every Save walked the window wider (and left, against the
# right edge)
# NO event-loop re-entry inside a send: an `update` in a send handler
# while the WM is resizing the same window hangs the pair (measured —
# this very scene did it before it was split into steps).
W1=$(qu 'cfg-refresh; winfo reqwidth [winfo toplevel $::cfg_T]')
sleep 0.4
W2=$(qu 'cfg-refresh; winfo reqwidth [winfo toplevel $::cfg_T]')
sleep 0.4
W3=$(qu 'cfg-refresh; winfo reqwidth [winfo toplevel $::cfg_T]')
if [ "$W1" = "$W2" ] && [ "$W2" = "$W3" ]; then STABLE=stable; else STABLE="$W1 $W2 $W3"; fi
# a refresh arriving INSIDE a refresh (a send spins the event loop
# mid-body) must DEFER, not run over the half-built tree: the log
# says fit, after-nested, fit — the nested call returned at once and
# its re-run came after the outer pass, not inside it
REENTER=$(qu 'rename cfg-fit cfg-fit-real
    set ::cfg_log {}
    proc cfg-fit {} {
        lappend ::cfg_log fit
        if {[llength $::cfg_log] == 1} {
            cfg-refresh
            lappend ::cfg_log after-nested
        }
        cfg-fit-real
    }
    set rc [catch {cfg-refresh} e]
    rename cfg-fit {}
    rename cfg-fit-real cfg-fit
    list rc $rc log $::cfg_log sel [expr {[cfg-selected] ne ""}]')
# ...and a dead item id — a fact of life around reloads — selects
# nothing quietly instead of erroring out of the gesture
DEADSEL=$(qu 'list rc [catch {cfg-select 999999} e] kept [expr {[cfg-selected] ne ""}]')
# an UNEXPECTED error in the apply path (not a refusal) must roll the
# desk back to its layers and explain itself, never throw a dialog
qu 'cfg-set set-drag-slop 11' >/dev/null
# the sabotage throws ONCE and repairs itself, so the recovery path
# it triggers is the real one and not a second victim
BOOM=$(qu 'rename cfg-show-value cfg-show-value-real
           proc cfg-show-value {it name value} {
               rename cfg-show-value {}
               rename cfg-show-value-real cfg-show-value
               error "boom in the renderer"
           }
           set rc [cfg-set set-edge-resist 21]
           list rc $rc mine [dict exists $::cfg_pending set-edge-resist] \
                others [expr {[dict size $::cfg_pending] > 0}] \
                resist [wm-call {set ::edge_resist}] \
                msg [[winfo toplevel $::cfg_T].b.note cget -text]')
# ...and when the undo ITSELF fails, the configurator gives up
SURRENDER=$(qu 'rename cfg-show-value cfg-show-value-real
           proc cfg-show-value {it name value} {
               rename cfg-show-value {}
               rename cfg-show-value-real cfg-show-value
               error "boom again"
           }
           rename cfg-restore cfg-restore-real
           proc cfg-restore {name} { error "the undo broke too" }
           cfg-set set-edge-resist 22
           rename cfg-restore {}
           rename cfg-restore-real cfg-restore
           set grim [[winfo toplevel $::cfg_T].b.note cget -text]
           list broken $::cfg_broken refused [cfg-set set-drag-slop 6] \
                grim $grim')
RESCUED=$(qu 'cfg-revert
           list broken $::cfg_broken \
                msg [[winfo toplevel $::cfg_T].b.note cget -text]')

# a bump must KEEP what stands beside the size in the record: the
# owner lost his -family to it once
q 'custom-write {set-desk-font -family Iosevka -size 11}' >/dev/null
sleep 0.3
q 'welcome-font-bump up' >/dev/null
sleep 0.5
KEPTFAM=$(grep -c 'set-desk-font -family Iosevka -size 12' "$HERE/cfg-config/tk9wm.custom.tcl" 2>/dev/null)
BUMPED=$(q 'font actual DeskFont -size')
BUMPFILE=$(grep -c 'set-desk-font' "$HERE/cfg-config/tk9wm.custom.tcl" 2>/dev/null)

# ---- the collections below the knob groups (plan step B) ----
# five family nodes; an element born folded; a field edit previews
# through the same door as a knob's; Save ADOPTS the panel set — own
# above the references in order — while the other families each
# write their whole element; the buried config bind wears ✗ in the
# tree
COLLNODES=$(qu 'set n {}
    dict for {i d} $::cfg_node {
        if {[dict get $d what] eq "coll"} { lappend n [dict get $d coll] }
    }
    lsort $n')
ELEMFOLD=$(qu 'set i [dict get $::cfg_fitem {@field panel dummy label}]
    expr {[$::cfg_T item state get [$::cfg_T item parent $i] open]
          ? "open" : "folded"}')
BTNPREV=$(qu 'cfg-set {@field panel dummy label} Кнопка')
sleep 0.5
BTNLIVE=$(q 'lindex [lindex [panel-cfg default shown] 0] 1')
WPREV=$(qu 'cfg-set {@field widgets часы -padding} 7')
sleep 0.3
WLIVE=$(q 'dict get $::widgets часы -padding')
BPREV=$(qu 'cfg-set {@field bindings Super+5 script} {list custom-five}')
sleep 0.3
BLIVE=$(q 'lindex [keymap-payload $::keymap \
                       [list [join [parse-chord Super+5] ,]]] 0')
KOFFPREV=$(qu 'cfg-set {@field keys windows state} off')
sleep 0.3
KLIVE=$(q 'dict exists $::key_bundles windows')
KPARREFUSED=$(qu 'cfg-set {@field keys windows params} {switcher {<Super>Tab}}')
qu 'cfg-save' >/dev/null
sleep 1
OWNSAVED=$(grep -c '^panel-buttons-own default$' "$HERE/cfg-config/tk9wm.custom.tcl")
BTNSAVED=$(grep -c '^panel-button dummy {label Кнопка}$' "$HERE/cfg-config/tk9wm.custom.tcl")
BINDSAVED=$(grep -c '^wm-bind Super+5 {list custom-five} {}$' "$HERE/cfg-config/tk9wm.custom.tcl")
WSAVED=$(grep -c '^wm-widget часы -type clock -padding 7$' "$HERE/cfg-config/tk9wm.custom.tcl")
KSAVED=$(grep -c '^wm-keys windows off$' "$HERE/cfg-config/tk9wm.custom.tcl")
AFTERSAVE=$(qu 'set c [dict get $::cfg_coll panel]
    set b [lindex [dict get $c elements] 0]
    list owned [dict get $c owned] owner [dict get $b owner] \
         label [dict get $b values label]')
# ONE ROW PER CHORD: the word in force is the row, and the one it
# stands over hangs UNDER it — a claimant, not a second element with
# the same name (the owner, 2026-08-01: two such rows read as a
# duplicate and explained nothing).
BINDROWS=$(qu 'set rows {}; set kids {}
    dict for {i d} $::cfg_node {
        if {[dict get $d what] eq "coll"} continue
        if {[dict get $d coll] ne "bindings"} continue
        if {[dict get $d key] ne "Super+5"} continue
        switch -- [dict get $d what] {
            elem   { lappend rows [$::cfg_T item element cget $i Cflag eFlag -text] }
            shadow { lappend kids [list [dict get $d owner] \
                         [$::cfg_T item element cget $i Cflag eFlag -text]] }
        }
    }
    list rows $rows under $kids')
# ...and each of those rows says whose word it is and where it was
# said — the doc column, which used to hold nothing for an element
BINDNOTE=$(qu 'set live ""; set dead ""
    dict for {i d} $::cfg_node {
        if {[dict get $d what] eq "coll"} continue
        if {[dict get $d coll] ne "bindings"} continue
        if {[dict get $d key] ne "Super+5"} continue
        set t [$::cfg_T item element cget $i Cdoc eDoc -text]
        switch -- [dict get $d what] {
            elem   { set live $t }
            shadow { set dead $t }
        }
    }
    list live $live dead $dead')

# THE CONFLICT WARNING: binding over a family's chord asks first, and
# the question names the holder, the family and the parameters it
# stands on. Answered NO here — so the chord must be untouched after.
qu 'proc cfg-confirm {msg} {set ::cfg_lastask $msg; return 0}' >/dev/null
qu 'cfg-insert-bind {Super+t w m} {list nope}' >/dev/null
CONFLICT=$(qu 'set ::cfg_lastask')
CHORDKEPT=$(q 'lindex [keymap-payload $::keymap [lmap t {<Super>t w m} \
    {join [parse-chord $t] ,}]] 0')
qu 'proc cfg-confirm {msg} {return 1}' >/dev/null

# ---- step C: the composition gestures ----
# Delete drops the reference and the action stays a card; Insert
# brings it back; Alt reorders through custom-reorder; Ctrl+Enter
# disassembles a bundle whose off REPLAYS before the kept binds; a
# needs not yet met SAVES on the action and its button stands by;
# windows carries no per-member params
qu 'proc cfg-confirm {msg} {return 1}
    proc t-knob {name} { cfg-select [dict get $::cfg_item $name]; return $name }
    proc t-dead {coll key} {
        dict for {i d} $::cfg_node {
            if {[dict get $d what] eq "elem" && [dict get $d coll] eq $coll
                    && [dict get $d key] eq $key
                    && [dict exists $d dead]} { cfg-select $i; return $i }
        }
        return none
    }
    proc t-fam {coll} {
        dict for {i d} $::cfg_node {
            if {[dict get $d what] eq "coll" && [dict get $d coll] eq $coll} {
                cfg-select $i; return $i
            }
        }
        return none
    }
    proc t-sel {coll key} {
        dict for {i d} $::cfg_node {
            if {[dict get $d what] eq "elem" && [dict get $d coll] eq $coll
                    && [dict get $d key] eq $key
                    && ![dict exists $d dead]} { cfg-select $i; return $i }
        }
        return none
    }
    list armed' >/dev/null
# OURS FIRST: the button we had dressed is our word — Delete takes it
# back, and in an owned set that is the button leaving the strip.
qu 't-sel panel dummy; cfg-delete; list deleted' >/dev/null
sleep 1
DELMINE=$(q 'dict exists $::layer_knobs custom {panel-button dummy}')
DELBTN=$(q 'llength [panel-cfg default shown]')
# THE SUBTREE READING: Delete on the family node takes back every
# word of ours about the panel — including the adoption itself, so
# the config's own set comes back into force.
qu 't-fam panel; cfg-delete; list deleted' >/dev/null
sleep 1
FAMBACK=$(qu 'list owned [dict get $::cfg_coll panel owned] \
    shown [llength [dict get $::cfg_coll panel elements]]')
# ...and NOT OURS: the same key on the config's own button asks first
# and, said yes to, makes the whole set ours minus that one.
qu 't-sel panel dummy; cfg-delete; list deleted' >/dev/null
sleep 1
NOTMINE=$(qu 'list owned [dict get $::cfg_coll panel owned] \
    shown [llength [dict get $::cfg_coll panel elements]]')
CARD=$(qu 'expr {"dummy" in [dict get $::cfg_coll panel cards]}')
qu 'cfg-insert-button dummy' >/dev/null
sleep 0.5
BACK=$(q 'set b [lindex [panel-cfg default shown] 0]
          list [lindex $b 0] [dict exists [lindex $b 2] launch]')
qu 'cfg-insert-button probe' >/dev/null
sleep 0.5
ORDER0=$(q 'lmap b [panel-cfg default shown] {lindex $b 0}')
qu 't-sel panel probe; cfg-move-elem above; list moved' >/dev/null
sleep 1
ORDER1=$(q 'lmap b [panel-cfg default shown] {lindex $b 0}')
FILEORD=$(awk '/^panel-button /{printf "%s ",$2}' "$HERE/cfg-config/tk9wm.custom.tcl")
qu 'set sel {}
    dict for {i d} $::cfg_node {
        if {[dict get $d what] eq "elem" && [dict get $d coll] eq "bindings"
                && [dict get $d key] in {{Super+t q} Super+h}} {
            lappend sel $i
        }
    }
    $::cfg_T selection clear all
    foreach i $sel { $::cfg_T selection add $i }
    cfg-take
    llength $sel' >/dev/null
sleep 0.5
TAKEN=$(q 'list accords [dict exists $::key_bundles accords] \
               quit [chord-of Quit] winops [chord-of winops] \
               help [chord-of key-help-open]')
q reload-config >/dev/null
sleep 1
REPLAY=$(q 'list quit [chord-of Quit] accords [dict exists $::key_bundles accords]')
qu 'cfg-refresh; cfg-insert-widget пульс clock' >/dev/null
sleep 0.5
NEWWIDGET=$(q 'dict get $::widgets пульс -type')
qu 'cfg-insert-bind {<Super>F9} {list niner}' >/dev/null
sleep 0.5
NEWBIND=$(q 'lindex [keymap-payload $::keymap \
                         [list [join [parse-chord <Super>F9] ,]]] 0')
qu 't-sel bindings Super+5; cfg-delete; list deleted' >/dev/null
sleep 1
FIVEBACK=$(q 'lindex [keymap-payload $::keymap \
                          [list [join [parse-chord Super+5] ,]]] 0')
# a needs not yet met is a legitimate word ON THE ACTION: the edit is
# ACCEPTED with a sentence, Save keeps it, the strip skips the button
# on replay while the reference stays visible, flagged waiting — and
# a re-Insert of the standing reference is a friendly no-op
NEEDSRC=$(qu 'cfg-set {@field actions dummy needs} {/bin/nonexistent}')
NEEDSMSG=$(qu 'set l [winfo toplevel $::cfg_T].b.note; $l cget -text')
qu 'cfg-save' >/dev/null
sleep 0.5
qu 'cfg-revert' >/dev/null
sleep 1
STANDBY=$(q 'lmap b [panel-cfg default shown] {lindex $b 0}')
WAITCARD=$(qu 'set r none
    foreach e [dict get $::cfg_coll panel elements] {
        if {[dict get $e key] eq "dummy"} {
            set r [expr {[dict exists $e waiting] ? "yes" : "no"}]
        }
    }
    set r')
qu 'cfg-insert-button dummy' >/dev/null
sleep 0.3
KEPTWORD=$(grep -c '^action dummy {needs /bin/nonexistent}$' "$HERE/cfg-config/tk9wm.custom.tcl")
WPARAMS=$(q 'dict get $::key_bundle_defs windows params')
WPREFUSE=$(q 'catch {wm-keys windows -switcher {<Super>Tab}}')
# DELETE TAKES BACK OUR WORD FIRST. The widget is the config's and we
# have only customized it, so the first Delete drops the customization
# and the config's own widget stands up again; the second, on a row
# that is no longer ours, asks and writes the removal.
qu 't-sel widgets часы; cfg-delete; list deleted' >/dev/null
sleep 0.5
WMINE=$(q 'list [dict exists $::widgets часы] \
    [dict exists $::layer_knobs custom {wm-widget часы}]')
qu 't-sel widgets часы; cfg-delete; list deleted' >/dev/null
sleep 0.5
WGONE=$(q 'dict exists $::widgets часы')
# ...and the navigation LANDS beside the deleted row, not at the top
# of the tree: the family's first element leaves the selection on the
# family node; one with a neighbour above leaves it on that neighbour
LANDPARENT=$(qu 'dict get $::cfg_node [cfg-selected]')
qu 't-sel panel dummy; cfg-delete; list deleted' >/dev/null
sleep 1
LANDPREV=$(qu 'dict get $::cfg_node [cfg-selected]')
# a column dragged by hand (the drag sets a fixed -width) is the
# user's: the fit stops touching it, and no -maxwidth clamps it
COLDRAG=$(qu 'set T $::cfg_T
    $T column configure Cval -width 400
    cfg-refresh
    list w [$T column cget Cval -width] \
         user [dict exists $::cfg_col_user Cval] \
         name [$T column cget Cname -width]')
# ---- the actions family (actions-first turn, slice 1) ----
# a field edit merges by name; two saves ACCUMULATE said+delta; a
# waiting action wears its flag; Insert declares, Delete erases
AFIELD=$(qu 'cfg-set {@field actions probe icon} Q')
sleep 0.3
ALIVE2=$(q 'dict get $::action_raw probe icon')
qu 'cfg-save' >/dev/null
sleep 0.5
ASAVED1=$(grep -c '^action probe {icon Q}$' "$HERE/cfg-config/tk9wm.custom.tcl")
qu 'cfg-set {@field actions probe run} {xclock}' >/dev/null
qu 'cfg-save' >/dev/null
sleep 0.5
ASAVED2=$(grep -c '^action probe {icon Q run xclock}$' "$HERE/cfg-config/tk9wm.custom.tcl")
AWAITFLAG=$(qu 'set r none
    dict for {i d} $::cfg_node {
        if {[dict get $d what] eq "elem" && [dict get $d coll] eq "actions"
                && [dict get $d key] eq "w8x"} {
            set r [$::cfg_T item element cget $i Cflag eFlag -text]
        }
    }
    set r')
# ---- what went wrong, laid out to be read ----
# The echo box says it and fades; this is where the whole message and
# the lines that led to it stay.
q 'problem-record {key Super+9} {the script says no} \
    {/home/x/tk9wm.tcl:3 /home/x/tk9wm.tcl:5}' >/dev/null
qu 'cfg-problems; list opened' >/dev/null
sleep 0.5
PROBVIEW=$(qu 'set w .cfg-problems
    list up [winfo exists $w] \
         rows [$w.list size] \
         first [$w.list get 0] \
         detail [string map {\n | } [$w.detail cget -text]]')
# ...and no two buttons in it promise the same Alt-letter: the ui
# says so at BUILD time now, so a suite can insist instead of
# somebody noticing by hand (the owner found Close and Clear both
# wearing C, 2026-08-01)
# ---- the dress: one ring round the box, and it stays lit while a
# value is being edited inside it ----
RING=$(qu 'set box [winfo parent $::cfg_T]
    focus $::cfg_T
    update idletasks; after 150; update
    set lit [$box cget -style]
    set addr set-fade                                ;# a row always visible
    cfg-entry [dict get $::cfg_item $addr] $addr     ;# the overlay opens
    after 250; update
    list box-style-focused $lit \
         while-editing [$box cget -style] \
         editor [expr {[winfo exists $::cfg_T.edit] ? [winfo class $::cfg_T.edit.t] : {none}}]')
# ...and what a half-typed value does to a scroll and to a stray click
GUARD=$(qu 'set r {}
    lappend r clean [cfg-editing-guard scroll] gone \
        [expr {![winfo exists $::cfg_T.edit]}]
    set addr set-fade
    cfg-entry [dict get $::cfg_item $addr] $addr
    after 200; update
    $::cfg_T.edit.t insert end "X"
    lappend r dirty [cfg-editing-guard scroll] \
        kept [winfo exists $::cfg_T.edit]
    cfg-entry-done cancel
    set r')
# ---- erasing one word keeps the previews standing on others ----
# The owner erased a customization and watched an unsaved edit
# elsewhere roll back with it (2026-08-01): the erase reloads, and a
# reload puts the desk back to what the LAYERS say.
KEEPS=$(qu 'cfg-set set-edge-resist 9
    cfg-save
    cfg-set set-fade 0.31          ;# saved, so there is something to erase
    cfg-save
    cfg-set set-edge-resist 4      ;# ...and this one is NOT saved
    t-knob set-fade
    cfg-erase
    list fade [cfg-cur set-fade] \
         still-pending [dict exists $::cfg_pending set-edge-resist] \
         desk [wm-call {set ::edge_resist}]')

# ...and Tab leaves the field instead of putting a tab in it: in the
# tree's editor that means committing and moving on
# ---- the walls stand still once they are up ----
# Erasing something reloads, and a reload used to re-measure the
# window: it resized itself under the owner's hands (2026-08-02).
WALLS=$(qu 'set W [winfo toplevel $::cfg_T]
    update idletasks
    set before [wm geometry $W]
    cfg-refresh
    after 300; update
    set mid [wm geometry $W]
    t-knob set-fade
    cfg-erase
    after 400; update
    list steady [expr {[wm geometry $W] eq $before && $mid eq $before}]')
# ...and a letter with a modifier on it is not the tree's letter:
# Alt+k belongs to the Knobs label, and the tree used to eat it
# ...and «select none» does not strand the selection on the invisible
# root, where no key navigates anywhere
NOROOT=$(qu 'focus $::cfg_T
    event generate $::cfg_T <Control-backslash> -when now
    after 200; update
    set sel [$::cfg_T selection get]
    list picked [expr {[llength $sel] == 1}] \
         root [expr {[lsearch -exact $sel [$::cfg_T item id root]] >= 0}] \
         cursor [expr {[cfg-selected] ne ""}]')
PLAINKEY=$(qu 'list plain [cfg-plain-key 0] shifted [cfg-plain-key 1] \
    alted [cfg-plain-key 8] ctrled [cfg-plain-key 4] supered [cfg-plain-key 64]')

TABOUT=$(qu 'set addr set-edge-resist
    cfg-entry [dict get $::cfg_item $addr] $addr
    after 200; update
    ui-field-set $::cfg_T.edit 6
    $::cfg_T.edit.t insert end 6          ;# TOUCHED: this one commits
    event generate $::cfg_T.edit.t <Tab> -when now
    after 200; update
    set typed [list open [winfo exists $::cfg_T.edit] \
        value [wm-call {set ::edge_resist}] \
        focus [expr {[focus] eq $::cfg_T}]]
    # ...and a value merely looked at is not an edit: Tab leaves it be
    cfg-entry [dict get $::cfg_item $addr] $addr
    after 200; update
    event generate $::cfg_T.edit.t <Tab> -when now
    after 200; update
    concat $typed [list untouched-open [winfo exists $::cfg_T.edit] \
        untouched-pending [dict exists $::cfg_pending $addr]]')

PIXEL=$(qu 'set T $::cfg_T
    set addr set-fade
    set it [dict get $::cfg_item $addr]
    cfg-entry $it $addr
    after 250; update
    lassign [$T item bbox $it Cval eVal] ex ey
    lassign [$::cfg_T.edit.t bbox 1.0] bx by
    set cellx [expr {[winfo rootx $T] + $ex}]
    set celly [expr {[winfo rooty $T] + $ey}]
    set editx [expr {[winfo rootx $::cfg_T.edit.t] + $bx}]
    set edity [expr {[winfo rooty $::cfg_T.edit.t] + $by}]
    cfg-entry-done cancel
    list dx [expr {$editx - $cellx}] dy [expr {$edity - $celly}]')
# ...and a button struck by its letter shows itself struck: pressed
# while it works, back up a moment later (the owner likes the wink,
# and Tk gives it only in places)
BLINK=$(qu 'set ::blinked 0
    toplevel .blinkprobe
    ttk::button .blinkprobe.b -text "&Go" -command {incr ::blinked}
    ui-accel .blinkprobe.b
    pack .blinkprobe.b
    update                              ;# a keyboard event needs a mapped window
    event generate .blinkprobe <Alt-Key-g> -when now
    set during [.blinkprobe.b instate pressed]
    after 200; update
    set r [list during $during after [.blinkprobe.b instate pressed] \
                fired $::blinked]
    destroy .blinkprobe
    set r')
ACCEL=$(qu 'llength [ui-accel-clashes]')
# ...and the guard is not decorative: two buttons asking for the same
# letter leave the first answering and the second no longer promising
CLASH=$(qu 'toplevel .accelprobe
    ttk::button .accelprobe.a -text "&Save" -command {}
    ttk::button .accelprobe.b -text "&Send" -command {}
    ui-accel .accelprobe.a
    ui-accel .accelprobe.b
    set r [list held [.accelprobe.a cget -underline] \
                demoted [.accelprobe.b cget -underline] \
                seen [llength [ui-accel-clashes]]]
    destroy .accelprobe
    set r')
qu 'cfg-problems-clear .cfg-problems; list cleared' >/dev/null
sleep 0.3
PROBGONE=$(q 'llength [problems]')

# ---- one slot, two spellings (slice 3) ----
# the tree shows the spelling in EFFECT and not the other: probe says
# run, dummy says launch, and neither wears the row it did not say
SLOTROWS=$(qu 'list p-run [dict exists $::cfg_fitem {@field actions probe run}] \
    p-launch [dict exists $::cfg_fitem {@field actions probe launch}] \
    d-run [dict exists $::cfg_fitem {@field actions dummy run}] \
    d-launch [dict exists $::cfg_fitem {@field actions dummy launch}]')
# what may cross over, and what may not: one Run of literal words is
# a command said as a script; anything richer stays a script
CROSS=$(q 'list plain [run-words-of {Run xclock -update 1}] \
    subst [run-words-of {Run tail -f $env(HOME)/log}] \
    other [run-words-of {exec true &}] \
    two [run-words-of {Run a; Run b}]')
# the switch itself: un-say one, say the other, and the row flips
qu 'cfg-slot-switch {@field actions probe run} launch {Run xclock}' >/dev/null
sleep 0.5
SWITCHED=$(q 'list said [dict get $::action_raw probe] \
    fires [lindex [dict get $::action_spec probe launch] 0]')
SLOTROWS2=$(qu 'list p-run [dict exists $::cfg_fitem {@field actions probe run}] \
    p-launch [dict exists $::cfg_fitem {@field actions probe launch}]')
# A DEED THE CONFIG DECLARES can be dropped now — the family had no
# word for it at all before, so the applet could only refuse. The
# removal is a customization like any other: it shows where the deed
# stood, saying so, and Delete on THAT brings the deed back.
qu 't-sel actions w8x; cfg-delete; list deleted' >/dev/null
sleep 1
AREMOVED=$(q 'list gone [expr {![dict exists $::action_raw w8x]}] \
    word [dict exists $::layer_knobs custom {action w8x}]')
AGHOST=$(qu 'set r none
    foreach e [dict get $::cfg_coll actions elements] {
        if {[dict get $e key] eq "w8x"} { set r [dict get $e why] }
    }
    set r')
qu 't-dead actions w8x; cfg-delete; list undone' >/dev/null
sleep 1
ABACK=$(q 'list back [dict exists $::action_raw w8x] \
    word [dict exists $::layer_knobs custom {action w8x}]')

qu 'cfg-insert-action {} fresh1' >/dev/null
sleep 0.3
AINS=$(grep -c '^action fresh1 {}$' "$HERE/cfg-config/tk9wm.custom.tcl")
qu 't-sel actions fresh1; cfg-delete; list deleted' >/dev/null
sleep 1
ADEL=$(grep -c '^action fresh1' "$HERE/cfg-config/tk9wm.custom.tcl")

# THE HINT IS MEASURED AFTER IT WRAPS, not before: the room for it
# is taken from the width the window is about to have, or the fit
# reserves the lines the LAST width needed (the owner, 2026-08-01 —
# three lines of gestures, two lines of room).
NOTEFIT=$(qu 'set W [winfo toplevel $::cfg_T]
    set ::cfg_user_sized 0
    set ::cfg_fit_done 0        ;# the fit runs once per window; this asks again
    cfg-fit
    update idletasks
    set room [expr {[$::cfg_T cget -width] - [winfo x $W.b.note] - 12}]
    set line [font metrics DeskFont -linespace]
    list wrapped [expr {[$W.b.note cget -wraplength] == $room}] \
         lines [expr {[winfo height $W.b] >= 3*$line}] \
         anchor [$W.b.note cget -anchor]')
# ...and NARROWING the window gives the hint the lines it now needs:
# there is slack going down and none going sideways
NOTEGROW=$(qu 'set W [winfo toplevel $::cfg_T]
    set ::cfg_user_sized 1
    wm geometry $W 1000x420; update idletasks
    after 200; update idletasks
    set wide [$W.b cget -height]
    wm geometry $W 420x420; update idletasks
    after 200; update idletasks
    set narrow [$W.b cget -height]
    list grew [expr {$narrow > $wide}] wide $wide narrow $narrow')

# the window must SIT INSIDE the workarea: a tall tree used to be
# born with its bottom edge under the panel
GEO=$(q 'set w [lindex [array names ::frameof] 0]
         set t $::frameof($w)
         regexp {^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fw fh fx fy
         lassign [workarea] wax way ww wh
         list [wm geometry $t] wa [workarea] fits \
              [expr {$fx >= $wax && $fy >= $way
                     && $fx + $fw <= $wax + $ww && $fy + $fh <= $way + $wh}]')

# ---- ONE REGISTRY INSTEAD OF THREE (config-tree, step 1) ----
# The proof the plan asks for: what the applet is served comes out of
# the node store and nowhere else, and the store holds all the kinds
# of node the three tables used to hold apart.
ONEREG=$(q 'list gone [expr {![info exists ::knob_registry]
                             && ![info exists ::collection_registry]
                             && ![info exists ::spec_registry]}] \
    knob [dict get [config-node-of {knobs set-fade}] node] \
    family [dict get [config-node-of {actions}] node] \
    field [dict get [config-node-of {actions @ launch}] node] \
    spec [dict get [config-node-of {@spec terminal env}] kind] \
    served [expr {[dict exists [knob-table] set-fade]
                  && [dict exists [collection-table] actions fields launch]}]')

# ---- the row menu, hanging off the badge (the owner, 2026-08-02) ----
# A knob the config sets now knows WHERE it was said — the line, not
# just the layer — which is what the menu's editor entries lead to.
# ...on a clean slate: earlier scenes leave previews standing (the Tab
# one deliberately does), and a Save here would adopt them and change
# whose the row under test is
q 'custom-erase set-edge-resist' >/dev/null
qu 'cfg-revert; list clean' >/dev/null
sleep 1
KWHERE=$(q 'knob-where set-edge-resist config')
# ...and only the CONFIG's lines are ever offered: the custom file is
# written by click and nobody opens it to edit
qu 'cfg-set set-drag-slop 11; cfg-save; list saved' >/dev/null
sleep 1
qu 'cfg-revert; list reread' >/dev/null    ;# the layer must be SOURCED to
sleep 1                                    ;# have lines at all
CUSTWHERE=$(q 'list config [llength [knob-where set-drag-slop config]] \
    custom [expr {[llength [knob-where set-drag-slop custom]] > 0}]')
# the badge is a link and says so: a cell with something in it wears
# the underlined font, an empty one does not
LINKFONT=$(qu 'set T $::cfg_T
    set said [$T item element cget \
                  [dict get $::cfg_item set-edge-resist] Cflag eFlag -font]
    set none -
    dict for {n it} $::cfg_item {
        if {[$T item element cget $it Cflag eFlag -text] eq ""} {
            set none [$T item element cget $it Cflag eFlag -font]
            break
        }
    }
    list said $said none $none')
# what the menu OFFERS on a config-owned row: nothing of ours to
# erase, nothing to reset, a value to pin, and the way to the line
MENU=$(qu 't-knob set-edge-resist
    set m [cfg-row-menu-build]
    set labels {}
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] eq "separator"} continue
        lappend labels [list [$m entrycget $i -label] [$m entrycget $i -state]]
    }
    set labels')
# Reset to saved is about ONE row: a preview standing elsewhere lives
qu 'cfg-set set-edge-resist 7; cfg-set set-fade 0.55; list previewed' >/dev/null
sleep 0.5
ROWRESET=$(qu 't-knob set-edge-resist
    cfg-row-do reset [cfg-row-subject [cfg-selected]]
    after 500
    list pend [dict exists $::cfg_pending set-edge-resist] \
         kept [dict exists $::cfg_pending set-fade]')
sleep 1
ROWDESK=$(q 'list resist $::edge_resist fade $::fade')
# ...and pinning is the same-value gesture said out loud: a word of
# ours holding what the layer below already gives
ROWPIN=$(qu 't-knob set-edge-resist
    cfg-row-do pin [cfg-row-subject [cfg-selected]]
    list pend [dict exists $::cfg_pending set-edge-resist] \
         value [expr {[dict exists $::cfg_pending set-edge-resist]
                      ? [dict get $::cfg_pending set-edge-resist value] : "-"}]')
qu 'cfg-save; list saved' >/dev/null
sleep 1
PINFILE=$(grep -c 'set-edge-resist 3' "$HERE/cfg-config/tk9wm.custom.tcl")
# now it IS ours, and the menu says so
MENU2=$(qu 't-knob set-edge-resist
    set m [cfg-row-menu-build]
    set r -
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] eq "separator"} continue
        if {[$m entrycget $i -label] eq "Erase my word"} {
            set r [$m entrycget $i -state]
        }
    }
    set r')

kill $WM 2>/dev/null
pkill -f 'ui/host[.]tcl' 2>/dev/null

echo "--- rows=$ROWS hostfont=$HOSTFONT wmfont=$WMFONT badge=$CFGBADGE"
echo "--- preview=$PREVIEW save=$SAVED0->$SAVED1 reverted=$REVERTED bad=$BAD"
echo "--- bumped=$BUMPED bumpfile=$BUMPFILE"
echo "--- where={$KWHERE} custwhere={$CUSTWHERE} menu={$MENU}"
echo "--- verdict"
if [ "${ROWS:-0}" -ge 25 ]; then
    echo "OK: the configurator renders the live registry ($ROWS rows)"
else
    echo "FAIL: rows=$ROWS"
fi
if [ -n "$HOSTFONT" ] && [ "$HOSTFONT" = "$WMFONT" ]; then
    echo "OK: the style bridge carried the desk font to the host"
else
    echo "FAIL: host font $HOSTFONT vs wm font $WMFONT"
fi
if [ "$CFGBADGE" = config ]; then
    echo "OK: the owner column knows set-edge-resist came from the config"
else
    echo "FAIL: owner of set-edge-resist = $CFGBADGE"
fi
if [ "$PREVIEW" = 0.42 ]; then
    echo "OK: an edit previews on the live desk at once"
else
    echo "FAIL: fade after preview = $PREVIEW"
fi
if [ "${SAVED0:-0}" = 0 ] && [ "$SAVED1" = 1 ]; then
    echo "OK: preview did not persist, Save did — through custom-write"
else
    echo "FAIL: custom file set-fade lines: before=$SAVED0 after=$SAVED1"
fi
if [ "$REVERTED" = 4 ]; then
    echo "OK: Revert reloaded the desk's own layers (slop back to default 4)"
else
    echo "FAIL: drag_slop after revert = $REVERTED"
fi
if [ "$BAD" = 0 ]; then
    echo "OK: a value the kind refuses is refused (fade 7)"
else
    echo "FAIL: cfg-set accepted fade 7"
fi
if [ "$BUMPED" = 12 ] && [ "$BUMPFILE" = 1 ]; then
    echo "OK: the mat's font button turned the desk font and persisted"
else
    echo "FAIL: bumped=$BUMPED (want 12), file lines=$BUMPFILE"
fi
if [ "$KEPTFAM" = 1 ]; then
    echo "OK: the bump kept the family standing beside the size"
else
    echo "FAIL: the record after a bump: $(grep set-desk-font "$HERE/cfg-config/tk9wm.custom.tcl")"
fi
if [ "$LISTCELL" = "[2 directories]" ] && [ "$LISTLIVE" = 3 ]; then
    echo "OK: a list summarizes in its cell and edits whole"
else
    echo "FAIL: list cell «$LISTCELL», live length $LISTLIVE"
fi
if [ "$KEPT" = "set-tray-icon-size" ] && [ "$FOLD" = 1 ]; then
    echo "OK: a refresh kept the selection and the folded group"
else
    echo "FAIL: after refresh selection=$KEPT folded=$FOLD"
fi
case $SAMEID in
    "knob 1 field 1")
        echo "OK: a refresh reconciles — the items themselves survive" ;;
    *) echo "FAIL: item survival: $SAMEID" ;;
esac
case $THEME in
    awdark|awlight) echo "OK: ttk wears the matching aw theme ($THEME)" ;;
    clam) echo "OK: ttk fell back to clam (awthemes absent)" ;;
    *) echo "FAIL: ttk theme is $THEME" ;;
esac
if [ "$SBFOCUS" = 0 ]; then
    echo "OK: the scrollbar is out of the focus cycle"
else
    echo "FAIL: scrollbar takefocus = $SBFOCUS"
fi
case "$BADLIST|$BADLISTMSG" in
    "0|"*unmatched*) echo "OK: an unmatched quote is refused with a sentence, not a stack" ;;
    *) echo "FAIL: bad list gave rc=$BADLIST msg «$BADLISTMSG»" ;;
esac
case "$BADPLACE|$BADPLACEMSG" in
    "0|"*bla*|"0|"*place*|"0|"*keyecho*) echo "OK: the desk's own refusal reaches the status line" ;;
    *) echo "FAIL: bad place gave rc=$BADPLACE msg «$BADPLACEMSG»" ;;
esac
case "$FONTCELL|$FONTOWNER|$FONTLIVE|$FONTFAM" in
    "-weight bold|custom|bold|1")
        echo "OK: a derived font shows its delta, and inherits the family" ;;
    *) echo "FAIL: font cell «$FONTCELL» owner=$FONTOWNER live=$FONTLIVE family-inherited=$FONTFAM" ;;
esac
if [ "$SAVEDSPEC" = "-family {DejaVu Sans}" ]; then
    echo "OK: a saved knob reads back as what was said, not as computed"
else
    echo "FAIL: after save the knob reads «$SAVEDSPEC»"
fi
case "$PARTIAL|$PARTIALCELL|$PARTIALLIVE" in
    "1|-family {DejaVu Sans}|DejaVu Sans")
        echo "OK: a partial font spec renders as itself and applies" ;;
    *) echo "FAIL: partial font: rc=$PARTIAL cell «$PARTIALCELL» live «$PARTIALLIVE»" ;;
esac
case "$SPECFORM|$SPECWORDS|$SPECDELTA" in
    "{DejaVu Sans} 13 bold|{DejaVu Sans} 11|{Liberation Serif} 1")
        echo "OK: a Tk font spec is legal, in one word or several, whole or partial" ;;
    *) echo "FAIL: font specs: {$SPECFORM} {$SPECWORDS} {$SPECDELTA}" ;;
esac
# ...and once the USER has sized it, the fit steps aside entirely
if [ "$STABLE" = stable ]; then
    echo "OK: refreshing does not grow the window"
else
    echo "FAIL: widths across three refreshes: $STABLE"
fi
case $REENTER in
    "rc 0 log {fit after-nested fit} sel 1")
        echo "OK: a nested refresh defers into one re-run after the pass" ;;
    *) echo "FAIL: re-entry: $REENTER" ;;
esac
case $DEADSEL in
    "rc 0 kept 1") echo "OK: selecting a dead item is a quiet no-op" ;;
    *) echo "FAIL: dead select: $DEADSEL" ;;
esac
case $HANDSIZED in
    "sized 1 geom 700x400"*)
        echo "OK: a window sized by hand keeps its size through a refresh" ;;
    *) echo "FAIL: hand-sized: $HANDSIZED" ;;
esac
case $FOLLOW in
    "host 14 seed 14") echo "OK: the applet followed the desk font, live" ;;
    *) echo "FAIL: font follow: $FOLLOW" ;;
esac
case $ENDS in
    "set-desk-background set-workarea-follow 1")
        echo "OK: Home/End and Alt+< / Alt+> reach the same two ends" ;;
    *) echo "FAIL: ends: $ENDS" ;;
esac
case $MODS in
    "shown <Super> round 64 same 1 refused 1")
        echo "OK: the drag modifier shows as <Super> and takes it back" ;;
    *) echo "FAIL: modifier: $MODS" ;;
esac
case $HEAD in
    "text {Knobs — everything this desk can be told} under 0 focus "*.t)
        echo "OK: the heading underlines its letter and Alt+k lands on the tree" ;;
    *) echo "FAIL: heading: $HEAD" ;;
esac
case $DESKWIN in
    "gone 0 back 1") echo "OK: the desk window comes and goes on the spot" ;;
    *) echo "FAIL: desk window: $DESKWIN" ;;
esac
case $SPECBAD in
    *"names no family"*) echo "OK: an empty font spec is refused by name" ;;
    *) echo "FAIL: empty spec said «$SPECBAD»" ;;
esac
if [ "$PENDBACK" = "-weight bold" ]; then
    echo "OK: a pending multi-word value comes back whole"
else
    echo "FAIL: pending value came back as «$PENDBACK»"
fi
case "$ERASEDOWNER|$ERASEDLIVE|$ERASEDFILE" in
    "code|normal|0") echo "OK: Erase took the click back — knob, file and desk" ;;
    *) echo "FAIL: after erase owner=$ERASEDOWNER live=$ERASEDLIVE file lines=$ERASEDFILE" ;;
esac
case "$BADCURSOR|$BADCURSORMSG|$GOODCURSOR|$CURSORLIVE" in
    "0|"*"no cursor named"*"|1|watch")
        echo "OK: a bad cursor name is refused by name, a good one applies" ;;
    *) echo "FAIL: cursor: bad=$BADCURSOR msg «$BADCURSORMSG» good=$GOODCURSOR live=$CURSORLIVE" ;;
esac
case $BOOM in
    "rc 0 mine 0 others 1 resist 3 msg "*"back on its saved value"*)
        echo "OK: an error put THAT knob back and left the rest pending" ;;
    *) echo "FAIL: narrow recovery: $BOOM" ;;
esac
case $SURRENDER in
    "broken 1 refused 0 grim "*"stopped touching"*)
        echo "OK: a failed undo makes it give up, loudly and completely" ;;
    *) echo "FAIL: surrender: $SURRENDER" ;;
esac
case $RESCUED in
    "broken 0 msg "*"working again"*)
        echo "OK: Revert is the way back out of the give-up state" ;;
    *) echo "FAIL: rescue: $RESCUED" ;;
esac
case $GOODMSG in
    *"Save makes it stick"*) echo "OK: a good value clears the error line" ;;
    *) echo "FAIL: after a good value the line says «$GOODMSG»" ;;
esac
case $COLLNODES in
    "actions bindings keys panel widgets")
        echo "OK: the five families stand in the tree" ;;
    *) echo "FAIL: collection nodes: $COLLNODES" ;;
esac
if [ "$ELEMFOLD" = folded ]; then
    echo "OK: an element is born folded — the tree is an overview first"
else
    echo "FAIL: element state: $ELEMFOLD"
fi
case "$BTNPREV|$BTNLIVE" in
    "1|Кнопка")
        echo "OK: a label override previews — the strip re-reads the reference" ;;
    *) echo "FAIL: panel field: rc=$BTNPREV label=«$BTNLIVE»" ;;
esac
case "$WPREV|$WLIVE" in
    "1|7") echo "OK: a widget field previews by re-declaring the widget whole" ;;
    *) echo "FAIL: widget field: rc=$WPREV padding=$WLIVE" ;;
esac
case "$BPREV|$BLIVE" in
    "1|list custom-five")
        echo "OK: a binding's script previews, its other half riding along" ;;
    *) echo "FAIL: binding field: rc=$BPREV script=«$BLIVE»" ;;
esac
case "$KOFFPREV|$KLIVE|$KPARREFUSED" in
    "1|0|0") echo "OK: a bundle turns off, and params on an off bundle are refused" ;;
    *) echo "FAIL: keys: off=$KOFFPREV live=$KLIVE params-rc=$KPARREFUSED" ;;
esac
case "$OWNSAVED|$BTNSAVED" in
    "1|1") echo "OK: Save adopted the panel — own above the touched button's delta" ;;
    *) echo "FAIL: adoption: own=$OWNSAVED button=$BTNSAVED:\
 $(grep panel "$HERE/cfg-config/tk9wm.custom.tcl")" ;;
esac
case "$BINDSAVED|$WSAVED|$KSAVED" in
    "1|1|1") echo "OK: bind, widget and bundle wrote their whole element each" ;;
    *) echo "FAIL: saved: bind=$BINDSAVED widget=$WSAVED keys=$KSAVED" ;;
esac
case $AFTERSAVE in
    "owned yes owner custom label Кнопка")
        echo "OK: after Save the set is owned and the reference custom's" ;;
    *) echo "FAIL: after save: $AFTERSAVE" ;;
esac
case $BINDROWS in
    "rows custom under {{config {✗ cfg}}}")
        echo "OK: one row per chord, and the config's word hangs under it" ;;
    *) echo "FAIL: bind rows: $BINDROWS" ;;
esac
case $BINDNOTE in
    "live {in force — yours, over the config's} dead {the config's word, not in force}")
        echo "OK: a bind row says whose word it is, and the buried one where" ;;
    *) echo "FAIL: bind notes: $BINDNOTE" ;;
esac
case "$CONFLICT|$CHORDKEPT" in
    *"accords family (prefix <Super>t"*"|winops")
        echo "OK: taking a family's chord asks first, naming it and its parameters" ;;
    *) echo "FAIL: conflict ask «$CONFLICT», chord now «$CHORDKEPT»" ;;
esac
case "$NEEDSRC|$NEEDSMSG" in
    "1|"*"stand by"*)
        echo "OK: a needs not yet met is accepted with a sentence, not refused" ;;
    *) echo "FAIL: needs edit: rc=$NEEDSRC msg «$NEEDSMSG»" ;;
esac
case "$STANDBY|$WAITCARD|$KEPTWORD" in
    "probe|yes|1")
        echo "OK: the needs rode the action; its reference stands by, flagged" ;;
    *) echo "FAIL: standby: panel=«$STANDBY» waiting=$WAITCARD word=$KEPTWORD" ;;
esac
case "$DELMINE|$DELBTN" in
    "0|0") echo "OK: on a button we had dressed, Delete took our word back" ;;
    *) echo "FAIL: after taking our word back: word=$DELMINE shown=$DELBTN" ;;
esac
case "$FAMBACK|$NOTMINE" in
    "owned no shown 1|owned yes shown 0")
        echo "OK: Delete on the family took back all of ours; on the\
 config's own button it asked and took the set over" ;;
    *) echo "FAIL: family={$FAMBACK} then not-ours={$NOTMINE}" ;;
esac
case $CARD in
    1) echo "OK: the deed stayed a card, ready for Insert to bring back" ;;
    *) echo "FAIL: dummy is not a card after the delete: $CARD" ;;
esac
case $BACK in
    "dummy 1") echo "OK: Insert brought the reference back, deed and all" ;;
    *) echo "FAIL: resurrection: $BACK" ;;
esac
case "$ORDER0|$ORDER1|$FILEORD" in
    "dummy probe|probe dummy|probe dummy ")
        echo "OK: Alt moved the button — the file order IS the panel order" ;;
    *) echo "FAIL: move: $ORDER0 -> $ORDER1, file: $FILEORD" ;;
esac
case $TAKEN in
    "accords 0 quit {Super+t q} winops {} help Super+h")
        echo "OK: the taken binds live on their own, the bundle fell silent" ;;
    *) echo "FAIL: take: $TAKEN" ;;
esac
case $REPLAY in
    "quit {Super+t q} accords 0")
        echo "OK: the taken binds survive the replay — off speaks before them" ;;
    *) echo "FAIL: replay: $REPLAY" ;;
esac
case "$NEWWIDGET|$NEWBIND" in
    "clock|list niner")
        echo "OK: Insert made a widget from its type and a bind from a chord" ;;
    *) echo "FAIL: inserts: widget=«$NEWWIDGET» bind=«$NEWBIND»" ;;
esac
case $FIVEBACK in
    "list config-five")
        echo "OK: deleting the custom bind stood the config's word back up" ;;
    *) echo "FAIL: after bind delete: «$FIVEBACK»" ;;
esac
case "$WPARAMS|$WPREFUSE|$WGONE" in
    "|1|0")
        echo "OK: windows has no per-member params, and the widget dropped" ;;
    *) echo "FAIL: wparams=«$WPARAMS» refuse=$WPREFUSE widget-gone=$WGONE" ;;
esac
case $WMINE in
    "1 0") echo "OK: the first Delete took back our word, the config's stood up" ;;
    *) echo "FAIL: after taking our word back: widget/custom = $WMINE" ;;
esac
case $NOTEFIT in
    "wrapped 1 lines 1 anchor nw")
        echo "OK: three lines' room for the hint, anchored at its top-left" ;;
    *) echo "FAIL: note fit: $NOTEFIT" ;;
esac
case $NOTEGROW in
    "grew 1 "*)
        echo "OK: a narrowed window gives the hint the lines it needs" ;;
    *) echo "FAIL: note growth: $NOTEGROW" ;;
esac
case "$LANDPARENT|$LANDPREV" in
    "what coll coll widgets|what elem coll panel key probe")
        echo "OK: a delete lands on the neighbour above, else the family node" ;;
    *) echo "FAIL: landing after a delete: parent=«$LANDPARENT» prev=«$LANDPREV»" ;;
esac
case $COLDRAG in
    "w 400 user 1 name {}")
        echo "OK: a hand-dragged column keeps its width through the fit" ;;
    *) echo "FAIL: column drag: $COLDRAG" ;;
esac
case "$AFIELD|$ALIVE2|$ASAVED1|$ASAVED2" in
    "1|Q|1|1")
        echo "OK: an action field merges by name and the saves accumulate" ;;
    *) echo "FAIL: action edit: rc=$AFIELD live=$ALIVE2 saved=$ASAVED1/$ASAVED2" ;;
esac
case $AWAITFLAG in
    "waiting cfg") echo "OK: a waiting action wears its flag in the tree" ;;
    *) echo "FAIL: waiting flag: «$AWAITFLAG»" ;;
esac
case "$LINTFLAG|$LINTDOC" in
    *"note"*"|"*"said the long way"*)
        echo "OK: a remark wears a mark on its element and speaks on its row" ;;
    *) echo "FAIL: lint in the tree: flag «$LINTFLAG» doc «$LINTDOC»" ;;
esac
case "$LINTNOTMOD" in
    "flag note unsaved 0")
        echo "OK: a remark wears its own word and says nothing about saving" ;;
    *) echo "FAIL: the linter's mark: $LINTNOTMOD" ;;
esac
if [ "$ACCEL" = 0 ]; then
    echo "OK: no two buttons in this applet promise the same Alt-letter"
else
    echo "FAIL: accelerator clashes: $ACCEL"
fi
if [ "$CLASH" = "held 0 demoted -1 seen 1" ]; then
    echo "OK: a clash leaves the first answering and the second silent about it"
else
    echo "FAIL: the clash guard: $CLASH"
fi
echo "--- keeps={$KEEPS} pixel={$PIXEL} tab={$TABOUT}"
echo "--- walls={$WALLS} plainkey={$PLAINKEY} noroot={$NOROOT}"
case "$ONEREG" in
    "gone 1 knob leaf family family field leaf spec envdict served 1")
        echo "OK: one node store answers for knobs, families and the action language" ;;
    *) echo "FAIL: the one registry: $ONEREG" ;;
esac
case "$KWHERE" in
    *"tk9wm.tcl:1") echo "OK: a knob remembers the config line that set it" ;;
    *) echo "FAIL: knob provenance: «$KWHERE»" ;;
esac
if [ "$CUSTWHERE" = "config 0 custom 1" ]; then  # ...and only config is offered
    echo "OK: the custom file's own line is known but never offered as config"
else
    echo "FAIL: layers of provenance: $CUSTWHERE"
fi
case "$LINKFONT" in
    "said LinkFont none DeskFont")
        echo "OK: a badge with something to say is underlined, an empty one is not" ;;
    *) echo "FAIL: the badge's font: $LINKFONT" ;;
esac
case "$MENU" in
    *"{Erase my word} disabled"*"{Reset to saved} disabled"*"{Pin this value as mine} normal"*"Said at tk9wm.tcl:1"*)
        echo "OK: the row menu offers what the row can do, and the line that says it" ;;
    *) echo "FAIL: the row menu: $MENU" ;;
esac
if [ "$ROWRESET" = "pend 0 kept 1" ] && [ "$ROWDESK" = "resist 3 fade 0.55" ]; then
    echo "OK: Reset to saved is about one row and leaves the other preview standing"
else
    echo "FAIL: row reset: $ROWRESET desk=$ROWDESK"
fi
if [ "$ROWPIN" = "pend 1 value 3" ] && [ "$PINFILE" -ge 1 ] \
        && [ "$MENU2" = "normal" ]; then
    echo "OK: pinning writes our own word for a value we already had"
else
    echo "FAIL: row pin: $ROWPIN file=$PINFILE erase=$MENU2"
fi
if [ "$TABOUT" = "open 0 value 66 focus 1 untouched-open 0 untouched-pending 1" ]; then
    echo "OK: Tab commits what was touched and lets a glance go untouched"
else
    echo "FAIL: tab out of the editor: $TABOUT"
fi
if [ "$WALLS" = "steady 1" ]; then
    echo "OK: neither a refresh nor an erase moved the window's walls"
else
    echo "FAIL: the walls moved: $WALLS"
fi
if [ "$NOROOT" = "picked 1 root 0 cursor 1" ]; then
    echo "OK: «select none» lands on a row one can navigate from"
else
    echo "FAIL: after select-none: $NOROOT"
fi
if [ "$PLAINKEY" = "plain 1 shifted 1 alted 0 ctrled 0 supered 0" ]; then
    echo "OK: the tree claims a letter only when no modifier is on it"
else
    echo "FAIL: plain-key rule: $PLAINKEY"
fi
case $KEEPS in
    "fade 0.31"*)
        echo "FAIL: the erase did not take its own word back: $KEEPS" ;;
    *"still-pending 1 desk 4")
        echo "OK: an erase took back its own word and left the other preview standing" ;;
    *) echo "FAIL: after the erase: $KEEPS" ;;
esac
case $PIXEL in
    "dx 0 dy 0") echo "OK: the editor's text lands exactly on the cell's" ;;
    *) echo "FAIL: the editor's text is off by $PIXEL" ;;
esac
if [ "$BLINK" = "during 1 after 0 fired 1" ]; then
    echo "OK: a button struck by its letter blinks while it works"
else
    echo "FAIL: the accelerator blink: $BLINK"
fi
case $RING in
    "box-style-focused UiRingOn.TFrame while-editing UiRingOn.TFrame editor Text")
        echo "OK: the ring is the box's, and an editor inside it does not put it out" ;;
    *) echo "FAIL: ring: $RING" ;;
esac
if [ "$GUARD" = "clean 1 gone 1 dirty 0 kept 1" ]; then
    echo "OK: an untouched field goes on a scroll; a typed one holds the tree still"
else
    echo "FAIL: editing guard: $GUARD"
fi
case "$PROBVIEW|$PROBGONE" in
    "up 1 rows 1 first {key Super+9 — the script says no} detail {the script says no||said at /home/x/tk9wm.tcl:3 ← /home/x/tk9wm.tcl:5}|0")
        echo "OK: a failure is listed whole, with the lines that led to it" ;;
    *) echo "FAIL: problems view: {$PROBVIEW} left=$PROBGONE" ;;
esac
case "$SLOTROWS|$SLOTROWS2" in
    "p-run 1 p-launch 0 d-run 0 d-launch 1|p-run 0 p-launch 1")
        echo "OK: the slot shows the spelling in effect, and flips with it" ;;
    *) echo "FAIL: slot rows: «$SLOTROWS» then «$SLOTROWS2»" ;;
esac
case $CROSS in
    "plain {xclock -update 1} subst {} other {} two {}")
        echo "OK: only one Run of literal words may cross to a command" ;;
    *) echo "FAIL: crossing: $CROSS" ;;
esac
case $SWITCHED in
    "said {icon Q launch {Run xclock}} fires Run")
        echo "OK: the switch un-said one spelling and said the other" ;;
    *) echo "FAIL: after the switch: $SWITCHED" ;;
esac
case "$AREMOVED|$AGHOST" in
    "gone 1 word 1|removed by you"*)
        echo "OK: the config's deed can be removed, and the removal says so" ;;
    *) echo "FAIL: removal: {$AREMOVED} ghost «$AGHOST»" ;;
esac
case $ABACK in
    "back 1 word 0")
        echo "OK: Delete on the removal took it back and the deed returned" ;;
    *) echo "FAIL: after undoing the removal: $ABACK" ;;
esac
case "$AINS|$ADEL" in
    "1|0") echo "OK: Insert declares a fresh action, Delete takes it back" ;;
    *) echo "FAIL: action insert/delete: ins=$AINS del=$ADEL" ;;
esac
echo "--- geometry: $GEO"
case $GEO in
    *"fits 1") echo "OK: the applet window sits inside the workarea" ;;
    *) echo "FAIL: window vs workarea: $GEO" ;;
esac
check_invariants "$HERE/wm-cfg.log"
