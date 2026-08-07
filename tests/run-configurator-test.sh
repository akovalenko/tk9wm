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
start_xvfb 1024x768x24

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
action facep {run {true}}
EOF

XDG_CONFIG_HOME="$HERE/cfg-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-cfg.log" 2>&1 &
WM=$!
sleep 1.5

q()  { printf '%s\n' "$1" > "$HERE/cfg-config/q.tcl"
       "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/cfg-config/q.tcl"; }
qu() { printf '%s\n' "$1" > "$HERE/cfg-config/qu.tcl"
       "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm-ui "$HERE/cfg-config/qu.tcl"; }
# A FAIL that leaves the exit code at zero is a suite that cannot
# fail: five verdicts rotted here unseen because every runner read
# the tail, saw the last scenes pass, and believed it. Every verdict
# says FAIL through this, and the exit says it again.
BAD=0
fail() { echo "$@"; BAD=1; }

q 'applet configurator' >/dev/null
sleep 3
ROWS=$(qu 'llength [dict keys $::cfg_item]')
# the said order, one storey down: the tree opens on the desk heading
# and its first row is the edit door — the declaration order showing,
# not the alphabet (which put set-desk-background first)
FIRSTROW=$(qu 'set g [lindex [$::cfg_T item children root] 0]
    set k [lindex [$::cfg_T item children $g] 0]
    list [$::cfg_T item element cget $g Cname eGrp -text] \
         [$::cfg_T item element cget $k Cname eTxt -text]')
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

# ---- IT OPENS AT A SIZE ONE CAN READ ----
# The fit is a one-shot (the walls must not walk on every refresh) and
# the shot was being spent by the BUILD's own refresh — measuring a
# tree the toplevel had never laid out, against a hint box wrapped to
# a width nobody knew yet. The owner's configurator opened with room
# for two rows (2026-08-02). The walls are closed by the first fit
# with the window actually on the screen; this asks for the outcome.
OPENFIT=$(qu 'set T $::cfg_T
    set W [winfo toplevel $T]
    list rows [expr {[winfo height $T] / [$T cget -itemheight]}] \
         done $::cfg_fit_done mapped [winfo ismapped $W] \
         byhand $::cfg_user_sized')

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
# a knob's word writes a WISH and the settler does the deed one idle
# tick later (the lifecycle refactor) — so the scene drains that tick
# and the desk window must be there; reading in the same breath as
# the word is reading the wish, which is what this used to assert
# back when the word still acted on the spot
DESKWIN=$(qu 'cfg-set set-desk-window off
              list gone [wm-call {update idletasks
                                  expr {[winfo exists .desk] ? 1 : 0}}] \
                   back [wm-call {set-desk-window on; update idletasks
                                  expr {[winfo exists .desk] ? 1 : 0}}]')
# ...and SAVED, it must still read as what was said, not as what the
# desk computed from it.
# The delta is re-said through the applet first: the scene above poked
# the title font on the DESK directly, and a Save has nothing to
# re-apply now that saying our own word again records no edit — which
# is exactly the rule this suite asks for a few scenes down.
qu 'cfg-set set-title-font {-weight bold}' >/dev/null
sleep 0.3
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
# ...and the ends are the TREE's ends. End walked the knob table, so
# it landed in front of the families with rows still below it (the
# owner, 2026-08-02): the last row is the last open descendant of the
# last top node, the first is the first heading. A heading's name
# lives in another element than a knob's, so the probe asks both.
ENDS=$(qu 'set T $::cfg_T
           focus $T
           proc row-any {} {
               set it [cfg-selected]
               if {$it eq ""} { return "" }
               foreach e {eTxt eGrp} {
                   if {![catch {$::cfg_T item element cget $it Cname $e -text} t]} {
                       return $t
                   }
               }
               return ""
           }
           event generate $T <KeyPress-End>
           set last [row-any]
           event generate $T <KeyPress-Home>
           set first [row-any]
           event generate $T <Alt-greater>
           set lastalt [row-any]
           event generate $T <Alt-less>
           set firstalt [row-any]
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
# ...and what a widget IS is one of the desk's own types, not free
# text: a catalogue the FAMILY answers for (choices-from), so the cell
# gets a menu and «bogusgadget» — a widget that cannot be built — is
# refused instead of committed (the owner, 2026-08-02)
WTYPE=$(qu 'set a {@field widgets часы -type}
    set k [cfg-kind-of $a]
    list kind [lindex $k 0] offers [expr {"clock" in [lrange $k 1 end]}] \
         refused [expr {![cfg-set $a bogusgadget]}] \
         still [cfg-cur $a]')
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
# A REFUSED WORD LEAVES THE STANDING INSTANCE ALONE: one bad
# parameter name used to take the whole family down while the tree
# went on showing it on (the owner, 2026-08-03). Asked of chords
# while it still stands, before the take below dismantles it; the
# no-parameters family answers with its own sentence.
BADPARAM=$(q 'set rc [catch {wm-keys chords -bogus 1} e]
    set rc2 [catch {wm-keys windows -x 1} e2]
    list rc $rc alive [dict exists $::key_bundles chords] \
        said [string match "*no parameter*" $e] \
        none [string match "*takes no parameters*" $e2]')
# ---- a dict member edits from the tree, as itself ----
# The write always went through the parent's whole word; the GESTURE
# stopped at fields — Enter on a bundle's prefix only folded the leaf
# (the owner, 2026-08-03). Driven by the real keystroke path
# (cfg-activate), asked of the live bundle, and put back after.
BUNDLEMEMBER=$(qu 'set it ""
    dict for {i d} $::cfg_node {
        if {[dict get $d what] eq "member" && [dict get $d coll] eq "keys"
                && [dict get $d key] eq "chords"
                && [dict get $d member] eq "prefix"} { set it $i }
    }
    foreach a [$::cfg_T item ancestors $it] {
        catch {$::cfg_T item expand $a}
    }
    $::cfg_T see $it
    update idletasks
    cfg-select $it
    cfg-activate
    after 200; update
    set r [list opened [winfo exists $::cfg_T.edit]]
    ui-field-set $::cfg_T.edit {<Super>u}
    ui-cell-done $::cfg_T commit
    after 400; update
    lappend r live [wm-call {dict get $::key_bundles chords params prefix}]
    cfg-set [list @member keys chords params prefix] {<Super>t}
    after 300
    dict unset ::cfg_pending [list @member keys chords params prefix]
    set r')
sleep 1
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
TAKEN=$(q 'list chords [dict exists $::key_bundles chords] \
               quit [chord-of Quit] winops [chord-of winops] \
               help [chord-of key-help-open]')
q reload-config >/dev/null
sleep 1
REPLAY=$(q 'list quit [chord-of Quit] chords [dict exists $::key_bundles chords]')
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
# EVERYTHING LAZY, BUILT NOW: the clash he found was in a window the
# suite never opened, so the suite opens all of them and then asks
EAGER=$(qu 'list bad [ui-build-all] clashes [llength [ui-accel-clashes]]')
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

# ---- one slot, one spelling on screen (slice 3) ----
# the slot wears its FACE: probe says run and the tree shows launch
# (the derived desugaring), dummy says launch and shows it — the run
# row never stands
SLOTROWS=$(qu 'list p-run [dict exists $::cfg_fitem {@field actions probe run}] \
    p-launch [dict exists $::cfg_fitem {@field actions probe launch}] \
    d-run [dict exists $::cfg_fitem {@field actions dummy run}] \
    d-launch [dict exists $::cfg_fitem {@field actions dummy launch}]')
# ...and the face row is honest: it shows the launch the run
# desugars to, and hands those words to the editor as its seed
FACEVAL=$(qu 'list val [cfg-field-derived {@field actions probe launch}] \
    cell [$::cfg_T item element cget \
        [dict get $::cfg_fitem {@field actions probe launch}] Cval eVal -text] \
    seed [dict get [cfg-cell-opts {@field actions probe launch}] value]')
# writing the face writes THROUGH: the same merging word un-says the
# run still standing under it — the pair may not stand together
qu 'cfg-set {@field actions facep launch} {Run xclock -digital}' >/dev/null
sleep 0.5
FACESAID=$(q 'dict get $::action_raw facep')
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
# ---- the icon row answers as a picture ----
# a found file shows its thumbnail and its path; a miss clears the
# picture and names the search that failed
ICONROW=$(qu 'set png [file join $::env(XDG_CONFIG_HOME) probe-icon.png]
    set src [image create photo -width 6 -height 6]
    $src put yellow -to 0 0 6 6
    $src write $png -format png
    image delete $src
    cfg-set {@field actions probe icon} $png
    set it [dict get $::cfg_fitem {@field actions probe icon}]
    set r [list img [expr {[$::cfg_T item element cget $it Cval eImg -image] ne ""}] \
                doc [$::cfg_T item element cget $it Cdoc eDoc -text]]
    cfg-set {@field actions probe icon} no-such-icon-xyzzy
    lappend r missdoc [$::cfg_T item element cget $it Cdoc eDoc -text] \
        missimg [expr {[$::cfg_T item element cget $it Cval eImg -image] eq ""}]
    set r')
# ---- the examples behind the ▾ ----
# a field that declared examples offers them: picking a row seeds the
# entry, the entry is bent by hand, and the bent words commit
EXAMPLES=$(qu 'set n {@field actions probe key}
    set r [list pick [cfg-picker-of $n] \
                n [dict size [cfg-examples-of $n]]]
    cfg-examples-dialog $n
    set w .cfg-examples
    update
    $w.list selection set 0
    event generate $w.list <<ListboxSelect>> -when now
    lappend r seed [$w.e get]
    $w.e delete 0 end
    $w.e insert 0 {<Super>F8}
    ui-pick-commit $w [list cfg-example-picked $n] {}
    after 300; update
    lappend r cur [cfg-cur $n]
    set r')
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

# ---- A WORD THAT CHANGES NOTHING IS NOT AN EDIT ----
# Typing back what our own layer already says left the row wearing
# «* unsaved» for a save that would rewrite the file identically (the
# owner, 2026-08-02). Saying our own word over the CODE's is another
# matter — that is a pin, and it keeps its mark.
NOOP=$(qu 'set n set-edge-resist
    cfg-set $n 9
    cfg-save
    after 500; update
    set r [list saved [dict exists $::cfg_pending $n]]
    cfg-set $n 9
    after 300; update
    lappend r same [dict exists $::cfg_pending $n]
    cfg-set $n 5
    after 300; update
    lappend r changed [dict exists $::cfg_pending $n]
    cfg-set $n 9
    after 300; update
    lappend r back [dict exists $::cfg_pending $n]
    set r')
# ...and a pin — our word over the code's own default — is still an
# edit, mark and all
PIN=$(qu 'set n set-workarea-follow
    set v [cfg-cur $n]
    cfg-set $n [expr {$v eq "stick" ? "off" : "stick"}]
    after 300; update
    cfg-set $n $v
    after 300; update
    set it [dict get $::cfg_item $n]
    cfg-select $it
    set m [cfg-row-menu-build]
    set reset ""
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] eq "separator"} continue
        if {[$m entrycget $i -label] eq "Reset to saved"} {
            set reset [$m entrycget $i -state]
        }
    }
    list pend [dict exists $::cfg_pending $n] reset $reset')
qu 'cfg-row-do reset [cfg-row-subject [dict get $::cfg_item set-workarea-follow]]
    list undone' >/dev/null
sleep 0.5
# ---- A NEWLINE IS DRAWN, NOT PRINTED ----
# a three-line script in a one-line cell used to put treectrl's
# control-character box on the screen — «vt», a thing to decipher
q 'custom-write {wm-bind {<Super>9} {list one
list two}}' >/dev/null
sleep 1
MULTILINE=$(qu 'set out {}
    set head {}
    dict for {i d} $::cfg_node {
        if {[dict get $d what] ni {field elem}} continue
        if {[dict get $d coll] ne "bindings"} continue
        if {[dict get $d key] ne "Super+9"} continue
        if {[dict get $d what] eq "field"
                && [dict get $d field] eq "script"} {
            set out [$::cfg_T item element cget $i Cval eVal -text]
        }
        if {[dict get $d what] eq "elem"} {
            set head [$::cfg_T item element cget $i Cval eVal -text]
        }
    }
    list cell [list $out] head [list $head]')
# ---- THE EDITOR STAYS INSIDE THE TREE ----
# a cell reaching past the tree's right edge gave the field a width
# partly outside the window: the text believed it had room it did not
# have, never scrolled, and the end of a long line was unreachable
EDGE=$(qu 'set T $::cfg_T
    set it [dict get $::cfg_item set-fade]
    cfg-entry $it set-fade
    after 400; update
    set r [list inside [expr {[winfo x $T.edit] + [winfo width $T.edit]
                              <= [winfo width $T]}]]
    ui-cell-done $T cancel
    set r')

# ---- MARKING ROWS IS A KEYBOARD GESTURE TOO ----
# The tree acts on several rows at once (Ctrl+Enter takes them) and
# the only way to mark them was the mouse, on a desk that is
# keyboard-first everywhere else. And with five rows marked, the row
# menu was about... which one? It says so now, rather than unmarking
# them: «take these five into a file of their own» is a thing one will
# want to say (the owner, 2026-08-02).
MARKS=$(qu 'set T $::cfg_T
    focus $T
    # from the tree itself, not from a remembered id: whatever this
    # suite has been doing to the rows, the first knob under the first
    # heading is always there
    set grp [lindex [$T item children root] 0]
    $T expand $grp
    cfg-select [lindex [$T item children $grp] 0]
    set r [list marked0 [llength [$T selection get]]]
    event generate $T <Shift-Down> -when now
    event generate $T <Shift-Down> -when now
    lappend r grew [llength [$T selection get]]
    set here [cfg-selected]
    set m [cfg-row-menu-build]
    lappend r says [string match "*of 3 marked*" [$m entrycget 0 -label]]
    event generate $T <Control-space> -when now
    lappend r unmarked [llength [$T selection get]]
    event generate $T <Control-space> -when now
    lappend r remarked [llength [$T selection get]]
    cfg-select $here
    set r')

# ---- WHAT IS NOT WRITTEN IS STILL AN ANSWER ----
# A widget that never said where it goes is not «nowhere» — it is
# where its TYPE prefers (widget-preferred-host: a clock rides the
# default panel), which is what the merged options hold; and the
# terminal the desk worked out for itself was known and not shown (the
# owner, 2026-08-02). Both are derived values, marked as not written.
qu 'cfg-insert-widget пробка clock; list made' >/dev/null
sleep 1
DERIVED=$(qu 'cfg-refresh
    after 300; update
    set on [dict get $::cfg_fitem {@field widgets пробка -on}]
    set t [dict get $::cfg_item set-terminal]
    list widget-on [$::cfg_T item element cget $on Cval eVal -text] \
         widget-flag [$::cfg_T item element cget $on Cflag eFlag -text] \
         terminal-shown [expr {[$::cfg_T item element cget $t Cval eVal -text] ne ""}] \
         terminal-flag [$::cfg_T item element cget $t Cflag eFlag -text]')

# ---- THE DESK SAYS A WORD OF ITS OWN, AND THE LIST CATCHES UP ----
# There is one writer for the custom layer and both sides call it —
# but only the writer knew. The owner hid the welcome mat from the
# desk and the configurator went on offering him `set-welcome on`
# (2026-08-02); the desk's own future words (pin this window where it
# stands) need the other half of that. Last of the scenes, because it
# writes the layer for real.
qu 'cfg-status ""; list cleared' >/dev/null
q 'custom-write {set-fade 0.61}' >/dev/null
sleep 1
DESKSAID=$(qu 'list value [cfg-cur set-fade] \
    said [string match "*itself*" [[winfo toplevel $::cfg_T].b.note cget -text]]')
# ...and our OWN word is not announced back at us: an echo of what
# this window just said is not news to it
qu 'cfg-status ""; cfg-write {set-fade 0.63}; list wrote' >/dev/null
sleep 1
OURSSAID=$(qu 'list said [string match "*itself*" \
    [[winfo toplevel $::cfg_T].b.note cget -text]]')
OURSVAL=$(q 'set ::fade')

# the window must SIT INSIDE the workarea: a tall tree used to be
# born with its bottom edge under the panel
GEO=$(q 'set w [lindex [array names ::frameof] 0]
         set t $::frameof($w)
         regexp {^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$} [wm geometry $t] -> fw fh fx fy
         lassign [workarea] wax way ww wh
         list [wm geometry $t] wa [workarea] fits \
              [expr {$fx >= $wax && $fy >= $way
                     && $fx + $fw <= $wax + $ww && $fy + $fh <= $way + $wh}]')

# ---- the linter, called where a script is WRITTEN ----
# (the owner, 2026-08-01: «проверка скриптов мне актуальна скорее
# именно при работе в редакторе»)
SCRIPTLINT=$(q 'set out {}
    foreach case {{wm-restart} {exec xterm} {exec xterm &} {restart-wm}} {
        set v [lindex [script-lint $case] 0]
        lappend out [expr {$v eq "" ? "clean" : [dict get $v level]}]
    }
    lappend out [nearest-command wm-restart]
    set out')
BADPARSE=$(q 'set v [lindex [script-lint "set x \{"] 0]
    list level [dict get $v level] parse [string match {*does not parse*} \
        [dict get $v text]]')
# ...and the editor says what it hears, without refusing the value
EDITLINT=$(qu 'set addr {@field bindings {Super+5} script}
    set ok [cfg-set $addr {wm-restart}]
    set W [winfo toplevel $::cfg_T]
    list ok $ok said [string match {*restart-wm*} [$W.b.note cget -text]]')
qu 'cfg-revert; list back' >/dev/null
sleep 1

# ---- A DICT IS A SUBTREE (config-tree step 3, his own example) ----
q 'action envy {run {true} env {GTK_IM_MODULE xim FOO {}}}' >/dev/null
sleep 0.5
qu 'cfg-refresh; list refreshed' >/dev/null
sleep 0.5
MEMBERS=$(qu 'set addr {@field actions envy env}
    set kids {}
    foreach it [$::cfg_T item children [dict get $::cfg_fitem $addr]] {
        lappend kids [$::cfg_T item element cget $it Cname eTxt -text]
    }
    list kids $kids value [cfg-cur {@member actions envy env GTK_IM_MODULE}] \
         empty [list [cfg-cur {@member actions envy env FOO}]]')
# a member is edited as itself and SAID as its parent — one pending,
# on the dict, so two members cannot race each other to be saved
MEMBEREDIT=$(qu 'cfg-set {@member actions envy env GTK_IM_MODULE} fcitx
    after 300; update
    list dict [cfg-cur {@field actions envy env}] \
         pend [dict exists $::cfg_pending {@field actions envy env}] \
         mpend [dict exists $::cfg_pending {@member actions envy env GTK_IM_MODULE}]')
# ---- ONE SUBJECT, ONE HEADING, and a row that makes one more ----
# `panel` was a heading of knobs AND a heading of buttons, standing
# twice (the owner, 2026-08-02); a family that shares its subject
# hangs under it as a subsection now. And every family one may add to
# ends in an «Add …» row — the plus, and the answer to a subtree with
# nothing in it, which showed neither its contents nor whether it was
# open at all.
TOPICS=$(qu 'proc lbl {it} {
        foreach e {eGrp eTxt} {
            if {![catch {$::cfg_T item element cget $it Cname $e -text} t]} {
                return $t
            }
        }
        return ""
    }
    set tops {}
    set under {}
    foreach it [$::cfg_T item children root] {
        lappend tops [lbl $it]
        if {[lbl $it] ni {panel keys}} continue
        foreach k [$::cfg_T item children $it] {
            if {[dict exists $::cfg_node $k]
                    && [dict get $::cfg_node $k what] eq "coll"} {
                lappend under [lbl $k]
            }
        }
    }
    list panel [llength [lsearch -all -exact $tops panel]] \
         keys [llength [lsearch -all -exact $tops keys]] \
         under [lsort $under]')
ADDROWS=$(qu 'set fam {}; set mem 0; set keysadd 0
    dict for {i d} $::cfg_node {
        if {[dict get $d what] ne "add"} continue
        if {[lindex [dict get $d addr] 0] eq "@add-member"} {
            incr mem
            if {[lindex [dict get $d addr] 2] eq "keys"} { incr keysadd }
            continue
        }
        lappend fam [dict get $d coll]
    }
    list families [lsort -unique $fam] dicts [expr {$mem > 0}] \
        keysadd $keysadd')
# ...and taking one out is legal here, where saying it empty is legal too
MEMBERDROP=$(qu 'cfg-member-drop {@member actions envy env FOO}
    after 300; update
    cfg-cur {@field actions envy env}')
# ...and the row IS the gesture where a name is all that is needed:
# stand on it, type, and the key is in the dict (the owner:
# «вставлять путём редактирования new name прямо в дереве, для env
# так очень уместно»). The name is typed in the NAME column.
ADDINLINE=$(qu 'set addr {@field actions envy env}
    set field [dict get $::cfg_fitem $addr]
    set row ""
    foreach k [$::cfg_T item children $field] {
        if {[dict exists $::cfg_node $k]
                && [dict get $::cfg_node $k what] eq "add"} { set row $k }
    }
    # a cell one cannot see has no place to open an editor over: every
    # storey above the row has to stand open first
    for {set a $field} {$a ne "" && $a != 0} {set a [$::cfg_T item parent $a]} {
        $::cfg_T expand $a
    }
    update idletasks
    cfg-select $row
    cfg-activate primary
    after 400; update
    set opened [winfo exists $::cfg_T.edit]
    ui-field-set $::cfg_T.edit LANG
    ui-cell-done $::cfg_T commit
    after 500; update
    list opened $opened keys [dict keys [cfg-cur $addr]]')

qu 'cfg-revert; list back' >/dev/null
sleep 1

# ---- SAID, AND EMPTY (the owner's question, 2026-08-02) ----
# «отсутствует ли он или присутствует пустой, а это влияет на семантику
# action» — the tree showed one empty cell for both, and only one of
# them puts the deed in a terminal.
q 'action tinker {run {true} terminal {}}' >/dev/null
sleep 0.5
qu 'cfg-refresh; list refreshed' >/dev/null
sleep 0.5
SAIDEMPTY=$(qu 'set T $::cfg_T
    set t [dict get $::cfg_fitem {@field actions tinker terminal}]
    set i [dict get $::cfg_fitem {@field actions tinker icon}]
    list terminal [list [$T item element cget $t Cflag eFlag -text]] \
         icon [list [$T item element cget $i Cflag eFlag -text]] \
         said [cfg-field-said? {@field actions tinker terminal}] \
         means [cfg-field-empty-means {@field actions tinker terminal}] \
         plain [cfg-field-empty-means {@field actions tinker icon}]')
# the menu names the consequence: where empty is a word one SAYS it
# empty, and there is no taking it back at all
TERMMENU=$(qu 'cfg-select [dict get $::cfg_fitem {@field actions tinker terminal}]
    set m [cfg-row-menu-build]
    set labels {}
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] eq "separator"} continue
        lappend labels [list [$m entrycget $i -label] [$m entrycget $i -state]]
    }
    set labels')
# ...and where it is not a word, the same keystroke takes the key back
qu 'cfg-set {@field actions tinker icon} Z; list set' >/dev/null
sleep 0.5
ICONMENU=$(qu 'cfg-select [dict get $::cfg_fitem {@field actions tinker icon}]
    set m [cfg-row-menu-build]
    set r -
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] eq "separator"} continue
        if {[$m entrycget $i -label] eq "Unsay this key"} {
            set r [$m entrycget $i -state]
        }
    }
    set r')
UNSAID=$(qu 'set addr {@field actions tinker icon}
    cfg-select [dict get $::cfg_fitem $addr]
    cfg-row-do unsay [cfg-row-subject [cfg-selected]]
    after 300
    list said [cfg-field-said? $addr] \
         terminal [cfg-field-said? {@field actions tinker terminal}]')

# THE TYPE IS FIRST-CLASS even when nobody said it: the row shows what
# the settings amount to and says it was derived, and writing it is an
# ordinary edit of an ordinary field
TYPEROW=$(qu 'set T $::cfg_T
    set i [dict get $::cfg_fitem {@field actions tinker type}]
    list value [$T item element cget $i Cval eVal -text] \
         flag [list [$T item element cget $i Cflag eFlag -text]] \
         said [cfg-field-said? {@field actions tinker type}]')
TYPESET=$(qu 'cfg-set {@field actions tinker type} generic
    after 300
    set T $::cfg_T
    set i [dict get $::cfg_fitem {@field actions tinker type}]
    list value [$T item element cget $i Cval eVal -text] \
         said [cfg-field-said? {@field actions tinker type}]')

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
# ...and the word IN FORCE is the one a row answers with, whatever
# layer said it: a knob written by a click names the custom file, the
# way a binding of yours always did (the owner, 2026-08-03 — the two
# rows of one tree used to answer differently, and the knob's answer
# was «the config does not mention it», true and useless).
qu 'cfg-set set-drag-slop 11; cfg-save; list saved' >/dev/null
sleep 1
qu 'cfg-revert; list reread' >/dev/null    ;# the layer must be SOURCED to
sleep 1                                    ;# have lines at all
CUSTWHERE=$(q 'list inforce [file tail [lindex [knob-where set-drag-slop] 0]] \
    config [llength [knob-where set-drag-slop config]] \
    custom [expr {[llength [knob-where set-drag-slop custom]] > 0}]')
# the badge is a link and says so: a cell with something in it wears
# the underlined font, an empty one does not
# ...and a knob row NEVER has an empty badge now: the desk's own
# value says `default` — a quiet handle to the row menu, where «Pin
# this value as mine» lives undiscoverable otherwise (the owner,
# 2026-08-02). Quiet = the `quiet` item state, so a theme flip
# repaints it through the element like everything else. The truly
# empty badge (an add row) keeps its plain font.
LINKFONT=$(qu 'set T $::cfg_T
    set it [dict get $::cfg_item set-edge-resist]
    set said [list [$T item element cget $it Cflag eFlag -font] \
                  [expr {"quiet" in [$T item state get $it]}]]
    set def -
    dict for {n i} $::cfg_item {
        if {[$T item element cget $i Cflag eFlag -text] eq "default"} {
            set def [list [$T item element cget $i Cflag eFlag -font] \
                         [expr {"quiet" in [$T item state get $i]}]]
            break
        }
    }
    set none -
    dict for {i d} $::cfg_node {
        if {[dict get $d what] eq "add"} {
            set none [$T item element cget $i Cflag eFlag -font]
            break
        }
    }
    list said $said default $def none $none')
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
# ...and now that a click of ours COVERS the config's own word, the
# menu says both: the line we wrote, and the one it stands on — the
# value this row would fall back to if the word were erased.
qu 'cfg-revert; list reread' >/dev/null   ;# sourced, so both have lines
sleep 1
OVERMENU=$(qu 't-knob set-edge-resist
    set m [cfg-row-menu-build]
    set labels {}
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] eq "separator"} continue
        lappend labels [$m entrycget $i -label]
    }
    set labels')
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

# ---- the ring box decorates, it is not a Tab stop ----
# The frame round the tree and its scrollbar took a focus stop of its
# own — the ring lit with nothing focused in it (the owner,
# 2026-08-02). The whole Tab cycle is walked: the tree is a stop, the
# box around it never.
BOXFOCUS=$(qu 'set box [winfo parent $::cfg_T]
    set stops {}
    set w $::cfg_T
    for {set i 0} {$i < 30} {incr i} {
        set w [tk_focusNext $w]
        if {$w eq $::cfg_T || $w in $stops} break
        lappend stops $w
    }
    list takefocus [$box cget -takefocus] stops $stops')
# ---- the editor sits ON an empty cell, not under it ----
# An empty text element answers bbox with a zero-size rectangle at
# its anchor — the cell's vertical middle — and the overlay took that
# point for a top: the first edit of any empty cell opened pixels
# below its row (the owner, 2026-08-02).
EMPTYCELL=$(qu 'set T $::cfg_T
    set addr set-emacs-edit-daemon
    set it [dict get $::cfg_item $addr]
    $T see $it
    update idletasks
    lassign [$T item bbox $it Cval] cx cy
    cfg-entry $it $addr
    after 200; update
    set r [list empty [expr {[cfg-cur $addr] eq ""}] \
        dx [expr {[winfo x $T.edit] - $cx}] \
        dy [expr {[winfo y $T.edit] - $cy}]]
    cfg-entry-done cancel
    set r')
# ---- the color chooser opens on the DERIVED color ----
# An unsaid color knob is wearing the theme's answer, and handing the
# dialog the empty value threw before anything mapped: the ▾ silently
# did nothing (the owner, 2026-08-02). The dialog itself cannot run
# headless; the seed it opens on can.
COLORSEED=$(qu 'set s [cfg-color-seed set-desk-background]
    list nonempty [expr {$s ne ""}] \
         true [expr {$s eq [cfg-cur set-desk-background]
                     || $s eq [wm-call {themed desk}]}]')
# ---- a bad chord is refused IN the dialog, a loose-case one is taken --
# The commit used to close the dialog and complain into the main
# window's status line — swallowed silence, from where one sat. And
# f9 is F9 said loosely: no keysym exists beside it to make the case
# meaning (the owner, 2026-08-02: Alt+f4).
BADCHORD=$(qu 'cfg-insert-binding-dialog
    set w .cfg-insert
    $w.chord insert 0 "Alt+f44"
    $w.script insert 0 "list x"
    cfg-bind-commit $w
    after 100; update
    set r [list open [winfo exists $w] \
        say [expr {[winfo exists $w.say] ? [$w.say cget -text] : {}}]]
    destroy $w
    set r')
FORGIVEN=$(qu 'cfg-insert-binding-dialog
    set w .cfg-insert
    $w.chord insert 0 "Alt+f9"
    $w.script insert 0 "list forgiven"
    cfg-bind-commit $w
    after 300; update
    list closed [expr {![winfo exists $w]}] \
         same [wm-call {expr {[parse-chord f9] eq [parse-chord F9]}}] \
         held [dict exists [wm-call {chord-holder {Alt+F9}}] who]')
# ---- past six lines the field stops growing and starts scrolling ----
# The scrollbar joins the text inside the same ring and leaves when
# the lines do (the owner, 2026-08-02); the ring is the focus face,
# the bar itself is no Tab stop.
FIELDSB=$(qu 'set T $::cfg_T
    set it [dict get $::cfg_item set-root-cursor]
    $T see $it
    update idletasks
    cfg-entry $it set-root-cursor
    after 200; update
    ui-field-set $T.edit [join {a b c d e f g h} \n]
    event generate $T.edit.t <KeyRelease> -when now
    update idletasks
    set r [list sb [winfo exists $T.edit.sb] h [$T.edit.t cget -height]]
    ui-field-set $T.edit "a\nb"
    event generate $T.edit.t <KeyRelease> -when now
    update idletasks
    lappend r sb2 [winfo exists $T.edit.sb] h2 [$T.edit.t cget -height]
    cfg-entry-done cancel
    set r')
# ---- the line the cursor moved to is a line the field shows ----
# A newline at the very END of the value used to buy no room at all:
# the growth counted the lines of the TRIMMED value, so the empty last
# one did not exist until a letter landed on it, and until then the
# cursor sat below the bottom edge (the owner, 2026-08-03).
NLGROW=$(qu 'set T $::cfg_T
    set it [dict get $::cfg_item set-root-cursor]
    $T see $it
    update idletasks
    cfg-entry $it set-root-cursor
    after 200; update
    ui-field-set $T.edit "один"
    $T.edit.t tag remove sel 1.0 end
    $T.edit.t mark set insert end-1c
    event generate $T.edit.t <Shift-Return> -when now
    update idletasks
    set r [list h [$T.edit.t cget -height] \
        row [lindex [split [$T.edit.t index insert] .] 0] \
        value [ui-field-get $T.edit]]
    cfg-entry-done cancel
    set r')
# ---- the picker refuses in the picker ----
# The caller says what valid means (the check), the dialog holds the
# door: a nameless widget used to fall through in silence — the
# commit returned 0 to a dialog already closed (the owner,
# 2026-08-02). Driven through the OK button, which is the wired path.
PICKCHECK=$(qu 'cfg-insert-widgets-dialog
    set w .cfg-insert
    $w.b.ok invoke
    set r [list open [winfo exists $w] \
        nameless [expr {[winfo exists $w.say] ? [$w.say cget -text] : {}}]]
    $w.e insert 0 "секунды"
    $w.b.ok invoke
    lappend r typeless [expr {[winfo exists $w.say] ? [$w.say cget -text] : {}}]
    $w.list selection set 0
    $w.b.ok invoke
    after 300; update
    lappend r closed [expr {![winfo exists $w]}]
    cfg-insert-widgets-dialog
    set w .cfg-insert
    $w.list selection set 0
    $w.e insert 0 "секунды"
    $w.b.ok invoke
    lappend r dup [expr {[winfo exists $w.say] ? [$w.say cget -text] : {}}]
    destroy $w
    set r')
sleep 0.5
PICKMADE=$(q 'dict exists $::widgets секунды')
# ---- the menu names what Del would do, on a row that is not ours ----
# The earlier scenes turned the windows bundle off and took chords
# apart, so no code word is left standing; the windows family comes
# back on first — a customization like any other, replayed on reload —
# and Alt+Tab is the code-side word these scenes stand on.
q 'custom-write {wm-keys windows}' >/dev/null
sleep 1
DELOFFER=$(qu 'cfg-refresh
    after 300; update
    set it ""
    dict for {i d} $::cfg_node {
        if {[dict get $d what] eq "elem" && [dict get $d coll] eq "bindings"
                && [dict get $d key] eq "Alt+Tab"} { set it $i }
    }
    cfg-select $it
    set m [cfg-row-menu-build]
    set found 0
    for {set i 0} {$i <= [$m index end]} {incr i} {
        if {[$m type $i] eq "separator"} continue
        if {[$m entrycget $i -label] eq "Silence this chord"} { set found 1 }
    }
    set found')
# ---- a word over the desk's own shows what it covers, and so does
#      a silence; erasing the silence brings the chord back ----
SILENCE=$(q 'custom-write {wm-bind {Alt+Tab} {list mine} taken}
    set e1 {}
    foreach e [dict get [collection-bindings] elements] {
        if {[dict get $e key] eq "Alt+Tab"} { set e1 $e }
    }
    custom-write {wm-unbind {Alt+Tab}}
    set e2 {}
    foreach e [dict get [collection-bindings] elements] {
        if {[dict get $e key] eq "Alt+Tab"} { set e2 $e }
    }
    custom-erase {wm-bind Alt+Tab}
    reload-config
    set e3 {}
    foreach e [dict get [collection-bindings] elements] {
        if {[dict get $e key] eq "Alt+Tab"} { set e3 $e }
    }
    list over [dict exists $e1 shadowed] mine [dict get $e1 owner] \
         silence [expr {[dict exists $e2 ineffectual]
                        && [dict get $e2 owner] eq "custom"}] \
         covered [dict exists $e2 shadowed] \
         back [list [dict get $e3 owner] [dict exists $e3 shadowed]]')
sleep 1
# ---- a bundle re-declared live does not stomp the custom word ----
# Re-saving a bundle's params replayed its binds over a custom
# override, while the tree went on calling the override «in force»
# (the owner, 2026-08-03). A bind is a REQUEST against the map; rank
# decides, whenever it arrives.
STOMP=$(q 'custom-write {wm-bind {Alt+space} {list mine2} taken2}
    say-as custom {wm-keys windows}
    set o [keymap-origin $::keymap [list [join [parse-chord Alt+space] ,]]]
    custom-erase {wm-bind Alt+space}
    reload-config
    list holds $o')
sleep 1

# --- THE PALETTE MOVING UNDER AN OPEN APPLET, which is the desk's own
#     <<ThemeChanged>>. `option add` dresses what is created next and
#     nothing that stands, so without the announcement the applet keeps
#     the theme it was born in (the owner, 2026-08-02). Measured on the
#     applet itself, over the send door: the tree's ground, and the ink
#     a selected row is drawn in — the pair that made a picked row
#     unreadable when only one of them followed.
BEFORE=$(qu 'list [lindex [$::cfg_T cget -background] 0] [ui-color selectfg]')
q 'set-theme light' >/dev/null
sleep 2
AFTER=$(qu 'list [lindex [$::cfg_T cget -background] 0] [ui-color selectfg]')
SELINK=$(qu 'lindex [$::cfg_T element cget eTxt -fill] 0')
# ...and a menu built AFTER the flip wears the palette as it stands:
# menus are dressed by hand (ui-menu), not by the option database —
# a timeline the ttk theme writes to as well, which is how the m menu
# stayed dark on a light desk (the owner, 2026-08-02)
MENUPAL=$(qu 'cfg-select [dict get $::cfg_item set-fade]
    set m [cfg-row-menu-build]
    list bg [expr {[$m cget -background] eq [ui-color bg]}] \
         active [expr {[$m cget -activebackground] eq [ui-color select]}] \
         marker [expr {[$m cget -selectcolor] eq [ui-color fg]}]')
echo "--- style before: $BEFORE  after set-theme light: $AFTER"
if [ "$BEFORE" != "$AFTER" ]; then
    echo "OK: the open applet repainted where it stood ($BEFORE -> $AFTER)"
else
    fail "FAIL: the applet kept the theme it was born in ($BEFORE)"
fi
# treectrl answers -background as a state list, so the braces it puts
# round the plain colour are its own and not part of the answer.
AFTERN=$(echo "$AFTER" | tr -d '{}')
case "$AFTERN" in
    "#ffffff "*) echo "OK: ...and it is the LIGHT ground it took, not any change" ;;
    *) fail "FAIL: the tree's ground after going light: $AFTER" ;;
esac
if [ -n "$SELINK" ] && [ "$SELINK" = "$(echo "$AFTERN" | awk '{print $2}')" ]; then
    echo "OK: a selected row is drawn in the selection's own ink, so the band\
 cannot swallow it"
else
    fail "FAIL: selected text is «$SELINK», the selection ink is\
 «$(echo "$AFTER" | awk '{print $2}')»"
fi

# ---- THE EDIT DOOR, PRESSED ----
# The window's own «Edit config…» opens the user's config through the
# desk's edit door; the where-cascade leads with that same door and
# names the terminal editor instead of guessing «$EDITOR». Driven on
# stub binaries so the machine's own editors cannot vote. Last scene
# on purpose: it takes the WM's PATH.
mkdir -p "$HERE/cfg-config/doorbin"
for c in myed xterm; do
    printf '#!/bin/sh\nexit 0\n' > "$HERE/cfg-config/doorbin/$c"
    chmod +x "$HERE/cfg-config/doorbin/$c"
done
q "array unset ::auto_execs
   unset -nocomplain ::env(VISUAL) ::env(TERMINAL)
   set ::env(EDITOR) myed
   set ::env(PATH) $HERE/cfg-config/doorbin
   set ::edit_door_found {}
   set ::terminal_found {}
   list reset" >/dev/null
EDITBTN=$(qu 'set b [winfo toplevel $::cfg_T].b.edit
    list exists [winfo exists $b] label [$b cget -text]')
DOORMENU=$(qu 'cfg-select [dict get $::cfg_item set-edge-resist]
    set m [cfg-row-menu-build]
    list [$m.p1 entrycget 0 -label] [$m.p1 entrycget 2 -label]')
qu '[winfo toplevel $::cfg_T].b.edit invoke; list pressed' >/dev/null
sleep 1
DOORSTATUS=$(qu '[winfo toplevel $::cfg_T].b.note cget -text')
DOORSPAWN=$(grep 'terminal: spawn' "$HERE/wm-cfg.log" | tail -1)

kill $WM 2>/dev/null
pkill -f 'ui/host[.]tcl' 2>/dev/null

echo "--- rows=$ROWS hostfont=$HOSTFONT wmfont=$WMFONT badge=$CFGBADGE"
echo "--- preview=$PREVIEW save=$SAVED0->$SAVED1 reverted=$REVERTED bad=$BAD"
echo "--- bumped=$BUMPED bumpfile=$BUMPFILE"
echo "--- where={$KWHERE} custwhere={$CUSTWHERE} menu={$MENU}"
echo "--- overmenu={$OVERMENU}"
echo "--- verdict"
if [ "${ROWS:-0}" -ge 25 ]; then
    echo "OK: the configurator renders the live registry ($ROWS rows)"
else
    fail "FAIL: rows=$ROWS"
fi
if [ "$FIRSTROW" = "desk set-edit-door" ]; then
    echo "OK: the tree opens on the edit door — knobs in said order"
else
    fail "FAIL: the tree opens on «$FIRSTROW», want «desk set-edit-door»"
fi
case $EDITBTN in
    'exists 1 label {Edit config…}')
        echo "OK: Edit config… stands in the window's own row" ;;
    *) fail "FAIL: the Edit config… button: $EDITBTN" ;;
esac
if [ "$DOORMENU" = '{open — myed ($EDITOR), in a terminal} {in myed, in a terminal}' ]; then
    echo "OK: the where-cascade leads with the door and names the editor"
else
    fail "FAIL: the cascade offers: $DOORMENU"
fi
case $DOORSTATUS in
    'opening the config — myed ($EDITOR), in a terminal')
        echo "OK: the press answered with the door it took" ;;
    *) fail "FAIL: after Edit config… the status says: $DOORSTATUS" ;;
esac
case $DOORSPAWN in
    *'-name tk9wm-edit'*'myed +1 '*'/cfg-config/tk9wm.tcl'*)
        echo "OK: ...and the config walked the door: +1, the desk's own terminal" ;;
    *) fail "FAIL: no edit spawn for the config: $DOORSPAWN" ;;
esac
if [ -n "$HOSTFONT" ] && [ "$HOSTFONT" = "$WMFONT" ]; then
    echo "OK: the style bridge carried the desk font to the host"
else
    fail "FAIL: host font $HOSTFONT vs wm font $WMFONT"
fi
if [ "$CFGBADGE" = config ]; then
    echo "OK: the owner column knows set-edge-resist came from the config"
else
    fail "FAIL: owner of set-edge-resist = $CFGBADGE"
fi
if [ "$PREVIEW" = 0.42 ]; then
    echo "OK: an edit previews on the live desk at once"
else
    fail "FAIL: fade after preview = $PREVIEW"
fi
if [ "${SAVED0:-0}" = 0 ] && [ "$SAVED1" = 1 ]; then
    echo "OK: preview did not persist, Save did — through custom-write"
else
    fail "FAIL: custom file set-fade lines: before=$SAVED0 after=$SAVED1"
fi
if [ "$REVERTED" = 4 ]; then
    echo "OK: Revert reloaded the desk's own layers (slop back to default 4)"
else
    fail "FAIL: drag_slop after revert = $REVERTED"
fi
if [ "$BAD" = 0 ]; then
    echo "OK: a value the kind refuses is refused (fade 7)"
else
    fail "FAIL: cfg-set accepted fade 7"
fi
if [ "$BUMPED" = 12 ] && [ "$BUMPFILE" = 1 ]; then
    echo "OK: the mat's font button turned the desk font and persisted"
else
    fail "FAIL: bumped=$BUMPED (want 12), file lines=$BUMPFILE"
fi
if [ "$KEPTFAM" = 1 ]; then
    echo "OK: the bump kept the family standing beside the size"
else
    fail "FAIL: the record after a bump: $(grep set-desk-font "$HERE/cfg-config/tk9wm.custom.tcl")"
fi
if [ "$LISTCELL" = "[2 directories]" ] && [ "$LISTLIVE" = 3 ]; then
    echo "OK: a list summarizes in its cell and edits whole"
else
    fail "FAIL: list cell «$LISTCELL», live length $LISTLIVE"
fi
if [ "$KEPT" = "set-tray-icon-size" ] && [ "$FOLD" = 1 ]; then
    echo "OK: a refresh kept the selection and the folded group"
else
    fail "FAIL: after refresh selection=$KEPT folded=$FOLD"
fi
case $SAMEID in
    "knob 1 field 1")
        echo "OK: a refresh reconciles — the items themselves survive" ;;
    *) fail "FAIL: item survival: $SAMEID" ;;
esac
case $THEME in
    awdark|awlight) echo "OK: ttk wears the matching aw theme ($THEME)" ;;
    clam) echo "OK: ttk fell back to clam (awthemes absent)" ;;
    *) fail "FAIL: ttk theme is $THEME" ;;
esac
if [ "$SBFOCUS" = 0 ]; then
    echo "OK: the scrollbar is out of the focus cycle"
else
    fail "FAIL: scrollbar takefocus = $SBFOCUS"
fi
if [ "$BOXFOCUS" = "takefocus 0 stops {.tk9wm-configurator.b.save\
 .tk9wm-configurator.b.revert .tk9wm-configurator.b.edit}" ]; then
    echo "OK: the ring box decorates without being a Tab stop of its own"
else
    fail "FAIL: ring box focus: $BOXFOCUS"
fi
if [ "$EMPTYCELL" = "empty 1 dx 0 dy 0" ]; then
    echo "OK: the editor opens ON an empty cell, not below it"
else
    fail "FAIL: empty-cell overlay: $EMPTYCELL"
fi
if [ "$COLORSEED" = "nonempty 1 true 1" ]; then
    echo "OK: the color chooser has a true seed on an unsaid knob"
else
    fail "FAIL: color seed: $COLORSEED"
fi
case "$BADCHORD" in
    "open 1 say "*"unknown keysym"*)
        echo "OK: a bad chord keeps the dialog open and says so in it" ;;
    *) fail "FAIL: bad chord in the dialog: $BADCHORD" ;;
esac
if [ "$FORGIVEN" = "closed 1 same 1 held 1" ]; then
    echo "OK: a loose-case keysym is taken, and the bind stands"
else
    fail "FAIL: forgiving chord: $FORGIVEN"
fi
if [ "$FIELDSB" = "sb 1 h 6 sb2 0 h2 2" ]; then
    echo "OK: past six lines the field scrolls, and the bar leaves with the lines"
else
    fail "FAIL: field scrollbar: $FIELDSB"
fi
if [ "$NLGROW" = "h 2 row 2 value один" ]; then
    echo "OK: a newline at the end grows the field the cursor moved into"
else
    fail "FAIL: trailing newline growth: $NLGROW"
fi
if [ "$PICKCHECK" = "open 1 nameless {name the widget first}\
 typeless {pick a type from the list} closed 1\
 dup {a widget named секунды already stands — pick another name}" ] \
        && [ "$PICKMADE" = 1 ]; then
    echo "OK: the picker refuses bad words in the dialog and lets good ones through"
else
    fail "FAIL: pick check: $PICKCHECK made=$PICKMADE"
fi
if [ "$DELOFFER" = 1 ]; then
    echo "OK: the row menu offers Del's act under its own name"
else
    fail "FAIL: del offer: $DELOFFER"
fi
if [ "$SILENCE" = "over 1 mine custom silence 1 covered 1 back {code 0}" ]; then
    echo "OK: a word or a silence over the desk's own shows what it covers,\
 and erasing it brings the chord back"
else
    fail "FAIL: silence/instead-of: $SILENCE"
fi
if [ "$MENUPAL" = "bg 1 active 1 marker 1" ]; then
    echo "OK: a menu built after the flip wears the palette as it stands"
else
    fail "FAIL: menu palette: $MENUPAL"
fi
if [ "$BADPARAM" = "rc 1 alive 1 said 1 none 1" ]; then
    echo "OK: a refused bundle word leaves the standing instance alone"
else
    fail "FAIL: bad param: $BADPARAM"
fi
if [ "$STOMP" = "holds custom" ]; then
    echo "OK: a bundle re-declared live leaves the custom word standing"
else
    fail "FAIL: stomp: $STOMP"
fi
if [ "$BUNDLEMEMBER" = "opened 1 live <Super>u" ]; then
    echo "OK: a dict member edits from the tree, and the parent's word carries it"
else
    fail "FAIL: bundle member edit: $BUNDLEMEMBER"
fi
case "$BADLIST|$BADLISTMSG" in
    "0|"*unmatched*) echo "OK: an unmatched quote is refused with a sentence, not a stack" ;;
    *) fail "FAIL: bad list gave rc=$BADLIST msg «$BADLISTMSG»" ;;
esac
case "$BADPLACE|$BADPLACEMSG" in
    "0|"*bla*|"0|"*place*|"0|"*keyecho*) echo "OK: the desk's own refusal reaches the status line" ;;
    *) fail "FAIL: bad place gave rc=$BADPLACE msg «$BADPLACEMSG»" ;;
esac
case "$FONTCELL|$FONTOWNER|$FONTLIVE|$FONTFAM" in
    "-weight bold|custom|bold|1")
        echo "OK: a derived font shows its delta, and inherits the family" ;;
    *) fail "FAIL: font cell «$FONTCELL» owner=$FONTOWNER live=$FONTLIVE family-inherited=$FONTFAM" ;;
esac
if [ "$SAVEDSPEC" = "-family {DejaVu Sans}" ]; then
    echo "OK: a saved knob reads back as what was said, not as computed"
else
    fail "FAIL: after save the knob reads «$SAVEDSPEC»"
fi
case "$PARTIAL|$PARTIALCELL|$PARTIALLIVE" in
    "1|-family {DejaVu Sans}|DejaVu Sans")
        echo "OK: a partial font spec renders as itself and applies" ;;
    *) fail "FAIL: partial font: rc=$PARTIAL cell «$PARTIALCELL» live «$PARTIALLIVE»" ;;
esac
case "$SPECFORM|$SPECWORDS|$SPECDELTA" in
    "{DejaVu Sans} 13 bold|{DejaVu Sans} 11|{Liberation Serif} 1")
        echo "OK: a Tk font spec is legal, in one word or several, whole or partial" ;;
    *) fail "FAIL: font specs: {$SPECFORM} {$SPECWORDS} {$SPECDELTA}" ;;
esac
# ...and once the USER has sized it, the fit steps aside entirely
if [ "$STABLE" = stable ]; then
    echo "OK: refreshing does not grow the window"
else
    fail "FAIL: widths across three refreshes: $STABLE"
fi
case $REENTER in
    "rc 0 log {fit after-nested fit} sel 1")
        echo "OK: a nested refresh defers into one re-run after the pass" ;;
    *) fail "FAIL: re-entry: $REENTER" ;;
esac
case $DEADSEL in
    "rc 0 kept 1") echo "OK: selecting a dead item is a quiet no-op" ;;
    *) fail "FAIL: dead select: $DEADSEL" ;;
esac
case $HANDSIZED in
    "sized 1 geom 700x400"*)
        echo "OK: a window sized by hand keeps its size through a refresh" ;;
    *) fail "FAIL: hand-sized: $HANDSIZED" ;;
esac
case $FOLLOW in
    "host 14 seed 14") echo "OK: the applet followed the desk font, live" ;;
    *) fail "FAIL: font follow: $FOLLOW" ;;
