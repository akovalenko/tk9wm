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
# THE DESK FONT is the one this window manager is set in, and
# everything else descends from it. Any Tk font spec or attribute set;
# the decoration heights follow its metrics.
#   set-desk-font -family "DejaVu Sans" -size 12
#
# A derivation is a base plus a delta, and a size may be a FACTOR of
# the base's — which is the part Tk cannot do, and the part that keeps
# a desk in proportion when its font changes:
#   wm-font PanelFont -size 11 -weight normal    ;# the panel, stated flat
#   wm-font PanelFont -size 0.85x                ;# ...or relative, and it lasts
#   wm-font ClockFont -size 1.6x -weight bold    ;# what the clock widget uses
# In code: TitleFont (the titlebar) and PanelFont (the strip), both the
# desk font unchanged until a line like the above says otherwise; a
# widget declares its own. `-from` picks another base than DeskFont.
# The declaration order is the derivation order.
#
# The titlebar alone, which is the same thing aimed at one font:
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
# Maximize is a SAVED GEOMETRY and not a state the client is held in: a
# maximized window can be moved and resized by hand like any other. What
# a hand resize should do to that mark has two honest answers, and this
# picks between them:
#   drop (default) — fvwm3's own, measured. A hand resize means this is
#     no longer the maximized window: the mark goes, the next toggle
#     MAXIMIZES instead of restoring (a window pulled bigger too), and it
#     saves the hand-set geometry, so the toggle after that comes back to
#     what the hand made.
#   keep — the mark survives; the toggle restores the pre-maximize
#     geometry however the window has been pulled about since.
#   set-maximize keep
# Both interactive resizes obey it — the border/corner drag and the
# keyboard mode alike. Moving a maximized window changes nothing under
# either answer.
#
# When the WORKAREA moves — this config changing the panel's side or
# height on a reload, a tray icon widening the band, the screen resized
# under everything — the windows follow it: what spans an axis of the old
# workarea spans the new one (so what looks maximized goes to the new
# maximization), what was flush against an edge is flush against that
# edge of the new rect, and what was flush with nothing stays where it
# is. `max` narrows that to windows that look maximized and nothing else;
# `off` leaves every window exactly where it was.
#   set-workarea-follow max
#   set-workarea-follow off
#
# ---- virtual desks ----
#
# Several independent sets of windows on one screen — fvwm's Desks. One
# knob, and it is a COUNT: one desk (the default) means the mechanism is
# off, and nothing about the desk changes.
#   set-desks 4
#
# Switching is VISIBILITY and nothing else: the windows of other desks
# leave the screen, keep their geometry, and are NOT told they were
# minimized (their WM_STATE stays Normal), so a client that paints by
# its state — emacs, telega — goes on painting. What is off the screen
# is off the screen; there is no pager and none is wanted, since the
# window list says where everything is.
#
# The keys come with the `desks` bundle (above): Super+N goes to a
# desk, Super+Shift+N sends the focused window there without following
# it. Reaching a window ACROSS desks — a panel button, a row of the
# window list — takes you to its desk, because that is what reaching a
# window means.
#
# Per window, in a style rule:
#   wm-style {filter -class Telegram} {desk 2}       ;# born there
#   wm-style {filter -title Таймер}   {desk sticky}  ;# on every desk
# ...and by hand: the window command `Sticky` toggles it.
#
# Two window lists, and they are two commands — bind whichever you
# want where:
#   winlist       this desk only; what Alt+Tab cycles through
#   winlist-all   every window there is, each foreign one marked with
#                 its desk; picking one goes there
#
# Pages — fvwm's other half, a viewport scrolling over one big virtual
# screen — are deliberately NOT here. Desks are visibility; pages are a
# coordinate system, and every clamp, maximize and placement decision
# would have to subtract a viewport origin.
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
# A press on the TITLEBAR is a click until the pointer has travelled
# this far — so aiming at a titlebar to raise or focus a window does
# not nudge it a pixel on the way. The cursor says which it is: the
# ordinary pointer while it is still a click, the carrying fleur from
# the moment it becomes a drag. 0 carries from the first pixel; the
# modifier gesture above has no slop and wants none, holding a modifier
# before pressing not being something one does by accident.
#   set-drag-slop 0
#
# Edge resistance: a carried window sticks to an edge of the WORKAREA
# within this many pixels, and it takes that much more pointer travel
# to get past. Flush against a strip is the position one is usually
# aiming for. 0 switches it off.
#   set-edge-resist 20
#
# The cursor over the desk itself. An X server leaves the root window
# wearing the ancient X_cursor until somebody sets it, and that
# somebody is conventionally the WM — so we do, and xsetroot is one
# fewer line in your session script. Any Tk cursor name; the empty
# string means hands off, keep whatever is there.
#   set-root-cursor left_ptr        ;# the default
#   set-root-cursor {}
#
# ---- the titlebar: buttons, and what they do ----
#
# Three different kinds of decision, kept apart. What a titlebar IS —
# its height, its grips, how a press becomes a gesture — is the WM's
# and has no knobs here. The other two are these:
#
# WHICH BUTTONS EXIST, and what they look like. Order within a side is
# declaration order, left to right; the stock set is menu on the left,
# then minimize, maximize and close on the right. The glyph is svg, so
# it is re-rendered crisp at whatever size the titlebar font dictates.
#
#   titlebar-button shade -side left -glyph {<svg
#    xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path
#    d="M3.5 4 L12.5 4" stroke="#ffffff" stroke-width="1.6"
#    stroke-linecap="round" fill="none"/></svg>}
#
# WHAT A GESTURE DOES. The part is a button's name or `title` for the
# strip itself; the gesture is <1>, <2>, <3> or <Double-1>; and the
# command is a command prefix the window is appended to — which is why
# the window commands (Capitalized, they take an optional window) fit
# it exactly. A button fires on release-inside, classic button
# semantics, so a drag away cancels; a gesture on the strip fires on
# the press. Button 1 on the strip carries the window and cannot be
# rebound.
#
#   titlebar-bind shade <1>        Lower
#   titlebar-bind title <Double-1> Maximize      ;# the default
#   titlebar-bind title <3>        winops        ;# the default
#
# A gesture that opens a MENU opens it under the hand — the pointer's
# x, dropping out of the bottom of the strip — and because a strip
# gesture fires on the press, the menu is up while the button is still
# down: hold it, drag onto an entry and release, and that entry fires.
# Release without going into the menu and it stays standing, to be used
# by hand or by keyboard; go in and come out again and it is dismissed.
# By key (<Alt>space) there is no hand, and the menu keeps the window's
# own top-left corner.
#
# The sharp one, deliberately NOT a default — a slip of the right
# button on the close box kills the client without letting it save
# anything:
#   titlebar-bind close <3> Destroy
#
# A window whose style refuses minimize is not given the minimize
# button: a button whose only answer is "no" is worse than none.
#
# ---- fade: how solid a window is ----
#
# A frame can be made translucent, frame and client together, and it
# happens ON THE FLY — the opacity is one property a COMPOSITOR reads,
# so nothing is unmapped, remapped or recreated. With no compositor
# running nobody reads it and nothing fades; that half is not the WM's.
#
# `Fade` toggles a window between solid and this much, `Unfade` is the
# unconditional way back (a sweep wants the pair, and a user toggling
# is not a program sweeping):
#   set-fade 0.75
#   wm-bind {<Super>minus} Fade
#   wm-bind {<Super>equal} Unfade
#
# A style rule makes a client rest translucent from the moment it maps,
# which is also where Unfade returns it to:
#   wm-style {filter -class {* Conky}} {opacity 0.4}
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
#   opacity N — how solid this client rests, 0 exclusive to 1. Needs a
#     compositor to be visible; see the fade section above.
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
# A place YIELDS to a window that asks for its own geometry — `xterm
# -geometry 20x20`, a session restoring where it was left. A rule is
# the user speaking in general; a -geometry is the same user speaking
# about THIS window, and the particular wins.
#
# It yields ASPECT BY ASPECT, because -geometry is two claims and X
# flags them separately:
#   the window said HOW BIG (USSize) — the rule's sizes drop and its
#     terms go sizeless: it may still pull the window to the edge it
#     names, at the size that was asked for;
#   the window said WHERE (USPosition) — the rule's position drops; it
#     may still say how big;
#   both — the rule has nothing left to say.
# Only the US forms. The P forms are the program's own idea, which it
# has for every window whether it thought about it or not, and are not
# a user's word.
#
# Add `force` to the spec for a rule that means it anyway:
#   wm-style {filter -class Emacs} {place {max force}}
#
# `max` is the whole workarea, spelled the way one thinks of it (the
# same grammar's {100%left 100%top}). It also behaves like the
# maximized STATE and not just a size: the titlebar's maximize button
# restores such a window to the size it asked for, at the place the
# ordinary cascade would have put it.
#
# Size increments bind a placement the way they bind maximize: an xterm
# placed 50%right keeps its right edge flush and eats the leftover on
# the left. Percentages are of ONE monitor's workarea — the primary,
# where placement rules deal their windows; never of the joined
# bounding box of a multihead desk. Maximize later, on whatever
# monitor the window has been carried to, fills THAT monitor.
#
# A `place` beats every position the client claims for itself, its own
# -geometry included: the config is the same user saying it once and
# for all. A term that cannot be read is logged and dropped, and the
# window opens where it otherwise would have.
#
# ---- actions: named deeds ----
#
# action NAME SETTINGS declares a named thing this desk can do —
# idempotent, wmaker-style: fired (by its chord, or from a panel
# button referencing it) it FOCUSES the most recently used window its
# `match` predicate finds, else RUNS its command. Settings keys, all
# optional:
#   run    — the command as RAW ARGV, no exec wrapping: {firefox
#            --new-window}. One spelling whether it runs bare or
#            inside a terminal — SUGAR for `launch {Run firefox
#            --new-window}` and nothing besides, so everything said
#            about Run below is said about run too
#   match  — predicate command prefix (same vocabulary as wm-style);
#            without one the action is a plain launcher
#   icon   — a face, for whatever panel may some day carry it:
#            anything resolve-icon takes (see the style section)
#   key    — a wm-bind chord sequence firing the action BY NAME —
#            live whether or not any panel shows it
#   needs  — commands this action refuses to run without (below)
#   env    — a VAR VALUE dict applied around the launch and put back
#            afterwards; an empty value means VAR= (set empty), not
#            unset
#   style  — a style rule for the windows the match finds, the
#            filter said once instead of twice
#   launch — the general form `run` is sugar for: any Tcl script, run
#            at fire time. Say ONE of the two — both together is an
#            error, and an empty value un-says the one you no longer
#            mean (`run {}`)
#   activate — the other escape, for the found half: a command prefix
#            the found window is appended to, instead of plain focus
#            (the emacs adapter derives one; say your own and it wins)
#   many   — what the CHORD does when the match finds SEVERAL windows:
#            `mru` (the default, and what the desk has always done —
#            the most recently used one) or `choose`, which opens the
#            window list filtered to this deed and asks. The list hangs
#            off the deed's panel button when it has one and stands in
#            the middle of the screen when it has none; it ends in a
#            «run another» row whenever the deed has something to
#            launch. THE CHORD ONLY: a panel button already wears both
#            answers on its face — its body is the most recent window,
#            its arrow is the same chooser — and this word does not
#            take that choice away from the hand on the mouse
#
# A key nobody knows is REFUSED where it is written. There is a table
# of what an action and its adapter words may carry (spec-keys), and
# every declaration is read against it — a mistyped word used to
# declare a deed that quietly did nothing at all.
#
# What the same table only REMARKS on, in the log at the declaration
# and as a mark beside the word in the configurator: a chord this
# desk cannot bind, a `needs` command the machine has not got, and a
# launch saying the long way (`exec … &`) what `Run` says short. One
# of them is louder than the rest — an `exec` with no `&` holds the
# whole desk still until it returns. None of it refuses anything: a
# remark is advice about a declaration that reads fine.
#
# An action the CONFIG declares can be dropped from the layer above
# it — `action-remove NAME` is the word for it, the counterpart of
# wm-unbind for a chord. It keys as the declaration does, so it is
# your last word about that deed and the erasure of it brings the
# deed back.
#
# `Run words…` is how a launch script starts something, and it is
# Capitalized like every other word here that ACTS. It does not read
# its words — no tilde, no expansion: the script is evaluated when
# the deed fires, at the global level like every callback here, so
# Tcl has already substituted and `$env(HOME)` means what it says.
# What the words BECOME is the context's business: bare they are a
# command, and beside a `terminal` word the same line means "start
# this in a terminal" — the script never learns about `xterm -e`.
#
#   action Log {
#       terminal {name log}
#       launch {Run tail -f $env(HOME)/log}
#   }
#
# Two `Run`s in one launch are two launches — under a terminal word,
# two terminals. And a launch script runs in the desk's own event
# loop: `Run` returns at once, but a synchronous `exec` in there
# freezes every window on the screen until it comes back.
#
#   action xterm {
#       match {filter -class xterm} run {xterm} key {<Super>x}
#   }
#   action ff {
#       match {filter -class firefox}
#       run {firefox}
#       env {GTK_IM_MODULE fcitx}
#   }
#
# The NAME is the action's primary key: saying action xterm again
# REFINES it rather than declaring a second one — the keys said now
# merge over what stood, the rest keep. An empty value takes its key
# away ({key {}} = no chord after all).
#
# `needs` gates the whole action on commands existing in PATH — no
# mutt on this machine, no mutt action: it WAITS instead (declared,
# visible in the configurator, not bound, on no strip), and the
# reload after the software lands brings it — and every button
# referencing it — alive by itself.
#
# ---- menus ----
#
# A menu is another surface for actions, the way the panel is: the
# panel lays references out in a strip, `wm-menu NAME {…}` lays them
# out in a transient list under a chord. A row is a reference to an
# action — a bare name, or `{action NAME …}` when it wants a key or a
# label of its own — or a label+do pair for the piece that is
# genuinely this config's:
#
#   wm-menu ssh {
#       key   {<Super>t s}
#       items {
#           {action ssh_web key w}
#           ssh_db
#           {label "log here" do {Run xterm -e tail -f /var/log/syslog}}
#       }
#   }
#
# A row without a key is numbered the winlist way, 1-9 then A-Z, and
# the numbering steps over the letters explicit keys claimed. A row
# referencing a WAITING action is not shown (the panel's rule); one
# referencing a deed nobody declared is skipped with a log line. The
# menu navigates, picks and dismisses exactly as the window list does.
#
# `body` is the dynamic half — a script asked for the rows AT OPEN
# TIME, answering the same grammar; `items` and `body` cannot both be
# said (the run ⊕ launch rule). A list of recent anythings is stale
# the moment it is written down, which is what the body is for:
#
#   wm-menu recent {
#       key  {<Super>t r}
#       body {my-recent-rows}
#   }
#
# ...where my-recent-rows is the config's own proc answering rows like
# {label /home/me/proj do {Run …}}. The name is the primary key and a
# second wm-menu about it REFINES, as an action does; wm-menu-remove
# NAME is the negative word.
#
# `Choose rows…` is the same list as a QUESTION — for the config's own
# scripts: it puts the rows up, waits without freezing the desk, and
# answers the picked row's `value` (its label when no value is said),
# or empty when the person did something else. A row is a bare word or
# `{label L ?value V? ?key K?}`. It waits, so it belongs in a script
# the desk runs — a binding's payload, a launch — not at the top level
# of this file:
#
#   wm-bind {<Super>o} {
#       set which [Choose {alpha {label beta value B key b}}]
#       if {$which ne ""} { Run xmessage $which }
#   }
#
# ---- the panel ----
#
# panel-button NAME declares a button on the WM's own panel — a
# strip that exists only when buttons are declared, and that
# maximize respects (the workarea ends at it). The button is a
# REFERENCE to the action named NAME: a click fires the action, the
# face flashes the verdict (green "found it", orange "launching").
# What the reference may add is how it dresses on THIS panel:
#
#   panel-button ff                      ;# the usual: as itself
#   panel-button ff {label Web icon X}   ;# dressed for this strip
#
# label is display only — the button's key stays the action's name;
# icon covers the action's own face. Everything else — match, run,
# chord, needs — is the action's to say, once, panel or no panel.
# Referencing an action declared LATER in the file (or not declared
# at all yet) is fine: the strip resolves its references after the
# file is read, and a name with no live action simply stands by,
# surfacing on the reload that brings its action alive.
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
#       panel-button терм
#   }
#   set-panel-side bottom              ;# ...and the default one below
#   panel-button emacs
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
# CTRL AND A CLICK — anywhere on the button, body or arrow — starts
# another one instead: the launch half of run-or-raise, whether or not
# a window is already there. It is one gesture for the whole button
# because a modifier answers a different question than a sub-target
# does (which BRANCH, not which half of the picture). The same door
# with a face on it is the «run another» row at the foot of the deed's
# own chooser (see `many` above).
#
# ---- the terminal layer ----
#
# An action that means "the named terminal running mutt" can SAY
# that, without exec-ing any particular emulator:
#
#   action mutt {terminal {name mutt} run {mutt} key {<Super>m}}
#
# The `terminal` key derives both halves of the idempotent action —
# and it answers the action's `Run` (its own, or the one `run` is
# sugar for) by opening the terminal around those words:
# the match — `filter -class mutt`, a single pattern, so either half
# of WM_CLASS answers — and the launch, built for the ACTIVE terminal
# by its adapter (xterm gets `-name mutt -e mutt`, kitty gets
# `--name mutt mutt`, the gnome-terminal factory `--class=mutt -- mutt`
# — its name lives in the class half, which the match takes too). An
# explicit match or launch beside it wins. `terminal {}` is "just a
# terminal": it matches any terminal window the desk knows of,
# whichever beast it is, and launches the active one when none lives.
#
# WHICH terminal is one line, and the beast and the binary are
# separate words — "this is kitty, and it lives over there":
#   set-terminal kitty
#   set-terminal kitty ~/bin/kitty.experimental.git.master
# Known beasts: kitty, alacritty, urxvt, st, xterm, konsole,
# gnome-terminal. Without the line the desk resolves one on its own:
# your $TERMINAL if it names a beast we know; x-terminal-emulator if
# YOU pointed it somewhere (update-alternatives in manual mode — auto
# mode is the packaging talking, not you); else the first beast found,
# best-loved first — kitty, alacritty, urxvt, st, xterm, and the DE
# terminals last. The log says what was picked and on whose word.
#
# The full spec, every key optional — and the COMMAND is not among
# them: it comes from the action's own run/launch, which is the whole
# point of the arrangement (a spec that named a command too would be
# a second place to say the same thing, and the two would disagree):
#   name   the window's name (WM_CLASS instance; on xterm/urxvt also
#          the xrdb branch — mutt*background: darkblue just works)
#   title  the window title (every beast has a word for it)
#   env    environment for the TERMINAL process itself:
#          env {XMODIFIERS {}} cuts uim-xim off an xterm. An empty
#          value means VAR= (set empty), not unset.
#   args   beast-keyed extras, applied VERBATIM when the branch names
#          the active beast (a beast name, a list of them, or *):
#          args {xterm {-bg darkblue} kitty {-o background=darkblue}}
#          This is your terminal's own dialect, said out loud — the WM
#          translates name/title and the command and NOTHING else, so
#          a shared button stays terminal-agnostic with goodies for
#          some.
#
# ...and with `needs` (see the actions section) the whole thing
# waits until mutt exists in PATH — the full declaration, worn by
# the panel with one reference line:
#
#   action mutt {
#       terminal {
#           name mutt
#           args {xterm {-bg darkblue} kitty {-o background=darkblue}}
#       }
#       run {mutt}
#       needs mutt
#       key {<Super>m}
#       icon mutt
#   }
#   panel-button mutt
#
# The launch half stands alone as a command too:
#   wm-bind {<Super>Return} {spawn-terminal {}}
#   wm-bind {<Super>s} {spawn-terminal {name scratch}}
#
# Every beast measured so far can name its windows one way or another
# (gnome-terminal through the class half only). Should one ever not,
# the degradation is honest: the button still launches, the name is
# dropped with a log line, and the match just never fires. A title
# survives even there.
#
# ---- the emacs layer ----
#
# One storey above the terminal: an action that means "the TELEGA
# frame of the telega daemon":
#
#   action telega {
#       emacs {daemon telega frame TELEGA eval (telega)}
#       key {<Super>g}
#   }
#
# The frame name is the identity: emacs puts a frame's name parameter
# into the WM_CLASS instance, so the action's match is the same single
# pattern the terminal layer derives — it finds the GUI frame as
# {TELEGA Emacs} and the named terminal as {TELEGA XTerm} alike. The
# launch ensures the daemon (emacsclient -a '' auto-starts one under
# that socket name), creates the frame named and runs the eval in it:
#
#   emacsclient -s telega -a '' -c \
#       -F '((name . "TELEGA") (tk9wm-frame . "TELEGA"))' -n \
#       --eval '(progn (set-frame-name nil) (telega))'
#
# THE FRAME NAME IS THE DEED'S OWN NAME unless it says otherwise, so
# the shortest emacs button is `action telega {type emacs}` — the deed
# is already called telega and there is no reason to type it twice.
# Say `frame` when the name must differ from the deed's (or when the
# deed's name is not a word X can carry: it becomes a WM_CLASS
# instance). What a nameless button must NOT do is match «any Emacs»:
# X says nothing about which daemon a frame belongs to, so on a desk
# with two servers that would raise whichever frame turned up first.
#
# Keys: `frame` (the identity; unsaid, the deed's own name), `daemon`
# (the -s socket; omit for the default daemon; `none` — see the plain
# life below), `eval`, `via gui|terminal` (this action's answer to the
# question below), `autodaemon on|off`, `keep-frame-name on|off` and
# `env` (all below).
#
# THE NAME IS FOR FINDING THE WINDOW, NOT FOR READING. WM_CLASS is
# written once, when the frame is born, and the name goes on being the
# TITLE — so without a word from us the telega frame says «TELEGA» in
# its titlebar forever, where emacs would have said which buffer one
# is looking at. So the launch hands the title straight back, with a
# (set-frame-name nil) of its own before the button's eval; the desk
# still finds the window by class, and the daemon still finds the
# frame by a parameter of ours that no rename can take away. Wanting
# the button's word to STAND in the title is a knob:
#   set-emacs-keep-frame-name on     ;# desk-wide
#   emacs {frame TELEGA keep-frame-name on}          ;# per action
#
# AUTO-STARTING DAEMONS is a choice. Default on — emacsclient -a ''
# brings the daemon up under the right socket in the same breath —
# but a desk where systemd (or a session script) owns the daemons
# wants a missing one to be an ERROR, not a spawn into whatever
# environment the WM had:
#   set-emacs-autodaemon off
# ...and per action, the `autodaemon` key overrides the desk answer.
# When a daemon IS auto-started, the spec's `env` rides the command
# line (exec env VAR=VAL emacsclient ...), so the daemon inherits it:
#   emacs {daemon telega frame TELEGA eval (telega)
#          env {TELEGA_DATA_DIR /tank/telega}}
#
# NO DAEMONS AT ALL is also a choice — the plain life:
#   set-emacs-daemons off            ;# desk-wide
#   emacs {frame TELEGA daemon none eval (telega)}   ;# per action
# A plain action is lookup-or-run: the same match (emacs puts --name
# into the WM_CLASS instance exactly like xterm), and the launch is
# simply `emacs --name TELEGA --eval (telega)` — in terminal mode,
# `emacs -nw ...` inside the named terminal. The stated price: with
# no server there is no eval-on-hit and no C-x 5 2 repair — a hit
# focuses the window, full stop.
#
# The eval runs in the fresh frame AND on every hit: the frame may
# have wandered off to other work, and the button means "back to
# telega". Wanting it smarter — stay put when the frame is already on
# a telega buffer — is the eval's own decision to make; it runs inside
# the frame and can ask where it is:
#   eval {(unless (derived-mode-p 'telega-root-mode 'telega-chat-mode)
#           (telega))}
#
# WHICH KIND OF FRAME is the desk's default, one line:
#   set-emacs-frames terminal        ;# gui is the default
# In terminal mode the same semantics goes through the terminal layer:
# a terminal named like the frame, running
# emacsclient -t -F '((name . "TELEGA"))' — so the match never changes.
#
# The terminal case is kept honest against C-x 5 2: the user opened
# another frame in that terminal and closed the named one — the
# terminal window still matches, but the frame inside is not the one
# the button means. A hit therefore focuses the window IMMEDIATELY and
# asks the daemon, in the background, to put the named frame back on
# top of its tty — recreating it (and re-running the eval) if it is
# gone and exactly one tty terminal lives to rebuild on. Every branch
# ends in an action or a log line; nothing hangs. Frames wearing names
# from this config are assumed OURS — nothing verifies which terminal
# a tty frame sits in, and naming frames to spoof your own desk is
# your own game.
#
# ---- and the OTHER emacs verb: the edit door ----
#
# «Show me the line that says this» — the configurator's `in emacs`,
# and whatever else comes to want it. A button is an IDENTITY (the
# telega frame, create-or-raise); a door is a DESTINATION, and any
# frame of the right emacs will do. Two knobs, no frame name:
#   set-emacs-edit create           ;# reuse is the default
#   set-emacs-edit-daemon work      ;# unsaid = the default server
# Reuse hands emacsclient -r and lets it pick a frame of that server;
# create says -c. The FILE rides as `+LINE FILE` rather than an eval,
# which is also what makes the frame come to the front: emacsclient
# raises the frame it visits a file in, and does nothing visible for a
# bare --eval.
#
# The server is the whole of the addressing — which is why the door
# needs no name where the buttons want one. An owner keeping telega.el
# in a server of its own can be sure an edit will never land in that
# frame, because it is not that server's business.
#
# In TERMINAL mode (set-emacs-frames terminal) there is no anonymous
# frame to reuse — a terminal window is found by its WM_CLASS instance
# and nothing else — so the desk keeps one editing terminal, named
# `emacs-tk9wm` (with the daemon's name appended when one is said, so
# two servers cannot fight over one window). Reuse raises that window
# and asks the daemon to put the file in the frame inside it; create
# opens a terminal of its own running emacsclient -nw.

