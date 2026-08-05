#!/bin/sh
# Battery driver: run the named suites one after another (each raises
# its own Xvfb, so they cannot share a display anyway) and print a
# one-line verdict per suite — GREEN with the OK count, or RED with
# the suite's own FAIL lines. The usual call names just the suites a
# change touches:
#
#     sh run-battery.sh ewmhmax maxflag reflow
cd "$(dirname "$0")" || exit 1
for t in "$@"; do
    OUT=$(sh "./run-$t-test.sh" 2>&1)
    FAILS=$(printf '%s\n' "$OUT" | grep -c '^FAIL')
    OKS=$(printf '%s\n' "$OUT" | grep -c '^OK')
    if [ "$FAILS" -eq 0 ] && [ "$OKS" -gt 0 ]; then
        echo "GREEN $t ($OKS ok)"
    else
        echo "RED   $t ($FAILS fails, $OKS ok)"
        printf '%s\n' "$OUT" | grep '^FAIL' | sed 's/^/      /'
    fi
done