esac
case $ENDS in
    "desk {Add a menu…} 1")
        echo "OK: Home/End and Alt+< / Alt+> reach the same two ends of the TREE" ;;
    *) fail "FAIL: ends: $ENDS" ;;
esac
case $MODS in
    "shown <Super> round 64 same 1 refused 1")
        echo "OK: the drag modifier shows as <Super> and takes it back" ;;
    *) fail "FAIL: modifier: $MODS" ;;
esac
case $HEAD in
    "text {Knobs — everything this desk can be told} under 0 focus "*.t)
        echo "OK: the heading underlines its letter and Alt+k lands on the tree" ;;
    *) fail "FAIL: heading: $HEAD" ;;
esac
case $DESKWIN in
    "gone 0 back 1") echo "OK: the desk window comes and goes on the spot" ;;
    *) fail "FAIL: desk window: $DESKWIN" ;;
esac
case $SPECBAD in
    *"names no family"*) echo "OK: an empty font spec is refused by name" ;;
    *) fail "FAIL: empty spec said «$SPECBAD»" ;;
esac
if [ "$PENDBACK" = "-weight bold" ]; then
    echo "OK: a pending multi-word value comes back whole"
else
    fail "FAIL: pending value came back as «$PENDBACK»"
fi
case "$ERASEDOWNER|$ERASEDLIVE|$ERASEDFILE" in
    "code|normal|0") echo "OK: Erase took the click back — knob, file and desk" ;;
    *) fail "FAIL: after erase owner=$ERASEDOWNER live=$ERASEDLIVE file lines=$ERASEDFILE" ;;
