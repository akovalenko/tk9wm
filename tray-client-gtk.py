#!/usr/bin/env python3
# A GTK3 tray client — the second opinion in the ARGB experiment.
#
# Tk's own systray is convenient (it ships in the kit) but it is also
# the implementation under test's cousin, and it leaves uninitialized
# pixels in the transparent part of its icon. GTK's GtkStatusIcon is
# what the world's XEmbed tray clients actually are — Chrome's Linux
# status icon among them — so it is the honest check that a tray cell
# shows OUR color through an icon's transparency.
#
#   tray-client-gtk.py [#rrggbb]
# Draws a filled circle with genuinely transparent corners (cairo
# ARGB32, alpha 0 outside the disc) and docks it.
import sys
import math

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk       # noqa: E402
import cairo                             # noqa: E402

SIZE = 22
spec = sys.argv[1] if len(sys.argv) > 1 else '#729fcf'
r, g, b = (int(spec[i:i + 2], 16) / 255.0 for i in (1, 3, 5))

surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, SIZE, SIZE)
cr = cairo.Context(surface)
cr.set_operator(cairo.OPERATOR_SOURCE)
cr.set_source_rgba(0, 0, 0, 0)           # a truly empty background
cr.paint()
cr.set_operator(cairo.OPERATOR_OVER)
cr.set_source_rgb(r, g, b)
cr.arc(SIZE / 2.0, SIZE / 2.0, SIZE / 2.0, 0, 2 * math.pi)
cr.fill()
surface.flush()

icon = Gtk.StatusIcon()
icon.set_from_pixbuf(Gdk.pixbuf_get_from_surface(surface, 0, 0, SIZE, SIZE))
icon.set_tooltip_text('tk9wm argb probe')
icon.set_visible(True)
print('GTKTRAY: icon created (%s)' % spec, flush=True)
Gtk.main()
