# tk9wm — an X11 window manager on Tcl/Tk 9

A reparenting window manager whose every decision and every piece of
policy is Tcl. The only C is `tkwmx`, a shim of window-manager
primitives that is **this project's own extension**
(`generic/tkwmx.c`). Spiritually the heir of tkwm (Eric Schenk, Neil
McKay, 1994–95), but with no patches to Tk: part of the TIP 47
machinery is in the Tk 9 core already, and the shim covers the rest.

The shape of it: one interpreter process, ONE X connection — Tk's own.
Tk draws the decorations (override-redirect frames) while the shim, on
that same connection, holds SubstructureRedirect, performs the WM
surgery (save-set, reparent, map) and hands the redirect events
**as dicts** straight into Tk's event loop.

```
configure  Makefile.in   build the shim, static and shared
generic/tkwmx.c          the shim itself
library/                 the WM proper: substrate.tcl, policy.tcl,
                         main.tcl, default-config.tcl (package tk9wm)
tk9wm.tcl                the entry point
tests/                   the WM regressions (run-*.sh) and their
                         clients; tests/tkwmx/ — the shim's own batteries
tools/                   live-display diagnostics and outside pokes
```

## Building

The shim is an ordinary Tcl extension and builds two ways from one
source file. Both are linked against the Tcl/Tk **stub** libraries
only, so `libtkwmx.so` carries no undefined Tcl or Tk symbol at all —
which is why it loads just as happily into a host that links Tcl
statically (a tclkit, a whale) as into one with a shared libtcl9.

```sh
./configure --with-tcl=/usr/lib     # the directory holding tclConfig.sh
make                                # -> libtkwmx.a and libtkwmx.so
```

`--with-tk=DIR` if `tkConfig.sh` does not sit next to `tclConfig.sh`;
`--disable-shared` for the static archive alone (what a kit build
wants), `--disable-static` for the reverse.

**Building against a whale.** You cannot point `--with-tcl` at one: a
whale is a single static binary with no headers, no stub libraries and
no `tclConfig.sh` inside it. What you point at is the Tcl/Tk install
tree whalebuild leaves *beside* the whale while building it —
`work/linux/install/lib`. Mind which tree:

```sh
# the NATIVE build — tclConfig.sh records real host paths
./configure --with-tcl=$HOME/…/whalebuild/work/linux/install/lib

# the CONTAINER build — do NOT use: its tclConfig.sh records the
# paths as seen INSIDE the box (-I/w/work/linux/install/include),
# and the compile fails on a missing tcl.h
#   …/whalebuild/work-linux/linux/install/lib
```

The .so this produces is not tied to the whale it was built against —
stubs make it good for any Tcl/Tk 9.0.x host. There is no win64 leg and
never will be: every primitive here — SubstructureRedirect,
reparenting, the save-set, the X error handler — is an X11 concept
with no GDI counterpart.

Then run it straight out of the checkout — `tk9wm.tcl` puts the
checkout on `auto_path`, so the freshly built shim is what gets
loaded:

```sh
wish9 tk9wm.tcl                     # or any Tcl/Tk 9 interpreter
```

What that interpreter needs is Tk 9 and **treectrl** (the titlebars,
the panel and the menus are treectrl widgets). Nothing else.

`make install` lays both packages out under `$(libdir)` as plain Tcl
package directories — `tkwmx0.1/` and `tk9wm0.1/` — so putting that
directory on `TCLLIBPATH` makes `package require tkwmx` and `package
require tk9wm` work from anywhere. The shim installs on its own
(`make install-shim`) for a host that only wants the primitives.

For **distribution** the .so should be built on a deliberately old
userland (an EL8-era container, glibc 2.28), the same way the whale is:
the binary's real floor is the glibc symbol versions it links against,
and the build box sets it.

A whale can also carry tk9wm as a compiled-in battery, static archive
and scripts both. Then there is nothing to build and nothing to
install — `package require tk9wm` answers out of the image.

## The files

