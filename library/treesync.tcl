# treesync — keyed rows onto a treectrl's items.
#
# The one idea: a widget's items are a PROJECTION of a model list,
# and the projection is reconciled, never rebuilt. An item whose key
# survives is UPDATED in place and moved when its position changed;
# what vanished dies; what appeared is made. Everything that lives
# ON an item — the selection, the open flag, user-defined states, a
# timer somebody aimed at it — rides along for free, and that is the
# whole point: a wholesale rebuild is a correctness cliff for every
# holder of an item id, and each holder used to need its own
# save-and-restore dance around it.
#
# Deliberately a LIBRARY with no upstairs knowledge (the owner's
# word, 2026-07-31): the WM's panel strip, the configurator's tree,
# any future mini-app in the ui host — one engine, their own
# callbacks. The engine knows keys, items and order; what a row
# LOOKS like is entirely the view's business.
#
#   treesync::sync T view rows ?parent?
#     rows    ordered list of {key data}: key is the row's semantic
#             descriptor — an action's name, a {collection key}
#             pair — unique under this parent; data is opaque and
#             handed to the callbacks whole.
#     view    dict of callbacks:
#               make   {T parent key data} -> item   create + dress
#                      a fresh item; the engine attaches and
#                      positions it, so make does neither
#               update {T item key data}             re-dress a
#                      surviving item (style set + element
#                      configure are cheap when nothing changed)
#               drop   {T item key}        optional  last words
#                      before a vanished row's item is deleted
#     parent  the subtree these rows are the children of (default:
#             root item 0) — a hierarchy syncs level by level, each
#             level under its own parent.
#     Returns the key -> item dict for this (T, parent): the map a
#     caller flashes, selects and re-judges through, instead of any
#     arithmetic about positions.
#
#   treesync::forget T ?parent?
#     Drop the stored map(s) — for the caller who rebuilt the tree
#     WHOLESALE (its styles changed shape, every item died with it)
#     and wants the next sync to start from nothing. A dying widget
#     forgets itself: the engine binds <Destroy> on first meeting.
namespace eval treesync {
    variable map {}      ;# {T parent} -> {key -> item}
    variable bound {}    ;# T -> 1 once its <Destroy> is armed
}
proc treesync::sync {T view rows {parent 0}} {
    variable map
    variable bound
    if {![dict exists $bound $T]} {
        dict set bound $T 1
        bind $T <Destroy> +[list treesync::forget $T]
    }
    set slot [list $T $parent]
    set old [expr {[dict exists $map $slot] ? [dict get $map $slot] : {}}]
    # The dead go first — their keys may be reborn as new rows below,
    # and a key must never point at two items even mid-sync.
    set live {}
    foreach row $rows { dict set live [lindex $row 0] 1 }
    dict for {key item} $old {
        if {![dict exists $live $key]} {
            if {[dict exists $view drop]} {
                uplevel #0 [list {*}[dict get $view drop] $T $item $key]
            }
            $T item delete $item
            dict unset old $key
        }
    }
    # The living, in row order: update or make, then put each in its
    # place — moved ONLY when out of place, so an untouched tail is
    # not churned (treectrl moves an attached item and attaches an
    # orphan with the same sibling commands).
    set new {}
    set prev ""
    foreach row $rows {
        lassign $row key data
        if {[dict exists $old $key]} {
            set item [dict get $old $key]
            uplevel #0 [list {*}[dict get $view update] $T $item $key $data]
        } else {
            set item [uplevel #0 \
                          [list {*}[dict get $view make] $T $parent $key $data]]
        }
        if {$prev eq ""} {
            if {[$T item firstchild $parent] ne $item} {
                $T item firstchild $parent $item
            }
        } elseif {[$T item nextsibling $prev] ne $item} {
            $T item nextsibling $prev $item
        }
        dict set new $key $item
        set prev $item
    }
    dict set map $slot $new
    return $new
}
proc treesync::forget {T {parent ""}} {
    variable map
    variable bound
    if {$parent eq ""} {
        dict for {slot -} $map {
            if {[lindex $slot 0] eq $T} { dict unset map $slot }
        }
        dict unset bound $T
    } else {
        dict unset map [list $T $parent]
    }
}
