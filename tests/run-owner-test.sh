#!/bin/sh
# Regression for WHOSE a binding is — the origin a leaf now carries.
#
# The desk used to work it out afterwards, by matching the layers'
# words against the live payload, and that could not tell two
# identical scripts apart nor say anything about a word that had
# stopped answering. Worse, it made a family's departure blind: the
# owner's desk, 2026-08-01 — three binds TAKEN out of the accords
# bundle died when the bundle was toggled, because `wm-keys off`
# swept its chords whoever owned them by then.
#
# So: a bind over a bundle's chord says so in the log and owns it;
# the bundle leaving takes only what is still its own; and the
# bindings family reports the owner from the binding itself, with a
# REASON on a word that no longer answers.
. "$(dirname "$0")/common.sh"
export DISPLAY=:68
rm -f /tmp/.X68-lock /tmp/.X11-unix/X68
Xvfb :68 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/owner-config"
mkdir -p "$HERE/owner-config"
cat > "$HERE/owner-config/tk9wm.tcl" <<'EOF'
wm-bind {<Super>9} {list from-the-config}
EOF

XDG_CONFIG_HOME="$HERE/owner-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-owner.log" 2>&1 &
WM=$!
sleep 1.5

q() { printf '%s\n' "$1" > "$HERE/owner-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/owner-config/q.tcl"; }
# sh keeps brackets literal inside double quotes; only $ needs the
# backslash — the Tcl below is written as Tcl, not escaped into it
origin() { q "keymap-origin \$::keymap [lmap t {$1} {join [parse-chord \$t] ,}]"; }
answers() { q "lindex [keymap-payload \$::keymap [lmap t {$1} {join [parse-chord \$t] ,}]] 0"; }

# the floor: the code's own bundle, and the config's own line
BEFORE="$(origin '<Super>t w m') $(origin '<Super>9')"

# THE TAKE: a plain bind over a chord the bundle answers
q 'custom-write {wm-bind {<Super>t w m} {list mine-now} {}}' >/dev/null
sleep 0.3
TAKEN="$(origin '<Super>t w m') $(answers '<Super>t w m')"
TOOK=$(grep -c "takes it from bundle accords" "$HERE/wm-owner.log")

# THE TOGGLE that used to destroy it
q 'wm-keys accords off' >/dev/null
sleep 0.3
AFTEROFF="$(origin '<Super>t w m') $(answers '<Super>t w m') $(answers '<Super>t q')"
LEFT=$(grep -c "leaves 1 chord(s) — not its own any more" "$HERE/wm-owner.log")

# ...and the family coming back takes its chord back, saying so —
# which is a claim the tree can now SHOW instead of a mystery
q 'wm-keys accords' >/dev/null
sleep 0.3
BACK="$(origin '<Super>t w m') $(answers '<Super>t w m')"
WHY=$(q 'set r none
    foreach e [dict get [collection-bindings] elements] {
        if {[dict get $e key] eq "Super+t w m" && [dict exists $e ineffectual]} {
            set r [dict get $e why]
        }
    }
    set r')

# ...and the config's own line answers WHERE it was said (info frame,
# the owner's pointer): the file and the line, not just the layer
WHERE=$(q 'set r none
    foreach e [dict get [collection-bindings] elements] {
        if {[dict get $e key] eq "Super+9" && [dict exists $e where]} {
            set r [file tail [dict get $e where]]
        }
    }
    set r')

kill $WM 2>/dev/null
sleep 0.3

echo "--- before={$BEFORE} taken={$TAKEN} afteroff={$AFTEROFF} back={$BACK}"
echo "--- why={$WHY} took=$TOOK left=$LEFT where=$WHERE"
echo "--- verdict"
if [ "$BEFORE" = "bundle accords config" ]; then
    echo "OK: a binding says whose it is — the family's, the config's"
else
    echo "FAIL: before: $BEFORE"
fi
if [ "$TAKEN" = "custom list mine-now" ] && [ "$TOOK" = 1 ]; then
    echo "OK: a bind over a family's chord takes it, and says so in the log"
else
    echo "FAIL: taken: $TAKEN (log lines: $TOOK)"
fi
if [ "$AFTEROFF" = "custom list mine-now " ] && [ "$LEFT" = 1 ]; then
    echo "OK: the family left with its own chords and kept its hands off mine"
else
    echo "FAIL: after the toggle: $AFTEROFF (left-lines: $LEFT)"
fi
case "$BACK|$WHY" in
    "bundle accords winops|"*"answers here now"*)
        echo "OK: the family taking it back is a claim the tree can explain" ;;
    *) echo "FAIL: back={$BACK} why={$WHY}" ;;
esac
if [ "$WHERE" = "tk9wm.tcl:1" ]; then
    echo "OK: a word from a file remembers which file and which line"
else
    echo "FAIL: where: «$WHERE» (want tk9wm.tcl:1)"
fi
check_invariants "$HERE/wm-owner.log"
