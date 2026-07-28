# tk9wm default config — an ANNOTATED EXAMPLE, not a preset carrier.
#
# This file is sourced only when ~/.config/tk9wm.tcl (XDG_CONFIG_HOME
# honored) does not exist, and it deliberately does nothing: every
# default lives in the WM's code, so an empty — or absent — config is
# already the stock behavior. Copy nothing; create your own file with
# just the lines you mean. The config is plain Tcl, sourced into the
# WM's interpreter after both layers are loaded, so everything below —
# and any policy/substrate proc — is at your disposal.
#
# ---- global knobs ----
#
# Titlebar font: any Tk font spec or attribute set; the decoration
# heights follow the font's metrics.
#   set-title-font -weight bold
#   set-title-font -family "DejaVu Sans" -size 12
#
# Title alignment in the bar: left (default), center, right.
#   set-title-justify center
#
# ---- per-client style rules ----
#
# wm-style PREDICATE SETTINGS appends a rule. The predicate is any
# command prefix called with the client's X window id; truth applies
# the settings dict. All matching rules apply, later rules win per-key.
# `always` is the match-everything builtin, `filter` the workhorse:
#
#   filter ?-regexp? ?-title PAT? ?-class PAT|{PAT PAT}? \
#       ?-command PAT? ?-machine PAT?
#
# The options AND together; patterns are globs matching the whole
# string, always case-insensitively (-regexp swaps the comparator;
# (?c) inside a pattern turns sensitivity back on). A single -class
# pattern matches either of {instance class}; two patterns are
# positional, exactly as xprop prints them. -command matches
# WM_COMMAND joined with spaces and falls back to the local client's
# /proc argv. An absent property never matches. Identity accessors
# for hand-rolled predicates: client-class (→ {instance class}),
# client-machine, client-command (WM_COMMAND argv list), client-pid,
# client-cmdline (argv list, local clients only), client-title.
#
# Keys so far:
#   increments respect|ignore — WM_NORMAL_HINTS resize increments;
#     default respect (xterm resizes land on whole cells).
#   icon IMAGE — a Tk image (create it right here in the config) shown
#     for the window in the window list; overrides the client's own
#     _NET_WM_ICON. Windows offering neither get a generated badge:
#     one-two letters of the class (or title) on a color hashed from
#     the same name.
#
# Ignore increments for everything:
#   wm-style always {increments ignore}
#
# Ignore them only for xterms, however capitalized:
#   wm-style {filter -class {* xterm}} {increments ignore}
#
# The proc predicate stays the escape hatch for anything richer —
# only local xterms started as /usr/bin/xterm:
#   proc my-xterm {w} {
#       expr {[lindex [client-class $w] 1] eq "XTerm"
#             && [lindex [client-cmdline $w] 0] eq "/usr/bin/xterm"}
#   }
#   wm-style my-xterm {increments ignore}
#
# Give those xterms a window-list icon. The `icon` value is anything
# resolve-icon takes: an existing Tk image name (used as-is), a file
# path (any format Tk's photo reads — png with alpha included; naming
# an .svg by hand is your own choice), or a bare NAME searched as
# NAME.png through the icon-path directories — set-icon-path DIRS,
# default ~/.local/share/icons/hicolor/48x48/apps,
# /usr/share/icons/hicolor/48x48/apps, /usr/share/pixmaps. An
# oversized image is shrunk to fit, alpha intact; a miss logs one
# line and shows the usual no-icon look:
#   wm-style my-xterm {icon terminal}
#   wm-style my-xterm {icon ~/icons/terminal.png}
#
# ---- the panel ----
#
# panel-button LABEL SETTINGS declares a button on the WM's own panel —
# a strip that exists only when buttons are declared, and that
# maximize respects (the workarea ends at it). A button is
# idempotent, wmaker-style: fired — by click or by its chord — it
# FOCUSES the most recently used window its `match` predicate finds,
# else LAUNCHES its `launch` script; the face flashes the verdict
# (green "found it", orange "launching"). Settings keys, all optional:
#   match  — predicate command prefix (same vocabulary as wm-style)
#   launch — any Tcl script, typically {exec ... &}
#   icon   — the button face: anything resolve-icon takes (see the
#            style section above)
#   key    — a wm-bind chord sequence firing this button
#
#   panel-button xterm {
#       match {filter -class xterm} launch {exec xterm &} key {<Super>x}
#   }
#
# The strip's shape. set-panel-side bottom|right picks the screen
# edge (default bottom; right makes it a vertical strip). While no
# button face resolves to an icon the strip is a thin text-chip row;
# the moment any does, every iconless button wears an auto-badge
# (letters of its label on a hashed color) and the strip grows to
# set-panel-icon-size (default 48 — the hicolor stock; a foreign
# image is resampled). set-panel-preset row|stack picks the iconic
# button layout: row is <image> Text (default), stack puts the label
# under the icon — the look for a thick bottom bar or a narrow right
# strip.
#   set-panel-side right
#   set-panel-preset stack
#   set-panel-icon-size 32
#
# ---- key bindings ----
#
# wm-bind SPEC SCRIPT binds a chord sequence, stumpwm-style: only the
# FIRST chord is a global grab; the rest is collected under a temporary
# keyboard grab (Esc or an unbound key aborts). A chord is any number
# of <Mod> prefixes — <Shift> <Ctrl> <Alt> <Super> <Mod1>..<Mod5> —
# and then a keysym name. Later binds win, so binding over a default
# replaces it. In-code defaults: the window ops menu (winops) on
# <Alt>space and <Super>t w m; the window list (winlist) on <Alt>Tab
# and <Super>t w w.
#
#   wm-bind {<Super>Return} {exec xterm &}
#   wm-bind {<Super>t w x}  {exec xterm &}
#
# The window list opened by a chord whose modifier is still held runs
# the fvwm alt-tab cycle: Tab advances with wraparound (Shift+Tab
# backwards), releasing the modifier commits; a quick full Alt+Tab
# toggles to the previous window. Turn the cycle mode off to always
# get a static menu:
#   set-winlist-cycle off
#
# Window list entries are numbered 1-9/A-Z and the number is a hotkey:
# bare in the static menu, together with the held modifier (Alt+3) in
# cycle mode. In every popup menu k/j and p/n move the selection when
# no item hotkey claims the letter; Ctrl+P/Ctrl+N move unconditionally.