esac
case "$BADCURSOR|$BADCURSORMSG|$GOODCURSOR|$CURSORLIVE" in
    "0|"*"no cursor named"*"|1|watch")
        echo "OK: a bad cursor name is refused by name, a good one applies" ;;
    *) fail "FAIL: cursor: bad=$BADCURSOR msg «$BADCURSORMSG» good=$GOODCURSOR live=$CURSORLIVE" ;;
esac
case $BOOM in
    "rc 0 mine 0 others 1 resist 3 msg "*"back on its saved value"*)
        echo "OK: an error put THAT knob back and left the rest pending" ;;
    *) fail "FAIL: narrow recovery: $BOOM" ;;
esac
case $SURRENDER in
    "broken 1 refused 0 grim "*"stopped touching"*)
        echo "OK: a failed undo makes it give up, loudly and completely" ;;
    *) fail "FAIL: surrender: $SURRENDER" ;;
esac
case $RESCUED in
    "broken 0 msg "*"working again"*)
        echo "OK: Revert is the way back out of the give-up state" ;;
    *) fail "FAIL: rescue: $RESCUED" ;;
esac
case $GOODMSG in
    *"Save makes it stick"*) echo "OK: a good value clears the error line" ;;
    *) fail "FAIL: after a good value the line says «$GOODMSG»" ;;
