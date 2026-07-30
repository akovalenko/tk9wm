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

# the CONTAINER build — usable only INSIDE the box: its tclConfig.sh
# records the paths as seen there (-I/w/work/linux/install/include),
# so a host compile fails on a missing tcl.h. In the box the same
# line is the right one — see the kit build below.
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

## As a kit: one file on a stock tclkit

The other end of that: no whale, no toolchain, nothing installed — the
window manager, its shim and treectrl wrapped into a single file that
runs on a stock **tclkit**. Both sdx forms are built by `kit/`:

```sh
WHALEBUILD=../whalebuild ./kit/so.sh          # the binary parts
TCLKIT=…/tclkit-9.0.4-Linux64-intel-tk SDX=…/sdx.kit ./kit/mkkit.sh
TCLKIT=… ./kit/smoke.sh ./kit/tk9wm.bin       # …and prove it runs
```

- `kit/tk9wm.kit` — a **starkit**: `tclkit tk9wm.kit`, ~1.7 MB.
- `kit/tk9wm.bin` — a **starpack**: `./tk9wm.bin`, ~7 MB, needs nothing.

The two shared libraries inside are built **in whalebuild's container
box** (`kit/so.sh`), and that is not only about the old glibc floor:
the Tcl/Tk install tree an extension links against bakes ABSOLUTE paths
into `tclConfig.sh` at core-configure time, so an extension configured
against the box's tree from outside the box gets a `-L` pointing at
nothing. treectrl is built by whalebuild itself (`cbuild.sh linux so
treectrl` — it owns the pinned source, the patches and the index); the
shim by our own `./configure`, run in the same box against the same
tree. Loading either out of the kit's VFS is the core's business: Tcl
copies a shared library to a temporary file and loads that.

