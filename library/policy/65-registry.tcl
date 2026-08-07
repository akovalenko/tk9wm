# ---- the spec registry: what a declaration may SAY ----
# The knobs have had this since the configurator was built:
# The `knobs` nodes say what each knob IS, and knob-table is "the
# configurator's whole worldview". The specs — what an `action` and
# its adapter words may carry — had no such table. Every key was
# checked by hand where it happened to be consumed (and the ACTION's
# own keys were not checked at all: a typo declared a deed that
# quietly did nothing), while the configurator's field list said the
# same things over again in another file, with nothing keeping the
# two honest. This is that table, and three things live off it: the
# check below, the collection's fields (spec-fields), and the linter
# when it lands — the same walk with softer verdicts.
#
# Per key: `kind` — what it is in the CONFIG's terms (the editor's
# kinds are a MAPPING of these, not the same list, which is the seam
# that lets a script get a real editor without the language moving);
# `doc` — the short label a field wears, the prose staying in
# default-config.tcl where it has room and a voice; `xor` — the key
# it cannot be said beside; `of` — whose table describes a subspec;
# `required` — a subspec key that must be there when the word is.
# ---- ONE REGISTRY FOR WHAT THE CONFIGURATION IS (plan step 1) ----
# Three tables used to describe this desk's configuration — the knobs
# (what a knob is and how to show it), the families (what a collection
# serves the editor), the action language's keys (what a deed may
# carry) — and they were the same kind of fact filed three ways, so
# every feature of the last week had to be sewn on three times.
#
# They are one table now, keyed by the node's PATH in the config tree:
#
#   {knobs set-fade}      a leaf the desk holds exactly one of
#   {actions}             a family: a dict of elements, one per name
#   {actions @ launch}    a leaf inside EVERY element of a family
#   {@spec terminal}      a shape a leaf may be `of` — a named sub-dict
#
# Each entry says what the node IS (`node`), and beside it whatever
# the editors, the linter and the saver want of it. The declarations
# keep the three spellings that read best where they stand — a knob
# still reads as a knob — but each files its nodes HERE, and every
# table door downstream is a view over this one dict.
set config_registry {}
proc config-node {path meta} { dict set ::config_registry $path $meta }
proc config-node-of {path} {
    if {![dict exists $::config_registry $path]} { return "" }
    return [dict get $::config_registry $path]
}
# The nodes one storey under a path, in declaration order, as
# name -> meta: the shape every door here wants to serve.
proc config-nodes-under {path} {
    set n [expr {[llength $path] + 1}]
    set out {}
    dict for {p meta} $::config_registry {
        if {[llength $p] != $n || [lrange $p 0 end-1] ne $path} continue
        dict set out [lindex $p end] $meta
    }
    return $out
}
# The families, each with its fields folded back in — what the
# collection registry used to BE, computed rather than kept.
proc config-families {} {
    set out {}
    dict for {p meta} $::config_registry {
        if {[llength $p] != 1 || [dict get $meta node] ne "family"} continue
        set name [lindex $p 0]
        dict set out $name [dict merge $meta \
            [list fields [config-nodes-under [list $name @]]]]
    }
    return $out
}

proc spec-keys {name table} {
    # the table itself is a node: whether a second declaration of the
    # same thing REFINES the first (the actions do) or replaces it
    # wholesale (a subspec is one value inside an action) decides what
    # an empty value down here can mean at all
    if {[config-node-of [list @spec $name]] eq ""} {
        config-node [list @spec $name] {node dict merge replaces}
    }
    dict for {k meta} $table {
        config-node [list @spec $name $k] [dict merge {node leaf} $meta]
    }
}
# ---- WHAT AN EMPTY VALUE MEANS (config-tree, step 2) ---------------
# Three empties lived in this vocabulary and none of them was declared:
# `action X {run {}}` took the key away, `env {VAR {}}` set the
# variable to nothing, and `terminal {}` was a WORD — «in a terminal,
# with nothing to add» — which cost a name checked in a loop.
#
# The fork behind it is settled (the owner, 2026-08-02): a custom word
# stays a DELTA that merges by key, because the alternative drags a
# whole subtree into the custom file for a one-word change. Un-say is
# therefore permanent, and where layers merge, an empty value is the
# only way to take a word back — so a leaf whose empty is a legitimate
# VALUE must say so, and this is where it says it.
proc node-empty-means {path} {
    set meta [config-node-of $path]
    if {$meta ne "" && [dict exists $meta empty]} { return [dict get $meta empty] }
    return unsay
}
# Empty-as-a-value inside a MERGING node is the one shape that cannot
# hold both meanings: there the empty is taken by un-say, so the node
# can be said and can be refined, but never taken back. The plan
# calls this the linter's duty — the registry can answer it, so the
# suite can insist on the list instead of somebody noticing.
proc config-empty-clashes {} {
    set out {}
    dict for {path meta} $::config_registry {
        if {![dict exists $meta empty] || [dict get $meta empty] ne "value"} continue
        set parent [config-node-of [lrange $path 0 end-1]]
        if {$parent eq "" || ![dict exists $parent merge]} continue
        if {[dict get $parent merge] eq "merges"} { lappend out $path }
    }
    return $out
}
proc spec-table {name} { config-nodes-under [list @spec $name] }

