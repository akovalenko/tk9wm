# ---- the terminal layer ----
# "A unix environment with a terminal, not pinned to a desktop" — the
# owner's phrase, and this layer is where it becomes machinery. A panel
# button that means "the named terminal running mutt" should SAY that
# and nothing else: which emulator the user loves, which flag spells a
# window's name and which one carries the command are the desk's
# knowledge, not the button's.
#
# The vocabulary every emulator shares turned out to be exactly two
# words — "this window is called NAME" and "run this inside" — plus a
# portable title. Nothing else is translated, deliberately: a
# cross-terminal option compiler is a tar pit (each beast themes its
# own way, and -geometry would fight our place rules), so extras ride
# an args branch that names its dialect out loud (see spawn-terminal).
#
# What the name buys is the instance half of WM_CLASS — the match half
# of an idempotent button, and on xterm/urxvt the per-name xrdb branch
# (mutt*background: darkblue) for free. Measured 2026-07-30 under
# Xvfb, not read off manpages:
#
#   xterm -name mutt             {mutt XTerm}    (-class coexists:
#                                -name mutt -class work = {mutt work})
#   urxvt -name mutt             {mutt URxvt}    (urxvtc: per window)
#   kitty --name mutt            {mutt kitty}    (per window under
#                                --single-instance too)
#   alacritty 0.13 --class mutt  {mutt mutt} — a single value fills
#       BOTH halves; the pair is general,INSTANCE, so
#       --class Alacritty,mutt = {mutt Alacritty}: our name in the
#       instance, the beast's own class kept for class-wide styling
#   st 0.9.3 -n mutt             {mutt st-256color} — the default
#       class is its termname, NOT "st" (a patched build may differ)
#   konsole -name mutt           {mutt konsole} — Qt still honors the
#       classic X11 -name; the class is lowercase. Its --qwindowtitle
#       is promptly overwritten by the tab's own title (measured with
#       -e) — kept anyway: a title is volatile on every beast whose
#       guest retitles, mutt in an xterm included.
#   gnome-terminal --name=mutt   {gnome-terminal-server Gnome-terminal}
#       — the factory IGNORES --name; but --class=mutt spawns a
#       DEDICATED server: {gnome-terminal-server mutt}. Its name lives
#       in the CLASS half, which is why the derived match takes either.
#
# The registry: one entry per beast we know. `name` and `title` are
# argv fragments with %s for the value (empty = this beast has no such
# word); `cmd` stands between the options and the command to run;
# `class` is the class half a window of this beast wears — what the
# terminal-window predicate recognizes. DECLARATION ORDER IS THE PROBE
# RANKING: what one installs by hand outranks what a DE brings.
# ...and each says what it LOOKS like, which is the other thing a
# button needs to know about the beast it will spawn (the owner,
# 2026-08-02). A terminal deed that names no icon of its own gets the
# icon of whatever this machine actually resolved to — kitty's on a
# kitty desk, xterm's on an xterm one — because "the terminal" is not
# one program and a button for it should not pretend otherwise. The
# names are the icon themes' own; a miss falls through to the generic
# one below and, failing that, to the badge, so a theme that carries
# none of them still gets a button.
# ...and `bg`/`fg` — background and ink as a GENERALIZABLE property
# of a normal terminal (the owner, 2026-08-04, the ssh-menu model
# task: a tint from the target's name tells twenty terminals apart at
# a glance). The value reaching %s is always #rrggbb — spawn-terminal
# normalizes through winfo rgb, because alacritty knows no X colour
# names at all. xterm is told through -xrm aimed at the VT100 widget
# alone, the right way: a bare -bg would paint its menus too — and
# with the DOT binding, strictly (the owner's measurement,
# 2026-08-05): the colour app-defaults carry dot-bound entries for
# these resources, and a star-bound -xrm loses to them on
# specificity — it worked on the suite's bare Xvfb and not on a real
# desk. A beast
# with no entry (vanilla st compiles its colours in; konsole and
# gnome-terminal keep theirs in profiles) gets the standing "has no
# way to say" line and spawns unpainted.
# ...and `dir` — where the emulator itself stands. The beasts that
# have a word for it say it (kitty's matters most: its new tabs open
# in the terminal's cwd); one that has none (xterm, st) is wrapped in
# `env -C` by spawn-terminal instead, which inherits the same.
set terminal_adapters {
    kitty          {name {--name %s}  title {--title %s} cmd {}   class kitty
                    icon kitty
                    dir {--directory %s}
                    bg {-o background=%s} fg {-o foreground=%s}}
    alacritty      {name {--class Alacritty,%s} title {-T %s} cmd {-e} class Alacritty
                    icon Alacritty
                    dir {--working-directory %s}
                    bg {-o {colors.primary.background = "%s"}}
                    fg {-o {colors.primary.foreground = "%s"}}}
    urxvt          {name {-name %s}   title {-T %s}      cmd {-e} class URxvt
                    icon urxvt
                    dir {-cd %s}
                    bg {-bg %s} fg {-fg %s}}
    st             {name {-n %s}      title {-T %s}      cmd {-e} class st-256color
                    icon st}
    xterm          {name {-name %s}   title {-T %s}      cmd {-e} class XTerm
                    icon xterm-color
                    bg {-xrm {*VT100.background: %s}}
                    fg {-xrm {*VT100.foreground: %s}}}
    konsole        {name {-name %s}   title {--qwindowtitle %s} cmd {-e} class konsole
                    icon konsole
                    dir {--workdir %s}}
    gnome-terminal {name {--class=%s} title {--title %s} cmd {--} class Gnome-terminal
                    icon org.gnome.Terminal
                    dir {--working-directory=%s}}
}
# What every terminal falls back to: the freedesktop standard name for
# "a terminal", carried by every icon theme worth the name.
keep terminal_icon_generic utilities-terminal
# The icon a terminal DEED wears when it named none — the resolved
# beast's, then the generic one. Empty when nothing is resolved at
# all, which is the case where the button is standing by anyway.
proc terminal-icon {} {
    set beast [lindex [terminal-resolve] 0]
    if {$beast eq ""} { return "" }
    set ad [dict get $::terminal_adapters $beast]
    set try {}
    if {[dict exists $ad icon]} { lappend try [dict get $ad icon] }
    lappend try $::terminal_icon_generic
    foreach n $try {
        if {[icon-file-of $n] ne ""} { return $n }
    }
    return ""
}
keep terminal_choice {}   ;# what set-terminal said: {beast path}, or empty
keep terminal_found {}    ;# the resolution, cached: {beast path how}

# set-terminal BEAST ?PATH? — the one config line that picks the
# terminal. The beast and the binary are SEPARATE on purpose (the
# owner's order): "this is kitty, and it lives in
# ~/bin/kitty.experimental.git.master" is one dialect at another path.
# No path = the beast's own name through PATH, at spawn time.
proc set-terminal {beast {path ""}} {
    if {![dict exists $::terminal_adapters $beast]} {
        error "set-terminal: unknown terminal \"$beast\" — one of:\
 [dict keys $::terminal_adapters]"
    }
    set ::terminal_choice [list $beast [expr {$path eq "" ? "" :
        [file normalize $path]}]]
    set ::terminal_found {}
}

