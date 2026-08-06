# elisp-cases.tcl — the elisp reader's cases, run by run-elisp-test.sh
# under a bare tclsh: argv is the path of library/elisp.tcl. Each case
# prints one OK/FAIL line; the exit code is the count of failures.
source -encoding utf-8 [lindex $argv 0]
chan configure stdout -encoding utf-8

set bad 0
proc is {what got want} {
    global bad
    if {$got eq $want} {
        puts "OK: $what"
    } else {
        puts "FAIL: $what\n    got  «$got»\n    want «$want»"
        incr bad
    }
}
proc dies {what script pattern} {
    global bad
    if {[catch {uplevel #0 $script} err]} {
        if {[string match *$pattern* $err]} {
            puts "OK: $what — refused: [lindex [split $err \n] 0]"
            return
        }
        puts "FAIL: $what — died of the wrong thing: $err"
        incr bad
        return
    }
    puts "FAIL: $what — was read instead of refused"
    incr bad
}

# ---- atoms
is "an integer"            [elisp-read {42}] 42
is "a negative integer"    [elisp-read {-7}] -7
is "a trailing-dot integer" [elisp-read {1.}] 1
is "a float"               [elisp-read {1.5}] 1.5
is "an exponent float"     [elisp-read {-2e3}] -2000.0
is "a bare-point float"    [elisp-read {.5}] 0.5
is "a telega-sized id"     [elisp-read {880396138110181}] 880396138110181
is "infinity prints back"  [elisp-read {1.0e+INF}] Inf
is "a symbol"              [elisp-read {foo-bar}] foo-bar
is "a keyword keeps its colon" [elisp-read {:title}] :title
is "t is itself"           [elisp-read {t}] t
is "nil is empty"          [elisp-read {nil}] {}
is "() is empty too"       [elisp-read {()}] {}
is "an escaped digit is a symbol" [elisp-read {\1}] 1
is "0x10 is a symbol there" [elisp-read {0x10}] 0x10

# ---- strings
is "a plain string"        [elisp-read {"hello"}] hello
is "a cyrillic string"     [elisp-read {"Вася Пупкин"}] {Вася Пупкин}
is "escaped quote and backslash" [elisp-read {"a\"b\\c"}] {a"b\c}
is "newline escape"        [elisp-read {"a\nb"}] "a\nb"
is "a literal newline stands" [elisp-read "\"a\nb\""] "a\nb"
is "hex escape"            [elisp-read {"\x41B"}] "Л"
is "unicode escape"        [elisp-read {"Ж"}] "Ж"
is "octal escape"          [elisp-read {"\101"}] "A"

# ---- lists, pairs, vectors, sugar
is "a nested list"         [elisp-read {(a (b c) d)}] {a {b c} d}
is "a dotted pair drops its dot" [elisp-read {(name . "TELEGA")}] {name TELEGA}
is "an improper tail joins" [elisp-read {(a b . c)}] {a b c}
is "a dotted nil tail is proper" [elisp-read {(a . nil)}] a
is "a dotted list tail splices" [elisp-read {(a . (b c))}] {a b c}
is "an alist reads as pairs" [elisp-read {((width . 80) (height . 24))}] {{width 80} {height 24}}
is "a vector is a list"    [elisp-read {[1 2 [3 4]]}] {1 2 {3 4}}
is "quote is spelled out"  [elisp-read {'x}] {quote x}
is "function too"          [elisp-read {#'car}] {function car}
is "a char is its code"    [elisp-read {?a}] 97
is "an escaped char too"   [elisp-read {?\n}] 10
is "comments vanish"       [elisp-read "(a ;; noise\n b)"] {a b}
is "a plist is a dict" \
    [dict get [elisp-read {(:id 42 :title "Вася")}] :title] Вася

# ---- the printed exotica
is "a propertized string is its string" \
    [elisp-read {#("Вася" 0 4 (face bold))}] Вася
is "a hash-table is its data" \
    [elisp-read {#s(hash-table size 2 test equal data (k1 "v1" k2 (a b)))}] \
    {k1 v1 k2 {a b}}
is "an empty hash-table is empty" \
    [elisp-read {#s(hash-table test eq data ())}] {}
is "another record is its elements" \
    [elisp-read {#s(cl-point 3 4)}] {cl-point 3 4}
is "shared structure reads as copies" \
    [elisp-read {(#1=(a b) #1#)}] {{a b} {a b}}
is "radix integers" [elisp-read {(#x1F #o17 #b101)}] {31 15 5}
is "-all reads every form" \
    [elisp-read -all "1 (two) \"три\""] {1 two три}

# ---- the refusals
dies "a cycle"        {elisp-read {#1=(a . #1#)}} cycle
dies "an unreadable"  {elisp-read {(frame #<frame F1>)}} unreadable
dies "a char-table"   {elisp-read {#^[1 2]}} char-table
dies "trailing text"  {elisp-read {(a) (b)}} "more text"
dies "an unbalanced paren" {elisp-read {(a b}} unterminated
dies "a modifier char" {elisp-read {?\C-x}} modifier
dies "an empty input" {elisp-read {}} "end of input"

# ---- the telega shape: a getTopChats answer, near enough — nested
# plists, vectors of positions, cyrillic titles, ids that need 64
# bits — read for what the menu wants of it
set answer {(#1=(:@type "chat" :id 880396138110181 :type
 (:@type "chatTypePrivate" :user_id 88039613)
 :title "Вася Пупкин" :positions
 [(:@type "chatPosition" :list (:@type "chatListMain") :order "6910000000000000000")]
 :unread_count 3)
 (:@type "chat" :id -1001234567890 :type
 (:@type "chatTypeSupergroup" :supergroup_id 1234567890)
 :title "рабочий чат «скобки (и такие)»" :positions [] :unread_count 0))}
set chats [elisp-read $answer]
is "two chats came back" [llength $chats] 2
set c1 [lindex $chats 0]
set c2 [lindex $chats 1]
is "the first id"    [dict get $c1 :id] 880396138110181
is "the first title" [dict get $c1 :title] {Вася Пупкин}
is "a nested plist reads through" \
    [dict get [dict get $c1 :type] :user_id] 88039613
is "a position rides a vector" \
    [dict get [lindex [dict get $c1 :positions] 0] :order] 6910000000000000000
is "a negative supergroup id" [dict get $c2 :id] -1001234567890
is "a title full of quoting survives" \
    [dict get $c2 :title] {рабочий чат «скобки (и такие)»}

if {$bad} { puts "SUITE FAILED: $bad case(s)" } else {
    puts "OK: the printed grammar reads whole, and the refusals refuse"
}
exit $bad
