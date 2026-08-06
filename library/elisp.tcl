# elisp.tcl — a reader for Emacs Lisp's printed representation.
#
# The desk talks to emacs daemons (the emacs layer, the telega menu),
# and what an emacsclient -e answers is a PRINTED elisp value: lists
# and dotted pairs, vectors, strings with escapes, symbols and
# keywords, numbers, propertized strings, #s(...) records with
# hash-tables among them, #N=/#N# shared structure. This file reads
# that grammar whole, plus the cheap source sugar (comments, quotes,
# ?chars, radix integers) — enough to read a .el form off a file too.
#
# TWO LAYERS, BY DESIGN (the owner's condition, 2026-08-06): the
# parser builds a TYPED TREE and knows nothing of what a consumer
# wants; the naive projection most callers read through is a separate
# walk over that tree. A typed mode later is the tree handed out as
# is — the reading layer does not change for it. The node grammar,
# whole:
#
#   {sym NAME}            a symbol; keywords keep their colon, nil is
#                         the symbol nil (the projection makes it "")
#   {num N}               integer or float, Tcl's own value; the
#                         unrepresentable NaN stays the string NaN
#   {str TEXT}            a string, escapes resolved
#   {list {NODE …}}       a proper list; () reads as {sym nil}, and a
#                         dotted tail that is itself a list splices
#                         back into a proper one, as the reader must
#   {dlist {NODE …} TAIL} an improper list: elements, then the tail
#                         after the dot
#   {vec {NODE …}}        a vector
#   {propstr TEXT {NODE …}}   #("text" …): the string, then the
#                         property forms as read
#   {record {NODE …}}     #s(…): the type word first, the rest as
#                         read — a hash-table is a record whose data
#                         the projection knows to unfold
#
# THE NAIVE PROJECTION flattens that to what a config actually
# handles: strings and symbols become their text, nil becomes empty,
# numbers themselves, lists and vectors become Tcl lists, a dotted
# pair drops its dot ((a . b) reads {a b}, so an alist reads as
# pairs), a propertized string is its string, a hash-table record is
# its data as a flat key-value list — a plist projects straight into
# a Tcl dict, which is the shape the telega menu reads with
# `dict get $chat :title`. The type distinctions are LOST, on
# purpose, and recoverable by the typed layer the day a consumer
# wants them.
#
# What is refused, out loud: an unreadable #<object>, a char-table,
# a #N# closing a cycle (this reader reads trees), character
# modifiers (?\C-x — print never writes them), \N{named} escapes.
# Shared non-cyclic structure (#1=… #1#) reads as copies.

namespace eval elisp {
    variable text ""
    variable pos 0
    variable len 0
    variable defs
}

# The error names WHERE: a window of the text around the point the
# reader stood at, because «unbalanced paren» without an address in a
# ten-kilobyte getTopChats answer is not a sentence one can act on.
proc elisp::fail {msg} {
    variable text; variable pos
    set from [expr {max(0, $pos - 24)}]
    set upto [expr {min([string length $text] - 1, $pos + 24)}]
    error "elisp-read: $msg at offset $pos\
 «[string range $text $from $upto]»"
}

proc elisp::begin {t} {
    variable text; variable pos; variable len; variable defs
    array unset defs
    set text $t
    set len [string length $t]
    set pos 0
}

proc elisp::skip-ws {} {
    variable text; variable pos; variable len
    while {$pos < $len} {
        set c [string index $text $pos]
        if {[string is space $c]} { incr pos; continue }
        if {$c eq ";"} {
            set nl [string first "\n" $text $pos]
            set pos [expr {$nl < 0 ? $len : $nl + 1}]
            continue
        }
        break
    }
}

# The characters that END an atom — elisp's own terminating macro
# characters. # and ? are deliberately not among them: foo#bar and
# foo?bar are symbols there and stay symbols here.
proc elisp::is-delim {c} {
    expr {$c eq "" || [string is space $c]
          || [string first $c "()\[\]\";'`,"] >= 0}
}

proc elisp::raw-token {} {
    variable text; variable pos; variable len
    set out ""
    while {$pos < $len && ![is-delim [string index $text $pos]]} {
        append out [string index $text $pos]
        incr pos
    }
    return $out
}

