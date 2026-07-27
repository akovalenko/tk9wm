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
# `always` is the match-everything builtin. Identity accessors for
# hand-rolled predicates: client-class (→ {instance class}),
# client-machine, client-pid, client-cmdline (argv list, local clients
# only), client-title.
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
# Ignore them only for local xterms started as /usr/bin/xterm:
#   proc my-xterm {w} {
#       expr {[lindex [client-class $w] 1] eq "XTerm"
#             && [lindex [client-cmdline $w] 0] eq "/usr/bin/xterm"}
#   }
#   wm-style my-xterm {increments ignore}
#
# Give those xterms a window-list icon of your choosing (any file
# format Tk's photo reads — png with alpha included):
#   image create photo imgTerm -file /home/me/icons/terminal.png
#   wm-style my-xterm {icon imgTerm}
#
# ---- the panel ----
#
# panel-button LABEL SETTINGS declares a button on the WM's own panel —
# a bottom strip that exists only when buttons are declared, and that
# maximize respects (the workarea ends above it). A button is
# idempotent, wmaker-style: fired — by click or by its chord — it
# FOCUSES the most recently used window its `match` predicate finds,
# else LAUNCHES its `launch` script; the face flashes the verdict
# (green "found it", orange "launching"). Settings keys, all optional:
#   match  — predicate command prefix (same vocabulary as wm-style)
#   launch — any Tcl script, typically {exec ... &}
#   icon   — a Tk image for the button face
#   key    — a wm-bind chord sequence firing this button
#
#   panel-button xterm {
#       match my-xterm launch {exec xterm &} key {<Super>x}
#   }
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