esac
case $COLLNODES in
    "actions bindings keys menus panel widgets")
        echo "OK: the six families stand in the tree" ;;
    *) fail "FAIL: collection nodes: $COLLNODES" ;;
esac
if [ "$ELEMFOLD" = folded ]; then
    echo "OK: an element is born folded — the tree is an overview first"
else
    fail "FAIL: element state: $ELEMFOLD"
fi
case "$BTNPREV|$BTNLIVE" in
    "1|Кнопка")
        echo "OK: a label override previews — the strip re-reads the reference" ;;
    *) fail "FAIL: panel field: rc=$BTNPREV label=«$BTNLIVE»" ;;
esac
if [ "$WTYPE" = "kind choice offers 1 refused 1 still clock" ]; then
    echo "OK: a widget's type is one of the desk's own, and nonsense is refused"
else
    fail "FAIL: the widget type catalogue: $WTYPE"
fi
case "$WPREV|$WLIVE" in
    "1|7") echo "OK: a widget field previews by re-declaring the widget whole" ;;
    *) fail "FAIL: widget field: rc=$WPREV padding=$WLIVE" ;;
esac
case "$BPREV|$BLIVE" in
    "1|list custom-five")
        echo "OK: a binding's script previews, its other half riding along" ;;
    *) fail "FAIL: binding field: rc=$BPREV script=«$BLIVE»" ;;
