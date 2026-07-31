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
    set bg [dict get $opts -background]
    set fg [dict get $opts -foreground]
    set link [contrast-link $bg]
    text $w.t -wrap word -borderwidth 0 -highlightthickness 0 \
        -background $bg -foreground $fg -font DeskFont \
        -cursor left_ptr -width 52 -height 9 -spacing3 4
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
    $w.t insert end "Hide this forever" {link hide}
    $w.t insert end " — the desk writes your first customization and\
 this note never returns."
    $w.t tag bind cfg  <ButtonRelease-1> {applet configurator}
    $w.t tag bind hide <ButtonRelease-1> {welcome-hide}
    $w.t configure -state disabled
    pack $w.t -expand 1 -fill both
}

proc welcome-hide {} {
    custom-write {set-welcome off}
}
