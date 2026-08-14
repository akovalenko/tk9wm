# tk9wm policy — the look-and-feel layer: OUR local decisions, none of
# which a WM fundamentally needs to be this way. Tk-widget decorations
# (titlebar / ✕ / slot, highlight colors), cascade placement, title-bar
# drag, click-to-focus, initial focus, refocus pick. Swap this layer for a
# different look/behavior; the substrate only ever calls the policy-*
# hooks defined here (contract — see substrate.tcl header and the idea
# file, step 9).
#
# Private state: ::frameof(client) = frame widget, ::leaderof(client) =
# WM_TRANSIENT_FOR leader read at manage time (0 = none), ::focus_hist =
# clients most-recently-focused first, plus the cascade and drag
# bookkeeping. The substrate's client geometry (::geomof) is not touched
# here — sizes always arrive as hook arguments.

package require treectrl   ;# titlebars: its text element cuts a long
                            ;# title with an ellipsis instead of overflowing

keep ncli 0
keep fid 0
keep focus_hist {}
# The two decoration numbers a config may move (set-border and
# set-grips write them); the look record in 10-look.tcl derives the
# rest from them, and consumers read the record, never these.
#
# Border width, all four sides. 6px is a resize GRIP, not just a
# line: the old 2px border left nothing to grab. The top strip above
# the titlebar was 2px for a while (top resize worked but was
# unhittable); the owner asked for grips uniform with the bottom
# (2026-07-28), so the strip is a full border now.
keep border 6
# Corner grip arm length — ALL four corners, deco-draw and rz-edge
# alike. The top arms briefly ran border+titleh ("hug the buttons"),
# then the buttons briefly shrank to gripz - border to meet 24px
# arms — both misreadings of the same wish (2026-07-28): SHORT arms
# like the bottom, with the buttons drawn flush into the strip's top
# corners, so the border (and the grip riding on it) presses right
# against the button the way the bottom border presses against the
# client area. The grip's cut is just a mark on the border — it does
# not chase the button's edge. Button size — see look-derive.
keep gripz 24
# The air above and below the title's text line, each side. It was a
# constant 3 inside look-derive until the owner met a 144dpi strip:
# the font's linespace plus six plus the border read too tall, and
# the lever that keeps the FONT while shrinking the strip (and the
# buttons with it — btnw follows titleh) is exactly this number
# (2026-08-14). Zero is the safe floor — the strip is the linespace
# and everything still fits by definition; negative goes tighter by
# clipping INTO the line, top and bottom equally (the text sits
# centered), which eats the font's own leading first and the deepest
# descender pixels after it — legal, and a taste.
keep titleair 3
# How much shorter than the strip a titlebar button is — the hole
# between the buttons and the client area (plus decotop's constant
# 2px seam). EMPTY means «half a border, rounded down»: buttons
# pressed right against the client were the owner's original no
# (2026-07-28), a whole border under them read too wide at 144dpi,
# and half is where his eye called the hole visually symmetric
# (2026-08-14) — a relation still, so the hole follows a moved
# border. A number pins it instead: `set-button-gap 0` is the old
# full-height look, bigger is airier.
keep btngap {}

