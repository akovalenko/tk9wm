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
# Minimize (ICCCM iconification — what a client asks for with
# WM_CHANGE_STATE: Tk's `wm iconify`, wine's Win32 SW_MINIMIZE, the
# winops menu's own entry):
#   iconify (default) — honor it. The window leaves the screen, keeps
#     its place in the window list with its title in [brackets], and
#     comes back when picked there, when a panel button matching it is
#     fired, or when the client maps itself again.
#   refuse — this desk has no minimize. The request is DECLINED to the
#     client's face (WM_STATE re-stated as NormalState), not ignored:
#     an app that already minimized itself internally — wine does — is
#     told to come back, instead of leaving a window on screen whose
#     owner thinks it is hidden and stops painting it.
#   set-minimize refuse
# Per client, the `minimize` style key wins over that default — see the
# style section below. The one case it exists for so far is wine: a
# wine window that goes through a real iconify round trip comes back
# activated but with its INNER focus lost, so keystrokes land on the
# top-level window (they work menu mnemonics and never reach the text
# field). Measured to reproduce under fvwm3 as well, so it is wine's
# defect, not the WM's — until it is fixed, refusing minimize for wine
# windows beats handing back a half-dead one:
#   wm-style {filter -class {*.exe *.exe}} {minimize refuse}
#
# Maximize is a SAVED GEOMETRY and not a straitjacket: a maximized
# window can be moved and resized by hand like any other, and the
# toggle puts back what was saved when it was maximized. What a hand
# resize should do to that mark has two honest answers, and this picks
# between them:
#   keep (default) — fvwm's. The mark survives; the toggle restores the
#     pre-maximize geometry however the window has been pulled about.
#   drop — the Windows/GNOME reading. A hand resize means this is no
#     longer the maximized window, so the mark goes and the next toggle
#     MAXIMIZES instead of restoring.
#   set-maximize drop
# Both interactive resizes obey it — the border/corner drag and the
# keyboard mode alike. Moving a maximized window changes nothing under
# either answer.
#
# The mouse gesture that carries a window from ANYWHERE on it: hold
# the modifier, press, move. Button 1 carries, button 3 resizes from
# the nearest corner — and for a window styled `decor none` (below)
# that gesture is the only mouse handle there is. <Super> by default,
# because <Alt> is spoken for inside too many applications; any
# modifier combination the key binder understands works.
#   set-drag-modifier {<Alt>}
#   set-drag-modifier {<Ctrl><Alt>}
#
# The cursor over the desk itself. An X server leaves the root window
# wearing the ancient X_cursor until somebody sets it, and that
# somebody is conventionally the WM — so we do, and xsetroot is one
# fewer line in your session script. Any Tk cursor name; the empty
# string means hands off, keep whatever is there.
#   set-root-cursor left_ptr        ;# the default
#   set-root-cursor {}
#
# ---- per-client style rules ----
#
# wm-style PREDICATE SETTINGS appends a rule. The predicate is any
# command prefix called with the client's X window id; truth applies
# the settings dict. All matching rules apply, later rules win per-key.
# `always` is the match-everything builtin, `filter` the workhorse:
#
#   filter ?-nocase? ?-regexp? ?-title PAT? ?-class PAT|{PAT PAT}? \
#       ?-command PAT? ?-machine PAT?
#
# The options AND together; patterns are globs matching the whole
# string, case-sensitively — -nocase relaxes that for the whole call,
# -regexp swaps the comparator (unanchored; (?i) inside a pattern is
# nocase for that pattern alone). Case matters by default because
# WM_CLASS uses it to tell things apart: an xterm is {xterm XTerm},
# and one started as `xterm -name ninja` is {ninja XTerm} — nocase,
# `-class xterm` would claim that one too. A single -class pattern
# matches either of {instance class}; two patterns are positional,
# exactly as xprop prints them. -command matches WM_COMMAND joined
# with spaces and falls back to the local client's /proc argv. An
# absent property never matches. Identity accessors for hand-rolled
# predicates: client-class (→ {instance class}), client-machine,
# client-command (WM_COMMAND argv list), client-pid, client-cmdline
# (argv list, local clients only), client-title.
#
# Keys so far:
#   increments respect|ignore — WM_NORMAL_HINTS resize increments;
#     default respect (xterm resizes land on whole cells).
#   minimize iconify|refuse — this client's answer to an iconify
#     request, overriding the desk-wide set-minimize (above).
#   decor full|border|none — how much frame this window wears. full
#     (default) is the titlebar and the border; border keeps the border
#     and its resize grips but drops the title strip — no name, no
#     buttons, and no bar to drag; none is nothing at all, the frame
#     exactly the size of the client. Mind what `none` costs: with no
#     border and no titlebar, the mouse has nothing to grab — move and
#     resize such a window from the keyboard (winops, <Alt>space).
#     A config RELOAD re-decides this for windows already on screen.
#   place TERMS — the geometry the window is BORN with; see the
#     placement section below.
#   icon IMAGE — a Tk image (create it right here in the config) shown
#     for the window in the window list; overrides the client's own
#     _NET_WM_ICON. Windows offering neither get a generated badge:
#     one-two letters of the class (or title) on a color hashed from
#     the same name.
#
# Ignore increments for everything:
#   wm-style always {increments ignore}
#
# Ignore them only for windows of class XTerm, whatever instance name
# they were started under:
#   wm-style {filter -class {* XTerm}} {increments ignore}
# ...and the same tolerant of capitalization drift:
#   wm-style {filter -nocase -class {* xterm}} {increments ignore}
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
# ---- where a window opens: the `place` key ----
#
# A list of terms, comma or whitespace separated — "30%bottom,50%right"
# and {30%bottom 50%right} are the same thing.
#
#   term = [SIZE]EDGE
#   SIZE = N%   — of the WORKAREA (the panel and the tray are never
#          covered), and of the FRAME: what you see is the half you
#          asked for, decoration included
#   EDGE = left|right|hcenter  (horizontal)
#          top|bottom|vcenter  (vertical)
#          center              = hcenter vcenter
#
# The edge picks the axis as well as the alignment. A term WITH a size
# sets both the size and the alignment on its axis; a term WITHOUT one
# keeps the window's own size and only pins it. Two terms on one axis:
# the later wins.
#
# An axis NO term claims is FILLED. That is what makes 50%right the
# right half at full height — and its flip side is worth knowing before
# it surprises: a lone `place right` is full height at the right edge,
# while "pin it, leave the size alone" takes a term per axis.
#
#   wm-style {filter -class Emacs}   {place max}
#   wm-style {filter -title "*mutt*"} {place 50%right}
#   wm-style my-monitor {place {30%bottom 50%right}}   ;# lower right
#   wm-style {filter -class {* XClock}} {place {right bottom}}
#
# `max` is the whole workarea, spelled the way one thinks of it (the
# same grammar's {100%left 100%top}). It also behaves like the
# maximized STATE and not just a size: the titlebar's maximize button
# restores such a window to the size it asked for, at the place the
# ordinary cascade would have put it.
#
# Size increments bind a placement the way they bind maximize: an xterm
# placed 50%right keeps its right edge flush and eats the leftover on
# the left. Percentages are of the whole X screen's workarea — on two
# monitors, 50%right is half of the JOINED desktop.
#
# A `place` beats every position the client claims for itself, its own
# -geometry included: the config is the same user saying it once and
# for all. A term that cannot be read is logged and dropped, and the
# window opens where it otherwise would have.
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
# The strip's shape. set-panel-side top|bottom|left|right picks the
# screen edge (default bottom; left and right make it a vertical
# strip). While no button face resolves to an icon the strip is a thin
# text-chip row; the moment any does, every iconless button wears an
# auto-badge (letters of its label on a hashed color) and the strip
# grows to set-panel-icon-size (default 48 — the hicolor stock; a
# foreign image is resampled). set-panel-preset row|stack picks the
# iconic button layout: row is <image> Text (default), stack puts the
# label under the icon — the look for a thick bottom bar or a narrow
# side strip.
#   set-panel-side left
#   set-panel-preset stack
#   set-panel-icon-size 32
#
# ---- more than one panel ----
#
# A panel is an instance with a name, and `panel NAME BODY` declares
# one: inside the block the commands above speak about THAT panel,
# outside it they speak about the one named `default` — so a config
# that never mentions a name keeps working exactly as it did.
#
#   panel dock {                       ;# a dock down the left edge
#       set-panel-side left
#       set-panel-preset stack
#       panel-button терм {icon xterm launch {exec xterm &}}
#   }
#   set-panel-side bottom              ;# ...and the default one below
#   panel-button emacs {match {filter -class Emacs}}
#
# Each panel keeps its own side, preset, icon size and buttons. What
# they share is the SCREEN, and they divide it in DECLARATION ORDER:
# each strip reserves a band across its edge out of what the strips
# before it left over, and what survives is the workarea (maximize and
# new windows stop there). So the corner between two edges belongs to
# whichever panel was declared first — write them in the order you
# want the corners to fall.
#
# A button whose match sees a LIVE window says so: an indicator bar
# along its bottom edge and a light face tint (recolor with
# set-panel-live-colors BAR FACE). Every button reserves an arrow
# strip inside its east edge (the moment any button carries a
# match); with more than one match the strip draws a separator line
# and the arrow, and the WHOLE strip is the click target — clicking
# drops the window list filtered to the matches (most recent first,
# numbered), picking focuses; a body click keeps the idempotent
# fire on the most recent match. The judgement follows windows
# coming, going and renaming themselves.
#
# ---- re-reading this file without restarting ----
#
# Super+t w r (or `whale-cli send-reload.tcl`) re-reads the config on
# the live desk: no restart, no client disturbed — windows, frames and
# focus stay exactly as they are. What happens is that everything
# configurable goes back to the CODE's defaults first — empty panel, no
# tray, stock fonts, stock bindings — and this file is then sourced on
# that clean floor, exactly as at startup.
#
# That is worth one rule: KEEP THIS FILE DECLARATIVE. Calling the set-*
# knobs, declaring panel buttons, style rules and key binds is all
# undoable — the reset knows where that state lives. Redefining a
# policy or substrate proc is not: nothing remembers what the proc used
# to be, so the patch would survive the reset and the next reload would
# build on top of it. Procs you define for your own use (predicates,
# launchers) are fine — they are just names, and this file redefines
# them every time it is read.
#
# A broken config leaves the desk on the defaults plus whatever it
# managed to set before it threw. The reset happening FIRST is what
# makes that predictable.
#
# ---- the system tray ----
#
# set-tray on makes this WM the display's tray manager (freedesktop's
# System Tray Protocol on XEMBED): docked icons appear as square cells
# at the FAR end of its panel's band — the right end of a horizontal
# bar, the bottom end of a vertical one — and the strip carves the
# workarea the way the panel does, with or without buttons. A display
# that already has a tray keeps it: we claim the selection only when
# nobody holds it, and hand the icons back if somebody takes it later.
#   set-tray on
#
# With more than one panel, set-tray-panel says whose bar the tray is
# part of (default: `default`) — that decides its edge, its
# orientation and the band it shares.
#   set-tray-panel dock
#
# The cell's BACKGROUND is what shows through the transparent parts of
# an icon (we do not advertise an ARGB visual — see the README for
# why a child window's alpha is nobody's to blend), so this is the
# knob that decides whether a round icon sits on the strip's color or
# on something else. The size is the cell's side in pixels.
#   set-tray-background #2e3436
#   set-tray-icon-size 24
#
# For clients that draw their icon with alpha whether or not anybody
# offered them a visual (Chrome does), there is set-tray-argb: the
# strip becomes a 32-bit top-level, the visual is advertised, and an
# opaque backdrop is put under the strip so the transparent parts of an
# icon show the tray's color instead of punching a hole through to the
# desk. It needs a COMPOSITOR running — without one nothing blends and
# the offer only makes things worse — so it is off by default. Set it
# before turning the tray on (changing it later rebuilds the tray).
#   set-tray-argb on
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

