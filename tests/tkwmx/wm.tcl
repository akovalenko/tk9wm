# The rest of the transport a window manager runs on: focus, grabs,
# keyboard, pointer, the manager selection, configure-by-mask and
# restacking. Headless, no window manager needed.
# The shim under test is the one built in THIS tree: ./configure &&
# make leaves libtkwmx.so and its pkgIndex.tcl at the root, three
# directories up. Any Tcl/Tk 9 interpreter can host the battery —
# it needs no window manager and no tk9wm.
lappend ::auto_path [file dirname [file dirname [file dirname \
    [file normalize [info script]]]]]
package require Tk
package require tkwmx

set fail 0
proc ok {what got want} {
    if {$got eq $want} { puts "PASS: $what" } else {
        puts "FAIL: $what — got «$got», want «$want»"; set ::fail 1
    }
}
proc A {n} { tkwmx::atom intern $n }

wm withdraw .
toplevel .t
wm geometry .t 200x120+10+10
update
set id [winfo id .t]
set wrap [lindex [tkwmx::window tree $id] 1]
set root [lindex [tkwmx::window tree $id] 0]

# --- focus: set it, then believe the SERVER about it
ok "focus set answers success" [tkwmx::focus set $wrap parent] 1
lassign [tkwmx::focus get] f rev
ok "focus get names the window" $f $wrap
ok "focus get names the revert" $rev parent
tkwmx::focus set pointer-root
ok "focus can be parked on pointer-root" [lindex [tkwmx::focus get] 0] 1

# --- keyboard: names, codes, the physical truth
set ks [tkwmx::keyboard keysym Tab]
ok "keysym by name"        [expr {$ks != 0}] 1
ok "and back to the name"  [tkwmx::keyboard name $ks] Tab
ok "keysym of an unknown name is 0" [tkwmx::keyboard keysym нетакого] 0
set kc [tkwmx::keyboard keycode $ks]
ok "keycode for it"        [expr {$kc > 0}] 1
ok "and the keysym at that code" [tkwmx::keyboard at $kc] $ks
ok "the keymap is 32 bytes" [string length [tkwmx::keyboard state]] 32
tkwmx::keyboard autorepeat 1

# --- grabs: a chord grab, and the sync button grab click-to-focus needs
tkwmx::grab key $kc 0 $root
tkwmx::grab ungrab-key $kc 0 $root
tkwmx::grab button 1 0x8000 $wrap {button-press}
tkwmx::grab ungrab-button 1 0x8000 $wrap
ok "keyboard grab is granted" [tkwmx::grab keyboard $root] 1
tkwmx::grab ungrab-keyboard
ok "pointer grab is granted"  [tkwmx::grab pointer $root] 1
tkwmx::grab ungrab-pointer
tkwmx::grab allow replay-pointer

# --- pointer
tkwmx::pointer warp $root 42 43
lassign [tkwmx::pointer query $root] rx ry
ok "warp then query agree" [list $rx $ry] {42 43}

# --- the manager selection: how a WM says it is the one here
set sel [A WM_S0]
ok "nobody owns WM_S0 yet" [tkwmx::selection get $sel] 0
ok "and we can take it"    [tkwmx::selection own $sel $wrap] 1
ok "the owner is us"       [tkwmx::selection get $sel] $wrap

# --- configure by mask: only the keys present are applied
tkwmx::window configure $wrap {x 70 width 260}
tkwmx::server sync
lassign [tkwmx::window geometry $wrap] gx gy gw gh
ok "configure moved x and width" [list $gx $gw] {70 260}
ok "and left y and height alone" [list $gy $gh] {10 120}

# --- restack takes a whole order at once
toplevel .u
wm geometry .u 100x100+120+10
update
set wrap2 [lindex [tkwmx::window tree [winfo id .u]] 1]
tkwmx::window restack [list $wrap $wrap2]
tkwmx::server sync
set kids [lindex [tkwmx::window tree $root] 2]
ok "both windows are still on the root" \
    [expr {$wrap in $kids && $wrap2 in $kids}] 1

# --- attributes, read: what adoption tells a manageable window by
set own [tkwmx::window create $root -50 -50 30 20 -override]
set at [tkwmx::window attrs $own]
ok "a fresh window is not viewable yet" [dict get $at map-state] unmapped
ok "and it says it is override-redirect" [dict get $at override-redirect] 1
tkwmx::window map $own
tkwmx::server sync
ok "mapped, it is viewable"      [dict get [tkwmx::window attrs $own] map-state] viewable
ok "geometry comes along"        [list [dict get $at width] [dict get $at height]] {30 20}
ok "a window that is gone answers {}" [tkwmx::window attrs 0x666666] {}

