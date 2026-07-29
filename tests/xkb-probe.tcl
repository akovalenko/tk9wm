# What a KeyPress carries once the xkb GROUP is switched: the state
# mask and the keysym the server resolved. Both are what the chord
# machinery has to survive — the lookup is keyed on "mods,keysym", so a
# mask that gains a bit or a keysym that turns Cyrillic breaks a
# binding that has nothing to do with either.
#
# The values go through a PROC and not into the format string: inside a
# bind script Tk substitutes every % sequence it knows, and %x %d %s are
# all bind substitutions before they are ever format ones.
package require Tk
chan configure stdout -buffering line
proc seen {state keysym keycode} {
    puts [format "PROBE state=0x%04x keysym=%s keycode=%s" \
              $state $keysym $keycode]
}
wm title . probe
wm geometry . 200x80+10+10
label .l -text "press" -padx 20 -pady 20
pack .l
bind . <KeyPress> {seen %s %K %k}
focus -force .
after 60000 exit
vwait forever