esac
case "$KOFFPREV|$KLIVE|$KPARREFUSED" in
    "1|0|0") echo "OK: a bundle turns off, and params on an off bundle are refused" ;;
    *) fail "FAIL: keys: off=$KOFFPREV live=$KLIVE params-rc=$KPARREFUSED" ;;
esac
case "$OWNSAVED|$BTNSAVED" in
    "1|1") echo "OK: Save adopted the panel — own above the touched button's delta" ;;
    *) fail "FAIL: adoption: own=$OWNSAVED button=$BTNSAVED:\
 $(grep panel "$HERE/cfg-config/tk9wm.custom.tcl")" ;;
esac
case "$BINDSAVED|$WSAVED|$KSAVED" in
    "1|1|1") echo "OK: bind, widget and bundle wrote their whole element each" ;;
    *) fail "FAIL: saved: bind=$BINDSAVED widget=$WSAVED keys=$KSAVED" ;;
esac
case $AFTERSAVE in
    "owned yes owner custom label Кнопка")
        echo "OK: after Save the set is owned and the reference custom's" ;;
    *) fail "FAIL: after save: $AFTERSAVE" ;;
esac
case $BINDROWS in
    "rows custom under {{config {✗ cfg}}}")
        echo "OK: one row per chord, and the config's word hangs under it" ;;
    *) fail "FAIL: bind rows: $BINDROWS" ;;