- `library/substrate.tcl` — the mechanism, without which no WM can be
  written: the `x-*` layer is the single seam to every X call (one proc
  = exactly one shim call; it is what made the move off cffi a matter
  of editing thirty bodies rather than a file), the X error handler
  (`Tk_ErrorHandler`, a permanent swallow-and-log), and the discipline
  of **"survived, but said so"**: an error that is meant to be
  outlived goes through `soft LABEL SCRIPT ?DEFAULT?` rather than a
  bare `catch` (the script runs in the caller's scope; repeats of one
  label+error pair collapse into a counter) — a silent catch once hid
  for months the fact that `XFree` was freeing nothing at all.

  There is no pump whatsoever (`tkwmx::event on` is
  `Tk_CreateGenericHandler`: the redirect arrives in the ordinary event
  loop, with no second connection, no worker thread and no ping-pong).
  Then: manage/unmanage with an honest size read (`XGetGeometry` at
  manage time — a client that never sent a ConfigureRequest still gets
  framed at its own size; the same read gives its **position** at
  manage time); the WM_NORMAL_HINTS facts — minimum, increments, base
  (they clamp WM-driven resizes; re-read on PropertyNotify; whether to
  honor increments is the policy layer's call); the **position claim**
  (`USPosition`/`PPosition` + `win_gravity` — a move request from a
  managed client that made a claim goes to a policy hook, everyone else
  gets a refusal with the ICCCM synthetic); a live re-read of
  `WM_TRANSIENT_FOR` on PropertyNotify (a dialog may aim at its leader
  after it is already mapped); client-identity accessors for predicates
  (`client-class`/`-machine`/`-command`/`-pid`/`-cmdline` — a local
  client's argv via /proc; the "is this client local?" check tolerates
  Tcl's canonicalization of the hostname through /etc/hosts); adoption
  of pre-existing windows.

  A **deterministic focus core**: focus with nowhere to sit is parked
  on a holder window (a port of fvwm's `NoFocusWin` — an
  override-redirect window off-screen; a child of the root, so passive
  key grabs stay alive, and PointerRoot parking falls away together
  with its side effect — it BOTH switched the session to
  focus-follows-pointer AND armed Tk's own implicit focus, which on
  LeaveNotify does `XSetInputFocus(PointerRoot)`). One repair path for
  dead ends (`focus-repair`: PointerRoot/None on the root, focus on our
  own decoration — FocusChange is selected on the slot and on the frame
  alike), in the order "park first, then aim". **The three ICCCM focus
  models**: passive (a bare XSetInputFocus), locally active
  (input=True + WM_TAKE_FOCUS — the focus plus a ClientMessage after
  it; Java, older wine) and **globally active** (input=False +
  WM_TAKE_FOCUS — wine 10+): an invitation only, we do NOT set focus
  ourselves — the client answers with the invitation's timestamp, and
  any competing XSetInputFocus of ours would make that answer stale (a
  war won in fvwm3 — fvwm commit 6ec006d9c). The invitation's stamp is
  **asked of the server** at the moment of sending (`server-time` — a
  zero-length property append, the `gdk_x11_get_server_time` recipe),
  so it is newer than the last focus change by construction and no
  re-sends are needed at all. Recovery is event-driven: EWMH
  `_NET_ACTIVE_WINDOW` **requests** are honored (wine asks for
  activation again by itself); `::focused`, the highlight and the
  root's `_NET_ACTIVE_WINDOW` move only on a **confirmed** FocusIn
  (optimistic publication would drown out wine's own activation
  request), and the intent between invitation and answer is held by
  the `::invited` mark.

  **ICCCM iconification** (`WM_CHANGE_STATE` from a client is Tk's `wm
  iconify` and wine's Win32 minimize; plus `initial_state =
  IconicState` in WM_HINTS, i.e. "start me minimized"): the request
  always gets an ANSWER — either an honest iconification (`WM_STATE` =
  Iconic, `_NET_WM_STATE_HIDDEN`, the client unmapped, focus gone, the
  window STAYS managed) or an intelligible refusal (`refuse-iconify` —
  NormalState is re-asserted to the client; wine answers that with
  `SC_RESTORE`, so its Win32 side un-minimizes again). Ignoring the
  request is not an option: the asking side has often already
  minimized itself and stopped drawing, leaving the window hanging on
  screen (live report against wine, 2026-07-28). `_NET_WM_STATE` is
  published as a LIST of what is true about the window right now,
  rather than a literal per call: a minimized fullscreen window would
  otherwise lose its fullscreen mark, and a client re-reading the
  property on the way back would learn it had been taken out of a
  state we are still holding it in. Coming back is the client's own
  map, a pick in the winlist, or a panel button.

  Plus: the close machinery (WM_DELETE_WINDOW / XKillClient; the polite
  path with a check — still managed 2 s after the delete fires the
  "client is silent" policy hook); root ConfigureNotify as the signal
  of a screen-size change (RandR → policy hook); the synthetic
  ConfigureNotify (ICCCM 4.1.5); live title reading
  (`_NET_WM_NAME`/`WM_NAME` on PropertyNotify) — **in every WM_NAME
  encoding**: `UTF8_STRING` and `STRING` we decode ourselves (STRING is
  latin1 by the letter of ICCCM, but a client in the C locale puts raw
  UTF-8 there, so: strict UTF-8 first, then latin1), while compound
  text (ISO 2022 with designations — an xterm's Russian title arrives
  as ISO 8859-5 or as JIS X 0208 strings, depending on the client's
  locale) is handed to Xlib's own converter via `XGetTextProperty` +
  `Xutf8TextPropertyToTextList`; the process locale is not needed for
  this, verified under the C locale.

  Reading the client's icon (`client-icon` — `_NET_WM_ICON` → the best
  of the sizes inside → a nearest-neighbor downscale → a PNG assembled
  in pure Tcl on top of zlib → a Tk photo; cached per window,
  invalidated on PropertyNotify and unmanage). WM-initiated resize
  (`wm-resize-client`). The EWMH minimum **plus `_NET_FRAME_EXTENTS`**
  (the decoration's thickness per side: a client cannot measure it
  itself — its own geometry is INSIDE the frame — while toolkits use
  it to work out room for menus, popups and input-method hints;
  published at manage time and whenever the metrics change, and it can
  be asked for before the first map — a `_NET_REQUEST_FRAME_EXTENTS`
  from a still-frameless window gets the same honest numbers; the
  legacy twin `_KDE_NET_WM_FRAME_STRUT` is laid down next to it, which
  is what Qt4-era clients read).

  **And the outward half of EWMH** — what a client learns about the
  DESK rather than about itself: `_NET_CLIENT_LIST` (in order of
  arrival) and `_NET_CLIENT_LIST_STACKING` (bottom-up, read from the
  server and following every raise — wmctrl, xdotool and every pager
  live off these), `_NET_WORKAREA` (the screen minus our strips — the
  toolkits decide from it where a popup fits), plus the declaration
  that "there is one desktop" (`_NET_NUMBER_OF_DESKTOPS`,
  `_NET_CURRENT_DESKTOP`, `_NET_DESKTOP_GEOMETRY`,
  `_NET_DESKTOP_VIEWPORT`, and `_NET_WM_DESKTOP` on every window):
  silence here makes a client guess, and guessing is exactly what "the
  popup is in the wrong place" is made of. The list was assembled by
  **diffing the root window against fvwm3**; out of its set we
  deliberately leave only `_KDE_NET_SYSTEM_TRAY_WINDOWS` (the
  pre-XEmbed KDE tray) and `_MIT_PRIORITY_COLORS` (a relic of the
  colormap era).

  Restart in place (`TK9WM_RESTART` ClientMessage → release the clients
  → execv itself; fresh code off the disk, the same pid). The key-grab
  machinery (`wm-bind` — chord sequences with stumpwm semantics:
  XGrabKey on the first chord only, as a quadruple over Caps/Num; the
  tail runs under a temporary XGrabKeyboard, Esc or an unknown key
  aborts; re-grab on MappingNotify. `grab-keys-to` — keyboard modality
  for UI on top of that same grab, the router gets press AND release.
  `modifier-held` — is the modifier physically down, via XQueryKeymap —
  the fvwm alt-tab semantics rest on it).

  **The system tray (XEmbed)** — here we are the tray manager
  ourselves: taking `_NET_SYSTEM_TRAY_S<screen>` with a fresh server
  stamp, announcing `MANAGER` to the root, accepting
  `SYSTEM_TRAY_REQUEST_DOCK`, reparenting the icon into a policy-layer
  cell, `XEMBED_EMBEDDED_NOTIFY`, visibility by the `XEMBED_MAPPED` bit
  of `_XEMBED_INFO` (re-read on PropertyNotify — that is how a client
  hides and shows its icon), an imposed size (an icon's own
  ConfigureRequest is answered with the ICCCM synthetic), and the icon
  leaving on death, on a reparent away, or on losing the selection. Not
  one line of C was needed — precisely what the shim's escape hatches
  were made for. **Orphaned icons are collected on their own** (a scan
  of the root's children for `_XEMBED_INFO` at startup, BEFORE ordinary
  adoption — an icon that is not override-redirect would otherwise be
  given a titlebar): by the protocol a client is obliged to reconnect
  when it hears the `MANAGER` announcement, but Chrome does not, and
  loses its icon identically on a restart of tk9wm and of stalonetray
  (measured 2026-07-29) — so the tray goes and fetches them itself, and
  our restart no longer drops an icon.

  Two traps here, both unobvious. **Selecting `structure-notify` on
  our own owner window is mandatory** — a client sends its request
  with the mask it selected on that window itself, and the server
  delivers such an event to whoever selected ITS TYPES ON THE
  DESTINATION, propagating upward only if there is nobody at all (the
  asker is exactly such a somebody — the message was going to them,
  not to us). And **ARGB is deliberately not announced**
  (`_NET_SYSTEM_TRAY_VISUAL` is not set) — a CHILD window's alpha is
  blended by nobody, a compositor intercepts toplevels only, so the
  transparent part of an icon would show a black square; with no
  announcement the toolkit draws in the default visual over our cell's
  background — **except Chrome**, which makes a 32-bit window
  unconditionally, without asking about the announcement (0x100000d at
  depth 32 inside our 24-bit cell, with nm-applet at depth 24 right
  next to it and no black squares whatsoever; ParentRelative cannot be
  forced on such a window even as a kludge — across depths that is a
  BadMatch). So an icon's depth is **logged at dock time**, and a
  mismatch with the cell gets its own line with an explanation: one
  diagnosis for the price of one number. For clients like that there is
  the **`set-tray-argb on` experiment** — see the tray strip below.

  Calls the policy-* hooks.

- `library/policy.tcl` — our local decisions: decorations made of Tk
  widgets — a treectrl titlebar (an ellipsized title plus
  maximize/close buttons: white outlined squares with svg glyphs,
  fvwm-style, release-inside), a canvas backing with a 1px outline and
  light corner grips, titlebar height derived from font metrics
  (`TitleFont`, overridden by `TK9WM_TITLE_FONT`, changed live with
  `set-title-font`; title alignment via `set-title-justify`).

  **Per-client style rules on predicates** (`wm-style` — a predicate is
  a boolean proc over a client; every matching rule applies, later wins
  per key). The first key is `increments respect|ignore` (default
  respect: WM resizes and maximize snap to the client's grid). Then
  **`decor full|border|none`** — how much frame a window wears: the
  full thing, only the grip border without the title strip, or nothing
  at all (the frame is exactly the client; such a window cannot be
  grabbed with the mouse — move/resize from the keyboard). Then
  **`place`** — the geometry a window is born with, see below.

  **`filter`** — a declarative predicate for every match site (the
  `wm-style` rules, a panel button's `match`): `{filter -class {*
  Firefox} -title "Browser*"}` — options AND together, globs match the
  whole string and are **case-sensitive** (`-nocase` lifts that for
  the whole call; case matters by design: xterm is `{xterm XTerm}`,
  and the same xterm under `-name ninja` is `{ninja XTerm}`, so a
  nocase `-class xterm` would catch both). `-regexp` changes the
  comparator (`(?i)` in the pattern is nocase applied precisely); a
  single `-class` pattern matches either of {instance class}, a pair
  matches positionally as in xprop; `-command` is WM_COMMAND with a
  fallback to a local client's /proc argv; a property that is not there
  did not match. A proc predicate remains the escape hatch.

  **Placement in four rules** — the **style `place`** (which beats
  everything else, the client's own `-geometry` included: the config is
  the same user, having said this once and for all), the **client's
  position claim** (`USPosition` — the user's word, verbatim;
  `PPosition` — the program's word, clamped to the screen and with the
  notorious (0,0) ignored; gravity NW means the point aims at the
  frame, Static at the client area; the claim beats dialog centering
  too, and adoption respects it), dialog centering on the parent, and
  the cascade — plus shrinking a window that does not fit down to the
  screen (never below its declared minimum).

  **The `place` grammar** — a list of terms separated by spaces or
  commas, a term being `[N%]EDGE`, where the edge names both the axis
  AND the pull (`left|right|hcenter`, `top|bottom|vcenter`, `center` =
  both). A sized term sets size and pull along its axis; a sizeless one
  keeps the window's own size and only pulls. **An axis with no term is
  filled entirely** — which is why `50%right` is the right half at full
  height. `max` is an alias for the whole workarea and is also a STATE
  (the maximize button returns the window to the size it asked for, at
  its cascade place). Percentages are of the workarea and of the FRAME;
  increments bind placement the way they bind maximize (the slack goes
  to the un-pulled side); an unreadable term is logged and dropped.

  Honest move requests from claimants, live (`wm geometry +x+y`
  works). **wink** — the frame blinks red twice when a client stays
  silent on WM_DELETE_WINDOW for more than 2 s. The panel migrates to
  the screen's new bottom on RandR (200 ms debounce). Drag by the
  title; resize by the border and all four corners (a 6px grip,
  per-zone cursors, the opposite edge anchored).

  **A gesture on a modifier** (`set-drag-modifier`, default `<Super>`)
  — hold it and drag from anywhere on the window: button 1 carries,
  button 3 pulls the nearest corner, and for a window with `decor none`
  this is the ONLY mouse handle there is. The gesture does not reach
  the client (the taken press answers the grab with `async-pointer`
  instead of `replay-pointer`, or the window would travel along with a
  text selection inside it), and the dragging cursor is the GRAB's
  cursor — the only way to show one over somebody else's window.
  **The root cursor** (`set-root-cursor`, default `left_ptr`) — the
  server leaves the ancient X_cursor on the root, and by tradition it
  is the WM that sets a normal one, not xsetroot by hand.

  Maximize with fvwm semantics (a workarea proc; resize and move do not
  clear it, a second toggle restores what was saved). **Fullscreen** on
  a client's EWMH request (`_NET_WM_STATE_FULLSCREEN`) — stronger than
  maximize, and deliberately so: it takes the whole SCREEN rather than
  the workarea, the decoration comes off, the panel and the tray go
  UNDER the window and do not resurface on their own rebuilds, size
  hints do not bind, and the client's own ConfigureRequests are refused
  wholesale for the duration of the state (a terminal rounds itself to
  whole cells on a font change — yielding would have left a strip of
  desk down the side). Its saved geometry is its own, separate from
  maximize's, and there is a winops menu entry as a way out if the
  client will not let the state go.

  Click-to-focus. A window is glued to its transients into one layer
  (raise/lower as a group, by relative sibling restacks — a leader
  never flashes over its own dialog, and a repeat raise of something
  already raised is a server-side no-op). Refocus after a close (a
  dialog's leader → the focus history).

  **Popup menus on treectrl** (keyboard through `grab-keys-to`, the
  mouse left free; navigation with Up/Down, k/j and p/n — where an
  entry's hotkey has not taken the letter — and Ctrl+P/Ctrl+N
  unconditionally): **winops** — the window action menu, which is the
  **window commands** below with a hotkey letter apiece rather than a
  list of its own. **bury** is lower, except the focus
  does not stay on the lowered window: it goes to whatever that
  uncovered. The candidates are read TOP-DOWN in the server's stacking
  order, and the first one whose frame genuinely intersects the buried
  group wins — a window that shared not one pixel with it was never
  "under" it, however recently it was focused; if nothing intersects,
  the topmost is taken; if there is nobody at all, focus stays where it
  was. The menu drops from the top-left corner, and the titlebar has a
  menu button of its own on the left.

  **Window commands** are those actions as a vocabulary — `Minimize`,
  `Maximize`, `Fullscreen`, `Move`, `Resize`, `Raise`, `Lower`, `Bury`,
  `Close`, `Destroy`, plus `Unmaximize` and `Unfullscreen`. `Restart`,
  `Reload` and `Quit` are about the desk rather than a window (the
  lowercase `restart-wm` and `reload-config` remain, being the
  implementations). **`Quit` is bound by default**, to `Super+t q`,
  and releases every client back to the root alive before stopping —
  with `.Xsession` exec'ing the window manager that ends the session,
  and a desk whose only exit is another terminal and a `kill` is the
  "how do I exit vim" joke with a login inside it. They are
  Capitalized against the rest of the
  config language, which is lowercase and declarative: a capital says
  this one *acts*, now. It also buys the names outright — `raise`,
  `lower`, `close` and `destroy` are Tcl's and Tk's, and a lowercase
  vocabulary would have had to spell four of the ten differently.

  Each takes its window as an optional argument and, without one, asks
  the context — so one definition serves a key binding, the menu, and a
  sweep alike:

  ```tcl
  wm-bind {<Ctrl><Shift>z} Minimize                    ;# the active window
  wm-bind {<Super>d} {Apply-To-Matching always Minimize}
  wm-bind {<Super>c} {Apply-To-Matching {filter -class Chromium} Close}
  ```

  `Apply-To-Matching PREDICATE COMMAND` runs one over every window a
  predicate accepts — the same predicates style rules and a panel
  button's `match` take, so there is one matching language and not two.
  It takes a **snapshot** first (these commands unmap and close
  windows, so the live set is a list the body would be editing), walks
  it most-recently-focused first (a hash order would land differently
  every run), and lets nothing abort it: a client whose style refuses
  minimization stays up without costing the windows after it, and one
  that dies mid-sweep is skipped. Nothing is bound to it by default — a
  desk-wide sweep is not something to discover by accident.

  **The WM's own windows** (`wm-window`) wear the same decoration every
  client wears — the same border and grips, the same titlebar font and
  colors, restyled by the same config knobs — and the confirmation on
  `Quit` is the first one built on it. They are override-redirect, and
  that is forced rather than chosen: our own windows are the one kind
  our redirect cannot catch, since SubstructureRedirect turns a child's
  map into a MapRequest for whoever selected it EXCEPT when the window
  is override-redirect or the client asking is the one that selected
  the redirect — and we are always that client. Measured, not assumed
  (`tools/probe-selftoplevel.tcl`): a plain toplevel from this process
  maps straight to the root, bare, and no MapRequest ever arrives. The
  WM could reparent its own window into a frame by hand, but then its
  dialog would be one of its own clients — listed in the window list,
  published in `_NET_CLIENT_LIST`, and swept up by `Apply-To-Matching
  always Minimize` with everything else. Drawing the decoration around
  an override-redirect toplevel costs nothing instead: `deco-draw`,
  `frame-layout` and the titlebar drag never needed a client, and the
  slot they wrap is an ordinary Tk frame — for a client it is what gets
  reparented into, and here it is simply where our widgets go.
  Keyboard comes from `grab-keys-to`, the router the menus use.

  That router is also what fixes the scope. A grab suits something
  **modal** — answer it or dismiss it, nothing else meanwhile — and
  suits nothing else, because a window meant to sit on the desk while
  you work wants ordinary focus, which an override-redirect window
  cannot have. The answer there is not to imitate focus but to stop
  being a WM window: a Tcl **thread with its own Tk** opens its own X
  connection, which makes it a different client to the server, so the
  redirect catches its windows and they are framed like anybody
  else's — focus, alt-tab, minimize and all (`tools/probe-threadgui.tcl`
  comes up fully decorated). It also means a form that blocks cannot
  freeze the desk, the WM's event loop not being the one running it.
  So: modal, short-lived, must not be a client → `wm-window`; complex,
  long-lived, wants to behave like a window → a thread and a real
  connection.

  **A user toggles, a program does not** — Emacs's
  `called-interactively-p`, and here for the same reason: one name
  should mean the obvious thing in both mouths, and the obvious thing
  differs. Pick `Maximize` off the menu over a maximized window and you
  plainly mean the other way, because you are looking at the window
  while you say it; press your own key twice and you mean the same. But
  `Apply-To-Matching always Maximize` means *make this desk maximized*,
  and a toggle there would un-maximize precisely the windows that were
  already right — a sweep whose result depends per window on the state
  it happened to find is a coin toss, not a sweep. So `Maximize` and
  `Fullscreen` toggle when you ask and force when a sweep asks;
  `Unmaximize` and `Unfullscreen` never guess. Interactive is the
  default, and the only thing that declares otherwise is the code that
  drives other commands.

  **minimize** takes the same path as a client's own request
  (`set-minimize iconify|refuse` — default iconify, overridden
  per-client by the `minimize` style key). With wine, a window that has
  been round the full iconify circle comes back active but with its
  INTERNAL focus lost — keys land in the main window, work as menu
  mnemonics and never reach the input field; it reproduces under fvwm3
  too, so the defect is wine's, and for `-class {*.exe *.exe}` a
  refusal is more honest than a half-dead window. A minimized window is
  shown in the winlist with its title in `[brackets]` — the way twm and
  fvwm have marked an iconified entry since the eighties — and picking
  it there brings it back, as does a panel button with a matching
  `match`.

  **Keyboard move/resize** — a modal mode on that same key router:
  arrows (and hjkl) move the frame or change the size (a 10 px step,
  Shift = 1 px, Ctrl = 50 px; resize steps by the client's increment
  when that is a real grid rather than a degenerate 1x1),
  Enter/space commits, Esc reverts to the geometry the mode was entered
  at. **The mode is visible:** for its whole duration the frame turns
  amber (a modal grip color on a par with the focus ones) and the
  titlebar lends its text to a live readout — `move +131+90` while
  moving, `resize 484x316 (80 x 24)` while resizing (client units in
  parentheses when it has a real grid). On commit and on revert both
  the color and the title come back; a client that renames itself
  mid-mode does not disturb the readout, it only changes what will be
  restored.

  **winlist** — the window list in MRU order, the initial selection on
  the second entry, entries **numbered 1-9/A-Z with the number as a
  hotkey** (instant pick; in cycle mode a held modifier is transparent:
  Alt+3 is hotkey 3, since you cannot let Alt go for a bare digit — the
  menu would close by committing). Every entry has an **icon**, from
  these sources in order of seniority: the config's `icon` style key
  (the user's word beats the client's), the client's own
  `_NET_WM_ICON`, or else a **pseudo-icon** — one or two letters of the
  class (of the title, where there is no class) on a colored badge, the
  color a stable hash of that same name (the trick from Telegram's
  contact list). Opened by a chord with the modifier still held, it is
  **fvwm alt-tab**: Tab runs down the list with wraparound (Shift+Tab
  back), releasing the modifier switches, a quick Alt+Tab toggles to
  the previous window (`set-winlist-cycle off` turns that off). The
  default bindings are in the code: winops on `<Alt>space` and
  `<Super>t w m`, winlist on `<Alt>Tab` and `<Super>t w w` (the static
  one — a sequence that ends with the keys released).

  **The panel** — a treectrl strip of our own along any of the four
  edges (`set-panel-side top|bottom|left|right`: only the orientation
  and the band's geometry change — the button logic does not see the
  side). It exists only when the config declares buttons
  (`panel-button LABEL {match … launch … icon … key … style …}`), and
  there can be **more than one**: `panel NAME BODY` declares a named
  instance, and everything said outside such a block belongs to the
  one named `default`, so a config that never heard of the plural
  keeps working. Each panel carries its own side, preset, icon size
  and buttons — a dock down the left edge beside a bar along the
  bottom is two declarations and no coordination. **`style` is a shortcut**: the same settings go into `wm-style`
  under this button's own `match` predicate, so one filter need not be
  written twice nor hoisted into a proc for the sake of a single
  repeat; the rule takes its place in the list at the button's point of
  declaration, so priority reads top-down through the config, and a
  `style` with no `match` is an error. A button is **idempotent,
  wmaker-fashion**: a click or a chord focuses the most recent window
  found by the `match` predicate, and failing that runs the `launch`
  script, with the button flashing its verdict (green "found" / orange
  "launching").

  The `icon` value (both on panel-button and on the winlist style key)
  is **polymorphic** through `resolve-icon`: a Tk image name goes
  through as is, a file path is any photo format (pointing at a .svg is
  the user's deliberate choice), a bare name is looked up as
  `name.png` through the `set-icon-path` directories (default: the
  user's and the system's hicolor 48x48 plus pixmaps; **png only** — we
  do not slip nanosvg in by ourselves), an oversized one is downscaled
  nearest-neighbor with alpha (the same rgba-png trick as client-icon),
  cached per {spec, size}, and a miss is a line in the log and the
  regular "no icon" look.

  **The panel's geometry is precomputed** at every (re)build: while no
  button's face has resolved to an icon, it stays the old thin text
  strip (backward compatibility); once one has, the strip grows to the
  icon square (`set-panel-icon-size`, default 48 for the hicolor
  stock), and icon-less buttons get an **auto-badge** (the label's
  letters on a crc32 color — the same trick as the winlist
  pseudo-icons), so a mixed panel keeps one height. An icon button's
  layout is the `set-panel-preset row|stack` preset (`row` is "icon
  text", `stack` puts the caption under the icon — the look for a thick
  bottom strip or a narrow side one).

  A button with a **live matched window** says so continuously: an
  indicator bar along its bottom edge plus a light tint on the face
  (the same state machinery as the flash feedback, only without the
  timer; `set-panel-live-colors BAR FACE` recolors it). Along each
  button's eastern edge an **arrow zone** is reserved (the strip
  appears as soon as the panel has even one match button — the row
  reads uniformly, and an unarmed button simply has calm emptiness
  there); with more than one match a separator line and an arrow are
  drawn in the zone, and **the whole strip** is clickable: a click
  drops a winlist filtered down to the matches and anchored at the
  button (MRU, icons, number hotkeys — the shared machinery), and a
  pick focuses. A click on the body is the old idempotent shot at the
  most recent one. Matches are re-evaluated on manage/unmanage and on
  every title change (a change can flip a `-title` matcher), debounced
  as the RandR rebuild is. Every raise-group ends by raising the
  panels to the top — StaysOnTop for the poor, until there are layers.

  **Strips and the workarea.** Everything glued to an edge — a panel,
  the tray riding on one — reserves a BAND across that edge, and the
  bands are carved out of the screen **in declaration order**: each
  strip takes its band from what the strips before it left, and what
  survives the last carve is the workarea (maximize and the placement
  of new windows stop there). So the corner between two edges belongs
  to whichever panel was declared first — a config steers the corners
  by the order it writes its panels in, and nothing has to negotiate
  at run time. The workarea is a RECTANGLE and not a size: a panel on
  the left or the top moves its ORIGIN, which is why placement clamps
  and the cascade count from that corner rather than from the
  screen's.

  **The tray strip** (`set-tray on`, off by default, as the panel is) —
  a row of square cells at the FAR end of its panel's band (the right
  end of a horizontal bar, the bottom end of a vertical one), in an
  override-redirect toplevel of its own: a panel rebuild destroys the
  strip whole, and somebody else's icon inside it would go down with
  it. Which panel is a knob — `set-tray-panel NAME`, default
  `default` — and it decides the tray's edge, its orientation and the
  band it shares; a tray on a panel nobody declared is the panel-less
  case, and the band is then the tray's alone. A cell is an ordinary frame, and its **background** is what shows
  through the transparent parts of an icon (the whole story of "why is
  my icon on a black square": `set-tray-background` paints it,
  `set-tray-icon-size` sizes it, default 24). The workarea cutout is
  shared with the panel (one edge, thickness the larger of the two),
  and the panel's button row is shortened by the strip's length so that
  no button hides under an icon.

  **`set-tray-argb on`** is the experiment for stubborn clients like
  Chrome: the strip becomes a 32-bit toplevel and we announce that
  visual, so the toolkit draws the icon with alpha. Two things are
  required for it, both ours: a cell of the same depth (only then is
  ParentRelative legal) and a **backing** — an ordinary opaque toplevel
  of exactly the same geometry, laid directly under the strip. The
  backing is not decoration but a measured necessity: the transparent
  parts of an icon have alpha ZERO in the strip's composited pixmap,
  and the compositor honestly shows what is behind them — the wallpaper,
  through an icon-sized hole. Neither ParentRelative (in ARGB mode the
  toolkit puts its own transparent background over ours) nor painting
  the strip itself saves this, because the icon's window covers the
  cell entirely and a child's pixels replace the parent's in that
  pixmap. With the backing, the holes show the tray color and the
  icon's antialiased edge blends against it. It needs a running
  compositor and is therefore off by default
  (`tests/run-trayargb-test.sh` measures it under compton).

  Implements the policy-* hooks (the contract is in substrate.tcl's
  header).

- `library/main.tcl` + `tk9wm.tcl` — the assembly. `main.tcl` is the
  **config** layer plus `tk9wm-main`; `tk9wm.tcl` is the entry script
  that finds the package and calls it. The config is ONE Tcl file,
  sourced after both layers are in and before the first window is
  managed — the user's `~/.config/tk9wm.tcl` (XDG_CONFIG_HOME
  honored), or `library/default-config.tcl` from the project when
  there is none. The project file is a commented example and
  deliberately NOT load-bearing: every default lives in the code, so a
  two-line user config ("bold titles, that's all") starts from exactly
  the stock behavior — it overrides, it does not rebuild. A broken
  config is logged and skipped: a WM that dies on a typo in its config
  locks the user out of the very session that would let them fix it.

  **Re-reading the config on a live desk** — `reload-config`: the
  chord `Super+t w r` (the default, in code) or the `TK9WM_RELOAD`
  ClientMessage (`tools/send-reload.tcl`). No restart, and not one
  client disturbed: windows, frames and focus stay where they are, and
  only what the config made is swept away and laid out afresh. The
  mechanism is "everything configurable goes back to the CODE's
  defaults, and the config draws on the clean floor", exactly as at
  startup. The defaults are not written down twice: they are
  **snapshotted** off the code itself a moment before the config is
  first read (`policy-snapshot-defaults`), so there is nowhere for them
  to drift apart from reality. The price is **the config's contract:
  it is declarative.** Pulling `set-*` knobs, declaring buttons, style
  rules and bindings is allowed (the reset knows where that state
  lives); redefining policy/substrate procs is not — the reset has
  nothing to undo a patch with, and the next reload would build on top
  of it. The config's own procs (predicates, launchers) survive the
  reset — they are just names, and the config redefines them every
  time. A broken config leaves the desk on defaults plus whatever it
  managed to set before it threw — the same rule as at startup, and
  the reason the reset goes FIRST: a config that fails must not be able
  to leave the previous one's settings half-standing.

**The synthetic ConfigureNotify (ICCCM 4.1.5) is sent on events, not on
timers:** at manage time, on the client's `MapNotify`, on **every**
`ConfigureRequest` (including one that was not satisfied — otherwise
the client believes it was moved), and on every step of a frame drag.
A copy goes to the **frame window** as well: a client is entitled to
expect a real ConfigureNotify there (Tk does; see `send_for_frame_too`
in fvwm).

## Running

Any Tcl/Tk 9 interpreter with treectrl, plus the shim (built here, or
compiled into the interpreter — see Building).

```sh
tests/run-xephyr.sh [display] [WxH]
```

is the live playground: tk9wm inside a Xephyr window on a real desktop
(`:7 1280x800` by default) — `Xephyr -noreset` → `xrdb -merge
~/.Xresources` → the WM → xterm and xclock (the clients start last, so
they pick up the resources, DPI included).

The test harness expects a sibling whalebuild checkout
(`../whalebuild/work/linux/whale`); `WHALE`, `WHALE_CLI` or `LINUX`
override it — point them at a stock tclkit or a system wish to run the
suite on another host. All of it lives in `tests/common.sh`.

## Tests

**The shim's own batteries** (`tests/tkwmx/`) are headless and need no
window manager at all — any Tcl/Tk 9 will host them:

```sh
make test                              # or, one at a time:
xvfb-run -a wish9 tests/tkwmx/props.tcl
```

`props.tcl` is the property battery: the write/read/delete round trip
for formats 8 and 32, the typed getters (text with its encoding ladder,
class, hints, normal-hints, protocols, transient) against a live Tk
toplevel, and — the half that is easy to get wrong — a window that died
under us answering `{}` instead of taking the process down with an X
error. Note what the battery has to do to find its subject: Tk keeps a
toplevel's WM properties on a WRAPPER window, which is the PARENT of
`winfo id` (and `wm frame` does not point at it either, since with no
WM nothing was reparented). A window manager sees wrappers, so the
tests ask `tkwmx::window tree` for the parent and work on that.
`events.tcl` covers the redirect and its dispatch, `wm.tcl` the rest of
the transport (focus, grabs, keyboard, pointer, the manager selection,
configure-by-mask, restacking).

**The WM regressions** live in `tests/`; each raises its own Xvfb and
runs as a single shell call:

- `run-demo.sh` (the full cycle plus screenshots), `run-adopt-test.sh`
  (picking up windows that predate the WM), `run-focus-test.sh`
  (hover-typing, the death/withdraw of the focused window, an external
  PointerRoot reset), `run-withdraw-test.sh` (withdraw/deiconify
  without the client dying), `run-dialog-test.sh` (a dialog with
  `WM_TRANSIENT_FOR` on a cramped screen: centering on the parent,
  clamping to the screen, `WM_STATE`), `run-gtk-test.sh` (the GTK3
  canary, zenity), `run-refocus-test.sh` (closing a dialog returns
  focus to the leader; a window's death, to the most recent by
  history), `run-stack-test.sh` (transients glued to the leader: a
  click on the leader does not bury its dialog; plus **bury** from
  winops — the group goes down and the focus lands on the window it was
  covering, NOT the topmost: a fourth window is seated in a far corner
  touching nothing, raised above the group, and the "topmost" rule
  would have picked exactly it).
- `run-title-test.sh` (the titlebar follows the client's renames; plus
  three WM_NAME encodings — compound text in ISO 8859-5 and in JIS X
  0208, and raw UTF-8 under type STRING — all three yielding one
  title), `run-resize-test.sh` (drags by the edges and corners on all
  four sides — the frame is uniformly grip-thick all round; a drag by
  the title; a drag started on the root is a noop), `run-size-test.sh`
  (honest sizes: a raw client with no ConfigureRequest, a declared
  minimum against a shrinking drag, an over-wide window squeezed to the
  screen), `run-button-test.sh` (maximize → workarea → restore; close
  sends WM_DELETE_WINDOW), `run-restart-test.sh` (restart in place: the
  same pid, the client picked back up), `run-config-test.sh` (config
  resolution XDG → default-config; the default snaps a wm-grid client's
  drag to its increments, the dev preset — ignore plus a bold centered
  title — gives back the raw size).
- `run-quit-test.sh` (the way out: `Super+t q` ends the window manager,
  and the client it was framing is still alive, still on screen and
  handed back to the root — a quit that took its clients along would be
  worse than none), `run-sweep-test.sh` (window commands and the sweep, from one config:
  a bare `Minimize` bound to a chord takes the ACTIVE window out of
  context and touches nothing else, then `Apply-To-Matching always
  Minimize` takes the rest — while the one client whose style refuses
  stays up, says so, and does not cost the windows after it), and
  `run-key-test.sh` (winops on Alt+Space: the hotkey x toggles maximize
  twice, navigation Ctrl+N/n/p/k/j + Enter fires raise; fvwm alt-tab: a
  quick Alt+Tab toggles to the previous window, a second Tab with Alt
  held wraps the selection, Alt+2 picks an entry by number without
  releasing Alt; the static list on `Super+t w w` with a bare number
  hotkey; the sequence `Super+t w m` opens winops through prefix grabs;
  an abort on an unknown key does not break the machinery),
  `run-icon-test.sh` (winlist icons from all three sources at once: a
  client's `_NET_WM_ICON` is read and downscaled, a config style rule
  overrides it, an icon-less client gets a pseudo-badge; the number
  hotkeys work with an icon column too), `run-panel-test.sh` (the
  idempotent button: on an empty desk the chord launches a client, with
  one alive it focuses it both by chord and by mouse click, taking
  focus away from a distracting window; maximize stops above the
  panel's strip).
- `run-transient-test.sh` (a late `WM_TRANSIENT_FOR`: a window with no
  leader aims at one after its map — its death gives focus to the
  leader, not to the history), `run-wink-test.sh` (silence on
  WM_DELETE_WINDOW: a stubborn client gets a wink, one that closed in
  time does not), `run-randr-test.sh` (the WM inside a resizeable
  nested Xephyr; shrink the screen and the panel follows the bottom),
  `run-place-test.sh` (the position claim: adoption preserves the
  corner, -geometry verbatim, hint-less windows cascade, a late move
  request is honestly carried out, a dialog's own +x+y beats
  centering).
- `run-style-test.sh` (the window's shape from its style, on a desk
  with a panel — that is, percentages of the workarea: `max` fills it,
  and the maximize button returns the window to a geometry it never
  had; `30%bottom,50%right` beats the client's own `+500+50`; a panel
  button's `style` shortcut gives the right half with no frame at all —
  extents 0; sizeless terms pin the window into a corner at its own
  size; `decor border` keeps the border and drops the title; an
  unreadable term is logged and does not stop the window opening),
  `run-drag-test.sh` (the gesture on a modifier: super+button 1 carries
  the window and does NOT reach the client — the reporter client stays
  silent, while the same drag without the modifier does not move the
  window and IS heard by the client; super+button 3 pulls the nearest
  corner; an undecorated window (`decor none`) moves by this gesture
  alone; the root cursor is accepted), `run-kbmove-test.sh` (keyboard
  move/resize from winops: arrow steps with Shift precision, the Enter
  commit, the Esc revert; the frame color is sampled by a pixel on the
  boundary during the mode and after it, the readout in client units on
  an xterm).
- `run-iconify-test.sh` (iconification: the client's request is
  honored for real — Iconic plus unmapped plus `_NET_WM_STATE_HIDDEN`,
  and the winlist brings the window back mapped and focused; a second
  phase with `set-minimize refuse` — a refusal out loud and the window
  still up), `run-filter-test.sh` (an in-process battery for the filter
  predicate against a live xterm and a whale client: whole-string globs
  and case (including the drift that stopped nocase being the default),
  `-nocase`, a single and a positional `-class`, `-regexp` with `(?i)`,
  an absent property meaning no match, the WM_COMMAND → /proc-argv
  fallback on a client decorated by xprop, filter inside a wm-style
  rule and inside a panel button's match), `run-iconpath-test.sh`
  (resolve-icon: a bare name out of the icon path is downscaled to the
  target, the cache hands back the same image, an explicit path, a Tk
  image passthrough, something small is not stretched, a miss and an
  svg decoy both give nothing with one log line, a style icon through
  winlist-icon, a panel button carrying its resolved icon).
- `run-panelgeo-test.sh` (the panel's geometry: mixed iconness grows
  the strip to the icon square and hangs an auto-badge on the icon-less
  button; `set-panel-side` puts the strip on any of the four edges with
  the workarea cut there (maximize runs into it — and a left or top
  strip moves the workarea's origin, which `run-panels-test.sh` checks
  against a two-panel desk);
  `set-panel-preset stack` puts the caption under the icon;
  `set-panel-icon-size` re-aims both the geometry and the resampling),
  `run-panellive-test.sh` (the live button: an empty desk is dark, one
  match is live with no multi and no separator, two are multi with a
  separator, a click on the edge of the arrow zone opens the filtered
  winlist in MRU order and picking the second focuses the older window,
  unmanage puts multi out, a client renaming itself flips the `-title`
  matcher both ways),
  `run-panels-test.sh` (panels in the plural: a `panel NAME BODY` dock
  on the left declared before the stock bottom bar, so the dock owns
  the corner and the bar starts where it ends; the workarea is what
  both of them left; buttons, the live judgement and a fire each reach
  their own panel and no other; a window is born inside that workarea
  and maximize fills it corner and all; a list anchored by the left
  dock opens beside it; the tray follows the panel it is told to ride;
  and a panel moved to another edge re-carves every band).
- `run-tray-test.sh` (the system tray: the selection is taken, two
  clients (`tray-client.tcl` on `tk systray` — the control client is in
  the kit itself, zero external dependencies) dock by icon, both really
  sit inside OUR cells and are held at 24x24, the strip stands in the
  corner at the panel's thickness and shrinks when a client kills its
  icon; on the screenshot a circle with transparent corners lies on the
  strip's color — not on black; the final phase is a restart in place —
  the surviving client's icon is picked up by the new instance as an
  orphan, with no action whatsoever from the client),
  `run-trayargb-test.sh` (the ARGB tray experiment under compton, with
  two clients — Tk's systray and a GTK3 `GtkStatusIcon`
  (`tray-client-gtk.py`, which is exactly what Chrome's status icon is
  on Linux): both take the announcement and make 32-bit windows, the
  strip reads in its own color, and an icon's transparent corner shows
  THE TRAY'S COLOR rather than a hole into the desk — by pixel probes
  on the screenshot. The Tk client leaves a square of litter around its
  circle: its systray does not clear its own offscreen pixmap in ARGB
  mode — a Tk defect, not ours, and the GTK client does not have it).
- `run-reload-test.sh` (re-reading the config on a live desk: three
  configs in a row on one instance — a rich one, a DIFFERENT one and an
  empty one. The panel is rebuilt from the new config and stands on the
  default edge although the second config says nothing about the edge;
  the old chord dies and the new one works; the tray icon comes back
  into a cell of the restarted tray; the empty config leaves neither
  panel nor tray, the workarea is the whole screen again, and the icon
  is handed to the root rather than killed; the client is alive and
  untouched through all of it), `run-ewmh-test.sh` (the outward half of
  EWMH: the client list in arrival order and the stacking list
  bottom-up which follows a raise while the arrival list does not;
  `_NET_WORKAREA` shortened by the panel's strip; "one desktop"
  declared; `_NET_WM_DESKTOP` and the KDE strut on the window; the list
  empties as the clients go).
- `run-fullscreen-test.sh` (EWMH fullscreen on LIVE clients: the atom
  is advertised in `_NET_SUPPORTED` — without it xterm and kitty,
  measurably, ask for nothing at all; a window asked from outside takes
  the whole screen and by pixel on the screenshot really covers both
  the panel and the tray, and a fresh icon docking does not lift the
  strip back up; leaving restores the exact geometry and removes the
  atom from the property; a window that asked BEFORE its first map
  (`fs-client.tcl`) is framed fullscreen at once; `xterm -fullscreen`
  and `kitty --start-as fullscreen` come up fullscreen by themselves),
  `run-extents-test.sh` (`_NET_FRAME_EXTENTS`: a framed window has the
  property and it matches the decoration's metrics, while a frameless
  window that asked `_NET_REQUEST_FRAME_EXTENTS` before its first map
  gets the same numbers).
- `run-emptydesk-test.sh` (the chord wedge on an empty desk: after the
  last window dies the focus reverts to None, and with None the server
  activates no passive XGrabKey at all — the WM is obliged to park
  focus on the holder window; the chord and the panel's launcher both
  fire on a desk emptied after a window's life, and the desk itself
  rests on the holder, NOT on PointerRoot), `run-takefocus-test.sh`
  (ICCCM WM_TAKE_FOCUS: a client that declared the protocol gets the
  ClientMessage both on the manage focus and on an alt-tab return —
  without it wine was left with a dead keyboard until a click; one that
  did not declare it never gets one).
- `run-gafocus-test.sh` (globally active, the wine 10+ model: the
  control client `ga-client.tcl` with input=False answers every
  invitation with an XSetInputFocus carrying the invitation's
  timestamp, and bumps the focus time after every honest answer — all
  answers honored, not one made stale by a competing focus op of the
  WM's, keys flow after the second return, the WM never set focus
  itself, and `_NET_ACTIVE_WINDOW` ends on the ga window),
  `run-gastart-test.sh` (the manage-invitation wedge, two rounds:
  typing into somebody else's window makes any accumulated clock stale,
  and yet the manage invitation is honored **on the first try** — the
  stamp was taken from the server; a stubborn client that rejects the
  invitation recovers through its own `_NET_ACTIVE_WINDOW` request,
  like a real wine. That no re-sends happened is checked separately),
  `run-gareset-test.sh` (the live :7 bug: an external focus reset to
  PointerRoot — exactly what Tk's implicit focus does on LeaveNotify —
  which the WM is obliged to notice, park on the holder and re-aim;
  both paths are checked (globally active and an ordinary client), that
  no answer went stale, that keys flow, and that `_NET_ACTIVE_WINDOW`
  agrees with the real focus).

**Live-display diagnostics** (`tools/`, read-only, any display):
`probe-focus.tcl` — a snapshot of the focus; `probe-watch.tcl` — a
watch on focus changes; `probe-trace.tcl` — what is under the pointer
and where the focus went, a line per change; `probe-at.tcl` — the chain
of windows under a pixel (pixels lie, the tree does not);
`probe-stack.tcl` — the root's children bottom-up, each annotated with
what its subtree holds (who is over whom, frame → client);
`probe-grab.tcl` — is anybody holding a passive grab on a window;
`probe-pointer.tcl` — is the pointer frozen by somebody else's sync
grab; `set-focus.tcl` / `set-pointerroot.tcl` — outside influence on
the focus; `send-restart.tcl` — ask a live WM to restart in place (to
pick up fresh sources: release the clients, then execv itself).
`spike/` is the historical root-redirect spike.

**A live-Xephyr trap:** after the Xephyr window is interactively
resized the screen grows (RandR) but **XTEST stays boxed into the
starting rectangle** — a synthetic pointer (`xdotool`) runs into the
old boundary while a live mouse goes everywhere. So headless driving of
such a session lies: set the final size up front (`-screen WxH`) and do
not resize the window.
