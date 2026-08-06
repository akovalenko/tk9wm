#!/bin/sh
# Regression for the edit door — the desk's one default for «open
# this file to edit». Unsaid, the door is emacs when this machine has
# one (both halves asked — the door rides emacsclient), else an
# editor in a terminal down the chain $VISUAL → $EDITOR →
# sensible-editor → the hunt (vim vi mcedit nano), xedit closing it
# as a bare X11 window. Every verdict carries its source; a word
# naming a missing binary falls through with a line; a said `emacs`
# stands even unfound; the none-verdict refuses out loud. The
# dispatch: a terminal editor gets +line inside the desk's own
# terminal under the tk9wm-edit name, a bare xedit gets the file with
# no +line word.
. "$(dirname "$0")/common.sh"
export DISPLAY=:111
rm -f /tmp/.X111-lock /tmp/.X11-unix/X111
Xvfb :111 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

BASE="$HERE/editdoor-config"
rm -rf "$BASE"
mkdir -p "$BASE"

# stub binaries, a directory per scenario shape: resolution only ever
# asks «is it in PATH», so an exit-0 script is a whole editor here
mkbin() {
    d="$BASE/$1"; shift
    mkdir -p "$d"
    for c in "$@"; do
        printf '#!/bin/sh\nexit 0\n' > "$d/$c"
        chmod +x "$d/$c"
    done
}
mkbin bin-emacs emacs emacsclient
mkbin bin-emacs-half emacs
mkbin bin-sens sensible-editor vim vi mcedit nano xedit
mkbin bin-hunt vim vi mcedit nano xedit
mkbin bin-nano nano xedit
mkbin bin-ed myed myvis
mkbin bin-xterm xterm
# ...except the two the dispatch really runs: xedit records its argv,
# xterm stands in for a terminal spawn (the log line is the check)
mkdir -p "$BASE/bin-xedit"
cat > "$BASE/bin-xedit/xedit" <<EOF
#!/bin/sh
printf '%s\n' "\$*" > "$BASE/xedit-argv"
EOF
chmod +x "$BASE/bin-xedit/xedit"

cat > "$BASE/tk9wm.tcl" <<'EOF'
# the test's own seam: one probe = one clean resolution — caches
# dropped, the editor words unset, PATH and the door's word as asked
proc door-probe {door path env} {
    array unset ::auto_execs
    foreach v {VISUAL EDITOR TERMINAL} { unset -nocomplain ::env($v) }
    dict for {k v} $env { set ::env($k) $v }
    set ::env(PATH) $path
    set ::edit_door $door
    set ::edit_door_found {}
    set ::terminal_found {}
    edit-door-resolve
}
EOF

XDG_CONFIG_HOME="$BASE" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-editdoor.log" 2>&1 &
WM=$!
sleep 1.5

q() { printf '%s\n' "$1" > "$BASE/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$BASE/q.tcl"; }

ck() { # ck LABEL GOT WANT
    if [ "$2" = "$3" ]; then echo "OK: $1"
    else echo "FAIL: $1 — got «$2», want «$3»"; fi
}

echo "--- resolution"
ck "unsaid + emacs here = the emacs door" \
   "$(q "door-probe {} $BASE/bin-emacs {}")" "emacs {} found"
ck "emacs without emacsclient is no emacs — the hunt speaks" \
   "$(q "door-probe {} $BASE/bin-emacs-half:$BASE/bin-hunt {}")" \
   "terminal vim probed"
ck "unsaid, emacs outranks a set \$EDITOR" \
   "$(q "door-probe {} $BASE/bin-emacs:$BASE/bin-ed {EDITOR myed}")" \
   "emacs {} found"
ck "said terminal: \$EDITOR, arguments kept" \
   "$(q "door-probe terminal $BASE/bin-emacs:$BASE/bin-ed {EDITOR {myed -q}}")" \
   "terminal {myed -q} \$EDITOR"
ck "\$VISUAL outranks \$EDITOR" \
   "$(q "door-probe terminal $BASE/bin-ed {VISUAL myvis EDITOR myed}")" \
   "terminal myvis \$VISUAL"