# ---- the customization layer ----
#
# Beside this hand-written file there may be a MACHINE-WRITTEN one:
# ~/.config/tk9wm.custom.tcl (XDG honored) — the configurator applet
# and the desk's own buttons write it; nobody edits it by hand, and
# its header says so. It loads AFTER this file, and on overlap the
# click wins: a knob set both here and there takes the customization's
# value, and the desk says so in its log, one line per knob:
#
#   WM: custom overrides the config: set-title-font
#
# So a config line that "stopped working" is never a mystery — the log
# names the shadow, and deleting the customization (or the whole
# custom file) hands the knob back to this file.
#
# THE WELCOME NOTE on the desk links to the configurator, config or
# no config — having written one does not retire it. What retires it
# is its own "hide forever" link (which writes the customization
# set-welcome off — for a fresh user, their first), or the same knob
# said here:
#   set-welcome off

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
# knobs, declaring actions, panel buttons, style rules and key binds is all
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
# WHEN A BINDING'S SCRIPT THROWS the desk says so ON THE SCREEN — the
# echo box, in its failure colour, for long enough to be read rather
# than glanced at — and keeps the whole message in a store the
# configurator can show later. Nothing has to be dismissed: it fades
# on its own, and anything the desk says next replaces it. Turning
# the echo off (`set-key-echo off`) does NOT silence failures: that
# switch is about the desk talking while you type.
#
# ---- key bindings ----
#
# KEYS COME IN FAMILIES, and a family is what one turns on, off or
# MOVES. Two are declared in code and both are on by default:
#
#   chords — the stumpwm-shaped prefix tree (window menu, window
#     list, reload, quit) plus the key that says what is under the
#     prefix you are standing in. Both are parameters:
#       wm-keys chords -prefix {<Super>x} -help {<Super>slash}
#     ...and the whole tree moves, help key and all.
#   windows — the reflexes hands arrive with, reckless on purpose
#     because applications want these chords too: the switcher, the
#     window menu, close, and hide-everything:
#       wm-keys windows -close {<Ctrl><Alt>w} -hide {<Super>m}
#   desks — one press per desk, and the modifier is the parameter:
#       wm-keys desks -mods {<Ctrl><Alt>} -send {<Ctrl><Alt><Shift>}
#     It binds one digit PER DESK, so with one desk (the default) it
#     binds nothing at all and Super+1 stays whoever's it was. Set
#     `set-desks` first and the keys follow the count by themselves.
#     The digits of the NUMPAD are the same keys — a chord on a digit
#     answers to both, so there is nothing to declare twice.
#
# Any of them goes away whole:
#   wm-keys windows off
#   wm-keys chords off        ;# ...and with it the help key
#
# Re-declaring a bundle UNBINDS what its last instance bound, which is
# what makes moving a prefix a move and not a copy — but only what is
# STILL the family's. A chord you have taken for yourself since (a
# plain wm-bind over one of its own) is yours, and the family leaves
# without it: taking one deed out of a family is precisely how one
# keeps it when the family goes (the owner's desk, 2026-08-01, where
# the old behaviour ate three such binds on a toggle).
#
# Every binding remembers WHOSE it is — the code's, a bundle's, this
# file's, the configurator's — and every line of YOURS that led to
# it: a binding written inside a proc of your own remembers both the
# line it is written on and the line that called that proc, which is
# usually the one you are looking for. Binding over somebody else's chord is
# allowed and says so in the log:
#
#   WM: key Super+d: config takes it from bundle windows
#

