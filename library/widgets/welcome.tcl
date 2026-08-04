# The welcome mat — the desk's standing invitation (config or none:
# only set-welcome off retires it; see welcome-inject). Plain text
# sitting directly on the desk's own background, no border and no
# box: an invitation, not a dialog. The ink and the link color are
# picked against set-desk-background by luminance (contrast-fg /
# contrast-link), because a welcome nobody can read — black on
# black — would be the worst first impression a desk can make.
#
# Two links. "Open the configurator" goes through the applet door
# (`applet configurator` — the ui host answers it when it exists).
# "Hide this forever" writes the desk's FIRST customization,
# set-welcome off — the invitation dogfoods the very layer it is
# inviting you to use.
wm-widget-type welcome {build welcome-widget-build}

proc welcome-widget-build {w opts} {
    # THE DESK'S COLOUR AS IT IS NOW, not as it was when this widget
    # was declared: the mat sits directly on the desk window and must
    # not drift from it. The ink follows by luminance, so a change of
    # ground changes the writing with it.
    set bg $::desk_background
    set fg [contrast-fg $bg]
    set link [contrast-link $bg]
    $w configure -background $bg
    text $w.t -wrap word -borderwidth 0 -highlightthickness 0 \
        -background $bg -foreground $fg -font DeskFont \
        -cursor left_ptr -width 52 -height 14 -spacing3 4
    # The height in CHARACTER LINES is a guess the wrap makes wrong
    # (the owner's mat scrolled by a couple of lines); the truth —
    # display lines after wrapping — is knowable once the widget has
    # its WIDTH, and that arrives as a <Configure>.
    #
    # Not as a <Map>, which was the first answer and only half of one:
    # the desk MEASURES a widget in a window nobody maps (see
    # widget-measure), so a re-fit waiting on a mapping never ran for
    # the measurement. The desk then reserved the guess, the mat built
    # for real re-fit itself deeper than that, and the extra ran off
    # the bottom — behind the panel with the desk window on, and
    # clipped by a toplevel pinned to the guess with it off (the owner,
    # 2026-08-03). A <Configure> arrives in both places, so the two
    # readings agree.
    #
    # The guard is for the width the widget has before it is laid out:
    # a count taken at one pixel wide answers in the hundreds, and this
    # binding fires once and then retires.
    bind $w.t <Configure> {
        if {%w > 1} {
            %W configure -height [expr {[%W count -displaylines 1.0 end] + 1}]
            bind %W <Configure> {}
        }
    }
    $w.t tag configure h -font TitleFont
    $w.t tag configure link -foreground $link -underline 1
    $w.t tag bind link <Enter> [list $w.t configure -cursor hand2]
    $w.t tag bind link <Leave> [list $w.t configure -cursor left_ptr]
    $w.t insert end "This desk is tk9wm.\n" h
    $w.t insert end "Everything here has a sensible default and a knob;\
 no config file is required.\n\n"
    $w.t insert end "Open the configurator" {link cfg}
    $w.t insert end " to shape the desk by hand: fonts, panels,\
 buttons, the terminal it favors.\n\n"
    $w.t insert end "About this desk" {link about}
    $w.t insert end " — what is running, from the running desk's own\
 mouth.\n\n"
    # ASK THE KEYMAP, do not assume: the help key is a parameter of
    # the chords bundle and a config may have moved it, in which case
    # advising Super+h would be advice to press nothing (the owner).
    # Bound to nothing at all — the sentence simply loses its tail.
    set hk [chord-of key-help-open]
    $w.t insert end "See every key this desk answers to" {link keys}
    if {$hk eq ""} {
        $w.t insert end ".\n\n"
    } else {
        $w.t insert end " — also on $hk.\n\n"
    }
    $w.t insert end "All type bigger" {link fup}
    $w.t insert end "  /  "
    $w.t insert end "smaller" {link fdn}
    $w.t insert end " — one press turns the one font everything\
 derives from, and it sticks (a customization, like any click\
 here).\n\n"
    # ...and its opposite number for colour. The word on the link is
    # what a press WILL DO, not what the desk is now: a switch that
    # names its own current state reads as a label and gets pressed by
    # somebody expecting to arrive where it already is.
    $w.t insert end [expr {$::theme eq "light"
        ? "Go back to the dark theme" : "Try the light theme"}] {link theme}
    $w.t insert end " — every colour on this desk comes from that one\
 word, and this press sticks too.\n\n"
    # ...and the one that FURNISHES rather than explains. Offered only
    # while the desk has no panel of its own: on a desk that already
    # has one it would be an invitation to throw away what is there,
    # which is not what a welcome note is for.
    if {![llength [panel-names]]} {
        $w.t insert end "Set up the basics" {link basics}
        $w.t insert end " — a panel with a tray and buttons for the\
 terminal, emacs and tmux, each appearing only if this machine has it.\
 Written as ordinary customizations you can then edit or take back.\n\n"
    }
    $w.t insert end "Hide this forever" {link hide}
    $w.t insert end " — the desk writes your first customization and\
 this note never returns."
    $w.t tag bind cfg   <ButtonRelease-1> {applet configurator}
    $w.t tag bind about <ButtonRelease-1> {applet about}
    $w.t tag bind keys  <ButtonRelease-1> {key-help-open}
    $w.t tag bind fup   <ButtonRelease-1> {welcome-font-bump up}
    $w.t tag bind fdn   <ButtonRelease-1> {welcome-font-bump down}
    $w.t tag bind theme <ButtonRelease-1> {welcome-theme-flip}
    $w.t tag bind basics <ButtonRelease-1> {welcome-preset minimal}
    $w.t tag bind hide <ButtonRelease-1> {welcome-hide}
    $w.t configure -state disabled
    pack $w.t -expand 1 -fill both
}

proc welcome-hide {} {
    custom-write {set-welcome off}
}
