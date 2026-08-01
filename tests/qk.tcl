wm-keys windows
                 list alttab [dict exists $::keymap [join [parse-chord {<Alt>Tab}] ,]] \
                      close [chord-of Close]