# AN ACTION'S WORDS MERGE, which is what makes a custom layer a delta
# — and what makes an empty value here mean «un-say».
config-node {@spec action} {node dict merge merges}
spec-keys action {
    type     {kind {choice generic terminal emacs}
              doc {what kind of deed — unsaid, the settings below say}}
    run      {kind words     xor launch  face launch
              doc {raw argv — sugar for a launch that says Run}}
    launch   {kind script    xor run
              doc {a Tcl script, run when the action fires — a plain command is «Run word word…»}
              examples {
                  {Run firefox} {a plain command — Run is the door}
                  {Run tail -f $env(HOME)/log} {words are data: $env(HOME), not ~}}}
    match    {kind predicate doc {a Tcl predicate, asked per window id — which window counts as already-running}
              examples {
                  {filter -class TELEGA} {either half of WM_CLASS, glob allowed}
                  terminal-window {any terminal emulator's window}}}
    activate {kind script    doc {run on the found window instead of just focusing it — for raises that need ceremony}}
    many     {kind {choice mru choose}
              doc {what the CHORD does with several windows — the button has both}}
    icon     {kind icon      doc {a face, for whatever panel carries it}}
    badge    {kind text
              doc {a letter or two laid over the icon — one picture, many actions}}
    key      {kind chord     doc {the chord that does it — panel or no panel}
              examples {
                  {<Super>t r f} {under the desk's own prefix — chords compose}
                  {<Super>F9} {a bare top-level chord}}}
    needs    {kind commands  doc {commands that must exist in PATH — the action waits until they do}}
    style    {kind text      doc {a wm-style rule laid on the windows this action matches — not the button's look}
              examples {
                  {place "max force"} {open maximized, and mean it}
                  {minimize refuse} {a window that may not iconify}}}
    env      {kind envdict   doc {environment for the process the launch starts}}
    env-unset {kind words
              doc {variables the launch must NOT have — absent, not empty}}
    dir      {kind text
              doc {the working directory — for what Run starts and for the terminal itself; ~ expands}}
    terminal {kind subspec of terminal empty value
              doc {settings for a terminal action — saying this word, even empty, is what makes it one}}
    emacs    {kind subspec of emacs
              doc {do it in emacs — saying this word is what makes the action an emacs one}}
}
spec-keys terminal {
    name  {kind text      doc {the window's name — the WM_CLASS instance}}
    title {kind text      doc {the window title}}
    bg    {kind text      doc {the background, any Tk colour — the beast's own dialect}}
    fg    {kind text      doc {the ink, any Tk colour — the beast's own dialect}}
    env   {kind envdict   doc {environment for the terminal process itself}}
    env-unset {kind words doc {variables it must NOT have — absent, not empty}}
    args  {kind beastdict
           doc {extra argv per emulator, keyed by its name (kitty, xterm, …) — applied verbatim}}
}
spec-keys emacs {
    daemon     {kind text doc {which daemon (-s); unsaid is the default one}}
    frame      {kind text
                doc {the frame name — the match hangs off it; unsaid, the deed lends its own}}
    eval       {kind text doc {elisp for the frame it makes}}
    via        {kind {choice gui terminal} doc {a gui frame, or one in a terminal}}
    autodaemon {kind {choice on off} doc {start a missing daemon, or refuse}}
    keep-frame-name {kind {choice on off}
                doc {keep the frame wearing this name — off hands the title back}}
    env        {kind envdict doc {environment for the daemon it may start}}
    env-unset  {kind words doc {variables it must NOT have — absent, not empty}}
}
# A MENU'S WORDS MERGE, as an action's do: refine by name, un-say a
# key with an empty value.
config-node {@spec menu} {node dict merge merges}
spec-keys menu {
    key   {kind chord doc {the chord that opens it}}
    items {kind rows  xor body
           doc {the rows, written down — action references, or label+do pairs}}
    body  {kind script xor items
           doc {a script asked for the rows at open time}}
    place {kind text
           doc {edge words, sizeless, over the workarea — unsaid, the desk works it out}}
}

# What a declaration is CHECKED against, and deliberately only the
# shallow half of the table: a key nobody registered is a typo, an
# xor pair said together is a choice not made, a dict-kinded word
# that is not a dict is the missing-braces mistake, and a subspec is
# read by its own table. The deeper judgements — does this chord
# parse, is that command on this machine — are the LINTER's: they
# are advice about a declaration that can be read, and this is the
# gate for one that cannot.
#
# Said at the declaration (in `action`), on the words the layers
# actually SAID — never on a derived spec, where `run` has already
# become the launch it is sugar for and the xor would fire on the
# machinery's own doing.
proc spec-check {who name settings} {
    set table [spec-table $name]
    foreach k [dict keys $settings] {
        if {![dict exists $table $k]} {
            error "$who: unknown $name key \"$k\"\
 ([join [dict keys $table] { }])"
        }
        set meta [dict get $table $k]
        set kind [dict get $meta kind]
        if {[dict exists $meta xor]} {
            foreach other [dict get $meta xor] {
                if {[dict exists $settings $other]} {
                    error "$who: $k and $other cannot both be said —\
 say one ($k {} un-says it)"
                }
            }
        }
        switch -- [lindex $kind 0] {
            envdict - beastdict { dict-shaped "$who: $k" $settings $k }
            choice {
                if {[dict get $settings $k] ni [lrange $kind 1 end]} {
                    error "$who: $k is [join [lrange $kind 1 end] { or }]"
                }
            }
            subspec {
                spec-check "$who: $k" [dict get $meta of] [dict get $settings $k]
            }
        }
    }
    dict for {k meta} $table {
        if {[dict exists $meta required] && ![dict exists $settings $k]} {
            error "$who: the $name spec needs $k\
 ([dict get $meta doc])"
        }
    }
}

# The configurator's field list, said ONCE: the language's kinds
# mapped onto the editors this tree actually has. A script is `text`
# until it has an editor of its own — the mapping is where that
# arrives, and the language does not move when it does.
proc spec-fields {name} {
    set editor {words list  commands list  envdict dict  beastdict dict
                subspec dict  chord chord  script text  predicate text
                icon icon  text text  rows list}
    set out {}
    dict for {k meta} [spec-table $name] {
        set kind [dict get $meta kind]
        dict set out $k [dict create \
            kind [expr {[lindex $kind 0] eq "choice"
                        ? $kind : [dict get $editor $kind]}] \
            doc [dict get $meta doc]]
        # the xor rides along: an editor that knows two keys are one
        # slot can offer the SWITCH instead of letting a user say
        # both and meet the refusal afterwards
        if {[dict exists $meta xor]} {
            dict set out $k xor [dict get $meta xor]
        }
        # ...and so does a FACE: a spelling that named one never
        # stands as a row of its own — the face answers for the slot
        # on screen while the written sugar stays written (the owner,
        # 2026-08-06: one spelling in the UI)
        if {[dict exists $meta face]} {
            dict set out $k face [dict get $meta face]
        }
        # A DICT OF PLAIN MEMBERS is a subtree, not a cell: the editor
        # can show one row per variable and edit them one at a time
        # (the owner's own example, «actions.Firefox.env.GTK_IM_MODULE»).
        # A subspec is a dict too and is NOT this: its members are the
        # sub-table's own keys, with kinds of their own.
        if {$kind in {envdict beastdict}} { dict set out $k members plain }
        # a slot that HOLDS A SCRIPT says so, so the editor knows to
        # ask the linter when one is written into it
        if {$kind eq "script"} { dict set out $k lint script }
        # ...and so does what an EMPTY value means here, because the
        # editor cannot show the difference between «not said» and
        # «said, and empty» without knowing there is one
        if {[dict exists $meta empty]} {
            dict set out $k empty [dict get $meta empty]
        }
        # ...and EXAMPLES, for the editor's ▾: words to take and bend
        # to one's need, not abstract help (the owner, 2026-08-06)
        if {[dict exists $meta examples]} {
            dict set out $k examples [dict get $meta examples]
        }
    }
    return $out
}

# Is this script nothing but one `Run` of literal words — and if so,
# which words? The question an editor asks before offering to show a
# launch as a plain command, and the linter asks for its own reasons.
#
# Deliberately STRICT, because the wrong answer here rewrites what
# somebody wrote: one command (no newline, no semicolon), `Run`
# first, and every word free of the characters that would mean
# something else at fire time — a `$`, a bracket, a backslash. A
# script that says more than a command can say keeps being a script,
# which is the honest half of the offer.
proc run-words-of {script} {
    set s [string trim $script]
    if {[regexp {[\n;]} $s]} { return "" }
    if {[catch {llength $s}]} { return "" }
    if {[llength $s] < 2 || [lindex $s 0] ne "Run"} { return "" }
    set words [lrange $s 1 end]
    foreach w $words {
        if {[regexp {[\[\$\\]} $w]} { return "" }
    }
    return $words
}

# The same question about the OLD spelling: is this launch one plain
# `exec`? Laxer than the one above on purpose — it does not rewrite
# anything, it only advises, and `Run` hands its words to exec
# anyway, so a `$` or a redirection means the same on either side.
# Answers {WORDS BACKGROUNDED}: the trailing `&` is the difference
# between a launch and a frozen desk, and the linter says so.
proc exec-words-of {script} {
    set s [string trim $script]
    if {[regexp {[\n;]} $s]} { return "" }
    if {[catch {llength $s}]} { return "" }
    if {[llength $s] < 2 || [lindex $s 0] ne "exec"} { return "" }
    set words [lrange $s 1 end]
    set bg 0
    if {[lindex $words end] eq "&"} {
        set words [lrange $words 0 end-1]
        set bg 1
    }
    if {![llength $words]} { return "" }
    list $words $bg
}

# ...and the tilde question over both: a leading ~ in a command's
# words reaches exec as a LITERAL ~ — Run reads nothing (the owner,
# 2026-08-01) — while `dir` expands its own since the cosmetics
# line. The asymmetry deserves a sentence at the moment of typing,
# with the exact repair in it.
proc tilde-word {words} {
    foreach w $words {
        if {[string index $w 0] eq "~"} { return $w }
    }
    return ""
}
proc tilde-advice {w} {
    if {[string range $w 0 1] eq "~/"} {
        return "«$w» reaches exec as a literal ~ — nothing expands in a\
 command's words; say \$env(HOME)[string range $w 1 end]"
    }
    return "«$w» reaches exec as a literal ~ — nothing expands in a\
 command's words; say the full path"
}

# ---- what went wrong, kept where it can be looked at ----
# A binding whose script throws used to leave one line in the log and
# nothing anywhere else — and the log is not where a hand on the
# keyboard is looking (the owner, 2026-08-01). A failure now goes to
# TWO places at once: the echo box says it happened, and the store
# keeps it for whoever wants to read it afterwards.
#
# The store is the durable half on purpose. The echo has no natural
# end — a key echo ends when the chord goes on, a report of a failure
# has nothing to be ended BY (the owner's own doubt, same day) — so
# it fades on a timer, and nothing is lost when it does.
keep problems {}          ;# newest first, capped: {what text where}
set PROBLEM_KEEP 50
proc problem-record {what text {where {}} {detail {}}} {
    set p [dict create what $what text $text where $where]
    if {[llength $detail]} { dict set p detail $detail }
    set ::problems [lrange [linsert $::problems 0 $p] 0 $::PROBLEM_KEEP]
    puts "WM: PROBLEM $what: $text"
    foreach line $detail { puts "WM:   | $line" }
    # A LONG DIAGNOSIS GOES ON THE SCREEN WHOLE. Most failures are a
    # sentence and a sentence is what the box shows; but some are only
    # useful with the last few lines the thing said before it gave up
    # — a daemon that will not start, say (the owner, 2026-08-01) —
    # and for those the box grows, like the help list it borrows its
    # shape from.
    soft "show a problem" {
        if {[llength $detail]} {
            policy-key-echo problem [list "$what: [problem-brief $text]" \
                [lmap l $detail {list $l}]]
        } else {
            policy-key-echo problem "$what: [problem-brief $text]"
        }
    }
}
proc problems-clear {} { set ::problems {}; return 0 }
proc problems {} { return $::problems }
# One line of it, because the box is one line wide and the store has
# the rest.
proc problem-brief {text} {
    set one [string trim [regsub -all {\s+} $text " "]]
    if {[string length $one] > 70} { set one "[string range $one 0 67]…" }
    return $one
}

# ---- the linter: the same table, softer verdicts ----
# What spec-check refuses, it refuses because the declaration cannot
# be READ. Everything else a table knows is advice — a chord this
# keyboard has no key for, a command this machine has not got yet, a
# launch saying the long way what the desk has a door for — and
# advice must not stop a desk from coming up. So it is a separate
# walk with its own verdicts, and both readers of it (the log at
# declaration, the flag in the configurator) show without judging.
#
# A verdict: {key K level warn|note text SENTENCE}. `key` is the
# word it hangs off — the configurator flags that row with it.
# ---- LINTING A SCRIPT WHERE IT IS WRITTEN -------------------------
# The most useful moment is the EDITOR (the owner, 2026-08-01): that
# is where a typo happens and where the person is standing. So this
# is not a new mechanism — it is the linter that already judges a
# deed's words, called from a second place, with the same shape of
# verdict. Everything here is ADVICE: a config may legitimately name
# a command that does not exist yet, and nothing is refused.
proc script-one-command {script} {
    set s [string trim $script]
    if {[string first "\n" $s] >= 0 || [string first ";" $s] >= 0} { return {} }
    if {[catch {llength $s} n] || !$n} { return {} }
    return $s
}
# The owner's own example: `wm-restart` for `restart-wm` — the parts
# are right and their order is not, which is the mistake a
# dash-joined vocabulary invites. Nothing cleverer is attempted;
# a wrong guess would be worse than none.
proc word-orders {parts} {
    if {[llength $parts] <= 1} { return [list $parts] }
    set out {}
    for {set i 0} {$i < [llength $parts]} {incr i} {
        set rest [lreplace $parts $i $i]
        foreach tail [word-orders $rest] {
            lappend out [linsert $tail 0 [lindex $parts $i]]
        }
    }
    return $out
}
proc nearest-command {cmd} {
    set parts [split $cmd -]
    if {[llength $parts] < 2 || [llength $parts] > 3} { return "" }
    foreach order [word-orders $parts] {
        set cand [join $order -]
        if {$cand ne $cmd && [llength [info commands $cand]]} { return $cand }
    }
    return ""
}
proc script-lint {script} {
    set out {}
    if {![info complete $script]} {
        lappend out [list level warn text \
            "this does not parse — an unmatched quote or brace"]
        return $out
    }
    set words [script-one-command $script]
    if {[llength $words]} {
        set cmd [lindex $words 0]
        if {![llength [info commands $cmd]]} {
            set say "«$cmd» is not a command this desk knows"
            set near [nearest-command $cmd]
            if {$near ne ""} { append say " — did you mean «$near»?" }
            lappend out [list level warn text $say]
        }
    }
    # ...and the exec rules the deeds already hear, said here too
    set e [exec-words-of $script]
    if {[llength $e]} {
        lassign $e ewords bg
        if {$bg} {
            lappend out [list level note text \
                "this is «Run $ewords» said the long way — Run is the door\
 the desk knows about"]
        } else {
            lappend out [list level warn text \
                "an exec with no & holds the desk still until it returns;\
 «Run $ewords» does not"]
        }
    }
    # ...and the tilde rule, on whichever words were extractable
    set words [run-words-of $script]
    if {![llength $words] && [llength $e]} { set words [lindex $e 0] }
    set tw [tilde-word $words]
    if {$tw ne ""} {
        lappend out [list level warn text [tilde-advice $tw]]
    }
    return $out
}
proc spec-lint {name settings} {
    set table [spec-table $name]
    set out {}
    dict for {k v} $settings {
        if {![dict exists $table $k]} continue   ;# spec-check's business
        set meta [dict get $table $k]
        switch -- [lindex [dict get $meta kind] 0] {
            chord {
                foreach tok $v {
                    if {[catch {parse-chord $tok} err]} {
                        lappend out [list key $k level warn text \
                            "«$tok» is not a chord this desk can bind: $err"]
                        break
                    }
                }
            }
            commands {
                foreach c $v {
                    # the cached MISS would answer for a command that
                    # has since arrived (the needs lesson)
                    array unset ::auto_execs $c
                    if {[auto_execok $c] eq ""} {
                        lappend out [list key $k level note text \
                            "«$c» is not on this machine — the deed\
 stands by, visible and unbound, until it is"]
                    }
                }
            }
            script {
                set e [exec-words-of $v]
                if {[llength $e]} {
                    lassign $e words bg
                    if {$bg} {
                        lappend out [list key $k level note text \
                            "this is «Run $words» said the long way —\
 Run is the door the desk knows about"]
                    } else {
                        lappend out [list key $k level warn text \
                            "an exec with no & holds the desk still\
 until it returns; «Run $words» does not"]
                    }
                }
                set words [run-words-of $v]
                if {![llength $words] && [llength $e]} {
                    set words [lindex $e 0]
                }
                set tw [tilde-word $words]
                if {$tw ne ""} {
                    lappend out [list key $k level warn text [tilde-advice $tw]]
                }
            }
            words {
                # only the command sugar (a words key that named a
                # script face) speaks argv; env-unset's words are
                # variable names, no path among them
                if {[dict exists $meta face]} {
                    set tw [tilde-word $v]
                    if {$tw ne ""} {
                        lappend out [list key $k level warn text \
                            [tilde-advice $tw]]
                    }
                }
            }
            subspec {
                # `terminal {}` was the only way to say «in a terminal»
                # before the type was a word of its own. It still
                # works — his config is full of them — and the note
                # says the plain spelling, which is also the one with
                # no empty-versus-absent question in it.
                if {[dict get $settings $k] eq ""} {
                    lappend out [list key $k level note text \
                        "this is «type $k» said the long way — the type is\
 a word of its own now, and says the same thing without an empty dict"]
                }
                foreach verdict [spec-lint [dict get $meta of] [dict get $settings $k]] {
                    dict set verdict key $k
                    lappend out $verdict
                }
            }
        }
    }
    return $out
}

# ---- WHAT KIND OF DEED IS THIS (the owner, 2026-08-02) ----------
# An action has a TYPE — generic, in a terminal, in emacs, and one
# day whatever xdg-open is — and until now it was read off WHICH
# SETTINGS WERE PRESENT. That is what made the difference between an
# absent `terminal` and an empty one carry meaning, and what would
# have made every new kind a new rule about presence.
#
# So the type is a word: `type terminal`. Presence stays its SUGAR,
# because a config that says `terminal {name X}` plainly means one
# (and because his own config is full of them) — but where the word
# is said, it is the answer, and two sets of settings side by side
# stop being a contradiction: the type picks which one applies and
# the other simply waits.
proc action-type {settings} {
    if {[dict exists $settings type] && [dict get $settings type] ne ""} {
        return [dict get $settings type]
    }
    foreach {key kind} {emacs emacs terminal terminal} {
        if {[dict exists $settings $key]} { return $kind }
    }
    return generic
}
proc spec-derive {who settings} {
    set kind [action-type $settings]
    if {$kind eq "terminal" && ![dict exists $settings terminal]} {
        # the type said so and the settings were not needed: an empty
        # dict is what «just a terminal» has always meant underneath
        dict set settings terminal {}
    }
    if {$kind eq "terminal"} {
        set t [dict get $settings terminal]
        # THE ACTION'S DIR REACHES THE TERMINAL PROCESS TOO (the
        # owner, 2026-08-06): a run-less terminal used to lose it in
        # silence — its launch never meets Run, where the env -C
        # prefix is made — and even with a run, the emulator standing
        # in the dir is the point where new tabs inherit their cwd.
        # Not a spec key of terminal's own: one dir, said once on the
        # action, lands on both processes.
        if {[dict exists $settings dir] && [dict get $settings dir] ne ""} {
            dict set t dir [dict get $settings dir]
        }
        if {![dict exists $settings match]} {
            if {[dict exists $t name] && [dict get $t name] ne ""} {
                dict set settings match \
                    [list filter -class [dict get $t name]]
            } else {
                dict set settings match terminal-window
            }
        }
        # What a `Run` inside this action's launch means: open the
        # terminal AROUND those words. Set whether or not a launch
        # was said, so a hand-written script gets the same answer the
        # sugar does.
        dict set settings runvia [list spawn-terminal-run $t]
        # ...and with nothing to run at all, the deed IS the terminal.
        if {![dict exists $settings launch]} {
            dict set settings launch [list spawn-terminal $t]
        }
        # THE FACE OF WHATEVER THIS MACHINE HAS. Derived and not
        # stated, like the match beside it: "the terminal" is not one
        # program, and a button for it wearing an xterm on a kitty
        # desk would be telling a small lie every time it is looked
        # at. Only when the deed named no icon of its own — and only
        # when one resolves, so a theme carrying none of them leaves
        # the button its badge rather than a blank.
        if {![dict exists $settings icon]} {
            set ti [terminal-icon]
            if {$ti ne ""} { dict set settings icon $ti }
        }
    }
    # `emacs` is the same kind of PROVIDER, one storey higher: the
    # match is the identical single-pattern filter (a frame's name
    # parameter IS the WM_CLASS instance — see the emacs layer), the
    # launch builds gui or terminal per set-emacs-frames (`via`
    # overrides per button), and the found path gets an activate hook:
    # a terminal hit may need the daemon to put the named frame back
    # on top of its tty.
    if {$kind eq "emacs" && [dict exists $settings emacs]} {
        set e [dict get $settings emacs]
        if {![dict exists $settings match]} {
            dict set settings match \
                [list filter -class [dict get $e frame]]
        }
        if {![dict exists $settings launch]} {
            dict set settings launch [list emacs-launch $e]
        }
        if {![dict exists $settings activate]} {
            dict set settings activate [list emacs-activate $e]
        }
    }
    return $settings
}
# OWNING THE SET. The customization layer's word about a panel is the
# WHOLE set or nothing (the owner, 2026-08-01): no deltas over the
# config's line-up. panel-buttons-own NAME empties panel NAME — the
# references go — and the ordinary panel-button lines that follow ARE
# the set, in the order the panel wears it; a remove verb would be a
# second way to say what absence already says, so there is none. And
# that is ALL it empties now: the chords ride the actions and the
# descriptions live in the action registry, so there is no bound key
# to sweep and no raw memory to keep — a dropped reference loses
# nothing that a bare `panel-button NAME` cannot bring back whole.
# The other collections keep a removal verb each, where absence
# cannot say it: a widget's declaration replaces by name and wm-bind
# by chord, so those two need only the taking-away.
proc panel-buttons-own {name} {
    panel-ensure $name
    dict set ::panels $name refs {}
    panel-rebuild-soon
}
proc wm-widget-remove {name} {
    dict unset ::widgets $name
    if {[llength [info commands widgets-build]]} { widgets-build }
}

# one rebuild per config's worth of declarations (or knob twiddles) —
# and it is every panel that is rebuilt, not the one whose knob moved:
# the bands are carved from one another, so a strip that got thicker
# moves the one declared after it too.
proc panel-rebuild-soon {} {
    array unset ::panel_geo    ;# the knob that asked may have changed the shape
    if {![info exists ::panel_pending]} {
        set ::panel_pending [after idle panels-build]
    }
}
# The bracket a RELOAD holds the strips in: inside it, panels-build
# is a note that a build is wanted; the release performs the ONE
# build the whole load amounts to. The standing strips are left
# exactly as they are meanwhile — wrong-sized for the half second a
# load takes, by the owner's own trade (2026-07-31): stale geometry
# over a teardown flickering after every config sentence that
# touches a panel.
set panels_hold 0
proc panels-held {script} {
    set ::panels_hold 1
    try {
        uplevel 1 $script
    } finally {
        set ::panels_hold 0
        panels-build
    }
}
# Every SHOWN button of every panel, as {panel name label settings}
# — the sweeps (re-judging matches, counting for a log line) say
# what they do to a button and not which panel it is on.
proc panel-all-buttons {} {
    set out {}
    dict for {name p} $::panels {
        foreach b [dict get $p shown] {
            lappend out [list $name {*}$b]
        }
    }
    return $out
}
# Every managed window a button's match accepts, MRU first — the
# winlist order, never-focused windows trailing. Feeds the fire (the
# head is the most recent), the live/multi judgement, and the arrow
# zone's filtered list.
proc panel-matches {label settings} {
    if {![dict exists $settings match]} { return {} }
    set pred [dict get $settings match]
    set cands $::focus_hist
    foreach w [array names ::frameof] {
        if {$w ni $cands} { lappend cands $w }
    }
    set hits {}
    set elsewhere {}
    foreach w $cands {
        if {![info exists ::frameof($w)]} continue
        if {[catch {uplevel #0 [list {*}$pred $w]} m]} {
            puts "WM: panel $label: predicate error on 0x[format %x $w]: $m"
        } elseif {$m} {
            # THIS DESK FIRST. A button reaches the window it matches
            # wherever that window is — going to it is what "reach"
            # means, and the desk follows (action-reach) — but a
            # candidate one can already see beats one on another desk,
            # however recently the other was focused. The two answers
            # to "I want a fresh one instead" already exist and need no
            # new grammar: Ctrl+click forces a launch, and `many
            # choose` opens the list, where the desk is a column.
            if {[desk-here-p $w]} { lappend hits $w } else { lappend elsewhere $w }
        }
    }
    return [concat $hits $elsewhere]
}
# Re-judge every button's match against the living windows and set
# the persistent states. Kicked (debounced — one manage can cascade
# a burst of property traffic) from the policy hooks: manage,
# unmanage, title change; run straight at the end of every rebuild.
keep panel_reeval_pending ""
proc panel-match-kick {} {
    if {![llength [panel-all-buttons]]} return
    after cancel $::panel_reeval_pending
    set ::panel_reeval_pending [after 200 panel-reeval]
}
proc panel-reeval {} {
    foreach b [panel-all-buttons] {
        lassign $b name aname label settings
        set T [panel-tree $name]
        if {$T eq ""} continue
        if {![info exists ::panel_items($name)]
                || ![dict exists $::panel_items($name) $aname]} continue
        set n [llength [panel-matches $label $settings]]
        $T item state set [dict get $::panel_items($name) $aname] \
            [list [expr {$n >= 1 ? "live" : "!live"}] \
                  [expr {$n >= 2 ? "multi" : "!multi"}]]
    }
}
# Everything the strip's shape depends on, decided in one place: the
# resolved face of every button ("" = no icon or a miss — one case,
# the badge), whether anything is iconic at all, the item height for
# the preset, and the strip thickness (horizontal: the item height;
# vertical: the widest button). The builder and the band's thickness
# question both come here; resolution is cached, so asking is cheap.
#
# MEMOIZED per rebuild, and that is a correctness fix and not a saving.
# One rebuild asks this many times — the builder once per panel, then
# every band carve once more — and it has to be the SAME answer every
# time: the band a panel reserves and the strip it draws are two
# consumers of one number.
#
# They came apart for real. Under a stock tclkit's Tk (core X fonts,
# helvetica) the two calls inside ONE build disagreed: 96 px for the
# builder, 70 for the band a moment later, the labels measuring half
# their width the second time. The strip then drew 70 inside a band
# that had reserved 96 and left a dead stripe nothing could use — and
# only the carve's clamp kept it from drawing outside its band
# altogether. Which of Tk's two answers is the honest one is not this
# code's business to adjudicate (an independent interpreter measuring
# that font agrees with the builder's); making the disagreement
# IMPOSSIBLE is. Every path that can change the answer goes through
# panel-rebuild-soon or panels-build, and both drop the memo.
array set panel_geo {}
proc panel-geometry {name} {
    if {![info exists ::panel_geo($name)]} {
	set ::panel_geo($name) [panel-measure $name]
    }
    return $::panel_geo($name)
}
proc panel-measure {name} {
    set buttons [panel-resolve $name]
    set preset [panel-cfg $name preset]
    # ICONS ONLY is the row preset with nothing written in it (the
    # owner, 2026-08-02). Said that way it needs no third set of
    # styles: the label element stays where it is and is given an
    # empty string, so every union, pad and alignment below goes on
    # meaning what it meant. What it DOES need is the iconic path
    # forced — a strip of blank chips is not "icons only", so a button
    # whose icon did not resolve wears the badge it already has.
    set bare [expr {$preset eq "icons"}]
    set isz [panel-cfg $name icon_size]
    set vert [expr {[panel-cfg $name side] in {left right}}]
    set faces {}
    set iconic 0
    foreach b $buttons {
        lassign $b aname label settings
        set img ""
        if {[dict exists $settings icon]} {
            set img [resolve-icon [dict get $settings icon] $isz]
        }
        if {$img ne ""} { set iconic 1 }
        lappend faces $img
    }
    if {$bare} { set iconic 1 }
    set line [font metrics PanelFont -linespace]
    # badge lettering follows the badge size (the winlist formula)
    set bfont [panel-badge-font $name]
    font configure $bfont -family [font actual PanelFont -family] \
        -size -[expr {max(7, $isz * 5 / 8)}]
    # DEMOTED WHERE THERE IS A CAPTION. With only icons on the strip
    # a mark has the whole chip to itself; beside a label it is a
    # guest, and the owner watched it walk into the text (2026-08-02
    # — "in row preset the badge covers the caption"). Smaller there,
    # and right-aligned to the icon below rather than started at a
    # fixed offset into it, which is what let a wider chip cross the
    # icon's far edge in the first place.
    set mfont [panel-mark-font $name]
    font configure $mfont -family [font actual PanelFont -family] \
        -size -[expr {$bare ? max(7, $isz / 3) : max(6, $isz * 3 / 10)}]
    # the arrow zone: once ANY button can match, every button
    # reserves an east strip for the multi arrow — the row reads
    # uniformly, an unarmed button just shows calm space there
    set aw [font measure PanelFont ▾]
    set zoned 0
    foreach b $buttons {
        if {[dict exists [lindex $b 2] match]} { set zoned 1; break }
    }
    set zone [expr {$zoned ? $aw + 12 : 0}]
    if {$bare} {
        set content $isz
    } elseif {!$iconic} {
        set content $line
    } elseif {$preset eq "stack"} {
        set content [expr {$isz + 2 + $line}]
    } else {
        set content [expr {max($isz, $line)}]
    }
    # The two paddings the item's height is made of, named because the
    # live indicator has to find the face's edge again later: FPAD is
    # the face's own inner air (-ipady), FGAP the air between the face
    # and the item's edge.
    set FPAD 3
    set FGAP 5
    set itemh [expr {$content + 2*$FPAD + 2*$FGAP}]
    if {![llength $buttons]} {
        set thick 0
    } elseif {$vert} {
        set maxw 0
        foreach b $buttons f $faces {
            lassign $b aname label settings
            set tw [expr {$bare ? 0 : [font measure PanelFont $label]}]
            if {!$iconic} {
                set cw $tw
            } else {
                set iw $isz
                if {$f eq ""} {
                    # the badge: at least the square, wide letters grow it
                    set iw [expr {max($isz, [font measure $bfont \
                        [lindex [pseudo-badge $label] 0]])}]
                }
                if {$preset eq "stack"} {
                    set cw [expr {max($iw, $tw)}]
                } elseif {$bare} {
                    set cw $iw
                } else {
                    set cw [expr {$iw + 4 + $tw}]
                }
            }
            set maxw [expr {max($maxw, $cw + 20 + ($bare ? 2 : 1) * $zone)}]
        }
        set thick [expr {$maxw + 2}]
    } else {
        set thick [expr {$itemh + 2}]
    }
    dict create faces $faces iconic $iconic itemh $itemh thick $thick \
        zone $zone aw $aw fpad $FPAD fgap $FGAP vert $vert bare $bare \
        preset $preset icon_size $isz badge_font $bfont mark_font $mfont
}
proc panel-thickness {name} { dict get [panel-geometry $name] thick }
# One badge font per panel, created on demand and named after the
# panel. Named and not indexed: a rebuild renumbers the widgets, and a
# font that changed meaning between two builds would letter a badge
# from somebody else's icon size.
proc panel-badge-font {name} {
    set f "PanelBadge-$name"
    if {$f ni [font names]} { font create $f -weight bold }
    return $f
}
# ...and a SMALLER one for the mark laid over an icon. Its own font
# and not the badge's: a badge IS the button's face and fills the
# square, a mark sits in the corner of somebody else's picture and has
# to stay out of the way of it. Per panel for the same reason the
# badge font is — a mark's size follows the icon's, and icon sizes are
# per panel.
proc panel-mark-font {name} {
    set f "PanelMark-$name"
    if {$f ni [font names]} { font create $f -weight bold }
    return $f
}
# WHAT A BUTTON WEARS OVER ITS ICON, when it says so. The point is not
# to need a new picture for every variation of one program (the owner,
# 2026-08-02): "run this in a terminal" wants the terminal's own icon,
# and inventing a hundred and one terminal icons is not a plan. A
# terminal with a `t` in the corner is tmux, and the base picture goes
# on being the truth about what will open.
proc panel-mark-of {settings} {
    expr {[dict exists $settings badge] ? [dict get $settings badge] : ""}
}
# Every panel, from nothing: the live strips come down and are put
# back up in declaration order. Wholesale and not per panel, because a
# band is carved out of what the bands before it left — a strip that
# grew moves every strip declared after it, and rebuilding just the one
# whose knob moved would leave the rest overlapping it.
#
# The widget path is the panel's INDEX and not its name: a name comes
# from the config and may be anything the user typed (Cyrillic, a dot,
# a leading capital — all illegal or ambiguous in a Tk path), while an
# index is always a legal component. The mapping is remembered in
# ::panel_win, which is what every later poke goes through.
proc panels-build {} {
    # A direct build ABSORBS a scheduled one: half the callers come
    # through panel-rebuild-soon's idle timer and the other half call
    # straight here, and a timer left armed past a direct build
    # rebuilt every strip once more — for nobody (it was one of the
    # three builds the owner's reload flickered through).
    if {[info exists ::panel_pending]} {
        after cancel $::panel_pending
        unset ::panel_pending
    }
    if {$::panels_hold} return
    array unset ::panel_geo    ;# fonts, RandR and the config all land here
    # a font outlives the panel that asked for it (a reload can drop a
    # panel entirely); collect the orphans rather than leak one per name
    foreach f [font names] {
        if {[string match "PanelBadge-*" $f]
            && ![dict exists $::panels [string range $f 11 end]]} {
            font delete $f
        }
    }
    # Resolve EVERY panel's references before building ANY: the bands
    # are carved out of one another, and a band asks every other
    # panel's thickness — which is a question about its resolved set.
    foreach name [panel-names] {
        dict set ::panels $name shown [panel-resolve $name 1]
    }
    # A PANEL WITH NO BUTTONS IS STILL A PANEL WHEN THE TRAY IS IN IT.
    # `set-tray on` alone left the desk with no strip at all — the
    # band a tray sits in is a panel, and a panel was only built for
    # its buttons, so the owner turned the tray on and nothing
    # appeared until he added a clock (2026-08-02). The tray's own
    # panel is ensured, so pointing the tray at a name nobody declared
    # still gives it somewhere to be.
    if {$::tray_on} { panel-ensure [tray-panel] }
    set idx 0
    set built {}
    dict for {name p} $::panels {
        incr idx
        if {[llength [dict get $p shown]]
                || ($::tray_on && [tray-panel] eq $name)} {
            panel-build $name $idx
            lappend built $name
        }
    }
    # The strips nobody rebuilt come down. Reconciliation, not the
    # old scorched-earth sweep: a surviving panel REUSED its window
    # inside panel-build, so what dies here is only the window of a
    # panel that lost its buttons or its whole declaration. A path
    # may have changed hands when the declaration order moved — a
    # window a survivor took over is not a leftover.
    foreach name [array names ::panel_win] {
        if {$name in $built} continue
        set w $::panel_win($name)
        unset ::panel_win($name)
        array unset ::panel_zone $name
        array unset ::panel_items $name
        array unset ::panel_sig $name
        set claimed 0
        foreach b $built {
            if {$::panel_win($b) eq $w} { set claimed 1; break }
        }
        if {!$claimed} { destroy $w }
    }
    tray-layout      ;# a panel's thickness is the tray's too — it follows
    # A strip that just came up is a NEW window, and whatever rode the
    # old one died with it. Rebuilding them here is what makes a panel
    # rebuild — the commonest event on this desk, and the one that
    # arrives from the most directions — carry its passengers.
    if {[llength [info commands widgets-build]]} { widgets-build }
    restack-soon     ;# the strips are new windows; seat them by layer
    publish-workarea ;# they just took a bite out of the screen
}
proc panel-build {name idx} {
    set g [panel-geometry $name]
    set faces [dict get $g faces]
    set iconic [dict get $g iconic]
    set itemh [dict get $g itemh]
    set thick [dict get $g thick]
    set zone [dict get $g zone]
    set aw [dict get $g aw]
    set vert [dict get $g vert]
    set preset [dict get $g preset]
    set bare [dict get $g bare]
    set isz [dict get $g icon_size]
    set bfont [dict get $g badge_font]
    set mfont [dict get $g mark_font]
    set side [panel-cfg $name side]
    set buttons [panel-cfg $name shown]
    set ::panel_zone($name) $zone
    set er [expr {8 + $zone}]   ;# the face's east inner pad
    # ...and the WEST one, which is the east one MIRRORED when nothing
    # is written in the button (the owner, 2026-08-02: "the icon at
    # the edge of the cell does not look great — maybe reserve the
    # arrow's space on the right and a symmetric one on the left,
    # purely for aesthetics"). With a label, the label fills the middle
    # and the asymmetry never shows; with only an icon there, the whole
    # arrow zone reads as empty space on one side and the icon sits
    # off-centre in its own chip. Nothing is measured differently — it
    # is the same pad on both sides.
    set ipx [expr {$bare ? [list $er $er] : [list 8 $er]}]
    set P .panel$idx
    set old [panel-window $name]   ;# BEFORE the claim below erases it
    set ::panel_win($name) $P
    # A VERTICAL strip is one column, and a column wants one width: the
    # faces are stretched to the widest button's content so their edges
    # line up instead of every face hugging its own label (owner's
    # report, 2026-07-29 — "ничего не выровнено друг с другом"). The
    # face is a UNION element and treectrl ignores -iexpand on those
    # (the badge square met the same wall), so the minimum goes on a
    # MEMBER: the label cell, which every style has. The arithmetic is
    # panel-geometry's, backwards — the strip is content + 20 + zone
    # wide, so the content cell is the strip less its own paddings.
    set memw [expr {max(1, $thick - 2 - 4 - 8 - $er)}]
    # The face is PINNED by its own vertical padding instead of being
    # left to float in the item's slack: the two presets distributed
    # that slack differently (a row centres its content, a stack lets
    # it sit at the top), so the face's lower edge — where the live
    # indicator has to land — was in a different place in each. With
    # the pad, the item is exactly face + 2*fgap and the edge is one
    # number in both.
    set fgap [dict get $g fgap]
    # RECONCILIATION (the owner's ask, 2026-07-31), two storeys. The
    # band is a MAPPED X window, and tearing it down per rebuild was
    # the flicker — a surviving panel keeps its toplevel, and the
    # band moves or resizes in place below, when it moves at all;
    # torn down only when the path changed hands (the declaration
    # order moved) — rare, and honestly a different panel then. One
    # storey further, the TREE inside survives too when the strip's
    # STRUCTURE stands: everything panel-geometry decides — heights,
    # thickness, orientation, the zone, which styles exist and their
    # baked pads — plus the side, folded into one signature. Same
    # signature: the items are reconciled through treesync (two
    # buttons swapping places is two items changing places, the
    # owner's dream case). Signature moved: the tree is honestly
    # built from nothing — its styles ARE the structure — and
    # treesync starts over with it (its map dies with the widget).
    if {$old ne "" && $old ne $P} { destroy $old }
    # ...and the THEME belongs in the signature for the same reason the
    # styles do: a style carries its colours, so a strip that kept its
    # tree across a theme change kept the old theme's paint with it —
    # measured, and the desk went half-light (2026-08-02).
    set sig [list [dict remove $g faces] $side $::theme]
    # THE STRIP'S OWN GROUND, not the outline. What shows of a panel's
    # window is not a border — it is the air around the things placed
    # in it: the gap before a widget area, the slack when the tree is
    # thinner than the band. Dressed in OUTLINE that was invisible for
    # as long as the outline and the ground were the same colour, and
    # the light theme showed what it had really been all along — a
    # heavy black frame around the clock, thick on the gap side and
    # thin on the others, which reads as a 3d bevel nobody drew (the
    # owner, 2026-08-02). Air takes the ground's colour.
    if {[winfo exists $P]} {
        $P configure -background [themed ground]
    } else {
        toplevel $P -background [themed ground]
        wm overrideredirect $P 1
    }
    if {[winfo exists $P.t] && [info exists ::panel_sig($name)]
            && $::panel_sig($name) eq $sig} {
        set T $P.t
        panel-items-sync $T $name $buttons $faces $iconic [dict get $g bare]
        panel-place $name $P $T $g $side [llength $buttons]
        return
    }
    set ::panel_sig($name) $sig
    destroy $P.t
    set T [treectrl $P.t -showheader no -showroot no -showbuttons no \
        -showlines no -borderwidth 0 -highlightthickness 0 \
        -background [themed ground] -itemheight $itemh \
        -orient [expr {$vert ? "vertical" : "horizontal"}]]
    bindtags $T [list $T all]
    $T state define found    ;# the flash: predicate found a window
    $T state define firing   ;# the flash: launching the command
    $T state define live     ;# persistent: the match sees a window
    $T state define multi    ;# persistent: ... more than one
    $T column create -tags C0
    if {$vert} { $T column configure C0 -width [expr {$thick - 2}] }
    $T element create eFace rect \
        -fill [list [themed found] found [themed firing] firing \
                    $::panel_live_face live [themed raised] {}] \
        -outline [themed rule] -outlinewidth 1
    $T element create eBIcon image
    $T element create ePRect rect
    $T element create ePTxt text -fill white -lines 1 -font $bfont
    $T element create eBTxt text -fill [themed ink] -lines 1 -font PanelFont
    $T element create eLive rect -fill [list $::panel_live_bar live] \
        -height 3
    $T element create eSep rect -fill [themed rule] -width 1 \
        -height [expr {$itemh - 14}]
    $T element create eArrow text -text ▾ -fill [themed dim] -font PanelFont
    # The mark over a face: small letters on a chip, so they read on
    # any picture underneath. Both are drawn only when a button asked
    # for one — an empty text and an unpainted rect draw nothing, which
    # is cheaper than a state and says the same thing.
    #
    # The chip's OUTLINE is dressed alongside its fill and not fixed
    # here. Standing on its own it drew the empty chip on every icon
    # that never asked for a mark — a black hairline, a rect with no
    # text in it and its padding for size (the owner's report,
    # 2026-08-02). "Unpainted" has to mean both paints.
    $T element create eMark text -fill [themed ink] -lines 1 -font $mfont
    $T element create eMarkBg rect -outlinewidth 1
    # Three button styles, assigned per item by what its face resolved
    # to: plain (today's text chip — every button when nothing is
    # iconic), icon, and badge; row and stack presets differ in the
    # style's orient and pads only. The badge square is pinned by
    # min-sizing the union MEMBER (the lettering's layout cell, which
    # the union rect then surrounds) — -width/-minwidth/-iexpand on
    # the union element itself are ignored by treectrl.
    $T style create sBtn
    $T style elements sBtn {eFace eBTxt}
    $T style layout sBtn eFace -union eBTxt -ipadx $ipx -ipady 3 \
        -padx 2 -pady $fgap -expand ns
    $T style layout sBtn eBTxt -expand ns
    if {$iconic && $preset eq "stack"} {
        $T style create sBtnI -orient vertical
        $T style elements sBtnI {eFace eBIcon eBTxt}
        $T style layout sBtnI eFace -union {eBIcon eBTxt} \
            -ipadx $ipx -ipady 3 -padx 2 -pady $fgap -expand wens
        # The icon's cell is the icon SQUARE, exactly as the badge's is
        # below — an image that came out smaller (a 24px file on a 48px
        # strip is not upscaled) sits centred in the square its button
        # was measured for, instead of dragging the mark that hangs off
        # its corner out into the open.
        $T style layout sBtnI eBIcon -minwidth $isz -minheight $isz \
            -expand we -pady {0 2}
        $T style layout sBtnI eBTxt -expand we
        $T style create sBtnB -orient vertical
        $T style elements sBtnB {eFace ePRect ePTxt eBTxt}
        $T style layout sBtnB eFace -union {ePRect eBTxt} \
            -ipadx $ipx -ipady 3 -padx 2 -pady $fgap -expand wens
        # The pad goes on the LETTERING, not on the rect around it: a
        # union element is not in the flow, and padding it grows the
        # union instead of spacing the flow (measured — the badge
        # button's content came out 4px taller than an icon button's,
        # so its whole stack sat lower and the label came down onto its
        # own indicator; owner's report, 2026-07-29).
        $T style layout sBtnB ePRect -union ePTxt -expand we
        # -expand we and not wens, exactly as the icon above it: with a
        # vertical slack to grab, the lettering grabs it, and the badge
        # button's whole stack slides down onto its own indicator.
        $T style layout sBtnB ePTxt -minwidth $isz -minheight $isz \
            -expand we -pady {0 2}
        $T style layout sBtnB eBTxt -expand we
        # In a STACK the face is CENTRED over the label, so where its
        # far edge falls depends on which of the two is wider — a
        # number this layout does not have. Walking the mark in from
        # the item's left edge, as the row preset does, therefore lands
        # it on the caption whenever the caption is the wider — which
        # in a stack it usually is (seen: a `t` sitting in the middle
        # of the word under the icon).
        #
        # It is centred instead, and then walked half its distance out:
        # expanding BOTH sides splits the slack evenly, so a pad on one
        # side moves the element by half of it. Centre plus half the
        # icon's width, less half the mark's, is the icon's own corner
        # — whatever the caption does. Vertically there is nothing to
        # guess: the icon is at the top, so the mark hangs from there.
        # Both faces, for the reason panel-btn-dress gives.
        set mw [font measure $mfont M]
        set mline [font metrics $mfont -linespace]
        foreach s {sBtnI sBtnB} {
            $T style elements $s [concat [$T style elements $s] {eMarkBg eMark}]
            $T style layout $s eMarkBg -detach yes -union eMark -ipadx 2 -ipady 1
            $T style layout $s eMark -detach yes -expand wse -minwidth $mw \
                -padx [list [expr {max(0, $isz - $mw - 4)}] 0] \
                -pady [list [expr {max(0, $fgap + 3 + $isz - $mline)}] 0]
        }
    } elseif {$iconic} {
        $T style create sBtnI
        $T style elements sBtnI {eFace eBIcon eBTxt}
        $T style layout sBtnI eFace -union {eBIcon eBTxt} \
            -ipadx $ipx -ipady 3 -padx 2 -pady $fgap -expand wens
        # The gap after the icon is the LABEL's, so with no label
        # there is none — left in, it hangs the icon off-centre in its
        # own chip.
        # ...and the icon's cell is the icon square here too — see the
        # stack preset above.
        $T style layout sBtnI eBIcon -minwidth $isz -minheight $isz \
            -expand ns -padx [list 0 [expr {$bare ? 0 : 4}]]
        $T style layout sBtnI eBTxt -expand ns
        $T style create sBtnB
        $T style elements sBtnB {eFace ePRect ePTxt eBTxt}
        $T style layout sBtnB eFace -union {ePRect eBTxt} \
            -ipadx $ipx -ipady 3 -padx 2 -pady $fgap -expand wens
        # ...and the same in the row preset, where the mis-placed pad
        # made the badge button WIDER than the rest and pushed its
        # right border out of line.
        $T style layout sBtnB ePRect -union ePTxt -expand ns
        # -expand ns, as the icon: the horizontal slack is not the
        # badge's to take — taking it is what pushed this button's
        # right border out of the column.
        $T style layout sBtnB ePTxt -minwidth $isz -minheight $isz \
            -expand ns -padx [list 0 [expr {$bare ? 0 : 4}]]
        $T style layout sBtnB eBTxt -expand ns
        # OVER THE FACE, not over the button. A detached element is
        # placed in the whole item, so «south-east» put the mark past
        # the label at the far end of the chip — right where it does
        # not belong. It is pinned by arithmetic instead, off the
        # numbers this builder already has: expanding north and east
        # anchors it south-WEST, and the pads walk it back to the
        # face's own lower-right corner. The icon and the badge occupy
        # the same square in the same place, so one set of numbers
        # lands the mark on either.
        # The widest a one-or-two letter mark can be, plus the chip's
        # own padding: right-aligning to THAT keeps every mark inside
        # the face instead of letting the long ones run past it.
        set mw [expr {[font measure $mfont M] + 4}]
        set mx [expr {max(0, 2 + [lindex $ipx 0] + $isz - $mw)}]
        set my [expr {max(0, ($itemh - $isz) / 2)}]
        foreach s {sBtnI sBtnB} {
            $T style elements $s [concat [$T style elements $s] {eMarkBg eMark}]
            $T style layout $s eMarkBg -detach yes -union eMark -ipadx 2 -ipady 1
            # A FIXED BOX, not a chip that shrinks to its letter.
            # Right-aligning a variable width to the face's edge put
            # the short marks well inside it and the long ones against
            # it — the same corner looking like two different places.
            # One box, the letter centred in it, and every mark sits
            # where the last one did. Sized for ONE letter, which is
            # what nearly every mark is: a box built for the rare pair
            # left the common case swimming in it, and on a small icon
            # ate the picture it is there to annotate.
            $T style layout $s eMark -detach yes -expand ne \
                -minwidth [font measure $mfont M] \
                -padx [list $mx 0] -pady [list 0 $my]
        }
    }
    # One column, one width: every label cell is min-sized to the
    # widest button's content, so the faces around them come out the
    # same and their edges line up. (Horizontally there is nothing to
    # line up — each button is as wide as it needs and they sit in a
    # row.) eBTxt is in every style's union, which is what makes one
    # line reach all three.
    if {$vert} {
        foreach s [$T style names] {
            # In a STACK the label cell is the whole content width (the
            # icon sits above it); in a ROW the icon shares the line, so
            # the label gets what is left of it. Get this wrong and the
            # face is wider than the strip, which treectrl answers by
            # pushing the label against the far edge.
            set mw $memw
            if {$bare} { set mw 1 }
            if {!$bare && $preset ne "stack" && $s in {sBtnI sBtnB}} {
                set mw [expr {max(1, $memw - $isz - 4)}]
            }
            if {$preset eq "stack" && $s in {sBtnI sBtnB}} {
                # under the icon, centred on it
                $T style layout $s eBTxt -minwidth $mw
            } else {
                # Beside the icon (or alone): the label sticks to the
                # WEST of its (now wider) cell, so a column of labels of
                # different lengths shares one left edge instead of each
                # floating in the middle of its own button (owner,
                # 2026-07-29). -sticky and not -expand: expand moves the
                # cell inside the style, sticky moves the element inside
                # the cell, and it is the cell that was widened here.
                $T style layout $s eBTxt -minwidth $mw -sticky w
            }
        }
    }
    # The live furniture rides every style: the indicator bar along
    # the bottom edge, and — in a zoned panel — the arrow furniture
    # inside the reserved east strip: a separator line and the glyph,
    # both drawn only when the arrow is armed (multi). The whole
    # strip, not the glyph, is the click target — see panel-click.
    foreach s [$T style names] {
        set els [concat [$T style elements $s] {eLive}]
        if {$zone} { lappend els eSep eArrow }
        $T style elements $s $els
        if {$vert} {
            # In a column the item's bottom edge is the NEXT button's
            # doorstep, and a full-width bar drawn there reads as that
            # button's top border — the indicator pointed at the wrong
            # face (owner's report, 2026-07-29). It belongs ON the face:
            # the content is top-aligned in the item, so the face's own
            # lower edge is 2*fgap up from the item's bottom, and -padx
            # 2 (the face's own) gives the bar exactly the face's width.
            # Drawn last, it takes over the bottom stretch of the face's
            # outline — an indicator that is part of the button rather
            # than a stripe near it.
            $T style layout $s eLive -detach yes -iexpand x -expand n \
                -padx 2 -pady [list 0 $fgap]
        } else {
            $T style layout $s eLive -detach yes -iexpand x -expand n
        }
        if {$zone} {
            $T style layout $s eSep -detach yes -expand wns \
                -padx [list 0 [expr {2 + $zone}]] -visible {yes multi no {}}
            $T style layout $s eArrow -detach yes -expand wns \
                -padx [list 0 [expr {2 + ($zone - $aw) / 2}]] \
                -visible {yes multi no {}}
        }
    }
    panel-items-sync $T $name $buttons $faces $iconic $bare
    bind $T <ButtonPress-1> [list panel-click $name %x %y %s]
    panel-place $name $P $T $g $side [llength $buttons]
}
# The items, reconciled through treesync — the same call dresses a
# fresh tree (every row a make) and refreshes a surviving one
# (updates and moves): two buttons swapping places is two items
# changing places, nothing else stirs. The returned map IS
# panel_items — what every flash, click and re-judgement asks.
proc panel-items-sync {T name buttons faces iconic {bare 0}} {
    set rows {}
    foreach b $buttons f $faces {
        lassign $b aname label settings
        lappend rows [list $aname \
            [list $label $f $iconic $bare [panel-mark-of $settings]]]
    }
    set ::panel_items($name) [treesync::sync $T \
        {make panel-btn-make update panel-btn-update} $rows]
}
# One dresser for a fresh item and a survivor alike: which of the
# three styles a button wears and what its elements show is ROW
# data, never item history.
proc panel-btn-dress {T item label face iconic {bare 0} {mark ""}} {
    if {!$iconic} {
        $T item style set $item C0 sBtn
    } elseif {$face ne ""} {
        $T item style set $item C0 sBtnI
        $T item element configure $item C0 eBIcon -image $face
    } else {
        $T item style set $item C0 sBtnB
        lassign [pseudo-badge $label] letters color
        $T item element configure $item C0 ePRect -fill $color
        $T item element configure $item C0 ePTxt -text $letters
    }
    # ...and in ICONS ONLY the label is simply not written. The
    # element stays in the style (that is what keeps the unions and
    # the alignment honest) and an empty text takes no room.
    $T item element configure $item C0 eBTxt -text [expr {$bare ? "" : $label}]
    # ...and the mark, over whichever face resolved. It was the icon's
    # alone, on the reading that a badge is already lettering and a
    # mark over that is two answers to one question. The owner asked
    # for both (2026-08-02) and the reading was wrong: they answer
    # DIFFERENT questions — the face says what opens, the mark says
    # which variation of it — and the badge is only lettering by
    # accident of having no picture to draw. Whatever the button wears,
    # it wears its mark the same way.
    #
    # No mark: no text, no fill AND no outline. Leaving the outline on
    # drew an empty chip as a hairline over every unmarked icon.
    if {$iconic} {
        $T item element configure $item C0 eMark -text $mark
        $T item element configure $item C0 eMarkBg \
            -fill [expr {$mark eq "" ? "" : [themed raised]}] \
            -outline [expr {$mark eq "" ? "" : [themed edge]}]
    }
}
proc panel-btn-make {T parent key data} {
    set item [$T item create]
    panel-btn-dress $T $item {*}$data
    return $item
}
proc panel-btn-update {T item key data} {
    panel-btn-dress $T $item {*}$data
}
# WHERE the strip goes is not the builder's arithmetic: it asks for
# its band (carved in declaration order out of what the panels
# before it left) and takes the edge-hugging part of it that is its
# own thickness — a band widened by a fat tray is not the panel's to
# fill. Shared by the full build and the items-only sync: the band
# can move under an unchanged strip (another panel grew), and moving
# in place is exactly what the reused window is for.
#
# The tray strip sits at the FAR end of this same band, in its own
# top-level above ours: the button row stops short of it so a button
# can never end up hidden under an icon.
# THE BAND'S INNER FACE WEARS A HAIRLINE. The screen edge holds three
# sides of a strip; the fourth is where the clients live, and a strip
# beside a client of its own lightness is two grounds fusing into one
# field — the light browser ran straight into the light panel, and
# the dark desk told the same story in negative (the owner,
# 2026-08-05, both at once). The line is dressed in `curb`, the role
# that steps away from ground in EITHER theme — edge could not say it
# in the dark, where edge IS the strip's own ground.
#   The pixel it stands on is already there. Every rider of a band —
# the tree, a widget area — keeps at least 1px of air to this face
# (the ±1 margins all over the strip geometry), so the line replaces
# air and moves nothing; raised, so the face reads as ONE line for
# the band's whole length, over whatever rode in. And it is drawn
# ONCE, here, on the panel's window — which spans the whole band for
# exactly this reason — never by a rider: the tray is laid a pixel
# short of the face instead (the owner's trade, 2026-08-05 — a pixel
# of tray for a line nobody else has to re-draw).
proc panel-hairline {P side w h} {
    set E $P.hair
    if {![winfo exists $E]} { frame $E -borderwidth 0 }
    $E configure -background [themed curb]
    switch -- $side {
        top    { place $E -x 0 -y [expr {$h - 1}] -width $w -height 1 }
        bottom { place $E -x 0 -y 0 -width $w -height 1 }
        left   { place $E -x [expr {$w - 1}] -y 0 -width 1 -height $h }
        right  { place $E -x 0 -y 0 -width 1 -height $h }
    }
    raise $E
}
proc panel-place {name P T g side n} {
    set thick [dict get $g thick]
    set vert [dict get $g vert]
    set band [strip-band $name]
    if {$band eq ""} { set band [panel-monitor $name] }
    # THE WINDOW COVERS ITS PASSENGERS. A widget riding this panel is a
    # child of this window, so the window has to be as deep as the band
    # it made deeper — otherwise the strip grows, the window does not,
    # and the difference is a stripe of nothing along the top with the
    # widget hanging out of the bottom (the owner, 2026-07-30). The
    # tray needs none of this: it is a toplevel of its own.
    set own $thick
    if {[llength [info commands widgets-thickness]]} {
        set thick [expr {max($thick, [widgets-thickness $name])}]
    }
    # ...and the tray's depth besides — strip-carve's own arithmetic,
    # repeated on purpose: the window is the band's floor and the
    # hairline's anchor, so it has to reach the band's true inner face
    # even when the tray is the deepest thing riding it.
    if {[tray-panel] eq $name} {
        set thick [expr {max($thick, [tray-thickness])}]
    }
    lassign [band-strip $band $side $thick] X Y W H
    set geo ${W}x${H}+${X}+${Y}
    set tray [expr {[tray-panel] eq $name ? [tray-extent] : 0}]
    # ...and the widget area sits between them, so the button row stops
    # short of both. A widget that placed itself would sooner or later
    # place itself on top of one of these.
    set wg 0
    if {[llength [info commands widgets-extent]]} { set wg [widgets-extent $name] }
    # The button row keeps ITS OWN depth and sits in the middle of a
    # strip that a widget made deeper: stretched to the full depth it
    # would be a row of buttons with a field of empty face under each.
    if {$vert} {
        place $T -x [expr {1 + ($W - $own) / 2}] -y 1 -width [expr {$own - 2}] \
            -height [expr {$H - 2 - $tray - $wg}]
    } else {
        place $T -x 1 -y [expr {1 + ($H - $own) / 2}] \
            -width [expr {$W - 2 - $tray - $wg}] -height [expr {$own - 2}]
    }
    wm geometry $P $geo
    panel-hairline $P $side $W $H
    stack-layer $P $::LAYER_DOCK 0     ;# the band's floor...
    panel-reeval     ;# a build starts stateless — judge the matches now
    puts "WM: panel $name up ($n buttons, $thick px,\
 $side/[dict get $g preset], $geo)"
}
# What "focus the hit" means, shared by the plain fire and by activate
# hooks that do more around it (the emacs layer's, so far).
proc panel-focus-hit {w} {
    # ...and the DESK first of all: a window one is sent to is a window
    # one must be able to see, so reaching across desks takes you there
    # (desk-follow is a no-op on a single-desk desk and for a sticky
    # window). Before the deiconify, which focuses on its own.
    desk-follow $w
    if {[info exists ::iconic($w)]} {
        deiconify-client $w   ;# raises and focuses on its own
        return
    }
    raise-group $w
    focus-to $w
}
# The index of an action's button in panel NAME's strip — by the
# action's NAME, which is the reference's key; -1 when the strip is
# not showing it (never referenced, or standing by).
proc panel-index {name aname} {
    set i 0
    foreach b [panel-cfg $name shown] {
        if {[lindex $b 0] eq $aname} { return $i }
        incr i
    }
    return -1
}
# The arrow zone: the deed's own fire, asked to CHOOSE and told which
# panel the hand was on. It has no code of its own any more — the
# filtered list, the anchoring, the pick going through the deed's door,
# the stale-zone case where fewer than two windows are left by the time
# the click lands: all of that is one story in action-fire, and the
# arrow is the gesture that says `choose` out loud. A button press
# itself is the same word saying `mru`, and the difference between the
# two halves of a button is exactly that one argument (see panel-click).
proc panel-arrow {name aname} {
    puts "WM: panel $name: arrow on $aname"
    action-fire $aname choose $name
}
# BY NAME, through the build's item map — a strip that does not carry
# the name simply does not flash, which is what lets action-flash ask
# every panel without asking first.
proc panel-flash {name aname state} {
    if {![info exists ::panel_items($name)]
            || ![dict exists $::panel_items($name) $aname]} return
    set item [dict get $::panel_items($name) $aname]
    set T [panel-tree $name]
    if {$T eq ""} return
    soft "panel flash" {
        $T item state set $item $state
        # the un-flash fires 600 ms later, by which time the panel may
        # have been rebuilt out from under this item — soft, like the rest
        after 600 [list soft "panel unflash" \
            [list $T item state set $item !$state]]
    }
}
proc panel-click {name x y {state 0}} {
    set T [panel-tree $name]
    if {$T eq ""} return
    if {[catch {$T identify -array A $x $y}] || $A(where) ne "item"} return
    # WHOSE button was hit is the item map's answer, read backwards —
    # a strip holds a dozen buttons at most, and the reverse walk is
    # cheaper to keep honest than a second map
    set aname ""
    if {[info exists ::panel_items($name)]} {
        dict for {an it} $::panel_items($name) {
            if {$it == $A(item)} { set aname $an; break }
        }
    }
    if {$aname eq ""} return
    # CTRL SAYS «START ANOTHER», and it says it about the whole button.
    # A modifier answers a different question than a sub-target does —
    # which BRANCH of run-or-raise, not which half of the picture — so
    # it is read before the zone and wins over it. Leaving the arrow to
    # mean something else under Ctrl would split the button's east edge
    # off from the rest of it under one and the same key, and there is
    # nothing on the face to say so.
    if {$state & 4} {
        puts "WM: panel $name: forced run of $aname"
        action-fire $aname run
        return
    }
    # the whole reserved east strip is the arrow's click target, not
    # the glyph — but only while the arrow is armed (multi)
    set zone [expr {[info exists ::panel_zone($name)] ? $::panel_zone($name) : 0}]
    if {$zone > 0 && "multi" in [$T item state get $A(item)]} {
        lassign [$T item bbox $A(item)] _x _y x2 _y2
        if {$x >= $x2 - 2 - $zone} { panel-arrow $name $aname; return }
    }
    # The MAIN AREA is the most recent window, always — a button wears
    # both answers on its face, and the deed's `many` is the word for
    # the keyboard, which has no face to wear them on (the owner,
    # 2026-08-03). Asking for `mru` outright, rather than letting the
    # press mean «auto», is what keeps that true.
    action-fire $aname mru
}
# The strips' place in the world is their LAYER (LAYER_DOCK), declared
# once when each is built. This name survives as the sentence the rest
# of the code says — "the panel belongs on top now" — and means: ask
# the model again.
proc panel-on-top {} { restack-soon }