esac
case $BINDNOTE in
    "live {in force — yours, over the config's} dead {the config's word, not in force}")
        echo "OK: a bind row says whose word it is, and the buried one where" ;;
    *) fail "FAIL: bind notes: $BINDNOTE" ;;
esac
case "$CONFLICT|$CHORDKEPT" in
    *"chords family (prefix <Super>t"*"|winops")
        echo "OK: taking a family's chord asks first, naming it and its parameters" ;;
    *) fail "FAIL: conflict ask «$CONFLICT», chord now «$CHORDKEPT»" ;;
esac
case "$NEEDSRC|$NEEDSMSG" in
    "1|"*"stand by"*)
        echo "OK: a needs not yet met is accepted with a sentence, not refused" ;;
    *) fail "FAIL: needs edit: rc=$NEEDSRC msg «$NEEDSMSG»" ;;
esac
case "$STANDBY|$WAITCARD|$KEPTWORD" in
    "probe|yes|1")
        echo "OK: the needs rode the action; its reference stands by, flagged" ;;
    *) fail "FAIL: standby: panel=«$STANDBY» waiting=$WAITCARD word=$KEPTWORD" ;;
esac
case "$DELMINE|$DELBTN" in
    "0|0") echo "OK: on a button we had dressed, Delete took our word back" ;;
    *) fail "FAIL: after taking our word back: word=$DELMINE shown=$DELBTN" ;;