# Recognize a binary's basename as a beast we know. The families hide
# behind other names: Debian's x-terminal-emulator resolves to shims
# (gnome-terminal.wrapper — whose xterm dialect EATS -name, rewriting
# it into --window-with-profile; measured), rxvt here IS urxvt (a
# symlink, and classic rxvt speaks the same -name/-e anyway), and
# uxterm/lxterm/koi8rxterm are xterm launchers passing "$@" through.
proc terminal-beast-of {name} {
    if {[dict exists $::terminal_adapters $name]} { return $name }
    switch -glob -- $name {
        gnome-terminal* { return gnome-terminal }
        urxvt* - rxvt*  { return urxvt }
        *xterm*         { return xterm }
    }
    return ""
}

# The chain: the config's word, the user's word ($TERMINAL, the loose
# convention i3 and friends read), the admin's word — x-terminal-
# emulator, but only in MANUAL mode: the alternatives system in auto
# mode is the packaging talking, and it points at a DE terminal
# exactly for the user who never chose one — and then the ranked
# probe. A shim behind the alternative is never executed; the beast's
# own binary is (whoever wants the shim's extras says
# `set-terminal xterm /usr/bin/uxterm` — they pass "$@" through).
# The verdict is cached until a reload; one log line says what was
# picked and on whose word.
# What the desk WOULD use with nobody saying — the resolution, and on
# whose word it stands: «xterm (probed)» is a guess about this
# machine, «kitty ($TERMINAL)» is somebody's environment, and the two
# are different promises. Shown in the tree where the knob is unsaid.
proc terminal-derived {} {
    set r [terminal-resolve]
    if {![llength $r]} { return "" }
    lassign $r beast path source
    return "$beast ($source)"
}
proc terminal-resolve {} {
    if {$::terminal_found ne ""} { return $::terminal_found }
    set found {}
    if {$::terminal_choice ne ""} {
        lassign $::terminal_choice beast path
        if {$path eq ""} { set path [lindex [auto_execok $beast] 0] }
        if {$path eq ""} {
            puts "WM: terminal: set-terminal $beast, but no such binary in PATH"
        } else {
            set found [list $beast $path set-terminal]
        }
    }
    if {$found eq "" && [info exists ::env(TERMINAL)]
            && $::env(TERMINAL) ne ""} {
        set beast [terminal-beast-of [file tail $::env(TERMINAL)]]
        set path [lindex [auto_execok $::env(TERMINAL)] 0]
        if {$beast ne "" && $path ne ""} {
            set found [list $beast $path \$TERMINAL]
        }
    }
    if {$found eq "" && ![catch {
            exec update-alternatives --query x-terminal-emulator} q]
            && [regexp -line {^Status: manual$} $q]
            && [regexp -line {^Value: (.+)$} $q -> val]} {
        set beast [terminal-beast-of [file tail $val]]
        if {$beast ne ""} {
            set path [lindex [auto_execok $beast] 0]
            if {$path ne ""} {
                set found [list $beast $path x-terminal-emulator]
            }
        }
    }
    if {$found eq ""} {
        foreach beast [dict keys $::terminal_adapters] {
            set path [lindex [auto_execok $beast] 0]
            if {$path ne ""} { set found [list $beast $path probed]; break }
        }
    }
    if {$found eq ""} {
        puts "WM: terminal: no emulator found (looked for\
 [dict keys $::terminal_adapters]) — set-terminal?"
        set found [list {} {} none]
    } else {
        puts "WM: terminal: [lindex $found 0] at [lindex $found 1]\
 ([lindex $found 2])"
    }
    set ::terminal_found $found
    return $found
}

# spawn-terminal SPEC — the launch half of a semantic button, and a
# command in its own right (bind it, menu it):
#
#     spawn-terminal {name mutt run mutt}
#     wm-bind {<Super>Return} {spawn-terminal {}}
#
# SPEC keys, each optional:
#   name   the window's name — the instance half of WM_CLASS (the class
#          half on the gnome-terminal factory; see the measurements)
#   run    the command, an exec-style list. A wrapper chain is plain
#          argv concatenation and gets no grammar of its own:
#          run {uim-fep -e ssh -t host "tmux attach || tmux"} — the
#          quoted tail stays one element, Tcl lists do the nesting.
#   title  the window title; every beast has a word for it (Debian
#          policy guarantees -T even for the shims), so a title
#          survives even the launch-only degradation — there it is the
#          only visible mark.
#   env    VAR VALUE dict for the TERMINAL's environment — the one
#          thing args cannot say: it needs its slot BEFORE the binary.
#          env {XMODIFIERS {}} is "cut uim-xim off this xterm"; an
#          empty value means VAR= (set empty), not unset.
#   bg/fg  the window's background and ink, any Tk-legal colour —
#          normalized to #rrggbb and spelled in the beast's own
#          dialect (the adapter table). A beast with no way to say
#          them spawns unpainted, with a line saying so.
#   args   beast-keyed extras:
#          {xterm {-bg darkblue} kitty {-o background=darkblue}}.
#          A key is a beast name, a LIST of beast names, or *; every
#          branch matching the active beast applies, in order,
#          VERBATIM. This is your terminal's own dialect said out
#          loud — nothing here is translated, and that is what lets a
#          shared button definition stay terminal-agnostic while
#          carrying goodies for some.
proc spawn-terminal {spec} {
    foreach k [dict keys $spec] {
        if {$k ni {name run title env args bg fg dir}} {
            error "spawn-terminal: unknown key \"$k\"\
 (name run title env args bg fg dir)"
        }
    }
    lassign [terminal-resolve] beast path
    if {$beast eq ""} {
        error "spawn-terminal: no terminal emulator (set-terminal?)"
    }
    set ad [dict get $::terminal_adapters $beast]
    # WHERE THE EMULATOR STANDS — the action's dir, threaded here by
    # spec-derive: the beast's own flag when the table has one, and a
    # plain `env -C` around the process when it has not — cwd is
    # inherited either way, which is what kitty's new tabs live on.
    # A `~` is a path said the human way — expand at use time, the
    # icon-file-of pattern (Tcl 9 dropped the implicit expansion).
    set dir ""
    if {[dict exists $spec dir] && [dict get $spec dir] ne ""} {
        set dir [dict get $spec dir]
        catch {set dir [file tildeexpand $dir]}
    }
    set argv [list $path]
    if {$dir ne "" && [dict exists $ad dir]} {
        lappend argv {*}[lmap a [dict get $ad dir] {
            string map [list %s $dir] $a}]
        set dir ""      ;# said in the beast's own words — no wrap
    }
    foreach key {name title bg fg} {
        if {![dict exists $spec $key] || [dict get $spec $key] eq ""} continue
        set val [dict get $spec $key]
        if {$key in {bg fg}} { set val [color-hex $val] }
        set fmt [expr {[dict exists $ad $key] ? [dict get $ad $key] : ""}]
        if {$fmt eq ""} {
            puts "WM: terminal: $beast has no way to say $key —\
 \"[dict get $spec $key]\" dropped"
            continue
        }
        lappend argv {*}[lmap a $fmt {
            string map [list %s $val] $a}]
    }
    if {[dict exists $spec args]} {
        dict for {beasts extra} [dict get $spec args] {
            if {$beasts eq "*" || $beast in $beasts} {
                lappend argv {*}$extra
            }
        }
    }
    if {[dict exists $spec run] && [llength [dict get $spec run]]} {
        lappend argv {*}[dict get $ad cmd] {*}[dict get $spec run]
    }
    set pre [env-argv $spec]
    if {$dir ne ""} { set pre [list -C $dir {*}$pre] }
    if {[llength $pre]} { set argv [list env {*}$pre {*}$argv] }
    puts "WM: terminal: spawn $argv"
    run-argv $argv
}