ck "a \$VISUAL naming a missing binary falls through" \
   "$(q "door-probe terminal $BASE/bin-ed {VISUAL ghost-editor EDITOR myed}")" \
   "terminal myed \$EDITOR"
ck "no words: sensible-editor before the hunt" \
   "$(q "door-probe {} $BASE/bin-sens {}")" "terminal sensible-editor probed"
ck "the hunt: vim first" \
   "$(q "door-probe {} $BASE/bin-hunt {}")" "terminal vim probed"
ck "...and nano when the vi family is out" \
   "$(q "door-probe {} $BASE/bin-nano {}")" "terminal nano probed"
ck "xedit closes the hunt, as its own window" \
   "$(q "door-probe {} $BASE/bin-xedit {}")" "bare xedit probed"
ck "an empty machine: the none-verdict" \
   "$(q "door-probe {} /var/empty {}")" "none {} none"
ck "a said emacs stands even unfound" \
   "$(q "door-probe emacs /var/empty {}")" "emacs {} set-edit-door"

echo "--- the knob"
q "door-probe {} $BASE/bin-hunt {}" >/dev/null
ck "derived answers the tree while the knob is unsaid" \
   "$(q 'dict get [knob-table] set-edit-door derived')" \
   "vim (probed), in a terminal"
ck "the word is in the vocabulary registry" \
   "$(q 'dict exists $::verb_registry set-edit-door')" "1"

echo "--- dispatch"
printf 'sample\n' > "$BASE/sample.txt"
q "door-probe terminal $BASE/bin-ed:$BASE/bin-xterm {EDITOR myed}" >/dev/null
q "edit-place door $BASE/sample.txt 7"
sleep 0.5
SPAWN=$(grep 'terminal: spawn' "$HERE/wm-editdoor.log" | tail -1)
case $SPAWN in
    *"-name tk9wm-edit"*) echo "OK: the edit terminal wears its name" ;;
    *) echo "FAIL: no tk9wm-edit name in the spawn: $SPAWN" ;;
esac
case $SPAWN in
    *"myed +7 $BASE/sample.txt"*) echo "OK: the editor gets +line and the file" ;;
    *) echo "FAIL: no «myed +7» in the spawn: $SPAWN" ;;
esac
rm -f "$BASE/xedit-argv"
q "door-probe {} $BASE/bin-xedit {}" >/dev/null
q "edit-place door $BASE/sample.txt 7"
sleep 0.5
ck "a bare xedit gets the file and no +line word" \
   "$(cat "$BASE/xedit-argv" 2>/dev/null)" "$BASE/sample.txt"

kill $WM 2>/dev/null

echo "--- the log's own words"
grep 'edit door:' "$HERE/wm-editdoor.log"
if grep -q 'edit door: emacs (found)' "$HERE/wm-editdoor.log"; then
    echo "OK: the verdict line names emacs and its source"
else
    echo "FAIL: no «emacs (found)» verdict line"
fi
if grep -q 'edit door: vim (probed), in a terminal' "$HERE/wm-editdoor.log"; then
    echo "OK: the verdict line names the hunted editor and the terminal"
else
    echo "FAIL: no «vim (probed), in a terminal» verdict line"
fi
if grep -q 'edit door: \$VISUAL names ghost-editor' "$HERE/wm-editdoor.log"; then
    echo "OK: the fall-through says which word it dropped"
else
    echo "FAIL: no fall-through line for the ghost \$VISUAL"
fi
if grep -q 'edit door: no editor anywhere' "$HERE/wm-editdoor.log"; then
    echo "OK: the empty machine refuses out loud"
else
    echo "FAIL: no refusal line for the empty machine"
fi
if grep -q 'set-\*, outside the vocabulary registry.*set-edit-door' \
        "$HERE/wm-editdoor.log"; then
    echo "FAIL: set-edit-door is loose outside the registry"
else
    echo "OK: the audit does not flag set-edit-door"
fi
check_invariants "$HERE/wm-editdoor.log"