proc elisp::read-form {} {
    variable text; variable pos; variable len
    skip-ws
    if {$pos >= $len} { fail "unexpected end of input" }
    set c [string index $text $pos]
    switch -- $c {
        "(" { incr pos; return [read-list] }
        "\[" { incr pos; return [list vec [read-seq "\]"]] }
        "\"" { incr pos; return [list str [read-string]] }
        "'" { incr pos
              return [list list [list {sym quote} [read-form]]] }
        "`" { incr pos
              return [list list [list {sym `} [read-form]]] }
        "," { incr pos
              if {[string index $text $pos] eq "@"} {
                  incr pos
                  return [list list [list {sym ,@} [read-form]]]
              }
              return [list list [list {sym ,} [read-form]]] }
        "?" { incr pos; return [list num [read-char]] }
        "#" { return [read-hash] }
        ")" - "\]" { fail "unbalanced «$c»" }
        default { return [read-atom] }
    }
}

proc elisp::read-seq {term} {
    variable text; variable pos; variable len
    set elems {}
    while 1 {
        skip-ws
        if {$pos >= $len} { fail "unterminated sequence (wanted $term)" }
        if {[string index $text $pos] eq $term} {
            incr pos
            return $elems
        }
        lappend elems [read-form]
    }
}

proc elisp::read-list {} {
    variable text; variable pos; variable len
    set elems {}
    while 1 {
        skip-ws
        if {$pos >= $len} { fail "unterminated list" }
        set c [string index $text $pos]
        if {$c eq ")"} {
            incr pos
            if {![llength $elems]} { return {sym nil} }
            return [list list $elems]
        }
        if {$c eq "." && [llength $elems]
                && [is-delim [string index $text [expr {$pos + 1}]]]} {
            incr pos
            set tail [read-form]
            skip-ws
            if {[string index $text $pos] ne ")"} {
                fail "one form after the dot"
            }
            incr pos
            # (a . (b c)) IS (a b c) and (a . nil) IS (a): the reader
            # normalizes, so the tree carries one spelling of a list
            switch -- [lindex $tail 0] {
                list { return [list list [concat $elems [lindex $tail 1]]] }
                sym  { if {[lindex $tail 1] eq "nil"} {
                           return [list list $elems]
                       } }
            }
            return [list dlist $elems $tail]
        }
        lappend elems [read-form]
    }
}

proc elisp::read-string {} {
    variable text; variable pos; variable len
    set out ""
    while 1 {
        if {$pos >= $len} { fail "unterminated string" }
        set c [string index $text $pos]
        incr pos
        if {$c eq "\""} { return [fold-surrogates $out] }
        if {$c ne "\\"} { append out $c; continue }
        append out [read-escape]
    }
}

# An emoji that crossed telega's wire comes out of emacs as CESU-8 —
# a surrogate PAIR encoded as two characters — and the tolerant
# channel profile (pipe-run reads -profile tcl8) hands them through
# as two lone surrogates. Folded here, once, for every consumer:
# a title reads as its emoji, not as two tofu boxes. A lone
# surrogate with no partner passes through as it came.
proc elisp::fold-surrogates {s} {
    if {![regexp {[\uD800-\uDBFF]} $s]} { return $s }
    set out ""
    set n [string length $s]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $s $i]
        scan $c %c hi
        if {$hi >= 0xD800 && $hi <= 0xDBFF && $i + 1 < $n} {
            scan [string index $s [expr {$i + 1}]] %c lo
            if {$lo >= 0xDC00 && $lo <= 0xDFFF} {
                append out [format %c \
                    [expr {0x10000 + (($hi & 0x3FF) << 10) + ($lo & 0x3FF)}]]
                incr i
                continue
            }
        }
        append out $c
    }
    return $out
}

proc elisp::read-escape {} {
    variable text; variable pos; variable len
    if {$pos >= $len} { fail "dangling backslash" }
    set c [string index $text $pos]
    incr pos
    switch -- $c {
        n { return "\n" }
        t { return "\t" }
        r { return "\r" }
        f { return "\f" }
        e { return "\x1b" }
        a { return "\a" }
        b { return "\b" }
        v { return "\v" }
        s { return " " }
        d { return "\x7f" }
        x {
            set n ""
            while {[string is xdigit -strict \
                        [string index $text $pos]]} {
                append n [string index $text $pos]
                incr pos
            }
            if {$n eq ""} { fail "\\x wants hex digits" }
            return [format %c 0x$n]
        }
        u { return [read-escape-hex 4] }
        U { return [read-escape-hex 8] }
        N { fail "\\N{named} escapes are not read here" }
        default {
            if {[string match {[0-7]} $c]} {
                set n $c
                while {[string length $n] < 3
                       && [string match {[0-7]} \
                               [string index $text $pos]]} {
                    append n [string index $text $pos]
                    incr pos
                }
                scan $n %o v
                return [format %c $v]
            }
            return $c   ;# \" \\ and any escaped literal
        }
    }
}

proc elisp::read-escape-hex {want} {
    variable text; variable pos; variable len
    set n [string range $text $pos [expr {$pos + $want - 1}]]
    if {[string length $n] != $want
            || ![string is xdigit -strict $n]} {
        fail "\\u wants exactly $want hex digits"
    }
    incr pos $want
    return [format %c 0x$n]
}

# ?a is the character as its code — a char IS an integer there. The
# modifier syntaxes print never writes are refused out loud rather
# than miscomputed.
proc elisp::read-char {} {
    variable text; variable pos; variable len
    if {$pos >= $len} { fail "unterminated ?char" }
    set c [string index $text $pos]
    if {$c ne "\\"} {
        incr pos
        return [scan $c %c]
    }
    set esc [string index $text [expr {$pos + 1}]]
    if {[string index $text [expr {$pos + 2}]] eq "-"
            && [string first $esc "CMSHsA"] >= 0} {
        fail "character modifiers (?\\C- ?\\M- …) are not read here"
    }
    if {$esc eq "^"} {
        fail "control syntax (?\\^X) is not read here"
    }
    incr pos
    return [scan [read-escape] %c]
}

proc elisp::read-radix {base} {
    set tok [raw-token]
    set sign ""
    if {[string index $tok 0] in {+ -}} {
        set sign [string index $tok 0]
        set tok [string range $tok 1 end]
    }
    set fmt [dict get {16 %x 8 %o 2 %b} $base]
    if {$tok eq "" || [scan $tok $fmt%n v used] != 2
            || $used != [string length $tok]} {
        fail "not a base-$base integer «$sign$tok»"
    }
    if {$sign eq "-"} { set v [expr {-$v}] }
    return [list num $v]
}

proc elisp::read-hash {} {
    variable text; variable pos; variable len; variable defs
    incr pos   ;# past the #
    if {$pos >= $len} { fail "dangling #" }
    set c [string index $text $pos]
    switch -glob -- $c {
        ' { incr pos
            return [list list [list {sym function} [read-form]]] }
        ( {
            # #("text" START END PROPS …) — a propertized string:
            # the string is the substance, the properties ride along
            # for a typed reader
            incr pos
            set elems [read-seq ")"]
            if {![llength $elems]
                    || [lindex $elems 0 0] ne "str"} {
                fail "#(…) starts with its string"
            }
            return [list propstr [lindex $elems 0 1] \
                        [lrange $elems 1 end]]
        }
        s {
            if {[string index $text [expr {$pos + 1}]] ne "("} {
                fail "#s wants a («record» …) after it"
            }
            incr pos 2
            set elems [read-seq ")"]
            if {![llength $elems]} { fail "#s() names no type" }
            return [list record $elems]
        }
        \# { incr pos; return {sym {}} }   ;# the empty-named symbol
        : { incr pos; return [list sym [raw-token]] }  ;# uninterned
        x - X { incr pos; return [read-radix 16] }
        o - O { incr pos; return [read-radix 8] }
        b - B { incr pos; return [read-radix 2] }
        < { fail "#<…> is unreadable by construction" }
        ^ { fail "char-tables are not read here" }
        {[0-9]} {
            set n ""
            while {[string match {[0-9]} [string index $text $pos]]} {
                append n [string index $text $pos]
                incr pos
            }
            set c [string index $text $pos]
            incr pos
            if {$c eq "="} {
                set defs($n) __elisp_building__
                set node [read-form]
                set defs($n) $node
                return $node
            }
            if {$c eq "#"} {
                if {![info exists defs($n)]} {
                    fail "#$n# names nothing defined"
                }
                if {$defs($n) eq "__elisp_building__"} {
                    fail "#$n# closes a cycle — this reader reads trees"
                }
                return $defs($n)
            }
            fail "#$n$c is not a syntax this reader knows"
        }
        default { fail "#$c is not a syntax this reader knows" }
    }
}

proc elisp::read-atom {} {
    variable text; variable pos; variable len
    set out ""
    set forced 0
    while {$pos < $len} {
        set c [string index $text $pos]
        if {[is-delim $c]} break
        incr pos
        if {$c eq "\\"} {
            if {$pos >= $len} { fail "dangling backslash" }
            append out [string index $text $pos]
            incr pos
            set forced 1
            continue
        }
        append out $c
    }
    if {$out eq ""} { fail "nothing to read" }
    if {!$forced} {
        set n [atom-number $out]
        if {[llength $n]} { return [list num [lindex $n 0]] }
    }
    return [list sym $out]
}

# Number or not, elisp's way: an integer may wear a trailing dot
# (1. is 1), a float needs a point or an exponent, INF and NaN print
# as 1.0e+INF / 0.0e+NaN. Anything else — 0x10 included, which elisp
# reads as a symbol — is a symbol.
proc elisp::atom-number {s} {
    if {[regexp {^[+-]?[0-9]+\.?$} $s]} {
        return [list [expr {[string trimright $s .] + 0}]]
    }
    if {[regexp {^([+-]?)[0-9]*\.?[0-9]+e\+INF$} $s -> sign]} {
        return [list [expr {$sign eq "-" ? -Inf : Inf}]]
    }
    if {[regexp {e\+NaN$} $s]} { return [list NaN] }
    if {[regexp {^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$} $s]
            && [regexp {[.eE]} $s]} {
        return [list [expr {$s + 0.0}]]
    }
    return {}
}

proc elisp::parse-one {t} {
    variable pos; variable len
    begin $t
    set n [read-form]
    skip-ws
    if {$pos < $len} { fail "one form expected, more text follows" }
    return $n
}

proc elisp::parse-all {t} {
    variable pos; variable len
    begin $t
    set out {}
    while 1 {
        skip-ws
        if {$pos >= $len} { return $out }
        lappend out [read-form]
    }
}

proc elisp::project {node} {
    set kind [lindex $node 0]
    switch -- $kind {
        num - str { return [lindex $node 1] }
        sym {
            # NOT through expr: a number-shaped symbol (elisp reads
            # 0x10 as a symbol) must come back as its own text, not
            # as what expr thinks the text is worth
            set name [lindex $node 1]
            if {$name eq "nil"} { return {} }
            return $name
        }
        propstr { return [lindex $node 1] }
        list - vec {
            set out {}
            foreach e [lindex $node 1] { lappend out [project $e] }
            return $out
        }
        dlist {
            set out {}
            foreach e [lindex $node 1] { lappend out [project $e] }
            lappend out [project [lindex $node 2]]
            return $out
        }
        record {
            set elems [lindex $node 1]
            if {[lindex $elems 0] eq {sym hash-table}} {
                # the table IS its data: the field list alternates
                # after the type word, and data carries the pairs
                for {set i 1} {$i < [llength $elems]} {incr i 2} {
                    if {[lindex $elems $i] eq {sym data}} {
                        return [project [lindex $elems [expr {$i + 1}]]]
                    }
                }
                return {}
            }
            set out {}
            foreach e $elems { lappend out [project $e] }
            return $out
        }
    }
    error "elisp::project: unknown node «$kind»"
}

# ---- the word the config reads through --------------------------
# `elisp-read TEXT` — one printed form, naively projected; text
# after the form is an error, because an answer that says more than
# one thing deserves to be read on purpose. `elisp-read -all TEXT`
# — every form in the text, as a list (a .el file is many forms).
proc elisp-read {args} {
    set all 0
    if {[lindex $args 0] eq "-all"} {
        set all 1
        set args [lrange $args 1 end]
    }
    if {[llength $args] != 1} {
        error "usage: elisp-read ?-all? TEXT"
    }
    set t [lindex $args 0]
    if {!$all} { return [elisp::project [elisp::parse-one $t]] }
    set out {}
    foreach node [elisp::parse-all $t] {
        lappend out [elisp::project $node]
    }
    return $out
}
