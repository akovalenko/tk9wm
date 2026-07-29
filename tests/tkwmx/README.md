# tkwmx tests

Headless, no window manager required:

```sh
xvfb-run -a /path/to/whale tests/props.tcl
```

`props.tcl` is the property battery: the write/read/delete round trip
for formats 8 and 32, the typed getters (text with its encoding ladder,
class, hints, normal-hints, protocols, transient) against a live Tk
toplevel, and — the half that is easy to get wrong — a window that died
under us answering `{}` instead of taking the process down with an X
error.

Note what the battery has to do to find its subject: Tk keeps a
toplevel's WM properties on a WRAPPER window, which is the PARENT of
`winfo id` (and `wm frame` does not point at it either, since with no
WM nothing was reparented). A window manager sees wrappers, so the
tests ask `tkwmx::window tree` for the parent and work on that.