esac
case "$FAMBACK|$NOTMINE" in
    "owned no shown 1|owned yes shown 0")
        echo "OK: Delete on the family took back all of ours; on the\
 config's own button it asked and took the set over" ;;
    *) fail "FAIL: family={$FAMBACK} then not-ours={$NOTMINE}" ;;
esac
case $CARD in
    1) echo "OK: the deed stayed a card, ready for Insert to bring back" ;;
    *) fail "FAIL: dummy is not a card after the delete: $CARD" ;;
esac
case $BACK in
    "dummy 1") echo "OK: Insert brought the reference back, deed and all" ;;
    *) fail "FAIL: resurrection: $BACK" ;;
esac
case "$ORDER0|$ORDER1|$FILEORD" in
    "dummy probe|probe dummy|probe dummy ")
        echo "OK: Alt moved the button — the file order IS the panel order" ;;
    *) fail "FAIL: move: $ORDER0 -> $ORDER1, file: $FILEORD" ;;
esac
case $TAKEN in
    "chords 0 quit {Super+t q} winops {} help Super+h")
        echo "OK: the taken binds live on their own, the bundle fell silent" ;;
    *) fail "FAIL: take: $TAKEN" ;;
esac
case $REPLAY in
    "quit {Super+t q} chords 0")
        echo "OK: the taken binds survive the replay — off speaks before them" ;;
    *) fail "FAIL: replay: $REPLAY" ;;
esac
case "$NEWWIDGET|$NEWBIND" in
    "clock|list niner")
        echo "OK: Insert made a widget from its type and a bind from a chord" ;;
    *) fail "FAIL: inserts: widget=«$NEWWIDGET» bind=«$NEWBIND»" ;;
esac
case $FIVEBACK in
    "list config-five")
        echo "OK: deleting the custom bind stood the config's word back up" ;;
    *) fail "FAIL: after bind delete: «$FIVEBACK»" ;;
esac
case "$WPARAMS|$WPREFUSE|$WGONE" in
    "|1|0")
        echo "OK: windows has no per-member params, and the widget dropped" ;;
    *) fail "FAIL: wparams=«$WPARAMS» refuse=$WPREFUSE widget-gone=$WGONE" ;;
esac
case $WMINE in
    "1 0") echo "OK: the first Delete took back our word, the config's stood up" ;;
    *) fail "FAIL: after taking our word back: widget/custom = $WMINE" ;;
esac
case $NOTEFIT in
    "wrapped 1 lines 1 anchor nw")
        echo "OK: three lines' room for the hint, anchored at its top-left" ;;
    *) fail "FAIL: note fit: $NOTEFIT" ;;
esac
case $NOTEGROW in
    "grew 1 "*)
        echo "OK: a narrowed window gives the hint the lines it needs" ;;
    *) fail "FAIL: note growth: $NOTEGROW" ;;
esac
case "$LANDPARENT|$LANDPREV" in
    "what coll coll widgets|what elem coll panel key probe")
        echo "OK: a delete lands on the neighbour above, else the family node" ;;
    *) fail "FAIL: landing after a delete: parent=«$LANDPARENT» prev=«$LANDPREV»" ;;
esac
case $COLDRAG in
    "w 400 user 1 name {}")
        echo "OK: a hand-dragged column keeps its width through the fit" ;;
    *) fail "FAIL: column drag: $COLDRAG" ;;
esac
case "$AFIELD|$ALIVE2|$ASAVED1|$ASAVED2" in
    "1|Q|1|1")
        echo "OK: an action field merges by name and the saves accumulate" ;;
    *) fail "FAIL: action edit: rc=$AFIELD live=$ALIVE2 saved=$ASAVED1/$ASAVED2" ;;
esac
case $AWAITFLAG in
    "waiting cfg") echo "OK: a waiting action wears its flag in the tree" ;;
    *) fail "FAIL: waiting flag: «$AWAITFLAG»" ;;
esac
case "$LINTFLAG|$LINTDOC" in
    *"note"*"|"*"said the long way"*)
        echo "OK: a remark wears a mark on its element and speaks on its row" ;;
    *) fail "FAIL: lint in the tree: flag «$LINTFLAG» doc «$LINTDOC»" ;;
esac
case "$LINTNOTMOD" in
    "flag note unsaved 0")
        echo "OK: a remark wears its own word and says nothing about saving" ;;
    *) fail "FAIL: the linter's mark: $LINTNOTMOD" ;;
esac
if [ "$EAGER" = "bad {} clashes 0" ]; then
    echo "OK: everything built on first use builds now, and promises nothing twice"
else
    fail "FAIL: the eager build: $EAGER"
fi
if [ "$ACCEL" = 0 ]; then
    echo "OK: no two buttons in this applet promise the same Alt-letter"
else
    fail "FAIL: accelerator clashes: $ACCEL"
fi
if [ "$CLASH" = "held 0 demoted -1 seen 1" ]; then
    echo "OK: a clash leaves the first answering and the second silent about it"
else
    fail "FAIL: the clash guard: $CLASH"
fi
echo "--- keeps={$KEEPS} pixel={$PIXEL} tab={$TABOUT}"
echo "--- boxfocus={$BOXFOCUS} emptycell={$EMPTYCELL} colorseed={$COLORSEED}"
echo "--- badchord={$BADCHORD} forgiven={$FORGIVEN}"
echo "--- fieldsb={$FIELDSB} nlgrow={$NLGROW} deloffer=$DELOFFER menupal={$MENUPAL}"
echo "--- pickcheck={$PICKCHECK} made=$PICKMADE"
echo "--- silence={$SILENCE} badparam={$BADPARAM} stomp={$STOMP}"
echo "--- walls={$WALLS} plainkey={$PLAINKEY} noroot={$NOROOT}"
if [ "$SCRIPTLINT" = "warn warn note clean restart-wm" ] \
        && [ "$BADPARSE" = "level warn parse 1" ]; then
    echo "OK: a script is judged where it is written, and the near miss is named"
else
    fail "FAIL: script-lint: $SCRIPTLINT parse=$BADPARSE"
fi
if [ "$EDITLINT" = "ok 1 said 1" ]; then
    echo "OK: the editor takes the value and passes the linter's word along"
else
    fail "FAIL: the editor's lint: $EDITLINT"
fi
if [ "$TYPEROW" = "value terminal flag derived said 0" ] \
        && [ "$TYPESET" = "value generic said 1" ]; then
    echo "OK: a deed's type shows what it amounts to, and writing it is an edit"
else
    fail "FAIL: the type row: $TYPEROW then $TYPESET"
fi
if [ "$MARKS" = "marked0 1 grew 3 says 1 unmarked 2 remarked 3" ]; then
    echo "OK: Shift+arrow marks as it walks, Ctrl+space toggles, the menu says whose"
else
    fail "FAIL: the marks: $MARKS"
fi
case "$DERIVED" in
    "widget-on {panel default} widget-flag derived terminal-shown 1 terminal-flag derived")
        echo "OK: an unsaid field and an unsaid knob show what they amount to" ;;
    *) fail "FAIL: derived values: $DERIVED" ;;
esac
if [ "$NOOP" = "saved 0 same 0 changed 1 back 0" ]; then
    echo "OK: typing back our own saved word is no edit, and a real one still is"
else
    fail "FAIL: the no-op edit: $NOOP"
fi
if [ "$PIN" = "pend 1 reset normal" ]; then
    echo "OK: our word over the code's default is a pin — marked, and undoable"
else
    fail "FAIL: the pin: $PIN"
fi
if [ "$MULTILINE" = "cell {{list one ⏎ list two}} head {{list one ⏎ list two}}" ]; then
    echo "OK: a newline in a cell is drawn, not printed as a control box"
else
    fail "FAIL: the multi-line cell: $MULTILINE"
fi
if [ "$EDGE" = "inside 1" ]; then
    echo "OK: the editor stands inside the tree, so its text can scroll"
else
    fail "FAIL: the editor ran past the tree: $EDGE"
fi
if [ "$DESKSAID" = "value 0.61 said 1" ] \
        && [ "$OURSSAID" = "said 0" ] && [ "$OURSVAL" = 0.63 ]; then
    echo "OK: a word the desk said itself reached the open editor, and only that word"
else
    fail "FAIL: the layer push: $DESKSAID / $OURSSAID"
fi
if [ "$TOPICS" = "panel 1 keys 1 under {bindings bundles buttons}" ]; then
    echo "OK: one heading per subject — the families hang under theirs"
else
    fail "FAIL: the topics: $TOPICS"
fi
if [ "$ADDROWS" = "families {actions bindings menus panel widgets} dicts 1 keysadd 0" ]; then
    echo "OK: every family one may add to ends in a row that makes one"
else
    fail "FAIL: the add rows: $ADDROWS"
fi
if [ "$ADDINLINE" = "opened 1 keys {GTK_IM_MODULE LANG}" ]; then
    echo "OK: a name typed into the add row of a dict is a new key"
else
    fail "FAIL: the inline add: $ADDINLINE"
