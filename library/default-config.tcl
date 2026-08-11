# tk9wm config — the annotated sample, and now YOUR file: on its
# first run the desk copies this into ~/.config/tk9wm.tcl
# (XDG_CONFIG_HOME honored) exactly so there is something to edit.
# Everything below is a comment — the file does nothing until a line
# loses its `#`. Every default lives in the WM's code, so an empty
# file is already the stock desk: uncomment only what you mean.
#
# The config is plain Tcl, sourced into the WM's interpreter, so any
# policy proc is at your disposal. Re-read it on the live desk with
# Super+t w r — no restart, no client disturbed. The file reads in
# three movements: the SIMPLE KNOBS (a line and an example each),
# then ACTIONS — the desk's own verbs, worth learning in order — and
# then the PROGRAMMABLE part: menus, Fire, Ask, and worked examples.
#
# =====================================================================
# 1. SIMPLE KNOBS
# =====================================================================
#
# ---- fonts: one base, everything follows ----
#
# The desk font is the one this window manager is set in; decoration
# heights follow its metrics, and the derived fonts move with it.
#   set-desk-font -family "DejaVu Sans" -size 12
#   set-desk-font {DejaVu Sans Mono} 11
#
# The titlebar's font alone — a delta over the desk font:
#   set-title-font -weight bold
#   set-title-font -size 11 -weight bold
#
# The panel strip's font, same idea; `wm-font` derives any named
# font, and a size may be a FACTOR of the base's, which is what keeps
# a desk in proportion when the base changes (`-from` picks another
# base; declaration order is derivation order). A widget type's faces
# get setters of the same shape from their declaration — the clock's
# set-clock-font and set-date-font, the desk indicator's
# set-desk-num-font:
#   set-panel-font -size 10
#   wm-font PanelFont -size 0.85x
#   set-clock-font -size 2x
#
# Title alignment in the bar — left (default), center, right:
#   set-title-justify center
#
# ---- windows: minimize, maximize, drag ----
#
# Minimize (ICCCM iconification): `iconify` honors it (default),
# `refuse` declines it to the client's face — this desk has no
# minimize, and an app that hid itself internally is told to come
# back. The case it exists for is wine, whose windows come back from
# an iconify round trip with their inner focus lost (measured, also
# under fvwm3) — per client the style key wins over the desk answer:
#   set-minimize refuse
#   wm-style {filter -class {*.exe *.exe}} {minimize refuse}
#
# Maximize is a SAVED GEOMETRY, not a state the client is held in.
# What a hand resize does to the mark: `drop` (default, fvwm3's own —
# a resized window is no longer «the maximized one», and the next
# toggle maximizes again), or `keep` (the toggle restores the
# pre-maximize geometry however the window was pulled about):
#   set-maximize keep
#
# When the WORKAREA moves (a panel changes side, a tray widens the
# band, the screen resizes) the windows follow it: what spanned an
# axis spans the new one, what was flush with an edge stays flush.
# `max` narrows that to maximized-looking windows, `off` moves none:
#   set-workarea-follow max
#   set-workarea-follow off
#
# The carry gesture — hold the modifier, press anywhere on the
# window: button 1 carries, button 3 resizes from the nearest corner
# (for a `decor none` window this is the only mouse handle). <Super>
# by default; <Alt> is spoken for inside too many applications:
#   set-drag-modifier {<Alt>}
#   set-drag-modifier {<Ctrl><Alt>}
#
# A titlebar press stays a CLICK until the pointer travels this many
# pixels, so aiming at a titlebar never nudges the window; 0 carries
# from the first pixel:
#   set-drag-slop 0
#
# A carried window sticks to a workarea edge within this many pixels
# (flush against a strip is where one usually aims); 0 is off:
#   set-edge-resist 20
#
# `Fade` toggles a window between solid and this much (a compositor
# must be running — the opacity is a property only a compositor
# reads); `Unfade` is the unconditional way back:
#   set-fade 0.75
#   wm-bind {<Super>minus} Fade
#   wm-bind {<Super>equal} Unfade
#
# ---- the desk itself ----
#
# How this desk walks you into a file to EDIT — this one, from the
# «Said at …» openers and the knobs window's «Edit config…» button.
# Unsaid, the desk picks for this machine: emacs when there is one,
# else $VISUAL/$EDITOR in your terminal, else an editor hunt
# (sensible-editor, vim, vi, mcedit, nano, xedit):
#   set-edit-door terminal
#   set-edit-door emacs
#
# The desk's colour scheme — the applets, menus and decorations wear
# it; dark is the default:
#   set-theme light
#
# The root cursor (the WM conventionally sets it — one xsetroot fewer
# in your session script); empty string = hands off:
#   set-root-cursor left_ptr
#   set-root-cursor {}
#
# THE DESK IS ONE WINDOW of ours at the bottom of the stack, and
# desk-layer widgets live inside it. Off if you paint the root
# yourself (feh, xsetroot, another desktop manager):
#   set-desk-window off
#   set-desk-background #1c1c1c
#
# Virtual desks, fvwm-style — one knob, and it is a COUNT (1 =
# mechanism off). Switching is VISIBILITY only: windows of other
# desks leave the screen un-minimized (WM_STATE stays Normal), so
# clients that paint by state keep painting. The `desks` key bundle
# follows the count by itself: Super+N goes, Super+Shift+N sends.
#   set-desks 4
# Per window: born on a desk, or on every desk (and the window
# command `Sticky` toggles the latter by hand):
#   wm-style {filter -class Telegram} {desk 2}
#   wm-style {filter -title Таймер}   {desk sticky}
# Two window lists exist as two commands, bind either: `winlist`
# (this desk — what Alt+Tab cycles) and `winlist-all` (everything,
# foreign rows marked with their desk; picking one goes there).
#
# The welcome note links a fresh desk to the configurator; its own
# «hide forever» link writes the customization, or say it here:
#   set-welcome off
#
# ---- keys: echo, help, cycle ----
#
# A running chord sequence SHOWS itself in a small box. A delay in ms
# makes it appear only when you hesitate (Emacs's echo-keystrokes):
#   set-key-echo 400
#   set-key-echo off
# Where the box sits — place-grammar edge words, sizeless:
#   set-key-echo-place {right top}
#
# Inside a sequence, this key lists everything under the prefix you
# are standing in; at top level it opens the whole keymap (a listed
# chord can be typed straight at the list). Answers even when the
# echo is off:
#   set-key-help {<Ctrl>h}
#   set-key-help off
#
# The window list under a still-held modifier runs the fvwm alt-tab
# cycle (Tab advances, releasing commits, a quick full Alt+Tab
# toggles to the previous window). Off = always a static menu:
#   set-winlist-cycle off
#
# A chord answers even while its modifier is still held down; off
# demands a clean press:
#   set-chord-hold off
# ...and a binding's script that holds the desk longer than this
# many ms is reported (the desk is the event loop — a slow script
# freezes every window):
#   set-key-hold-warn 2000
#
# ---- panel, tray, icons (the knobs; the strip itself is §5) ----
#
#   set-panel-side left          ;# bottom (default), top, left, right
#   set-panel-preset stack       ;# row (default), stack, icons
#   set-panel-icon-size 32       ;# default 48, the hicolor stock
#   set-panel-live-colors #8ae234 #5d6e59   ;# the live-match bar and tint
#
# Where a bare icon NAME is searched (NAME.png, then NAME.svg, per
# directory list — see the style section for what an icon value is):
#   set-icon-path {~/.local/share/icons/hicolor/48x48/apps /usr/share/pixmaps}
#
#   set-tray on                  ;# be the display's tray manager
#   set-tray-panel dock          ;# whose bar the tray rides (default: default)
#   set-tray-background #2e3436  ;# shows through icons' transparent parts
#   set-tray-icon-size 24
#   set-tray-argb on             ;# 32-bit strip for alpha-drawing clients
#                                ;# (Chrome); needs a compositor, off by
#                                ;# default — set before set-tray on
#
# ---- which terminal, which emacs (the knobs; the layers are §4) ----
#
# The beast and the binary are separate words. Without the line the
# desk resolves one: $TERMINAL if it names a known beast, then
# x-terminal-emulator if YOU pointed it (update-alternatives manual
# mode), then the first found — kitty, alacritty, urxvt, st, xterm,
# DE terminals last. The log says what was picked and on whose word.
#   set-terminal kitty
#   set-terminal kitty ~/bin/kitty.experimental
#
#   set-emacs-frames terminal    ;# gui frames (default) or in-terminal
#   set-emacs-daemons off        ;# the plain, serverless life
#   set-emacs-autodaemon off     ;# a missing daemon is an error, not a spawn
#   set-emacs-keep-frame-name on ;# the button's word stays in the title
#   set-emacs-edit create        ;# the edit door: reuse (default) or create
#   set-emacs-edit-daemon work   ;# which server edits; unsaid = default one
#
# =====================================================================
# 2. PER-WINDOW RULES: wm-style, filter, place
# =====================================================================
#
# wm-style PREDICATE SETTINGS appends a rule; the predicate is any
# command prefix called with the client's X window id, all matching
# rules apply, later rules win per key. `always` matches everything;
# `filter` is the workhorse:
#
#   filter ?-nocase? ?-regexp? ?-title PAT? ?-class PAT|{PAT PAT}? \
#       ?-command PAT? ?-machine PAT?
#
# Options AND together; patterns are globs over the whole string,
# case-sensitive (WM_CLASS uses case to tell things apart: an xterm
# is {xterm XTerm}, and `xterm -name ninja` is {ninja XTerm}). One
# -class pattern matches EITHER half of {instance class}; two are
# positional, as xprop prints them. -regexp swaps the comparator
# (unanchored; (?i) inside a pattern). -command matches WM_COMMAND
# joined with spaces, falling back to a local client's /proc argv.
# Identity accessors for hand-rolled predicates: client-class,
# client-title, client-machine, client-command, client-pid,
# client-cmdline.
#
# The style keys:
#   increments respect|ignore  resize grid from WM_NORMAL_HINTS;
#                              binds the FREE resize only — maximize
#                              and %-places fill to the pixel anyway
#   minimize iconify|refuse    this client's answer, over set-minimize
#   decor full|border|none     how much frame: border drops the title
#                              strip, none is nothing at all — mind
#                              that `none` leaves only the modifier
#                              drag and the keyboard (winops)
#   opacity N                  rests translucent, 0 < N <= 1 (needs a
#                              compositor); Unfade returns here
#   desk N|sticky              born on that desk, or on every one
#   layer N|below|normal|above|dock|top
#                              its rung in the stack: above floats
#                              over the desk yet under the panel
#                              (dock); a NUMBER (0..12) says what no
#                              word can — «over the panel AND over a
#                              fullscreen window» is 10 or more
#   start iconic|fullscreen    born minimized, or born fullscreen —
#                              the config's word for what a client
#                              asks with WM_HINTS initial_state or a
#                              pre-map _NET_WM_STATE; `normal` is the
#                              blank a later rule may answer with
#   place TERMS                the geometry it is born with (below)
#   icon IMAGE                 window-list face, over _NET_WM_ICON —
#                              a Tk image name, a file path (png/svg),
#                              or a bare NAME searched through
#                              set-icon-path; a miss logs one line
#
#   wm-style always {increments ignore}
#   wm-style {filter -class {* XTerm}} {increments ignore}
#   wm-style {filter -nocase -class {* xterm}} {increments ignore}
#   wm-style my-xterm {icon ~/icons/terminal.png}
#
# The proc predicate is the escape hatch for anything richer:
#   proc my-xterm {w} {
#       expr {[lindex [client-class $w] 1] eq "XTerm"
#             && [lindex [client-cmdline $w] 0] eq "/usr/bin/xterm"}
#   }
#   wm-style my-xterm {increments ignore}
#
# ---- place: where a window opens ----
#
# A list of terms, comma or whitespace separated:
#   term = [SIZE]EDGE
#   SIZE = N%     of the WORKAREA (strips never covered), frame included
#   EDGE = left|right|hcenter | top|bottom|vcenter | center
# The edge picks the axis and the alignment; a sized term sets both,
# a sizeless one only pins. An axis NO term claims is FILLED — that
# is what makes 50%right the right half at full height; «pin it,
# leave the size alone» takes a term per axis ({right bottom}).
#
#   wm-style {filter -class Emacs}    {place max}
#   wm-style {filter -title "*mutt*"} {place 50%right}
#   wm-style my-monitor {place {30%bottom 50%right}}
#   wm-style {filter -class {* XClock}} {place {right bottom}}
#
# A place YIELDS, aspect by aspect, to a window that asked for its
# own -geometry (the US forms only — a user's word about THIS window
# beats the rule's general one): said HOW BIG, the rule goes
# sizeless; said WHERE, the rule's position drops. `force` means it
# anyway:
#   wm-style {filter -class Emacs} {place {max force}}
#
# `max` is the whole workarea and behaves like the maximized STATE
# (the titlebar toggle restores). Percentages are of ONE monitor's
# workarea — the primary — never of a multihead bounding box.
# Increments do not bind sized axes (the mutter rule).
#
# =====================================================================
# 3. TITLEBAR, WINDOW MENU, COMMANDS, BINDINGS
# =====================================================================
#
# ---- titlebar buttons, and what a gesture does ----
#
# Which buttons exist: order within a side is declaration order; the
# stock set is menu left, minimize/maximize/close right. A glyph is
# svg (re-rendered crisp at the title font's size) or a character or
# two in the strip's own font:
#   titlebar-button shade -side left -glyph {<svg
#    xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path
#    d="M3.5 4 L12.5 4" stroke="#ffffff" stroke-width="1.6"
#    stroke-linecap="round" fill="none"/></svg>}
#
# What a gesture does: the part is a button's name or `title` for the
# strip itself; gestures are <1> <2> <3> <Double-1>; the command is a
# prefix the window is appended to — the Capitalized window commands
# fit exactly. Buttons fire on release-inside; strip gestures on the
# press (a menu opened by one is up while the button is still down —
# drag onto an entry and release). Button 1 on the strip carries.
#   titlebar-bind shade <1>        Lower
#   titlebar-bind title <Double-1> Maximize     ;# the default
#   titlebar-bind title <3>        winops       ;# the default
#   titlebar-bind close <3> Destroy   ;# sharp, deliberately not stock
#
# When a button exists at all: `-needs CMDS` gates on the machine,
# `-when PRED` on the window (wm-style's predicates, judged when the
# frame is dressed). The stock minimize button's own rule is `-when
# minimize-allowed`.
#   titlebar-button ask -side right -needs claude -glyph ?
#   titlebar-bind   ask <1> Ask-Claude
#
# ---- the window menu's own rows ----
#
# winops-item NAME {label … command … ?key …? ?needs …? ?when …?} — a
# row under the stock window commands; `command` is a prefix the
# window is appended to. The name is the primary key, a second word
# refines, winops-item-remove is the negative word.
#   winops-item ask {label "ask claude" key a needs claude command Ask-Claude}
#
# A row whose verb is a TOGGLE wears a state marker (Maximize and
# the axis pair, Fullscreen, Above, Sticky do out of the box); for a
# verb of your own, declare what it reads:
#   proc Solo {w} { ... }
#   proc solo-p {w} { ... }
#   winops-item solo {label соло key o command Solo}
#   command-state Solo solo-p
#
# ---- window commands ----
#
# Lowercase DESCRIBES; Capitalized DOES, the moment it runs:
#   Minimize  Maximize  Fullscreen  Move  Resize
#   Raise     Lower     Bury        Close Destroy
#   Unmaximize  Unfullscreen  Fade  Unfade  Maximize-V  Maximize-H
# The axis pair composes (tall then wide is full); the titlebar's
# maximize button carries them classically — middle tall, right wide.
# Bound, a command acts on the ACTIVE window:
#   wm-bind {<Ctrl><Shift>z} Minimize
#   wm-bind {<Super>Up}      Maximize
#
# A USER TOGGLES, A PROGRAM DOES NOT: picked off a menu or pressed on
# a key, Maximize over a maximized window means «the other way»; in
# an Apply-To-Matching sweep it forces, so the sweep cannot undo the
# windows that were already right. Un-verbs never guess.
#
# Apply-To-Matching PREDICATE COMMAND — one command over every
# matching window; a refusing client does not stop the sweep. Not
# bound by default, deliberately:
#   wm-bind {<Super>d} {Apply-To-Matching always Minimize}
#   wm-bind {<Super>c} {Apply-To-Matching {filter -class Chromium} Close}
#
# About the desk rather than a window: `Restart` (same pid, fresh
# code, clients readopted), `Reload` (re-read this file live, also
# Super+t w r), `Quit` (asks first; clients are RELEASED alive — but
# a session that ends with its WM still ends). Their lowercase
# originals restart-wm/reload-config still work.
#
# ---- key bindings ----
#
# wm-bind SPEC SCRIPT, stumpwm-style: only the FIRST chord is a
# global grab, the rest collect under a temporary keyboard grab. A
# chord is <Mod> prefixes (<Shift> <Ctrl> <Alt> <Super>, <Mod1>..
# <Mod5>; <Alt>=<Meta>=<Mod1>, <Super>=<Mod4>) and a keysym. Later
# binds win. The spelling the desk SHOWS also binds — a line read off
# the echo can be typed straight back:
#   wm-bind {<Super>Return} {Run xterm}
#   wm-bind {<Super>t w x}  {Run xterm}
#   wm-bind {Super+t Ctrl+j} {Run xterm}    ;# same grammar, echo dialect
# A third argument names it for the help list:
#   wm-bind {<Super>Return} {Run urxvtc -e tmux new -As0} "a terminal"
#
# A SHIFTED SYMBOL IS SPELLED BY THE KEY IT SITS ON (group 0 level 0,
# which keeps chords Latin on any layout): bind <Shift>slash, not
# `question`. A top chord is always live — half-typed prefixes cost
# nothing, press the prefix again. In-code defaults: winops on
# <Alt>space and <Super>t w m, winlist on <Alt>Tab and <Super>t w w.
#
# KEYS COME IN FAMILIES — a family is what one turns on, off or
# MOVES, and its parameters move the whole tree:
#   wm-keys chords -prefix {<Super>x} -help {<Super>slash}
#   wm-keys windows -close {<Ctrl><Alt>w} -hide {<Super>m}
#   wm-keys desks -mods {<Ctrl><Alt>} -send {<Ctrl><Alt><Shift>}
#   wm-keys windows off
# Re-declaring a bundle unbinds what is STILL the family's: a chord
# you took for yourself since (a plain wm-bind over it) is yours and
# stays. Every binding remembers whose it is and the config line that
# said it; binding over somebody's chord is allowed and logged.
#
# `wm-unbind SPEC` is the negative word; `action-remove`,
# `wm-menu-remove`, `winops-item-remove`, `wm-widget-remove` are its
# kin for the named families.
#
# =====================================================================
# 4. ACTIONS — the desk's verbs, in rising order
# =====================================================================
#
# action NAME SETTINGS declares a named thing this desk can do —
# run-or-raise: fired (by chord, panel button, menu row), it FOCUSES
# the most recent window its match finds, else RUNS its command.
# The name is the primary key: a second `action NAME` REFINES (said
# keys merge over what stood; an empty value un-says its key), and
# `action-remove NAME` drops a deed the layer below declared. Every
# declaration is checked against the spec table — an unknown key is
# refused where written, not silently kept; softer diagnoses (a bad
# chord, an absent needs command, an exec said the long way, a ~ in
# command words) are REMARKS in the log and the configurator.
#
# The simplest deed — a launcher, no match:
#   action screenshot {run {flameshot gui} key {<Super>Print}}
#
# Run-or-raise proper — the match says which window counts:
#   action ff {
#       match {filter -class firefox}
#       run {firefox}
#       key {<Super>f}
#       icon firefox
#   }
#
# `run` is RAW ARGV — no shell, no expansion, one uniform spelling
# whether it runs bare or inside a terminal. It is sugar for `launch
# {Run firefox}`; say one of the two. `Run` reads nothing: the launch
# script is Tcl evaluated at fire time, so $env(HOME) means what it
# says and a `~` stays a literal ~ (the linter reminds you).
#
# The other keys, when you need them:
#   env {GTK_IM_MODULE fcitx}   around the launch; empty value = VAR=
#   env-unset {WAYLAND_DISPLAY} vars that must be ABSENT, not empty
#   dir ~/proj                  working directory — for what Run
#                               starts AND for the terminal process
#                               itself (kitty's new tabs open there);
#                               a path, so its ~ expands
#   needs mutt                  commands that must exist in PATH: the
#                               deed WAITS (visible, unbound, off the
#                               strips) and comes alive on the reload
#                               after the software lands
#   badge W                     a letter or two over the icon
#   style {place 50%right}      a wm-style for the windows it matches
#   many choose                 what the CHORD does with several
#                               matches: mru (default) or choose —
#                               the filtered window list; a button
#                               already wears both (body = mru,
#                               arrow = chooser)
#   activate SCRIPT             the found window goes here instead of
#                               plain focus — raises needing ceremony
#
# ---- a terminal deed: say WHAT, not which emulator ----
#
# The `terminal` word derives both halves for the ACTIVE terminal
# (set-terminal, §1): the launch opens the emulator around the
# action's own run — xterm gets `-name mutt -e mutt`, kitty
# `--name mutt mutt` — and the match is `filter -class mutt`, the
# name landing in WM_CLASS however the beast spells it:
#
#   action mutt {terminal {name mutt} run {mutt} key {<Super>m}}
#
# NAME YOUR TERMINALS. `terminal {}` is «just a terminal»: it matches
# ANY terminal window the desk knows, whichever beast — which is
# exactly right for one catch-all shell button and exactly wrong for
# everything else (a tmux in a plain xterm would answer it). A named
# terminal matches only the windows it opened.
#
# The full terminal spec — the COMMAND is deliberately not among its
# keys, it comes from the action's run/launch:
#   name    WM_CLASS instance (on xterm/urxvt also the xrdb branch)
#   title   the window title — say it when the command's first word
#           would read wrong in the list (`sh` for a tmux button)
#   bg/fg   colours, any Tk-legal word, spoken in the beast's own
#           dialect (xterm via -xrm at the VT100 widget; st has no
#           way and spawns unpainted, with a log line)
#   env     environment for the terminal PROCESS itself
#   env-unset  vars the terminal must not have
#   args    beast-keyed extras, verbatim, when the branch names the
#           active beast: args {xterm {-bg darkblue} kitty {-o background=darkblue}}
#
# The worked button — waits for mutt, dressed, on the strip:
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
# ---- an emacs deed: one storey above the terminal ----
#
# «The TELEGA frame of the telega daemon», as one word:
#   action telega {
#       emacs {daemon telega frame TELEGA eval (telega)}
#       key {<Super>g}
#   }
# emacs puts a frame's name into the WM_CLASS instance, so the match
# is the same one pattern — it finds the GUI frame as {TELEGA Emacs}
# and, under set-emacs-frames terminal, the named terminal running
# emacsclient -t. The launch ensures the daemon (emacsclient -a ''),
# creates the named frame and runs the eval in it — and the eval
# re-runs on every HIT too, because the frame may have wandered off
# and the button means «back to telega». Make the eval smarter if
# you want it to stay put:
#   eval {(unless (derived-mode-p 'telega-root-mode 'telega-chat-mode)
#           (telega))}
#
# THE FRAME NAME IS THE DEED'S OWN unless said otherwise — the
# shortest emacs button is `action telega {type emacs}`. What a
# nameless button must NOT do is match «any Emacs»: X says nothing
# about which daemon a frame belongs to. The name is for FINDING,
# not reading: the launch hands the title back to emacs at once
# (set-emacs-keep-frame-name to keep the button's word instead).
# Keys: frame, daemon (`none` = the serverless plain life: plain
# lookup-or-run, no eval-on-hit), eval, via gui|terminal, autodaemon
# on|off (a spec's env rides an auto-started daemon's command line),
# keep-frame-name on|off, env, env-unset. Desk-wide answers: the
# set-emacs-* knobs (§1).
#
# A FRAME SAID EMPTY — `frame {}` — is the frameless deed: a PURE
# EVAL. No window, no match, no raise: every press just says the
# form to the daemon — «tell telega to X» as a button.
#   action tg-mute {
#       emacs {daemon telega frame {} eval (telega-mute-all)}
#       key {<Super>m}
#   }
# Said on purpose, never fallen into: an unsaid frame still lends
# the deed's name. It wants an eval (a frameless deed with nothing
# to say is nothing) and refuses the frame words — via,
# keep-frame-name, a match — out loud. set-emacs-daemons off
# empties it: no server means nobody to talk to, and the press says
# so in the log instead of pretending.
#
# In terminal mode the desk stays honest against C-x 5 2: a hit
# focuses the terminal window immediately and asks the daemon, in
# the background, to put the named frame back on top of its tty —
# recreating it if it is gone and exactly one tty terminal lives.
#
# The EDIT DOOR is the other emacs verb: a destination, not an
# identity — any frame of the right server will do, so it has knobs
# (set-emacs-edit, set-emacs-edit-daemon) and no frame name. The
# configurator's «in emacs» walks through it.
#
# ---- colours from names ----
#
# `name-tint NAME ?-from white|black? ?-amount 0..1?` answers a
# stable colour hashed from a name — the badge hash, published. The
# ssh model task, whole: twenty terminals told apart at a glance,
#
#   foreach t {web db backup} {
#       action ssh_$t [list terminal [list name ssh_$t title "ssh $t" \
#           bg [name-tint $t -from black]] run [list ssh $t]]
#   }
#
# =====================================================================
# 5. THE PANEL, MORE PANELS, WIDGETS
# =====================================================================
#
# panel-button NAME declares a button on the strip (the strip exists
# only when buttons do; maximize respects it). The button is a
# REFERENCE to the action of that name — the face flashes the verdict
# (green «found», orange «launching») — and may dress differently on
# this strip; everything else is the action's to say, once:
#   panel-button ff
#   panel-button ff {label Web icon X}
# Referencing an action declared later (or not yet) is fine: a name
# with no live action stands by and surfaces when its action does.
#
# A button whose match sees a LIVE window says so (bar + face tint,
# recolour with set-panel-live-colors); with matches it wears an
# arrow strip — the whole strip clicks into the filtered window
# list, most recent first; the body keeps the idempotent fire.
# CTRL+CLICK anywhere on the button LAUNCHES ANOTHER, match or no
# match — the same door the chooser's «run another» row opens.
#
# The strip's shape knobs are in §1 (side, preset, icon size). While
# no face resolves to an icon the strip is a thin text-chip row; the
# first icon makes every iconless button wear an auto-badge and the
# strip grow to the icon size.
#
# More than one panel: `panel NAME BODY` — inside the block the
# panel words speak about THAT panel, outside about `default`:
#   panel dock {
#       set-panel-side left
#       set-panel-preset stack
#       panel-button терм
#   }
#   set-panel-side bottom
#   panel-button emacs
# Panels divide the screen in DECLARATION ORDER — the corner between
# two edges belongs to whichever was declared first — and what
# survives is the workarea.
#
# ---- widgets: the desk's own furniture ----
#
# A widget knows how to fill a frame, not where it hangs — that is
# one option, so one declaration lands on a panel, a workarea
# corner, or the desktop under every window. `-on` unsaid is not
# «nowhere»: each TYPE says where it belongs by nature.
#   wm-widget clock -type clock
#   wm-widget clock -type clock -on {panel default} -place {right vcenter}
#   wm-widget clock -type clock -on workarea -place {right top}
#   wm-widget clock -type clock -on screen -place center -layer desk
# Options: -on workarea|screen|{panel NAME}; -place (edge words,
# sizeless; ignored on a panel — the strip hands out the slot);
# -padding (default 4); -background, -foreground; -every (ms between
# beats, for a type with a heartbeat). Same host and corner share an
# area in declaration order. A reload rebuilds every widget — that is
# how a widget changes its mind. Beyond those, a TYPE declares its own
# params — the configurator shows them per widget, and a word the type
# does not take is refused by name. The clock takes -time-format and
# -date-format (`clock format` strings), -timezone (an IANA zone —
# unsaid, this machine's own) and -label (a tiny word telling one
# clock from another — only ever said, never derived from the zone);
# it is set in ClockFont, DateFont and ClockLabelFont, 1.6x, 0.8x and
# 0.6x of the desk font, and its calendar rings the ZONE's today:
#   wm-widget осло -type clock -timezone Europe/Oslo -label OSL
# The desk indicator (type desks) takes -style dots|text and -gap. The battery takes -source
# ({sys ?NAME|path?} for /sys/class/power_supply, or {command {argv…}}
# whose stdout is a bare percent or termux-battery-status JSON — a
# phone over ssh), -letter to tell several apart, and -low; a dead
# command shows grey with a dash until an answer returns:
#   wm-widget батарея -type battery -letter L
#   wm-widget телефон -type battery -letter P \
#       -source {command {ssh phone termux-battery-status}} -every 60000
# The weather reads Open-Meteo — free, no key. Its -source is {name
# PLACE} (geocoded once through the API's gazetteer), {latlon LAT
# LON}, or {command {argv…}} whose stdout is the API's own JSON;
# unsaid, it is {name Tbilisi}. -label puts a word beside the
# temperature; a click opens a seven-day sheet in the panel's corner,
# drawn from what is already known — offline it stands, in a dimmer
# ink. One glance-sheet stands at a time: the forecast and the clock's
# calendar displace each other. The sky is reached by tcltls, curl or
# bare http, whichever the machine carries:
#   wm-widget погода -type weather -label Тб
#   wm-widget дома -type weather -source {name Москва} -label М
#
# =====================================================================
# 6. MENUS, AND THE PROGRAMMABLE DESK
# =====================================================================
#
# ---- menus: actions laid out under a chord ----
#
# wm-menu NAME {…} — the panel's other surface. A row is a reference
# to an action (bare name, or `{action NAME …}` with a key/label of
# its own), an INLINE spec (`action {…}` — Fire's rule, for the deed
# that is data), or a label+do pair for the piece that is genuinely
# this config's:
#   wm-menu ssh {
#       key   {<Super>t s}
#       items {
#           {action ssh_web key w}
#           ssh_db
#           {label "bash here" action {type terminal launch {Run bash}}}
#           {label "log here" do {Run xterm -e tail -f /var/log/syslog}}
#       }
#   }
# Unkeyed rows are numbered the winlist way (1-9, A-Z, stepping over
# claimed letters). A row referencing a WAITING action is quietly
# not shown (the panel's rule); a reference nobody declared is a
# problem line. The name refines like an action's; wm-menu-remove is
# the negative word. `place` overrules where it opens (edge words,
# sizeless); brought up by mouse it lands under the hand.
#
# A row may carry a SECOND reading under Shift — `shift-do` or
# `shift-action` beside the plain half; Shift+Return, Shift+letter
# and Shift+click all take it:
#   {label ~/proj key p
#    do       {Fire {terminal {name claude_proj} dir ~/proj
#                    run claude}}
#    shift-do {Fire {terminal {name claude_proj} dir ~/proj
#                    run {claude --continue}}}}
#
# `body` is the dynamic half — a script asked for the rows AT OPEN
# TIME (items ⊕ body, the run/launch rule): a list of recent
# anythings is stale the moment it is written down.
#   wm-menu recent {
#       key  {<Super>t r}
#       body {my-recent-rows}
#   }
#
# ---- Fire: run-or-raise as a word ----
#
# `Fire NAME ?mode?` fires a declared action from any script (mode:
# auto, mru, choose, run). `Fire SPEC ?mode?` is the same fire over
# an INLINE spec — the whole derivation works, terminal adapter
# included, and nothing lands in the registry: for the deed that is
# DATA (a menu body of twenty ssh targets is not twenty
# declarations). Surface words (key, icon, badge, style) are refused
# inline; an inline emacs deed must say its frame.
#   Fire mutt
#   Fire {terminal {name ssh_web} run {ssh web}}
#
# ---- Ask, Choose, Window-Shot, Exec ----
#
# `Ask PROMPT ?-initial …? ?-place …? ?-width …?` — one line of text
# from the person, dressed as the key echo. Enter ANSWERS (empty
# included), Escape CANCELS the asking script quietly: «answered
# nothing» and «did not answer» are different facts. Not modal; a
# newer ask displaces the standing one. It waits on a future, so it
# belongs in a script the desk runs — a binding, a menu row.
#
# `Choose rows…` is the same list as a QUESTION: answers the picked
# row's value (label when unsaid), or empty. A row is a bare word or
# {label L ?value V? ?key K? ?shift-value V?}:
#   wm-bind {<Super>o} {
#       set which [Choose {alpha {label beta value B key b}}]
#       if {$which ne ""} { Run xmessage $which }
#   }
#
# `Window-Shot ?W? ?DIR?` raises the window, lets it repaint, and
# writes its on-screen rectangle to a PNG (unsaid DIR: $HOME),
# answering the path or empty with a reason. Nothing external runs.
#   winops-item shot {label скриншот key t
#                     command {Window-Shot-To ~/screenshots}}
#
# `Exec cmd…` runs a command and reads its output without holding
# the desk (a future underneath — script use only); `elisp-read`
# turns printed elisp into Tcl shapes (plist → dict, propertized
# string → its string, nil → empty; -all for a text of many forms);
# `elisp-string` spells a Tcl string as the elisp literal — the word
# for a file name or a title going INTO an eval.
#
# ---- the ask-claude model task, whole ----
#
#   proc Ask-Claude {{w 0}} {
#       set shot [Window-Shot $w $::env(HOME)/screenshots]
#       if {$shot eq ""} return
#       set what [Ask "спросить про это окно:"]
#       if {$what eq ""} return
#       Fire [list terminal {name claude_ask} dir [file dirname $shot] \
#           run [list claude \
#               "юзер спрашивает про скриншот [file tail $shot]: $what"]]
#   }
#   titlebar-button ask -side right -needs claude -glyph ?
#   titlebar-bind   ask <1> Ask-Claude
#   winops-item ask {label "ask claude" key a needs claude command Ask-Claude}
#
# ---- the claude-projects model task, whole ----
#
# A dynamic menu of the projects claude was last opened in, freshest
# first; Return starts a fresh session in the project's own
# terminal, Shift-Return continues the last one, and a live project
# terminal is raised by either. The recency is read where it
# honestly is: ~/.claude.json knows the paths, the transcripts under
# ~/.claude/projects/<slug>/ carry the times (the slug is the path
# with every non-alphanumeric turned to a dash). `package require
# json` is tcllib's, travelling with the library:
#
#   proc claude-recent-projects {{n 12}} {
#       package require json
#       set ch [open [file join $::env(HOME) .claude.json] r]
#       set cfg [json::json2dict [read $ch]]
#       close $ch
#       set stamped {}
#       foreach dir [dict keys [dict getdef $cfg projects {}]] {
#           set slug [regsub -all {[^A-Za-z0-9]} $dir -]
#           set newest 0
#           foreach f [glob -nocomplain -directory [file join \
#                   $::env(HOME) .claude projects $slug] *.jsonl] {
#               set m [file mtime $f]
#               if {$m > $newest} { set newest $m }
#           }
#           if {$newest} { lappend stamped [list $newest $dir] }
#       }
#       set out {}
#       foreach p [lrange [lsort -integer -decreasing -index 0 \
#                              $stamped] 0 [expr {$n - 1}]] {
#           lappend out [lindex $p 1]
#       }
#       return $out
#   }
#   proc claude-items {} {
#       set items {}
#       foreach dir [claude-recent-projects] {
#           set slug [regsub -all {[^A-Za-z0-9]} $dir _]
#           set t [list terminal [list name claude_$slug] dir $dir]
#           lappend items [list \
#               label [string map [list $::env(HOME) ~] $dir] \
#               do       [list Fire [concat $t {run claude}]] \
#               shift-do [list Fire [concat $t {run {claude --continue}}]]]
#       }
#       return $items
#   }
#   wm-menu claude {key {<Super>t p} body {claude-items}}
#
# ---- the telega-recipients model task, whole ----
#
# A menu of the people telega talks to most, asked of the daemon AT
# OPEN TIME and opened in the same emacs — a body error lands as a
# problem line rather than a dead chord:
#
#   proc telega-chats {} {
#       set out [Exec emacsclient -s telega --eval \
#                    {(telega--getTopChats "Users" 12)}]
#       set items {}
#       foreach chat [elisp-read $out] {
#           lappend items [list label [dict get $chat :title] \
#               do [list telega-open [dict get $chat :id]]]
#       }
#       return $items
#   }
#   proc telega-open {id} {
#       Fire [list emacs [list daemon telega frame TELEGA eval \
#           "(telega-chat--pop-to-buffer (telega-chat-get $id))"]]
#   }
#   wm-menu telega {key {<Super>t t} body {telega-chats}}
#
# ---- the telega-say model task: arguments ride a funcall ----
#
# Say a phrase into a chat from any script of the desk — a pure
# eval (`frame {}`, §4): no window anywhere, the daemon does the
# thing. And the pattern that keeps elisp NATURAL as it grows (the
# owner's, 2026-08-11): the body is a lambda in one static braced
# block, and the Tcl values arrive as funcall ARGUMENTS at the end
# — the id a bare number, the phrase through elisp-string — instead
# of being substituted into the middle of a long elisp sheet. One
# boundary, and every quoting question is answered at it.
#
#   proc telega-say {id phrase} {
#       set elisp {
#           (lambda (id phrase)
#             (with-current-buffer
#                 (telega-chatbuf--get-create (telega-chat-get id) nil)
#               (end-of-buffer)
#               (insert phrase)
#               (telega-chatbuf-input-send nil)))
#       }
#       Fire [list emacs [list daemon telega frame {} eval \
#                 "(funcall $elisp $id [elisp-string $phrase])"]]
#   }
#
# =====================================================================
# 7. LAYERS, RELOADING, AND WORKING ON THE DESK
# =====================================================================
#
# Beside this file there may be a MACHINE-WRITTEN one:
# ~/.config/tk9wm.custom.tcl — the configurator and the desk's own
# buttons write it, nobody edits it by hand. It loads AFTER this
# file and on overlap the click wins, one log line per shadowed
# knob («WM: custom overrides the config: set-title-font») — so a
# config line that «stopped working» is never a mystery.
#
# `Reload` (Super+t w r) re-reads this file on the live desk: every
# configurable thing goes back to the CODE's defaults first, then
# this file draws on the clean floor — which is why the file should
# stay DECLARATIVE. Knobs, actions, styles, binds, procs of your own
# are all fine; redefining a POLICY proc is not (nothing remembers
# what it was, and the next reload builds on the patch). A broken
# config leaves the desk on defaults plus whatever ran before the
# throw, and the log blames the exact line.
#
# `Reread` sources both layers of the WM's own code again — the
# development loop (procs replace, state carries; a vanished proc
# stays until restart). `Restart` execs a fresh process in place,
# clients adopted back.