# What `Run` means while a terminal action fires: the words are the
# command the terminal is opened AROUND. The spec is the action's own
# terminal word — name, title, env, beast dialect — and the command is
# the only part of it that comes from the launch.
proc spawn-terminal-run {spec argv} {
    dict set spec run $argv
    spawn-terminal $spec
}

# The predicate behind a nameless `terminal {}` button: is this window
# a terminal AT ALL — the class half against every class the registry
# knows, plus the xterm launchers wearing their own (their -class
# flags read straight out of /usr/bin/uxterm and friends). Any beast's
# window answers, whoever is active today: the desk one switched
# set-terminal on still has yesterday's windows.
proc terminal-window {w} {
    set cls [lindex [client-class $w] 1]
    dict for {beast ad} $::terminal_adapters {
        if {$cls eq [dict get $ad class]} { return 1 }
    }
    expr {$cls in {UXTerm KOI8RXTerm}}
}

# ---- errands: work the desk waits for without stopping ----
# The event loop IS the desk: a handler that blocks freezes every
# window on the screen. So anything that talks to the world outside
# runs as an ERRAND — a coroutine over the future substrate (fut.tcl,
# vendored) — and reads top to bottom instead of scattering itself
# over a channel callback, a state variable and a guard timer, which
# is what the emacs round trip was before this.
#
# The body is a COMMAND, not a script fragment: an errand outlives
# the frame that started it, so anything it needs must be baked into
# the command word by word ([list something $cmd]) rather than left
# as a variable that will not be there. An errand that throws says so
# and dies alone; a cancelled one (a timeout is a cancel) is not an
# error to report twice.
keep errand_seq 0
proc wm-errand {label body} {
    set name ::errand[incr ::errand_seq]
    coroutine $name apply [list {label body} {
        if {[catch {uplevel #0 $body} err opts]} {
            if {[lrange [dict get $opts -errorcode] 0 1] eq {FUT CANCELLED}} {
                puts "WM: errand «$label» timed out"
            } else {
                puts "WM: errand «$label» FAILED: $err"
            }
        }
    }] $label $body
}
# ---- pipe-run: a process, without holding the desk still ----
# THE WORKHORSE the rest of this stands on (the owner's ask,
# 2026-08-01: whatever runs processes here must be able to keep
# stdout and stderr apart, so it can grow into a proper launcher
# rather than be replaced by one).
#
# Answers a FUTURE settling with {status N out TEXT err TEXT}. The
# pipeline is read by the EVENT LOOP — no wait, no frozen desk — and
# every launch is its own pipeline: nothing here serializes anything,
# which is what one expects of a desk (the owner: xbindkeys does not
# serialize his bindings either).
#
#   -stderr merge     (default) stderr joins stdout, as `exec 2>@1`
#   -stderr separate  kept apart, through a `chan pipe` — measured to
#                     work in this build, and it costs no temp file
#   -stderr drop      thrown away
#   -stderr said      nothing is wired: the argv has its own say
#                     (`2>`, `>&`) and the caller means it to stand
#   -timeout MS       cancel and kill the pipeline after this long; 0
#                     (default) waits as long as it takes. `emacs
#                     --daemon` deciding to byte-compile mu4e at
#                     startup is exactly the case: taking a minute is
#                     allowed, taking the desk with it is not.
#
# THE STATUS NEEDS A BLOCKING CLOSE. A non-blocking pipeline's close
# returns at once and reaps nothing — measured, whale9: the same run
# reported status 0 non-blocking and 3 blocking. Both ends are drained
# by then, so the switch costs nothing.
proc pipe-run {argv args} {
    set o [dict merge {-stderr merge -timeout 0 -patience 0 -say {} -tail 10} \
               $args]
    set f [fut::new]
    set st [dict create out "" err "" status 0]
    set errrd ""
    switch -- [dict get $o -stderr] {
        merge    { set spec [list {*}$argv 2>@1] }
        drop     { set spec [list {*}$argv 2>/dev/null] }
        said     { set spec $argv }
        separate {
            lassign [chan pipe] errrd errwr
            set spec [list {*}$argv 2>@$errwr]
        }
        default { error "pipe-run: -stderr is merge, separate, drop or said" }
    }
    if {[catch {open |$spec r} ch]} {
        catch {close $errrd}; catch {close $errwr}
        fut::fail $f $ch
        return $f
    }
    if {$errrd ne ""} { close $errwr }
    set state [dict create f $f ch $ch errrd $errrd st $st open 1 \
                   pids [pid $ch]]
    if {$errrd ne ""} { dict incr state open }
    set ::pipe_state($ch) $state
    # -profile tcl8, because a child's bytes must not wedge the desk:
    # Tcl 9's strict default THROWS on the first byte that is not
    # honest UTF-8, inside the fileevent handler — and real children
    # write such bytes (measured, 2026-08-06: emacs prints an emoji
    # that came over telega's wire as CESU-8 surrogates, and a
    # getTopChats answer killed the read). tcl8 is the pre-9 behavior:
    # every byte decodes to SOMETHING and the reader downstream deals
    # with what it means.
    foreach {c which} [list $ch out $errrd err] {
        if {$c eq ""} continue
        fconfigure $c -blocking 0 -profile tcl8
        fileevent $c readable [list pipe-run-read $ch $c $which]
    }
    # ...through a proc of its own, because fut::cancel hands every
    # cancel handler the future as a LAST argument: registering
    # `pipe-run-close $ch 1` meant a wrong-arg error in a background
    # `after`, and the kill below never ran (measured, 2026-08-01 —
    # the timeout said the right thing while the process lived on)
    fut::oncancel $f [list pipe-run-cancelled $ch]
    if {[dict get $o -timeout] > 0} {
        after [dict get $o -timeout] \
            [list pipe-run-timeout $ch [dict get $o -timeout] [dict get $o -tail]]
    }
    if {[dict get $o -patience] > 0} {
        after [dict get $o -patience] [list pipe-run-patience $ch \
            [dict get $o -patience] [dict get $o -tail] [dict get $o -say]]
    }
    return $f
}
proc pipe-run-cancelled {key f} { pipe-run-close $key 1 }
# WHAT IT MANAGED TO SAY BEFORE IT WAS CUT OFF. A process that ran out
# of time is exactly the one whose last few lines are worth reading —
# «starting the daemon takes forever» is a sentence, and the tail is
# the diagnosis (the owner, 2026-08-01).
proc pipe-run-tail {key n} {
    if {![info exists ::pipe_state($key)]} { return {} }
    set st [dict get $::pipe_state($key) st]
    set lines {}
    foreach which {out err} {
        foreach l [split [string trim [dict get $st $which]] \n] {
            if {[string trim $l] ne ""} { lappend lines $l }
        }
    }
    return [lrange $lines end-[expr {$n - 1}] end]
}
proc pipe-run-timeout {key ms n} {
    if {![info exists ::pipe_state($key)]} return
    set tail [pipe-run-tail $key $n]
    set f [dict get $::pipe_state($key) f]
    # killed HERE rather than through fut::cancel, so the tail can
    # ride in the error code: an awaiter reads a sentence, and
    # whoever wants the diagnosis has it without parsing the sentence
    pipe-run-close $key 1
    fut::fail $f "timed out after $ms ms" \
        [list -code error -errorcode [list PIPE TIMEOUT $tail]]
}

# ---- patience: say it is slow, but do not kill it ----
# Some waits must not end in a kill. `emacsclient -a ''` starts the
# daemon ITSELF and waits for the socket — killing the client when we
# lose patience does not stop the daemon coming up, it only throws
# away the answer we were waiting for (the owner, 2026-08-01). So:
# patience runs out, somebody is TOLD, and the wait goes on.
proc pipe-run-patience {key ms n say} {
    if {![info exists ::pipe_state($key)]} return
    if {[llength $say]} {
        soft "say a slow process is slow" \
            [list {*}$say $ms [pipe-run-tail $key $n]]
    }
}
proc pipe-run-read {key c which} {
    if {![info exists ::pipe_state($key)]} { catch {close $c}; return }
    set state $::pipe_state($key)
    set st [dict get $state st]
    dict append st $which [read $c]
    dict set state st $st
    if {[eof $c]} {
        fileevent $c readable {}
        dict incr state open -1
    }
    set ::pipe_state($key) $state
    # ...and when both ends have said everything they had to say, the
    # status is read once, by the close below
    if {[dict get $state open] <= 0} { pipe-run-close $key 0 }
}
# ...and the end of it, whichever end it is: the status is read here
# and nowhere else, so a cancel and a clean finish leave the same
# shape behind.
proc pipe-run-close {key killed} {
    if {![info exists ::pipe_state($key)]} return
    set state $::pipe_state($key)
    unset ::pipe_state($key)
    set ch [dict get $state ch]
    set st [dict get $state st]
    catch {fileevent $ch readable {}}
    if {[dict get $state errrd] ne ""} {
        catch {fileevent [dict get $state errrd] readable {}}
        catch {close [dict get $state errrd]}
    }
    # A CANCEL MUST KILL FIRST. Closing a pipeline's channel waits for
    # its children — so a timeout on `sleep 30` would have held the
    # desk still for the thirty seconds it was cancelling (measured,
    # 2026-08-01: the process outlived its own timeout). Killed
    # first, the close returns at once.
    if {$killed} {
        foreach p [dict get $state pids] { catch {exec kill $p} }
    }
    catch {fconfigure $ch -blocking 1}
    set status 0
    if {[catch {close $ch} err opts]} {
        set ec ""
        catch {set ec [dict get $opts -errorcode]}
        if {[lindex $ec 0] eq "CHILDSTATUS"} {
            set status [lindex $ec 2]
        } else {
            set status -1
            dict append st err $err
        }
    }
    dict set st status $status
    if {!$killed} { fut::fulfill [dict get $state f] $st }
}

# ---- exec, cooperative where it can be ----
# The owner's call (2026-08-01), and the better one: not a new word
# to remember but the SAME word, doing what it always did — except
# that inside a coroutine it parks instead of holding the desk still.
# A binding writes `exec gpg --decrypt … | grep password:` and reads
# like a shell script; the desk answers keys while gpg thinks.
# Shadowing the global is his call too (2026-08-02, reversing an
# earlier «never touch exec»; the origin was a bound `exec xedit`
# freezing the desk until the editor closed), and the objection —
# that a synchronous exec is legitimate in the config and in the
# desk's own code — still holds: neither runs in a coroutine, and
# both forward to the real exec exactly as before.
#
# It is a shim, not a new command, so it has to be honest about
# exec's own contract, which is fussier than it looks:
#   - a non-zero exit is an error, and the message carries what the
#     child managed to say first — that is the sentence worth
#     reading when a bound command goes wrong;
#   - ANYTHING on stderr is an error of its own unless -ignorestderr
#     says otherwise;
#   - -keepnewline keeps the trailing newline the result otherwise
#     loses;
#   - `&` at the end means «do not wait», which is the opposite of
#     what parking is for.
# Redirections and pipes RIDE ALONG (the owner's word, 2026-08-07:
# let everything through): the words go to pipe-run as they stand —
# open's pipeline shares exec's grammar — and when the line itself
# says where stderr goes (`2>`, `>&`), no plumbing of our own is
# added and stderr stops being an error, which is exec's own rule
# for a redirected stream. What still goes to the real exec, renamed
# rather than replaced: the background form (`&` means «do not
# wait», and the real exec does not wait), a switch it did not parse
# (the honest error lives there), or no coroutine to park in.
if {![llength [info commands exec-blocking]]} {
    rename exec exec-blocking
}
proc exec {args} {
    set said $args
    set opts {}
    while {[llength $args]} {
        set a [lindex $args 0]
        if {$a eq "--"} { set args [lrange $args 1 end]; break }
        if {$a ni {-keepnewline -ignorestderr}} break
        lappend opts $a
        set args [lrange $args 1 end]
    }
    if {[info coroutine] eq "" || ![llength $args]
            || [string match -* [lindex $args 0]]
            || [lindex $args end] eq "&"} {
        return [exec-blocking {*}$said]
    }
    set mode separate
    foreach a $args {
        if {[regexp {^(2>|>>?&)} $a]} { set mode said; break }
    }
    set r [fut::await [pipe-run $args -stderr $mode]]
    set err [dict get $r err]
    set out [dict get $r out]
    if {"-keepnewline" ni $opts && [string index $out end] eq "\n"} {
        set out [string range $out 0 end-1]
    }
    if {[dict get $r status] != 0} {
        set msg [string trim "$out\n$err"]
        if {$msg ne ""} { append msg \n }
        append msg "child process exited abnormally"
        return -code error -errorcode \
            [list CHILDSTATUS 0 [dict get $r status]] $msg
    }
    if {$err ne "" && "-ignorestderr" ni $opts} {
        return -code error -errorcode NONE [string trim $err]
    }
    return $out
}
# ---- Exec: the same, said the way one writes a script ----
# `exec` with the desk left running. Capitalized like every word here
# that ACTS, and a word of its own rather than a redefinition of
# Tcl's: the global `exec` stays what it is, in the config's top
# level (where blocking is harmless — nothing is interactive yet) and
# in the desk's own code.
#
# Needs a coroutine, because that is what parking is made of; a bind
# script gets one, a config's top level does not — and the error says
# so rather than hanging.
# ...and the same thing under a name that INSISTS on it: `exec` falls
# back to blocking where it must, `Exec` says the cooperative form is
# the point and refuses to be anything else.
proc Exec {args} {
    if {[info coroutine] eq ""} {
        error "Exec needs a coroutine to park in — a binding's script has one; at a config's top level exec blocks, and hurts nobody doing it"
    }
    return [exec {*}$args]
}

# A command's output as a future: the pipe is read by the event loop,
# the future settles at eof, and a cancel (fut::timeout's, say) kills
# the pipe rather than leaving it draining into nobody.
proc pipe-output {cmd} {
    set f [fut::new]
    if {[catch {open |[list {*}$cmd 2>@1] r} ch]} {
        fut::fail $f $ch
        return $f
    }
    chan configure $ch -blocking 0 -profile tcl8
    set ::pipe_buf($ch) {}
    fut::oncancel $f [list pipe-output-close $ch]
    fileevent $ch readable [list pipe-output-read $ch $f]
    return $f
}
proc pipe-output-read {ch f} {
    append ::pipe_buf($ch) [read $ch]
    if {![eof $ch]} return
    set out $::pipe_buf($ch)
    fileevent $ch readable {}
    unset ::pipe_buf($ch)
    # a non-zero exit is not a failure here: emacsclient says what is
    # wrong ON the pipe, and that text is the answer worth having
    if {[catch {close $ch} err] && [string trim $out] eq ""} { set out $err }
    fut::fulfill $f $out
}
proc pipe-output-close {ch} {
    catch {fileevent $ch readable {}}
    unset -nocomplain ::pipe_buf($ch)
    catch {close $ch}
}

# ---- the emacs layer ----
# A button that means "the telega frame of the telega daemon" — on the
# desk the owner actually keeps: dedicated daemons (emacs --daemon=telega
# for telega.el), frames either X or inside a terminal, whichever the
# user prefers. The load-bearing find, measured 2026-07-31 on Emacs
# 32.0.50: A FRAME'S NAME PARAMETER IS THE INSTANCE HALF OF WM_CLASS —
# `emacsclient -c -F '((name . "TELEGA"))'` yields {TELEGA Emacs} — so
# the match is the terminal layer's own single-pattern filter, and one
# button finds its frame as {TELEGA Emacs} or its named terminal as
# {TELEGA XTerm} with the same predicate, no daemon round-trip in the
# match path at all.
#
# The -F goes on TERMINAL frames too (the owner's design): a tty frame
# carries the name, so the daemon can be asked for it later. That is
# what makes the terminal case honest against `C-x 5 2` — the user
# opened another frame in that terminal and closed the named one; the
# terminal window still matches, but the frame inside is not ours any
# more. The fire path then REPAIRS: focus the window at once (nothing
# waits on a daemon), and one background round-trip asks the daemon to
# put the named frame back on top of its tty — or to recreate it there.
# Ownership is assumed, not verified: a frame wearing a name from this
# config is OURS (the owner's ruling; whoever names frames to spoof a
# desk is spoofing their own).
#
# The rest of the measured floor this stands on (2026-07-31, not
# documentation): `nil` in frame-parameter over emacsclient -e is the
# daemon's selected frame — the last frame that saw input or creation
# ON ANY DISPLAY — and outer-window-id values COLLIDE between X
# servers, so frames are always found by (frame-list) filter, never by
# nil and never by bare id. `emacsclient -s NAME -a ''` auto-starts a
# daemon WITH that socket name, so ensure-daemon costs nothing. And on
# a tty, select-frame-set-input-focus (plus a redisplay) is what moves
# tty-top-frame; bare raise-frame does not.
keep emacs_frames gui
keep emacs_daemons on      ;# off = every emacs button is plain lookup-or-run
keep emacs_autodaemon on   ;# off = a dead socket is an error, never a spawn
# Whether a missing daemon is STARTED (-a '') or is an error. Default
# on — the one-command ensure is half the layer's point — but some
# desks have systemd (or a session script) owning the daemons, and an
# accidentally auto-started one lives in whatever environment the WM
# happened to have: the owner's case for the off switch. Per button:
# the `autodaemon` spec key.
# ...and whether there are daemons AT ALL. Off = every emacs button
# degrades to the simple life: lookup by the same match, run
# `emacs --name FRAME --eval ...` when nothing lives (emacs puts
# --name into the WM_CLASS instance exactly like xterm does, so the
# match never changes). No server means no eval-on-hit and no tty
# repair — the hit is the whole story; that is the price and it is
# stated here rather than discovered. Per button: `daemon none`.
# ...and WHETHER THE FRAME KEEPS THE NAME IT WAS BORN WITH. It is born
# with one because the name is how the desk finds the window: a
# frame's name parameter is the instance half of its WM_CLASS. But
# WM_CLASS is written once, at creation, and the name goes on being
# the TITLE — so a frame made for a button called `telega` wears the
# word TELEGA in its titlebar forever, where emacs would otherwise say
# what buffer one is looking at.
#
# The owner's own pattern was to hand the title back by hand — a
# button carrying `eval {(set-frame-name nil)}` — and that is the
# better default (his call, 2026-08-02): the desk still finds the
# window by class, the daemon still finds the frame by our own
# tk9wm-frame parameter, and the titlebar goes back to saying
# something. `keep-frame-name on` — desk-wide here, per button in the
# spec — is for whoever wants the button's word standing in the title.
keep emacs_keep_frame_name off
# All these knobs are consulted AT FIRE TIME, never baked in at the
# button's declaration — a knob set later in the config must win
# (the styleof lesson, again).
proc emacs-plain? {spec} {
    expr {$::emacs_daemons eq "off"
          || ([dict exists $spec daemon] && [dict get $spec daemon] eq "none")}
}
proc emacs-keep-name? {spec} {
    if {[dict exists $spec keep-frame-name]} {
        return [expr {[dict get $spec keep-frame-name] eq "on"}]
    }
    expr {$::emacs_keep_frame_name eq "on"}
}
# What used to be emacs-spec-check lives in the spec registry now:
# the key list, the frame it cannot do without, the two words `via`
# and `autodaemon` may be, and the env's shape are all things the
# table says, and spec-check reads them at the declaration.
# The styleguard lesson, applied everywhere a config hands us a dict:
# an odd list must die at ITS declaration, not inside a dict call at
# some later use with a stack that names nobody.
proc dict-shaped {who d key} {
    if {[dict exists $d $key] && [llength [dict get $d $key]] % 2} {
        error "$who is not a dict (odd length):\
 «[dict get $d $key]» — values with spaces need their own braces"
    }
}
# The env the launch runs under, applied around a SCRIPT: children of
# any exec inherit ::env, and the previous values go back whatever
# happens. An empty value means VAR= (set empty), not unset.
proc with-env {envd script {unsetl {}}} {
    set saved {}
    dict for {var val} $envd {
        lappend saved $var [expr {[info exists ::env($var)]
                                  ? [list [set ::env($var)]] : {}}]
        set ::env($var) $val
    }
    # ...and the ones that must be ABSENT rather than empty. The owner
    # worked around their lack with `env XMODIFIERS=` (2026-08-01);
    # said this way, the child sees no such variable at all — and the
    # config needs no tombstone for it, because absence is a member of
    # another word instead of a state of this one.
    foreach var $unsetl {
        lappend saved $var [expr {[info exists ::env($var)]
                                  ? [list [set ::env($var)]] : {}}]
        unset -nocomplain ::env($var)
    }
    set code [catch {uplevel #0 $script} res opts]
    foreach {var prev} $saved {
        if {[llength $prev]} {
            set ::env($var) [lindex $prev 0]
        } else {
            unset -nocomplain ::env($var)
        }
    }
    if {$code} { return -options $opts $res }
    return $res
}
# The env words of a spec, as env(1) takes them: assignments, and
# -u for what must not be there at all. Empty here means the variable
# is set to nothing, which is a different wish and stays sayable.
proc env-argv {spec} {
    set out {}
    if {[dict exists $spec env-unset]} {
        foreach var [dict get $spec env-unset] { lappend out -u $var }
    }
    if {[dict exists $spec env]} {
        dict for {var val} [dict get $spec env] { lappend out $var=$val }
    }
    return $out
}
# The name, spelled into elisp. Config-authored, so sane — but a quote
# or backslash must not silently change the expression's shape.
proc emacs-lisp-string {s} {
    return "\"[string map {\\ \\\\ \" \\\"} $s]\""
}
proc emacs-client-cmd {spec} {
    set cmd [list emacsclient]
    if {[dict exists $spec daemon] && [dict get $spec daemon] ne ""} {
        lappend cmd -s [dict get $spec daemon]
    }
    return $cmd
}
# WHAT THE NEW FRAME IS TOLD, once, at birth: give the title back
# (unless the button wants its word kept — see set-emacs-keep-frame-
# name), and then whatever the button itself says. In that order, so
# an eval that fails still leaves the title mended — and so an eval
# that sets a title of its own has the last word.
#
# Only the LAUNCH carries the rename. The button's own eval rides
# every activation too (emacs-activate), and a frame does not need to
# be told a second time to be nameless.
proc emacs-launch-eval {spec} {
    set forms {}
    if {![emacs-keep-name? $spec]} { lappend forms {(set-frame-name nil)} }
    if {[dict exists $spec eval]} { lappend forms [dict get $spec eval] }
    switch -- [llength $forms] {
        0 { return {} }
        1 { return [lindex $forms 0] }
        default { return "(progn [join $forms { }])" }
    }
}
# The launch half: nothing named ours exists, make it — daemon
# included, -a '' starting one under the right socket if need be. The
# gui shape is the owner's own command; the terminal shape is the SAME
# semantics handed to the terminal layer, so the frame name and the
# terminal name coincide and the shared match keeps holding.
proc emacs-launch {spec} {
    # The identity launcher, and it cannot work without one: a deed
    # lends its own name (action-derive), and a bare call from a
    # script must say a frame. The edit door, which needs no identity
    # at all, goes through emacs-edit-open instead.
    if {![dict exists $spec frame]} {
        error "emacs-launch: no frame name — a deed lends its own,\
 a bare call must say one"
    }
    set frame [dict get $spec frame]
    set via $::emacs_frames
    if {[dict exists $spec via]} { set via [dict get $spec via] }
    # The spec's env rides the argv (exec env VAR=VAL ...), so an
    # auto-started daemon inherits it too — the owner's case: a
    # daemon born of -a '' otherwise lives in whatever environment
    # the WM happened to have.
    set pre [env-argv $spec]
    if {[llength $pre]} { set pre [list env {*}$pre] }
    if {[emacs-plain? $spec]} {
        # The simple life, by request: lookup-or-run, no server
        # anywhere. emacs puts --name into the WM_CLASS instance
        # exactly like xterm, so the match is untouched; the eval
        # runs once, at birth — with no server there is no
        # eval-on-hit and no tty repair, and the hit is the whole
        # story.
        set ev [emacs-launch-eval $spec]
        if {$via eq "terminal"} {
            set run [concat $pre [list emacs -nw]]
            if {$ev ne ""} { lappend run --eval $ev }
            spawn-terminal [list name $frame title $frame run $run]
        } else {
            set cmd [concat $pre [list emacs --name $frame]]
            if {$ev ne ""} { lappend cmd --eval $ev }
            puts "WM: emacs: launch $cmd"
            exec {*}$cmd &
        }
        return
    }
    # A HANDLE THAT THE FRAME'S OWN NAME CANNOT TAKE AWAY. The name
    # is what emacs shows in the title and what an X frame's WM_CLASS
    # instance is made from — and a useful pattern the owner found
    # (2026-08-01) hands the title back to emacs right after birth:
    # `eval {(set-frame-name nil)}`. WM_CLASS is set once at creation
    # and survives that, so the desk still FINDS the window; the
    # daemon-side lookup did not, because it asked for a frame by
    # name. With one tty terminal alive it would then take the
    # rebuild branch and make a SECOND frame in a terminal — a raise
    # turning into a spawn, which is as wrong as it sounds.
    #
    # So the frame carries our own parameter as well, and it is that
    # one the lookup asks for. Emacs leaves parameters it does not
    # know alone; a frame made before this line still answers by name
    # (see activate-frame.el).
    set F "((name . [emacs-lisp-string $frame]) (tk9wm-frame . [emacs-lisp-string $frame]))"
    set auto $::emacs_autodaemon
    if {[dict exists $spec autodaemon]} { set auto [dict get $spec autodaemon] }
    set cmd [emacs-client-cmd $spec]
    if {$auto eq "on"} { lappend cmd -a {} }
    set ev [emacs-launch-eval $spec]
    # A TITLE FOR THE TERMINAL, and it is the frame's word: a terminal
    # left to name its own window takes the first word of the command
    # it was given, which here is `env` or `emacsclient` — true, and
    # useless (the owner's point about the tmux button, 2026-08-02).
    # The name goes on being the WM_CLASS instance the match reads.
    if {$via eq "terminal"} {
        set run [concat $pre $cmd [list -t -F $F]]
        if {$ev ne ""} { lappend run --eval $ev }
        spawn-terminal [list name $frame title $frame run $run]
    } else {
        set cmd [concat $pre $cmd [list -c -F $F -n]]
        if {$ev ne ""} { lappend cmd --eval $ev }
        puts "WM: emacs: launch $cmd"
        exec {*}$cmd &
    }
}
# THE FRAMELESS DEED — `frame {}` — is a PURE EVAL (the owner's ask,
# 2026-08-11): no frame made, no window matched, the press just says
# the form to the daemon and the daemon does the thing. The use is
# real — «tell telega to X», «toggle the theme» — deeds whose whole
# meaning is a form, not a window. Every press is a launch (there is
# nothing to find), the daemon's verdict lands in the log like every
# eval's, and autodaemon governs the socket exactly as it does for a
# frame — the spec's env riding an auto-started daemon the same way.
# set-emacs-daemons off is the one word that empties it: a pure eval
# has nobody else to talk to, and says so instead of pretending.
proc emacs-eval-fire {spec} {
    if {[emacs-plain? $spec]} {
        problem-record "emacs" "a pure eval (frame {}) needs a daemon —\
 set-emacs-daemons off leaves it nobody to talk to"
        return
    }
    set pre [env-argv $spec]
    if {[llength $pre]} { set pre [list env {*}$pre] }
    set cmd [concat $pre [emacs-client-cmd $spec]]
    set auto $::emacs_autodaemon
    if {[dict exists $spec autodaemon]} { set auto [dict get $spec autodaemon] }
    if {$auto eq "on"} { lappend cmd -a {} }
    lappend cmd -e [dict get $spec eval]
    puts "WM: emacs: eval $cmd"
    wm-errand "emacs eval" [list emacs-eval-run $cmd]
}
# The activate half, replacing the plain focus for a hit of an emacs
# button. The window comes up IMMEDIATELY — no fire waits on a daemon —
# and what the round-trip then does depends on what the hit is: an
# {NAME Emacs} window IS the frame, done; a terminal window gets the
# repair eval below. One self-contained expression, so the daemon
# decides and reports in a single trip: the named frame exists — put
# it on top of its tty; gone, and exactly one tty terminal lives —
# recreate it there (re-running the button's eval in it: the frame was
# closed, its meaning starts over); anything else — say so. The
# verdict lands in the log either way, which is what "no hanging bugs"
# means here: every branch ends in an action or a sentence.
# Elisp that outgrows one line lives in .el files under library/elisp/
# (the owner's order): editable as elisp, not as a string in Tcl. The
# WM does not punch placeholders into the text either — a template is
# NATURAL elisp against a small API, and this wraps it in a let that
# provides that API (the file's form sits inside the let textually, so
# lexical binding covers it). Read per use: the file is small, and
# Reread semantics come for free.
proc emacs-template {name bindings} {
    set ch [open [file join $::tk9wm_library elisp $name] r]
    set body [read $ch]
    close $ch
    return "(let ($bindings)\n$body)"
}
proc emacs-activate {spec w} {
    panel-focus-hit $w
    # THE EVAL RIDES EVERY ACTIVATION, not only a fresh frame (the
    # owner's report, live): the frame may have wandered off to other
    # work, and the button means "back to telega" — so (telega) runs
    # on the hit too. A smarter policy — "stay put when already in a
    # telega buffer" — is the eval's own business: it runs inside the
    # frame and can ask where it is.
    # A plain-mode button (set-emacs-daemons off, or daemon none) has
    # no server to talk to: the hit IS the whole story, by contract.
    if {[emacs-plain? $spec]} return
    set isgui [expr {[lindex [client-class $w] 1] eq "Emacs"}]
    if {$isgui && ![dict exists $spec eval]} return
    set fix t
    if {[dict exists $spec eval]} {
        set fix "(with-demoted-errors \"%S\" [dict get $spec eval])"
    }
    emacs-eval-bg $spec [emacs-template activate-frame.el \
        "(tk9wm-name [emacs-lisp-string [dict get $spec frame]])\
 (tk9wm-keep [expr {[emacs-keep-name? $spec] ? "t" : "nil"}])\
 (tk9wm-fix (lambda () $fix))"]
}
# A background emacsclient -e: the WM's event loop never waits on a
# socket. No -a here on purpose — a repair must not START a daemon; if
# the socket is dead, the honest outcome is its error in the log. The
# guard reaps a connection that answers nothing: a wedged daemon must
# not leak channels, and must say so.
# ---- which editor, and through which door ----
# HOW THIS DESK WALKS AN EDITOR INTO A FILE — one default for every
# «open it» the desk offers, resolved the way the terminal is: a
# chain with its sources said out loud, cached until a reload, one
# log line naming what was picked and on whose word. Unsaid, the door
# is emacs when this machine has one — the door rides emacsclient,
# but «is there an emacs here» is the question, so both halves are
# asked — else an editor in a terminal.
keep edit_door {}          ;# the config's word: emacs | terminal; {} = pick here
keep edit_door_found {}    ;# the resolution, cached: {door argv source}
proc set-edit-door {how} {
    set ::edit_door $how
    set ::edit_door_found {}
}
# The terminal door's editor — a chain with an attribution each: the
# user's own word first ($VISUAL outranks $EDITOR, the order
# sensible-editor itself reads them in; either may carry arguments),
# then sensible-editor — Debian's, and it honors a select-editor
# choice this desk has no window into — then a plain hunt. A word
# naming a binary this machine lacks falls through with a line, the
# way $TERMINAL does. xedit closes the hunt and is its own X11
# window: the third element says so, and the door opens it bare
# rather than wrap a GUI in a terminal it never asked for.
proc editor-resolve {} {
    foreach var {VISUAL EDITOR} {
        if {![info exists ::env($var)] || $::env($var) eq ""} continue
        set argv [regexp -all -inline {\S+} $::env($var)]
        if {[auto_execok [lindex $argv 0]] eq ""} {
            puts "WM: edit door: \$$var names [lindex $argv 0] — no such\
 binary in PATH"
            continue
        }
        return [list $argv "\$$var" 0]
    }
    foreach ed {sensible-editor vim vi mcedit nano} {
        if {[auto_execok $ed] ne ""} { return [list [list $ed] probed 0] }
    }
    if {[auto_execok xedit] ne ""} { return [list xedit probed 1] }
    return {}
}
# The resolution: what the desk WOULD open, and on whose word —
# «emacs (found)» is a promise about this machine, «vim ($EDITOR)»
# somebody's environment. A said `emacs` stands even with no emacs
# here: the user said it, and the honest outcome is emacsclient's own
# error at the moment of opening, not a silent detour. Cached like
# the terminal's verdict — PATH does not move under a desk
# mid-session, and when it does, a reload re-asks.
proc edit-door-resolve {} {
    if {$::edit_door_found ne ""} { return $::edit_door_found }
    set found {}
    if {$::edit_door eq "emacs"
            || ($::edit_door eq "" && [auto_execok emacs] ne ""
                && [auto_execok emacsclient] ne "")} {
        set found [list emacs {} [expr {$::edit_door eq "emacs"
                                        ? "set-edit-door" : "found"}]]
    } else {
        set r [editor-resolve]
        if {[llength $r]} {
            lassign $r argv source bare
            set found [list [expr {$bare ? "bare" : "terminal"}] $argv $source]
        }
    }
    if {$found eq ""} {
        puts "WM: edit door: no editor anywhere — set-edit-door, \$EDITOR,\
 or install one (sensible-editor vim vi mcedit nano xedit)"
        set found {none {} none}
    } else {
        puts "WM: edit door: [edit-door-name $found]"
    }
    set ::edit_door_found $found
    return $found
}
# The verdict as one line — the log's and, while the knob is unsaid,
# the tree's derived answer.
proc edit-door-name {found} {
    lassign $found door argv source
    switch -- $door {
        emacs    { return "emacs ($source)" }
        terminal { return "[lindex $argv 0] ($source), in a terminal" }
        bare     { return "[lindex $argv 0] ($source), its own window" }
    }
    return ""
}
proc edit-door-derived {} { edit-door-name [edit-door-resolve] }
# OPENING THE LINE THAT SAYS IT. A config is a file a person writes by
# hand, so «where is this said» deserves a way to get there (the
# owner, 2026-08-02). Only the CONFIG's own lines are ever offered:
# the custom file is written by click, and nobody opens it to edit.
# All doors are the desk's existing ones — an emacs frame of ours, or
# an editor in whatever terminal the desk was told to use — so a
# machine with none says so instead of failing silently. `door` is
# the desk's own pick (set-edit-door and the resolution above); the
# named doors stay for a caller that means one in particular.
proc edit-place {how file line} {
    if {![string is integer -strict $line] || $line < 1} {
        error "edit-place: $line is not a line number"
    }
    switch -- $how {
        door {
            lassign [edit-door-resolve] door argv
            switch -- $door {
                emacs    { emacs-edit-open $file $line }
                terminal { edit-in-terminal $argv $file $line }
                bare     { exec {*}$argv $file & }
                none     { error "no way to edit — set-edit-door,\
 \$EDITOR, or install an editor" }
            }
        }
        emacs { emacs-edit-open $file $line }
        terminal {
            set r [editor-resolve]
            if {![llength $r]} {
                error "no editor for a terminal — \$EDITOR, or install one"
            }
            lassign $r argv - bare
            if {$bare} { exec {*}$argv $file & } else {
                edit-in-terminal $argv $file $line
            }
        }
        default { error "edit-place: door, emacs or terminal, not $how" }
    }
    return
}
# The line rides `+N` — the dialect vi, vim, nano, mcedit and
# emacsclient share, and what sensible-editor passes through. The
# bare branch above drops it instead: xedit has no line word, and a
# `+7` handed to it would be read as a file to open.
proc edit-in-terminal {argv file line} {
    spawn-terminal-run [dict create name tk9wm-edit \
        title "[lindex $argv 0] [file tail $file]"] \
        [concat $argv [list +$line $file]]
}
# ---- the edit door ----
# «Open this file, at this line» is a different verb from «the telega
# frame», and mixing them was what made the emacs layer look bigger
# than it is (the owner's design round, 2026-08-02). A BUTTON is an
# identity: create-or-raise, and the reuse is the action machinery's
# own doing — match first, launch only when nothing answers. A door is
# a DESTINATION: any frame of the right emacs will do, and the only
# thing to decide is whether an edit lands in a frame that already
# exists or in a fresh one.
#
# So the knob is named for the door it governs rather than for emacs
# at large, and there is exactly one of it. Reuse is the default: a
# person who asks to see a config line means «show me», not «give me
# another window».
keep emacs_edit reuse
# WHICH EMACS EDITS. The server is the whole of the addressing here —
# emacsclient -s NAME -r picks a frame of THAT server and no other —
# which is why the door needs no frame name while the buttons want
# one: the owner keeps telega.el in a server of its own, and an edit
# on the default server has no way to land in it even by accident
# (his ruling, 2026-08-02: and were telega on the default server, «in
# the emacs where I keep everything» is exactly where he would want
# the file). Empty is the default server.
keep emacs_edit_daemon {}
proc set-emacs-edit-daemon {name} { set ::emacs_edit_daemon $name }
proc emacs-edit-spec {} {
    expr {$::emacs_edit_daemon eq ""
          ? {} : [dict create daemon $::emacs_edit_daemon]}
}
# In a terminal there is no anonymous frame to reuse: a terminal
# window is found by its WM_CLASS instance and nothing else, so the
# desk keeps ONE editing terminal and knows its name. The server rides
# that name — two daemons would otherwise fight over one window, which
# is the same confusion the frame names exist to prevent.
proc emacs-edit-terminal-name {} {
    expr {$::emacs_edit_daemon eq ""
          ? "emacs-tk9wm" : "emacs-tk9wm-$::emacs_edit_daemon"}
}
# THE FILE IS AN ARGUMENT, NOT AN EVAL. emacsclient takes `+LINE FILE`
# itself, and a file argument is the shape that RAISES the frame it
# lands in — where a bare --eval runs in an invisible one and says
# nothing (the owner, measured 2026-08-02). Only the terminal-reuse
# branch below cannot use it, because putting a file into a frame that
# already exists inside a given terminal is a thing only the daemon
# can do; that one carries his focus form instead.
proc emacs-edit-open {file line} {
    set spec [emacs-edit-spec]
    set cmd [emacs-client-cmd $spec]
    if {$::emacs_autodaemon eq "on"} { lappend cmd -a {} }
    set place [list +$line $file]
    if {$::emacs_frames ne "terminal"} {
        lappend cmd [expr {$::emacs_edit eq "create" ? "-c" : "-r"}] -n
        set cmd [concat $cmd $place]
        puts "WM: emacs: edit $cmd"
        exec {*}$cmd &
        return
    }
    if {$::emacs_edit eq "create"} {
        # ...nothing looked for and nothing shared: a terminal of its
        # own, holding this one edit.
        spawn-terminal [list name tk9wm-edit title [file tail $file] \
            run [concat $cmd [list -nw] $place]]
        return
    }
    set name [emacs-edit-terminal-name]
    set hit [lindex [panel-matches "edit in emacs" \
        [dict create match [list filter -class $name]]] 0]
    if {$hit ne ""} {
        # The window comes up at once and the daemon is asked in the
        # background — the same two-step the emacs buttons use, for
        # the same reason: no fire waits on a socket.
        puts "WM: emacs: edit in $name 0x[format %x $hit]"
        panel-focus-hit $hit
        emacs-eval-bg $spec [emacs-template open-place.el \
            "(tk9wm-name [emacs-lisp-string $name])\
 (tk9wm-file [emacs-lisp-string $file]) (tk9wm-line $line)"]
        return
    }
    set F "((name . [emacs-lisp-string $name])\
 (tk9wm-frame . [emacs-lisp-string $name]))"
    spawn-terminal [list name $name title $name \
        run [concat $cmd [list -t -F $F] $place]]
}
proc emacs-eval-bg {spec expr} {
    set cmd [concat [emacs-client-cmd $spec] [list -e $expr]]
    wm-errand "emacs eval" [list emacs-eval-run $cmd]
}
# HOW LONG A DAEMON MAY TAKE TO ANSWER. Five seconds was the number
# from when a daemon was a fast thing; an emacs that decides to
# byte-compile mu4e on the way up takes a minute and is not broken
# (the owner, 2026-08-01). Running out of it is not silent any more:
# it is a problem with the last lines the daemon said, which is the
# whole of what one needs to see.
#
# A config word, NOT a knob: running out of patience decides nothing
# except when the desk starts talking about the wait, and a dial for
# that is noise in the configurator (the owner, 2026-08-02).
keep emacs_wait 60000
proc emacs-eval-run {cmd} {
    set f [pipe-run $cmd -stderr merge -patience $::emacs_wait \
               -say [list emacs-taking-forever]]
    if {[catch {fut::await $f} r opts]} {
        problem-record "emacs" $r {} \
            [expr {[lindex [dict get $opts -errorcode] 0] eq "PIPE"
                   ? [lindex [dict get $opts -errorcode] 2] : {}}]
        return
    }
    if {[dict get $r status] != 0} {
        problem-record "emacs" "emacsclient exited [dict get $r status]" {} \
            [pipe-tail-of [dict get $r out] 10]
        return
    }
    puts "WM: emacs: verdict: [string trim [dict get $r out]]"
}
# ...and what the desk says while it goes on waiting. NOT a kill: the
# client is starting the daemon, and the daemon is worth having.
proc emacs-taking-forever {ms tail} {
    problem-record "emacs" "starting the daemon, or waiting for it, has\
 taken over [expr {$ms / 1000}] s — still waiting" {} $tail
}
# The last lines of a lump of output, for a diagnosis.
proc pipe-tail-of {text n} {
    set lines {}
    foreach l [split [string trim $text] \n] {
        if {[string trim $l] ne ""} { lappend lines $l }
    }
    return [lrange $lines end-[expr {$n - 1}] end]
}