`kit/smoke.sh` is the honest check rather than a formality — it puts up
a real desk on a throwaway Xvfb with a panel in the config, because a
panel is what pulls treectrl out of the kit's own `lib/`: a run that
frames a client and shows a panel has proved both libraries loaded.

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
  aborts; re-grab on MappingNotify; a running sequence reports itself
  through `policy-key-echo`. `grab-keys-to` — keyboard modality
  for UI on top of that same grab, the router gets press AND release.
  `modifier-held` — is the modifier physically down, via XQueryKeymap —
  the fvwm alt-tab semantics rest on it. `x-group` — read the xkb group
  as `{locked effective}`, or lock the keyboard into one; nothing here
  uses it yet, and it is deliberately not what a chord is looked up by,
  but a desk that wants to show or choose the layout — an indicator, a
  switch key, per-window layouts — needs exactly this).

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

  **Placement in four rules** — the **client's position claim**
  (`USPosition` — the user's word, honored as given and clamped only to
  the SCREEN; `PPosition` — the program's word, clamped to the workarea
  and with the notorious (0,0) ignored; gravity NW means the point aims
  at the frame, Static at the client area; the claim beats dialog
  centering too, and adoption respects it), the **style `place`**,
  dialog centering on the parent, and the cascade — plus shrinking a
  window that does not fit down to the screen (never below its declared
  minimum).

  A `place` **yields to the window's own `-geometry`** and outranks
  everything below it. A rule is the user speaking in general; a
  `-geometry` is the same user speaking about *this* window — and the
  particular wins (owner's call, 2026-07-30, reversing the day-old rule
  that a rule beat everything: with `place max` as a standing policy for
  half the desk, a rule that also overrode every `-geometry` leaves no
  way to ask for anything else).

  It yields **aspect by aspect**, because `-geometry` is two claims and
  X flags them separately. Said how big (`USSize`) → the rule's sizes
  drop and its terms go **sizeless**: it may still pull the window to
  the edge it names, at the size that was asked for. Said where
  (`USPosition`) → the rule's position drops; it may still say how big.
  Both → the rule has nothing left to say. An all-or-nothing yield read
  `xterm -geometry 20x20` as no claim at all and placed it exactly like
  a bare xterm, 20x20 and everything thrown away (owner's report, same
  day). Only the US forms: the P forms are the program's own idea, which
  it has for every window whether it thought about it or not. `force` in
  the spec is how a rule says it means it anyway.

  **Which flags a toolkit actually sets** is not guessable and was
  measured (2026-07-30): `xterm -geometry 20x20` sets `USSize` alone,
  and xterm stamps `USSize` whenever `-geometry` is present *at all* —
  `-geometry +300+200` claims both. Tk's `wm geometry` sets `USPosition`
  and **never** `USSize`, whatever the string carried. Qt Creator sets
  both, plus `StaticGravity`, from its own restored geometry — so
  `USPosition` in the wild means "the app remembers where it was" at
  least as often as "the user typed it", and nothing in the protocol
  distinguishes them. The WM logs the claim it read (`WM: 0x… claims
  +0+-2 — USPosition, gravity Static`) because the property is the
  app's to change at any moment and `xprop` by click lands on the
  frame, which on this desk is a Tk toplevel carrying hints of its own.

  **What `+0+0` is the corner of** is the screen, not the workarea:
  a position in `WM_NORMAL_HINTS` is in ROOT coordinates, and
  `_NET_WORKAREA` is advice to whoever is placing a window, not a
  redefinition of the coordinate system. So a panel is entitled to
  overlap a window that asked for the corner, and `USPosition` is not
  pushed out from under it. It IS clamped to the screen, which is
  arithmetic about reachability rather than policy: Qt Creator's main
  window asks for `+0-2` and would arrive with its titlebar above the
  top edge, which is nobody's intent.

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

  **A title press is a click until it travels** (`set-drag-slop`,
  default 4 px) — aiming at a titlebar to raise a window should not
  nudge it a pixel on the way, and the cursor says which it is so far:
  the ordinary pointer while it is still a click, the carrying fleur
  from the moment it becomes a drag (then the window catches up in one
  step, so the spot that was grabbed stays under the pointer). The
  modifier gesture has no slop and wants none. **Edge resistance**
  (`set-edge-resist`, default 12 px) sticks a carried window to an edge
  of the workarea — flush against a strip is the position one is
  usually aiming for, and hitting it by hand to the pixel is aiming
  nobody should have to do.

  **A pointer gesture on a window a keyboard mode is holding** is not
  an error: it reads as a helper within that mode, so the mode stays in
  charge — its readout follows the carrying, and its Esc still undoes
  everything back to where the mode began, the carrying included
  (owner's call, 2026-07-30).

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

  Maximize with fvwm semantics (a workarea proc; the mark is a saved
  geometry rather than a state the client is held in, so the window can
  be moved and resized by hand meanwhile). What a **hand resize** does to
  that mark has two honest answers, so it is an option —
  `set-maximize drop|keep`, and `drop` is both the default and what
  fvwm3 actually does (measured by hand, 2026-07-30, after this was
  attributed the other way round for a day): the resize means this is no
  longer the maximized window, so the mark goes and the next toggle
  maximizes — a window pulled *bigger* included — saving the hand-set
  geometry, so the toggle after that comes back to what the hand made.
  `keep` is the other reading, in which the mark is a saved geometry and
  nothing else, and the toggle restores what was saved at maximize time
  however the window has been pulled about since. The rule lives in
  `resize-by-edge`, which is where both interactive resizes meet, so the
  border drag and the keyboard mode cannot drift apart on it. Moving a
  maximized window changes nothing under either answer (fvwm3 agrees) —
  that gesture says nothing about size, and the desktops that unmaximize
  on a title drag are resizing the window under the pointer, which is a
  different thing nobody asked for here.

  **The windows follow the workarea when it moves** — a panel that
  changes side or grows a row on a reload, a tray icon that widens the
  band, a screen resized under everything. One rule, applied to each axis
  on its own: a window that SPANS the workarea in that axis (sitting at
  the origin, exactly as long as maximize would have made it there) spans
  the new one; one flush at the near or the far edge stays flush at that
  edge of the new rect; one flush at neither does not move in that axis.
  Both halves of the wish fall out of it — what looks maximized (spans
  both axes) goes to the new maximization, and what was stuck to a border
  re-sticks — and so does the case in between: a full-height column
  re-fits in the axis it filled and re-sticks in the one it hugged.
  Spanning is measured against what `maximize-fit` would produce and not
  against the raw extent, or a maximized xterm — whole cells, slack at
  the far edge — would read as merely flush at the near edge. The
  maximized MARK is not touched in either direction: this is the WM
  moving furniture rather than a hand on the window, so `drop` does not
  fire, and a window that merely looks maximized is not marked as one.
  A maximized window's saved geometry travels by the same rule, so the
  way back does not end up under a panel that moved. Nothing is clamped
  back onto the screen (a window parked half off the edge, or under the
  panel because it claimed that corner, is related to no edge of ours),
  and a window a gesture is holding right now is left to the gesture.
  `set-workarea-follow off|max|stick`: `stick` is the whole rule and the
  default, `max` moves only what looks maximized, `off` is what every
  version before this did. **Fullscreen** on
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

  **The titlebar in three layers** (the owner, 2026-07-30). What a
  titlebar and a grip ARE, which buttons one wears, and what pressing
  one DOES are three different kinds of decision, and they used to be
  one piece of knowledge smeared over six places: the glyphs, the
  column set in `frame-buttons`, the treectrl construction in
  `policy-attach` with the three names hard-coded, a SECOND copy of
  that construction in `wm-window`, the arming machinery, and a
  `switch` saying what each button did. Adding one button meant editing
  five of them. Now:

  - **the strip** — `title-metrics` (height and button cell size),
    `chrome-of` (how much of it a window wears), `deco-draw`,
    `titlebar-build` (one builder, used by client frames and by the
    WM's own windows alike — the duplicate copy is gone), and the
    press/arm/release machinery that turns a click into "this part,
    this gesture". It knows there are button cells; it does not know
    their names;
  - **the buttons** — `titlebar-button NAME -glyph SVG ?-side?`, one
    catalogue, declaration order left to right within a side. A frame
    wears a SET of them, per frame because it varies: the WM's own
    windows wear close alone, and a client whose style refuses minimize
    is not given a button whose only answer would be to refuse;
  - **the gestures** — `titlebar-bind PART GESTURE COMMAND`, where a
    part is a button's name or `title` for the strip. The same table
    answers "what does close do", "what does a double click on the
    title do" and "what does button 3 on the title do", because those
    are one question asked three times. The command is a prefix the
    window is appended to, which is why the window commands fit it
    exactly and why this layer needs no case per button.

  Stock: menu (left), then minimize, maximize, close; `Minimize`,
  `Maximize` and `Close` on their button-1 presses, `winops` on the
  menu; a double click on the strip maximizes and button 3 on it opens
  the ops menu. `titlebar-bind close <3> Destroy` is one line for
  whoever wants it and deliberately not a default — a slip of the right
  button on the close box would kill an application without asking it
  to save anything.

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

  **No input method, ever** (`tk useinputmethods 0`, three lines after
  Tk itself) — a window manager cannot afford to be one's hostage, and
  this is a post-mortem rather than a precaution. Tk creates an XIC
  lazily for EVERY window that sees an event — frames, titlebars,
  panel, menus, compass — and `Tk_DestroyWindow` then calls
  `XDestroyIC`, a SYNCHRONOUS round trip to the XIM server. Kill the
  XIM server on a running desk (swapping input methods is a thing
  people do) and the next `destroy` of any window of ours blocks in
  `XIfEvent` → `poll(-1)`, **inside the X event handler**: the loop
  goes on reading X events and dispatches none, nothing is framed, no
  chord fires, nothing is logged, and `ps` shows a healthy process
  asleep. There is no error to catch anywhere — it took a backtrace to
  see. Switching it off costs nothing here, since nothing in this WM
  accepts typed text and every key we care about is decoded from
  keycodes by hand; a GUI that WOULD want an input method belongs on
  the far side of the line drawn in `wm-window` — its own thread, its
  own connection, its own Tk. The startup line says which way the
  switch is, in as many words.

  **A chord is Latin whatever the group, and survives it.** The lookup
  asks the keymap for **group 0, level 0** by hand rather than trusting
  the event, so a chord is named by its Latin keysym whatever is being
  typed: `<Super>l` is `<Super>l` on a Cyrillic group, and so is a menu
  hotkey. The state mask is the half that had to be fixed — XKB reports
  the effective group in **bits 13-14 of the core event state**
  (`XkbGroupForCoreState`, `X11/extensions/XKB.h`), and the shim hands
  that state through untouched, while the chord's grab keeps working
  across a group change (XKB keeps a separate grab state with no group
  in it). So the press still arrived, gained `0x2000` on the way, and
  missed a table keyed on the bare modifier: the key was swallowed by
  our own grab and nothing ran. The group bits join Lock and Mod2 in
  what a chord ignores, and none of this touches the xkb configuration
  — it is all on our side of the event.

  **Two spellings, one chord.** `<Super>t` is how a config WRITES a
  chord; `Super+t` is how the desk SHOWS it (the log, the echo, the
  help list) — and `wm-bind` takes both, so a line read off the screen
  can be typed straight back into a config. The `<Mod>` prefixes are
  stripped first, then anything before a `+` is a modifier name too,
  which is unambiguous because an X keysym name never contains one (the
  key next to Backspace is `plus`). `<Control>`/`<Ctrl>`,
  `<Alt>`/`<Meta>`/`<Mod1>` and `<Super>`/`<Mod4>` are the same
  modifiers under different names.

  **A shifted symbol is spelled by the key it sits on.** The lookup
  asks the keymap for group 0 level 0, which is exactly what makes a
  chord Latin on any layout — and the same thing means `?` never
  arrives as `?`: pressing Shift+/ comes in as `<Shift>slash` whatever
  the pair prints, so a binding named `question` could not match on ANY
  layout. Making it match would mean also resolving the event's OWN
  group and level and trying that keysym too — a decision about what a
  chord IS, not a fix, and not taken here.

  **What is under this prefix** (`set-key-help`, default `<Super>h`) —
  Emacs's `C-h` after a prefix key: inside a sequence it lists the keys
  that go on from where you are, in the same box — the WHOLE subtree,
  one leaf per line. Showing a submap as "… (2 more)" was the first
  version and a greedy saving: a desk has a dozen or so bindings, they
  fit, and a level hiding them buys something only if the group can say
  what it IS — which cannot be synthesized out of the keys under it, so
  between expanding and describing the honest one is expanding (the
  owner, 2026-07-30). The listing is laid out by the GRID and not by
  spaces in a label, because a proportional font makes padded text
  ragged and the columns are the point of a list one reads down; a
  listing longer than the screen starts a second pair of columns rather
  than running off the bottom. A binding can carry its own NAME
  (`wm-bind SPEC SCRIPT ?NAME?`) for when the script is not a fit thing
  to read — which is how a panel button's chord shows as `emacs` and
  not as `panel-fire dock 2`. The number is right for the machinery (it
  addresses the button's cell, the thing that gets flashed, and two
  buttons may share a label), so the caller says what it IS rather than
  anything reversing a name out of a command afterwards.
  It costs nothing from the global namespace, being reachable only
  while a sequence holds the keyboard, and it answers even when the
  echo is `off` — that switches off the desk speaking unbidden, not the
  desk answering. Asking does not move the sequence: the next key walks
  on from the same submap. The default is `<Super>h` because coming
  from `<Super>t` the thumb is already on Super — one roll rather than
  a regrip, the same thing that makes `C-x C-h` comfortable.

  **A top chord is always live.** Inside a sequence, a press the
  current submap does not know but the TOP map does starts over from
  there instead of aborting — reaching for `<Super>t` when a forgotten
  `<Super>t` is already pending is the commonest way to land on
  "undefined key" by accident, and the intent behind that press is
  never "abort", it is "begin" (the owner, 2026-07-30). It costs a
  sequence nothing, because the SUBMAP IS ASKED FIRST: a config that
  binds `<Super>t` under `<Super>t` keeps that meaning exactly where it
  bound it, and the restart applies everywhere else. The same holds for
  a top chord that is an ACTION rather than a prefix — `<Alt>space`
  still opens the ops menu from inside a half-typed sequence, which is
  the same promise ("a global key is global") read from the other end.
  Escape sits between the two maps: a submap's own Escape beats the
  cancel, and the cancel beats the restart, since a globally bound
  Escape would otherwise take away the one way out that works from
  anywhere.

  **A sequence shows itself** (`set-key-echo`, `set-key-echo-place`), in
  the same amber the keyboard modes wear, because it is one of them: a
  small box says `Super+t …` while it waits for the rest, and
  `Super+t z is undefined` for a moment when a press ends it. A prefix
  takes the whole keyboard, and doing that in silence leaves the desk
  indistinguishable from a wedged one at the exact moment one is least
  sure — while an undefined key inside a sequence was the quietest
  event on the desk: nothing happened, and nothing said so. It appears
  **at once** by default, which is deliberately not Emacs's
  `echo-keystrokes` (a second's hesitation first): Emacs echoes a
  prefix typed hundreds of times an hour, where a box on every `C-x`
  would be noise, and a WM chord is a rare deliberate thing. Whoever
  finds the flash of a fast `Super+t q` too much sets a delay in
  milliseconds and gets Emacs's behaviour, or `off`. The placement
  knob takes the `place` grammar's edge words, sizeless (the box is as
  big as its text), over the workarea. The substrate only knows WHEN
  there is something to say (`policy-key-echo kind text`); what it
  looks like is the policy's, and the window is named `tk9wm-key-echo`
  so a test outside the process can assert it is really on the screen.

  **Nothing maps before it knows where it goes.** The box asks its
  LABEL how big it is, and the `update idletasks` that answer needs is
  also what maps a freshly built toplevel — so the first version
  appeared at Tk's idea of a place (a 200x200 default toplevel at the
  origin) and moved to ours a heartbeat later, which reads as a flash
  in the wrong corner. It is built withdrawn, sized, placed and only
  then deiconified, and it STAYS from then on — hidden by withdrawing
  rather than destroyed, so the first map is the only one there is.
  The menus and the compass never met this, and the reason is worth
  keeping: neither asks a widget its size (the menu multiplies item
  height by count and measures the font for the width, the compass
  derives a square from font metrics), so neither needs an update
  before `wm geometry`. It is that one question that costs a map. The
  witness is the SERVER's own event order — `xev -root -event
  substructure`, where the box must map with no move after it — since
  a flash that short is not something a screenshot can be aimed at.

  **One router, and taking it serves notice.** Everything
  keyboard-modal here goes through `grab-keys-to` — the menus, the
  confirmation, the keyboard move/resize — and it is a SINGLE SLOT.
  Taking it now runs the previous holder's `onlost` script, whoever
  ends it and including the holder releasing it itself, which makes
  that callback the one place a modal thing tears itself down (so every
  one of them is idempotent; they are all "end my mode", which is
  idempotent anyway). Overwriting silently was how a keyboard resize
  survived the window menu being opened over it with the mouse: the
  menu took the router, the pick gave it back to nobody, and the mode
  was left standing with its amber frame and its compass and nothing to
  answer its keys (owner's report, 2026-07-29). One slot with no
  handover is that bug for every PAIR of modal things; with the
  handover there is no pair left to get wrong. A preempted move or
  resize **cancels** — it never got its Enter, and a window quietly
  keeping an unfinished move is the worse surprise.

  **The WM checks its own modal invariants**, because what goes wrong
  with modes is never the mode — it is the interleaving, and there are
  more pairs of those than anyone checks by hand. `wm-invariants` says
  what must be true when nothing is mid-gesture (a keyboard mode is the
  router's holder or is not there at all; no compass without a mode; no
  frame wearing the modal amber without one; no popup without a router;
  the keyboard never grabbed for nobody; no key echo showing a sequence
  that is not running), and a violation goes to the
  log as `WM: INVARIANT …`. That makes the check free for every
  scenario the suite drives, whatever it was written for —
  `check_invariants` in `tests/common.sh` is one line at the end of a
  test and turns it into an interleaving test as well. The check is
  deferred by a TIMER and not to idle: building a popup calls
  `update idletasks`, which drains the idle queue, so an idle check ran
  inside the very construction it was waiting for and complained about
  a popup that had not taken the router yet.

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

  **A keyboard move or resize RAISES what it is about.** A window can
  be active and buried — `Lower` keeps the focus where it is, which is
  what makes "drop it, see what is under it, bring it back" work, and
  the ops MENU on such a window is deliberately kept: commanding a
  window one cannot see is the whole point of that gesture. Dragging
  one is the case that reads as broken (the compass and the amber frame
  under other windows, and nothing visibly moving), and fvwm looks
  equally odd, which is what made it look inevitable. It is not: the
  answer was already here three times over — `drag-start`, `rz-start`
  and `policy-client-press` all raise before they manipulate, so a
  keyboard move that did not was not this WM following fvwm but this WM
  disagreeing with itself (one operation, one outcome). Raise only, no
  focus: the mouse paths focus because a CLICK is how one points at a
  window, and this mode does no pointing. And the raise is not undone
  at the end by either Enter or Escape — Escape puts back the geometry,
  which is what the mode changed, while the raise is what manipulating
  a window does, exactly as the mouse leaves it.

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

  **The compass** — both keyboard modes put up nine digits laid out the
  way they sit on a numpad, each one drawn **at the point it names**, so
  it is a map rather than a picture of a keyboard: whatever a digit
  stands for happens where that digit is. It stands for two things, over
  two different rectangles.

  In **move** it maps destinations over the workarea: press 7 and the
  frame sticks to the top-left corner, 5 centers it, 3 takes the
  bottom-right. The size is never touched — this is a move — and the
  placement goes through the same `place-axis` the config's `place`
  style does, so a jump and a configured placement land in the same
  pixel. A jump is a **step and not a verdict**: it does not commit, so
  Esc still reverts to the geometry the mode was entered at and one can
  try 7, then 3, then 5 before pressing Enter; **0** goes back to that
  entry geometry without leaving the mode.

  In **resize** it maps handles over the window itself — which side or
  corner the arrows drag, drawn where that handle is, the one in force
  lit in the lighter shade the frame's grips wear. The arrow moves *the
  handle*: an east edge grows the window as it travels right, a west
  edge shrinks it and the frame follows so the east edge stays put, and
  a handle with no freedom on an axis (a bare north against a horizontal
  arrow) does not answer at all. The mode starts on the **south-east**
  handle, which is what it always did before it could be told otherwise;
  the compass only says so out loud. Both resizes now do the same
  arithmetic — the pointer drag and the arrows share one
  `resize-by-edge` — and since a west or north handle moves the frame,
  Esc puts the **position** back as well as the size. One cell falls out
  of the mapping: a cell centered on both axes owns no edge, so **5 is
  not a handle**, and the compass has the hole in the middle every
  eight-handle selection box has ever had. The hole is derived from the
  same table the destinations are, not stipulated.

  The digits scale to the box they are drawn on (a cell is at most a
  quarter of its short side), and the resize handles are anchored to the
  **client area** rather than the frame, which keeps them off the
  titlebar the mode is using for its readout. They are placed **once**
  and stay there: handles that followed the frame read as digits coming
  unstuck and wandering, since only some of them move on any given step
  — a west drag pins the east cells and walks the west ones (owner's
  report, 2026-07-29). A compass that stands still is the better object
  anyway: it is a keymap, saying which key is which handle, not a
  decoration of the edges — the frame's own grips are that. The cells
  are clamped to the screen, so a window hanging off an edge still shows
  its digits somewhere readable. The numpad works whatever
  NumLock is doing (the key router reads keysym level 0, where the
  numpad carries `KP_Home`/`KP_Up`/… — the digits of the top row work
  too). The compass stands for exactly as long as its digits are live,
  for the reason the amber frame exists at all.

  What the **move** compass does about a **maximized** window is
  arithmetic and not a state flag: a frame as wide as the workarea lands in the same X
  whether it is asked for left, center or right, so that column of the
  compass is degenerate and drawing three digits on one point would be a
  lie. No slack on either axis — a maximized window, a fullscreen-sized
  one, one grown by hand — and there is no compass at all, nothing to
  offer; no slack on one axis and only the free one is drawn, three
  digits down the middle of the other. Either short answer is logged
  with the measurements behind it, because a compass missing its cells
  reads as a bug otherwise. The keys of a degenerate axis stay accepted:
  7 and 9 are then honest synonyms of 8. The resize compass has no such
  case — a window can be pulled by any of its sides whatever size it
  happens to be.

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
wish9 tk9wm.tcl                     # take an empty desk
wish9 tk9wm.tcl -replace            # ...or take it from whoever has it
```

**Replacing a running window manager** is ICCCM 2.8, and both
directions of it work. We own the manager selection `WM_S<screen>`, so
somebody else's `--replace` reaches us: the answer is to release every
client back to the root alive and exit, which is what our own `exit`
has always done. `-replace` is the same request the other way — it asks
the current owner to stand down, waits for its owner window to go
(10 s, `::replace_timeout`), then takes the redirect. The clients live
through it and are adopted by the newcomer; that is the whole point, a
handover that costs the desk its windows being a reboot with extra
steps. Verified against fvwm3 in both directions (run-replace-test.sh).

Without `-replace`, a desk that is already taken is a refusal that
names the owner instead of a bare `BadAccess`. A manager that owns no
selection cannot be asked at all — the refusal says that too, since
nothing but killing it will do.

### …and what that does to your session

ICCCM knows no "hand over and stay": the newcomer waits for the old
manager's owner window to be GONE, which reliably means its process is.
So **a session held by the window manager ends when the manager is
replaced** — `exec tk9wm` as the last line of `.xsession` makes the
session's lifetime the manager's lifetime, and `-replace` from anywhere
then logs you out (owner's report, 2026-07-29). This is not ours and
not fixable here: any `--replace` against any `exec`ed manager does the
same, and desktops where it does not (GNOME, XFCE) are the ones whose
session is held by a session manager rather than by the WM.

The same coupling is deliberate in the other direction — `Quit` ends
the session on purpose, a desk one cannot leave from the inside being
the "how do I exit vim" joke with a login in it. So the WM does not
choose: it states WHY it left, and the session script decides what that
means. **Exit codes:**

| code | meaning |
|------|---------|
| 0 | left on purpose — `Quit`, or the display went away |
| 1 | could not start: the desk is taken (see above), or the redirect was refused |
| 3 | another manager took the desk and we stood down for it |

Two recipes, and the difference between them is a policy, not a bug:

```sh
# .xsession — the desk IS the session: Quit logs out, and so does a
# replacement. The simple one, and the right one if nobody replaces you.
exec tk9wm

# ...or: survive replacements, still log out on Quit. When we stand
# down (3) the script keeps the session alive under the new manager;
# any other exit ends it as before.
tk9wm; [ $? = 3 ] && exec tail -f /dev/null
```

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
  screen), `run-button-test.sh` (the titlebar in its three
  layers: maximize → workarea → restore and close sending
  WM_DELETE_WINDOW; the minimize button iconifying, and absent from a
  window whose style refuses; the strip's own gestures, a double click
  maximizing and button 3 opening the ops menu; and a CONFIG saying all
  three kinds of thing — declaring a button with its own glyph, binding
  it to a window command, and putting Destroy on button 3 of close), `run-restart-test.sh` (restart in place: the
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
  `run-keyecho-test.sh` (what a sequence says about itself and the
  always-live top chord: the box appears with the prefix and follows
  the typing — asserted from OUTSIDE the process, by finding the named
  window on the screen, not by believing our own log — sits where
  `set-key-echo-place` put it, leaves with the sequence, reports an
  undefined key for its second and no longer; it maps ONCE and already
  in its place, witnessed through xev on the server's own event order; `Super+t` inside a
  sequence restarts it and the echo starts over, `Alt+Space` inside one
  reaches its action, and where the config binds `<Super>t` under
  `<Super>t` the submap wins; `<Super>h` expands the whole subtree —
  including a panel button's chord under its own label — and leaves the
  sequence standing; a config line spelled `Super+t Ctrl+j` lands in the very
  same submap as the in-code defaults, and `<Shift>slash` fires for the
  key that prints `?`),
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
  nested Xephyr; shrink the screen and the panel follows the bottom —
  and so does the maximized client, which is the workarea reflow with
  the screen rather than a reload as its cause),
  `run-reflow-test.sh` (the workarea moving under five windows, one per
  per-axis case, through three live reloads that move the panel bottom →
  top → right → left: the spanning column re-fits and the flush corner
  re-sticks while the window flush with nothing does not move at all; a
  maximized xterm is re-fitted rather than carried, which only holds if
  spanning is measured with size hints and not raw extents; a maximized
  window's saved geometry travels too, measured by unmaximizing it at the
  end onto edges that have moved twice; and `set-workarea-follow off`
  moves nothing),
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
  an xterm; and a LOWERED window that is still the active one, where
  entering the mode raises it over its neighbour — measured on the
  server's stacking order against the neighbour rather than the top of
  it, the compass having nine cells of its own up there), `run-compass-test.sh` (the numpad compass in that mode:
  7/3/5 stick the frame to the corner, the opposite corner and the
  center of an 800x600 workarea — measured against the decoration the
  WM's own metrics line declares — a jump does not commit (Esc still
  reverts) and 0 returns without leaving the mode; then the degenerate
  cases, a maximized window offered no compass at all and a full-width
  one offered 8/5/2 and not the cells that would sit on top of them;
  then the same digits as resize HANDLES — the mode starting on se, 7
  taking the nw corner so that dragging it right and down shrinks the
  window while its far corner stays put, 8 taking the north edge which
  ignores a horizontal arrow, the Esc that puts back the position a
  west/north handle moved, a pixel inside the east cell sampled before
  and after the east edge is pulled away from under it to show that the
  digits stay put, and the middle of the window sampled to show that 5
  is no handle), `run-maxflag-test.sh` (`set-maximize keep|drop`: the
  same maximize-shrink-toggle scenario under both readings and by both
  resizes — mouse and keyboard, which the rule's placement in
  `resize-by-edge` is what guarantees; the second config arrives by a
  live reload), `run-modes-test.sh` (modal interleavings: a keyboard
  resize interrupted by the window menu opened with the MOUSE and then
  Maximize picked from it, a keyboard move interrupted by a menu that
  is then dismissed, a keyboard move interrupted by its window dying —
  each asserting both the behaviour and that the WM raised no
  invariant complaint, plus that the keyboard was not left grabbed
  after any of it), `run-carry-test.sh` (a two-pixel wobble on a
  titlebar moves nothing while a real drag carries by the whole travel,
  slop included; a carry aimed 5 px inside the workarea's left edge
  lands ON it and one aimed 30 px inside stays 30 px inside; and a
  client asking for `+0+-2` keeps its x under a left-hand panel while
  its y is clamped onto the screen — the desk has a panel precisely so
  the two rectangles differ), `run-yield-test.sh` (one rule against six
  windows, each claiming a different combination: said nothing, said how
  big, said where, said both, said both under `force`, and an unmatched
  reference for "the size it would have had anyway". The cast is mixed
  out of necessity — xterms for the size claims, since Tk never sets
  `USSize`, and a Tk client for the position-only one, since xterm
  cannot make that claim alone), `run-chordstate-test.sh` (what a chord
  ignores in an event's state: the same binding fired at every
  combination of Caps, Num and the two xkb group bits, plus the
  negative controls — Shift and Control still make a chord distinct —
  and that the keysym it is matched on comes from group 0 — then the
  same chord fired for real through the server's own grab, and — where
  the host lets the group actually move — again after a switch. The leg
  **verifies the switch happened** instead of assuming it, by asking a
  client what keysym a plain key now produces; a leg that assumed would
  pass whether or not the thing it names occurred. The suite's own Xvfb
  needs **`-noreset`** for any of this: an X server resets when its
  last client disconnects and a reset restores the default keymap, so
  `setxkbmap` set the layout, disconnected, and the reset undid it
  before anything could look — nothing failing and nothing complaining
  the whole way).
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
- `run-replace-test.sh` (ICCCM manager replacement, both directions: a
  plain start owns `WM_S<n>`; a newcomer without `-replace` refuses and
  names the owner, leaving the running desk alone; one with `-replace`
  takes the desk, the first stands down and its client survives to be
  adopted; a restart in place still comes back up through its own
  selection; and — where fvwm3 is installed — the foreign half, its
  `--replace` taking the desk from us and ours taking it back, with the
  client living through both handovers).
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
