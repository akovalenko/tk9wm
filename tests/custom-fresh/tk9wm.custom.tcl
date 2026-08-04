# tk9wm customizations — MACHINE-WRITTEN, do not edit by hand:
# the configurator rewrites this file whole. Hand-written
# configuration belongs in tk9wm.tcl, which loads BEFORE this
# file; on overlap the desk says so in its log.
action emacs {emacs {frame tk9wm-frame} needs emacs key {<Super>t e}}
action terminal {type terminal key {<Super>t t}}
action tmux {terminal {name tmux title tmux}
                      run {sh -c {tmux attach || tmux new}}
                      badge t needs tmux key {<Super>t m}}
set-tray on
set-welcome off

# ...and the ordered declarations, in the order they were made:
# fonts derive, buttons lay out and widgets share an area BY ORDER.
wm-widget clock -type clock -on {panel default} -place {right vcenter}
panel-buttons-own default
panel-button terminal
panel-button emacs
panel-button tmux
