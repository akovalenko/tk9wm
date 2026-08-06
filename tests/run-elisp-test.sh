#!/bin/sh
# Regression for the elisp reader — the one suite that needs no X at
# all: library/elisp.tcl is pure functions, so a bare tclsh (whale-cli
# here) sources it alone and reads forms at it. The cases walk the
# printed grammar whole — atoms, strings with escapes and cyrillic,
# lists proper and dotted, vectors, plists into dicts, propertized
# strings, hash-table records, shared structure — and the refusals
# that keep it honest: cycles, unreadables, trailing text. The last
# case is a telega-shaped getTopChats answer, read for ids and
# titles, which is the model task's whole ask.
. "$(dirname "$0")/common.sh"
exec "$WHALE_CLI" "$HERE/elisp-cases.tcl" "$ROOT/library/elisp.tcl"