fi
if [ "$MEMBERS" = "kids {GTK_IM_MODULE FOO {Add a key…}} value xim empty {{}}" ] \
        && [ "$MEMBEREDIT" = "dict {GTK_IM_MODULE fcitx FOO {}} pend 1 mpend 0" ] \
        && [ "$MEMBERDROP" = "GTK_IM_MODULE fcitx" ]; then
    echo "OK: a dict is a subtree — a member edits as itself and is said as its parent"
else
    fail "FAIL: dict members: $MEMBERS | $MEMBEREDIT | $MEMBERDROP"
fi
case "$SAIDEMPTY" in
    "terminal {{said empty note}} icon {{}} said 1 means value plain unsay")
        echo "OK: a key said with nothing in it reads differently from one never said" ;;
    *) fail "FAIL: said-empty: $SAIDEMPTY" ;;
esac
case "$TERMMENU" in
    *"{Say it empty} disabled"*"{Unsay this key} disabled"*)
        echo "OK: where empty is a word, the menu says so and offers no taking back" ;;
    *) fail "FAIL: the terminal field's menu: $TERMMENU" ;;
esac
if [ "$ICONMENU" = "normal" ] && [ "$UNSAID" = "said 0 terminal 1" ]; then
    echo "OK: an ordinary key can be unsaid by name, and its neighbour stands"
else
    fail "FAIL: unsaying a key: menu=$ICONMENU after=$UNSAID"
fi
case "$ONEREG" in
    "gone 1 knob leaf family family field leaf spec envdict served 1")
        echo "OK: one node store answers for knobs, families and the action language" ;;
    *) fail "FAIL: the one registry: $ONEREG" ;;
esac
case "$KWHERE" in
    *"tk9wm.tcl:1") echo "OK: a knob remembers the config line that set it" ;;
    *) fail "FAIL: knob provenance: «$KWHERE»" ;;
esac
case "$CUSTWHERE" in
    "inforce tk9wm.custom.tcl:"*" config 0 custom 1")
        echo "OK: a knob written by a click answers with the file it was\
 written in" ;;
    *) fail "FAIL: layers of provenance: $CUSTWHERE" ;;
esac
case "$OVERMENU" in
    *"Said at tk9wm.custom.tcl:"*"over the config's tk9wm.tcl:1"*)
        echo "OK: ...and when it covers a config word, the menu offers that\
 line too — what the value would fall back to" ;;
    *) fail "FAIL: the menu over a covered config word: $OVERMENU" ;;
esac
case "$LINKFONT" in
    "said {LinkFont 0} default {LinkFont 1} none DeskFont")
        echo "OK: every knob row wears a handle — loud when it has news,\
 quiet on a default, and an empty badge stays plain" ;;
    *) fail "FAIL: the badge's font: $LINKFONT" ;;
esac
case "$MENU" in
    *"{Erase my word} disabled"*"{Reset to saved} disabled"*"{Pin this value as mine} normal"*"Said at tk9wm.tcl:1"*)
        echo "OK: the row menu offers what the row can do, and the line that says it" ;;
    *) fail "FAIL: the row menu: $MENU" ;;
esac
if [ "$ROWRESET" = "pend 0 kept 1" ] && [ "$ROWDESK" = "resist 3 fade 0.55" ]; then
    echo "OK: Reset to saved is about one row and leaves the other preview standing"
else
    fail "FAIL: row reset: $ROWRESET desk=$ROWDESK"
fi
if [ "$ROWPIN" = "pend 1 value 3" ] && [ "$PINFILE" -ge 1 ] \
        && [ "$MENU2" = "normal" ]; then
    echo "OK: pinning writes our own word for a value we already had"
else
    fail "FAIL: row pin: $ROWPIN file=$PINFILE erase=$MENU2"
fi
if [ "$TABOUT" = "open 0 value 66 focus 1 untouched-open 0 untouched-pending 1" ]; then
    echo "OK: Tab commits what was touched and lets a glance go untouched"
else
    fail "FAIL: tab out of the editor: $TABOUT"
fi
if [ "$WALLS" = "steady 1" ]; then
    echo "OK: neither a refresh nor an erase moved the window's walls"
else
    fail "FAIL: the walls moved: $WALLS"
fi
if [ "$NOROOT" = "picked 1 root 0 cursor 1" ]; then
    echo "OK: «select none» lands on a row one can navigate from"
else
    fail "FAIL: after select-none: $NOROOT"
fi
if [ "$PLAINKEY" = "plain 1 shifted 1 alted 0 ctrled 0 supered 0" ]; then
    echo "OK: the tree claims a letter only when no modifier is on it"
else
    fail "FAIL: plain-key rule: $PLAINKEY"
fi
case $KEEPS in
    "fade 0.31"*)
        fail "FAIL: the erase did not take its own word back: $KEEPS" ;;
    *"still-pending 1 desk 4")
        echo "OK: an erase took back its own word and left the other preview standing" ;;
    *) fail "FAIL: after the erase: $KEEPS" ;;
esac
case $PIXEL in
    "dx 0 dy 0") echo "OK: the editor's text lands exactly on the cell's" ;;
    *) fail "FAIL: the editor's text is off by $PIXEL" ;;
esac
if [ "$BLINK" = "during 1 after 0 fired 1" ]; then
    echo "OK: a button struck by its letter blinks while it works"
else
    fail "FAIL: the accelerator blink: $BLINK"
fi
case $RING in
    "box-style-focused UiRingOn.TFrame while-editing UiRingOn.TFrame editor Text")
        echo "OK: the ring is the box's, and an editor inside it does not put it out" ;;
    *) fail "FAIL: ring: $RING" ;;
esac
if [ "$GUARD" = "clean 1 gone 1 dirty 0 kept 1" ]; then
    echo "OK: an untouched field goes on a scroll; a typed one holds the tree still"
else
    fail "FAIL: editing guard: $GUARD"
fi
case "$PROBVIEW|$PROBGONE" in
    "up 1 rows 1 first {key Super+9 — the script says no} detail {the script says no||said at /home/x/tk9wm.tcl:3 ← /home/x/tk9wm.tcl:5}|0")
        echo "OK: a failure is listed whole, with the lines that led to it" ;;
    *) fail "FAIL: problems view: {$PROBVIEW} left=$PROBGONE" ;;
esac
case "$SLOTROWS|$SLOTROWS2" in
    "p-run 0 p-launch 1 d-run 0 d-launch 1|p-run 0 p-launch 1")
        echo "OK: the slot wears its face — a written run stands as launch" ;;
    *) fail "FAIL: slot rows: «$SLOTROWS» then «$SLOTROWS2»" ;;
esac
case $FACEVAL in
    "val {Run xclock} cell {Run xclock} seed {Run xclock}")
        echo "OK: the face row shows the derived launch and seeds the editor with it" ;;
    *) fail "FAIL: the face row: $FACEVAL" ;;
esac
case $FACESAID in
    "launch {Run xclock -digital}")
        echo "OK: writing the face un-says the run beneath it in the same word" ;;
    *) fail "FAIL: after writing the face: $FACESAID" ;;
esac
case $ICONROW in
    "img 1 doc "*"probe-icon.png missdoc {no no-such-icon-xyzzy.png"*" missimg 1")
        echo "OK: the icon row shows the picture it found, and names the miss" ;;
    *) fail "FAIL: the icon row: $ICONROW" ;;
esac
case $EXAMPLES in
    "pick cfg-examples-dialog n 2 seed {<Super>t r f} cur <Super>F8")
        echo "OK: the examples dialog seeds the entry, and the bent words commit" ;;
    *) fail "FAIL: the examples dialog: $EXAMPLES" ;;
esac
case $CROSS in
    "plain {xclock -update 1} subst {} other {} two {}")
        echo "OK: only one Run of literal words may cross to a command" ;;
    *) fail "FAIL: crossing: $CROSS" ;;
esac
case $SWITCHED in
    "said {icon Q launch {Run xclock}} fires Run")
        echo "OK: the switch un-said one spelling and said the other" ;;
    *) fail "FAIL: after the switch: $SWITCHED" ;;
esac
case "$AREMOVED|$AGHOST" in
    "gone 1 word 1|removed by you"*)
        echo "OK: the config's deed can be removed, and the removal says so" ;;
    *) fail "FAIL: removal: {$AREMOVED} ghost «$AGHOST»" ;;
esac
case $ABACK in
    "back 1 word 0")
        echo "OK: Delete on the removal took it back and the deed returned" ;;
    *) fail "FAIL: after undoing the removal: $ABACK" ;;
esac
case "$AINS|$ADEL" in
    "1|0") echo "OK: Insert declares a fresh action, Delete takes it back" ;;
    *) fail "FAIL: action insert/delete: ins=$AINS del=$ADEL" ;;
esac
echo "--- openfit: $OPENFIT"
OFROWS=$(echo "$OPENFIT" | awk '{print $2}')
OFDONE=$(echo "$OPENFIT" | awk '{print $4}')
OFMAP=$(echo "$OPENFIT" | awk '{print $6}')
OFHAND=$(echo "$OPENFIT" | awk '{print $8}')
if [ "$OFROWS" -ge 10 ] && [ "$OFDONE" = 1 ] && [ "$OFMAP" = 1 ] \
        && [ "$OFHAND" = 0 ]; then
    echo "OK: it opens with room to read, and the walls were closed on screen"
else
    fail "FAIL: the first fit: $OPENFIT"
fi
echo "--- geometry: $GEO"
case $GEO in
    *"fits 1") echo "OK: the applet window sits inside the workarea" ;;
    *) fail "FAIL: window vs workarea: $GEO" ;;
esac

check_invariants "$HERE/wm-cfg.log"
if grep -q 'WM: INVARIANT' "$HERE/wm-cfg.log"; then BAD=1; fi
exit $BAD