# wm-bind SPEC SCRIPT binds a chord sequence, stumpwm-style: only the
# FIRST chord is a global grab; the rest is collected under a temporary
# keyboard grab (Esc or an unbound key aborts). A chord is any number
# of <Mod> prefixes — <Shift> <Ctrl> <Alt> <Super> <Mod1>..<Mod5> —
# and then a keysym name (<Control> and <Ctrl> are the same one, as
# are <Alt>/<Meta>/<Mod1> and <Super>/<Mod4>). Later binds win, so
# binding over a default replaces it. In-code defaults: the window ops
# menu (winops) on <Alt>space and <Super>t w m; the window list
# (winlist) on <Alt>Tab and <Super>t w w.
#
# THE SPELLING THE DESK SHOWS ALSO BINDS: the echo and the log write a
# chord as Super+t / Ctrl+h, and wm-bind takes that form too, so a line
# read off the screen can be typed straight back here.
#
#   wm-bind {Super+t Ctrl+j} {Run xterm}      ;# same as {<Super>t <Ctrl>j}
#
# A third argument NAMES the binding for the help list, for when the
# script is not a fit thing to read. Nothing needs it usually — winops,
# Quit or the first words of a Run say enough — and a panel button
# fills it in for you with the button's own label.
#
#   wm-bind {<Super>Return} {Run urxvtc -e tmux new -As0} "a terminal"
#
# A SHIFTED SYMBOL IS SPELLED BY THE KEY IT SITS ON. The lookup asks
# the keymap for group 0 level 0, which is what makes a chord Latin on
# any layout — and it means `?` never arrives as `?`. Bind <Shift>slash
# (or whichever key prints it for you), not `question`.
#
#   wm-bind {<Super>Return} {Run xterm}
#   wm-bind {<Super>t w x}  {Run xterm}
#
# A TOP CHORD IS ALWAYS LIVE: pressed inside a sequence that does not
# bind it, <Super>t starts over instead of failing, and <Alt>space
# still opens the ops menu. So a forgotten half-typed prefix costs
# nothing — press the prefix again. Bind a chord inside a submap and
# THAT wins there, of course.
#
# A running sequence SHOWS itself: a small box says «Super+t …» while
# it waits, and «Super+t z is undefined» for a moment when a press ends
# it. It appears the instant the prefix lands; give it a delay in
# milliseconds and it only shows up when you hesitate (Emacs's
# echo-keystrokes), or switch it off:
#   set-key-echo 400
#   set-key-echo off
#
# Where it sits — the `place` grammar's edge words, sizeless (the box
# is as big as its text), over the workarea; an unnamed axis centers:
#   set-key-echo-place {right top}
#   set-key-echo-place center
#
# WHAT IS UNDER THIS PREFIX — <Super>h inside a sequence lists the keys
# that go on from where you are, in the same box: Emacs's C-h after a
# prefix. The SAME key answers at the TOP level too (a stock binding,
# key-help-open): the whole keymap opens under the usual sequence
# grab, the next press walks from the root — a listed chord can be
# typed straight at the list — and Escape leaves. The welcome note
# links to the same place. The WHOLE subtree, not the next step only (a desk's dozen or
# so bindings fit on the screen, and a long list goes into columns
# rather than off the bottom). It costs nothing globally, being reachable only while a
# sequence holds the keyboard, and it answers even when the echo is
# `off` (that switches off the desk speaking unbidden, not the desk
# answering). Asking does not move the sequence: the next key walks on
# from the same place. A submap that binds this key keeps it.
#   set-key-help {<Ctrl>h}
#   set-key-help off
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