# --- selecting on OUR OWN window ADDS to Tk's mask, never replaces it.
# Tk selects every event it wants once, when it creates the window, and
# never selects again — so a plain XSelectInput here would blind the
# widget for good.
set before [dict get [tkwmx::window attrs $id] your-event-mask]
tkwmx::event select $id {substructure-redirect focus-change}
tkwmx::server sync
set after [dict get [tkwmx::window attrs $id] your-event-mask]
set lost {}
foreach m $before { if {$m ni $after} { lappend lost $m } }
ok "Tk had a mask of its own"            [expr {[llength $before] > 0}] 1
ok "and not a bit of it was lost"        $lost {}
ok "while ours are there now" \
    [expr {"substructure-redirect" in $after && "focus-change" in $after}] 1

# --- a fresh server timestamp, fetched and not guessed
tkwmx::event select $own {property-change}
set stamp [A TKWMX_TIME]
set t1 [tkwmx::server time $own $stamp]
set t2 [tkwmx::server time $own $stamp]
ok "the server names a time"   [expr {$t1 > 0}] 1
ok "and time does not go back" [expr {$t2 >= $t1}] 1

# --- server odds and ends
ok "error text comes from the server" \
    [expr {[string length [tkwmx::server error-text 3]] > 0}] 1
tkwmx::server close-down-mode retain-temporary

# --- backgrounds: the two a tray needs, and the one the server refuses
#
# A raw PIXEL is the point of the numeric form: in a 32-bit visual the
# alpha sits in bits no TrueColor mask covers, so a toolkit that
# computes colors from the masks (Tk does) can only ever ask for alpha
# zero — a window a compositor draws as not there. Handing the pixel in
# whole is how a script paints an opaque ARGB window.
set kid [tkwmx::window create $wrap 0 0 20 20]
ok "a background pixel is accepted" \
    [catch {tkwmx::window attrs $kid {background 0xff2e3436}}] 0
ok "and the window can be repainted from it" \
    [catch {tkwmx::window clear $kid}] 0
ok "clear can ask the client to redraw too" \
    [catch {tkwmx::window clear $kid -exposures}] 0
ok "parent-relative is accepted within one depth" \
    [catch {tkwmx::window attrs $kid {background parent-relative}}] 0
ok "so is none" [catch {tkwmx::window attrs $kid {background none}}] 0
ok "and nonsense is refused" \
    [catch {tkwmx::window attrs $kid {background chartreuse}}] 1
# ...and ACROSS depths the server says no (BadMatch) — which is exactly
# why a tray cannot force the classic cure on an ARGB icon unless its
# own cell is ARGB too. Needs a 32-bit visual; a screen without one
# simply skips the case.
if {"truecolor 32" in [winfo visualsavailable .]} {
    toplevel .t32 -visual "truecolor 32" -colormap new
    wm geometry .t32 40x40+300+300
    update
    set deep [lindex [tkwmx::window tree [winfo id .t32]] 1]
    # a 24-bit window (created under a 24-bit parent, so it inherited
    # that depth) moved under the 32-bit one: reparenting across depths
    # is legal — it is what a tray does to an ARGB icon every day —
    # while ParentRelative across them is not
    set shallow [tkwmx::window create $wrap 0 0 10 10]
    tkwmx::window reparent $shallow $deep 0 0
    tkwmx::server sync 0
    ok "parent-relative across depths is refused, not fatal" \
        [catch {tkwmx::window attrs $shallow {background parent-relative}} m] 1
    ok "and it says why" [string match "*refused*" $m] 1
    ok "the deep window is really 32 bits" \
        [dict get [tkwmx::window attrs $deep] depth] 32
}

# --- a ClientMessage ABOUT one window, delivered to ANOTHER: EWMH is
# full of them (_NET_ACTIVE_WINDOW, _NET_REQUEST_FRAME_EXTENTS, and
# ICCCM's WM_CHANGE_STATE), all naming a client window and all sent to
# the root, where the manager listens.
set ::got {}
tkwmx::event on {apply {{ev} {
    if {[dict get $ev type] eq "client-message"
            && [dict get $ev message-type] == [tkwmx::atom intern TKWMX_PROBE]} {
        set ::got [dict get $ev window]
    }
}}}
tkwmx::event select $root {substructure-notify}
tkwmx::event client $kid [A TKWMX_PROBE] {1 2 3 4 5} 32 \
    {substructure-notify} $root
tkwmx::server sync 0
update
ok "the message arrived at the destination" [expr {$::got != 0}] 1
ok "...naming the window it was ABOUT"      $::got $kid
tkwmx::event on {}

# --- exec-self: only the failure is testable here (the success replaces
# this very process), and failing it must be a plain Tcl error
ok "exec-self refuses what it cannot run" \
    [catch {tkwmx::exec-self /no/such/binary {}}] 1

puts [expr {$fail ? "SOME FAILED" : "ALL PASS"}]
exit $fail
