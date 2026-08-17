#!/usr/bin/env python3
# A GTK3 stand-in for gnome-calculator — the window that taught the
# desk about black corners (2026-08-17). What matters is reproduced
# exactly: an UNDECORATED top-level (the Motif word 0, as every CSD
# app says it) on the screen's RGBA visual, drawing a rounded
# rectangle with genuinely transparent corners — alpha 0 outside the
# arcs, as GTK4 rounds every one of its windows. GTK3 rather than
# GTK4 because it drives headless with no fuss and the tray suite
# already trusts it; the visual and the alpha are the same story.
#
#   argb-client-gtk.py [#rrggbb]
#
# The corner radius is 32, so a probe a few pixels into the corner is
# comfortably outside the arc: what shows there is whatever the
# compositor blends in — the desk if the alpha survived the frame,
# black if it was flattened away.
import sys
import math

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk            # noqa: E402
import cairo                             # noqa: E402

R = 32
spec = sys.argv[1] if len(sys.argv) > 1 else '#729fcf'
r, g, b = (int(spec[i:i + 2], 16) / 255.0 for i in (1, 3, 5))

win = Gtk.Window(title='argb')
win.set_decorated(False)
win.set_default_size(240, 180)
win.set_app_paintable(True)
vis = win.get_screen().get_rgba_visual()
if vis is None:
    print('ARGB: no rgba visual on this screen', flush=True)
    sys.exit(77)
win.set_visual(vis)


def draw(widget, cr):
    w = widget.get_allocated_width()
    h = widget.get_allocated_height()
    cr.set_operator(cairo.OPERATOR_SOURCE)
    cr.set_source_rgba(0, 0, 0, 0)       # a truly empty ground, corners included
    cr.paint()
    cr.set_source_rgba(r, g, b, 1)
    cr.new_path()
    cr.arc(w - R, R, R, -math.pi / 2, 0)
    cr.arc(w - R, h - R, R, 0, math.pi / 2)
    cr.arc(R, h - R, R, math.pi / 2, math.pi)
    cr.arc(R, R, R, math.pi, 3 * math.pi / 2)
    cr.close_path()
    cr.fill()


win.connect('draw', draw)
win.connect('destroy', Gtk.main_quit)
win.show_all()
print('ARGB: 0x%x up (%s, r=%d)' % (win.get_window().get_xid(), spec, R),
      flush=True)
Gtk.main()