# ---- working ON the window manager ----
#
# `Reread` sources both layers again on the running desk: every proc is
# replaced, and the desk — clients, frames, grabs, the config you had
# loaded — carries on. It is the development loop, not a hot-patch
# facility, and it has an honest edge: a proc that has gone away stays
# until a restart, a variable whose shape changed keeps the old shape,
# and a file with a typo in it leaves that layer half-loaded (it says
# so and does not take the desk down). `Reload` next to it re-reads
# THIS file; `Restart` execs a fresh process in place.
#
#   wm-bind {<Super>t r r} Reread
#
# ---- widgets: the desk's own furniture ----
#
# A clock, and in time whatever else. A widget knows how to fill a
# frame and nothing about where it hangs — that is one option, so the
# same declaration puts it on a panel, in a corner of the workarea, or
# on the desktop under every window:
#
#   wm-widget clock -type clock                    ;# where its TYPE prefers
#   wm-widget clock -type clock -on {panel default} -place {right vcenter}
#   wm-widget clock -type clock -on workarea -place {right top}
#
# -on left UNSAID is not «nowhere»: each type says where it belongs by
# nature — the panel for a clock or a desk indicator, the desk for a
# thing one reads once — so a bare declaration lands where that kind of
# widget usually goes.
#   wm-widget clock -type clock -on screen -place center -layer desk
#
#   -on       workarea (default) | screen | {panel NAME}
#   -place    the `place` grammar's edge words, sizeless — WHERE ON THE
#             DESK. On a panel it is ignored: the strip hands out the
#             slot (the far end, before the tray), because a widget
#             that picks its own corner on a strip sooner or later
#             picks the tray's.
#   -padding  air inside it, default 4; -background, -foreground
#
# Widgets naming the same host and the same corner share an AREA and
# are laid out in declaration order — along the strip on a panel, in a
# column on the desk.
#
# THE DESK IS ONE WINDOW of ours, at the bottom of the stack, and every
# desk-layer widget lives inside it. Switch it off if you paint the
# root yourself (xsetroot, feh, another desktop manager) — the widgets
# then get a window apiece, as before:
#   set-desk-window off
#   set-desk-background #1c1c1c
#
# A widget riding a panel makes the panel deeper, the way the tray
# does. Widgets are cheap: a reload destroys and rebuilds every one of
# them, which is the whole story of how a widget changes its mind.
#
# The clock takes -time-format and -date-format (`clock format`
# strings, default %H:%M and «%a %d %b») and is set in ClockFont and
# DateFont — 1.6 and 0.8 of the desk font, so they move with it.
#
# ---- window commands ----
#
# Everything else in this file is lowercase and DESCRIBES a desk. A
# command is Capitalized, and DOES something the moment it runs:
#
#   Minimize  Maximize  Fullscreen  Move  Resize
#   Raise     Lower     Bury        Close Destroy
#   Unmaximize  Unfullscreen  Fade  Unfade
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