# ---- window commands ----
#
# Everything else in this file is lowercase and DESCRIBES a desk. A
# command is Capitalized, and DOES something the moment it runs:
#
#   Minimize  Maximize  Fullscreen  Move  Resize
#   Raise     Lower     Bury        Close Destroy
#   Unmaximize  Unfullscreen
#
# These are the winops menu's entries, available by name. Bind one and
# it acts on the ACTIVE window — it works out from context which window
# is meant, so the binding never has to name one:
#
#   wm-bind {<Ctrl><Shift>z} Minimize
#   wm-bind {<Super>Up}      Maximize
#
# A USER TOGGLES, A PROGRAM DOES NOT — Emacs's called-interactively-p,
# and here for the same reason. Pick Maximize off the menu over a
# maximized window and you plainly mean "the other way"; press your own
# key twice and you mean the same. But `Apply-To-Matching always
# Maximize` means make this desk maximized, and a toggle there would
# un-maximize exactly the windows that were already right. So Maximize
# and Fullscreen toggle when you ask and force when a sweep does.
# Unmaximize and Unfullscreen never guess, in either mouth.
#
# (The case is not decoration: `raise`, `lower`, `close` and `destroy`
# belong to Tcl and Tk, and taking those names would break the toolkit
# this window manager is drawn with. Raise is ours; raise is still
# Tk's.)
#
# Apply-To-Matching PREDICATE COMMAND runs one over every window the
# predicate accepts — the same predicates the style rules and a panel
# button's `match` take. This is "minimize everything", and it is not
# bound by default because a desk-wide sweep is not something to
# discover by accident:
#
#   wm-bind {<Super>d} {Apply-To-Matching always Minimize}
#
# It takes as many windows as will go: a client whose style refuses
# minimization stays up and does not stop the sweep, and a window that
# closes underneath it is simply skipped. Any predicate works, so the
# sweep can be narrow:
#
#   wm-bind {<Super>c} {Apply-To-Matching {filter -class Chromium} Close}
#
# Two commands are about the DESK rather than a window:
#
#   Restart   restart in place — same pid, fresh code off the disk,
#             clients released and adopted back
#   Reload    re-read this file on the live desk (also <Super>t w r)
#   Quit      leave: it ASKS FIRST (a decorated confirmation of the
#             WM's own, keyboard-first — y/n, Left/Right or Tab to
#             move, Return for the highlighted one, Escape to stay;
#             Cancel starts selected). Confirmed, every client is
#             RELEASED back to the root alive rather than closed —
#             but that is all the WM can promise: a .Xsession that
#             ends with the window manager (exec wm, or wm & wait)
#             ends the whole session when it goes, and the question
#             says so. Bound by default to <Super>t q — a desk you
#             can only leave by finding another terminal and killing
#             yourself is not a desk.
#
# Their lowercase originals, restart-wm and reload-config, still work:
# they are the implementations, the way close-client is what Close
# calls, so an older config needs no editing.
