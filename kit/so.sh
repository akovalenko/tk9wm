#!/bin/sh
# so.sh — build the two binary parts a kit needs, as stubs-linked
# shared libraries: the tkwmx shim and treectrl.
#
# Both are built INSIDE whalebuild's container box, and that is the
# whole point rather than a convenience. The box holds an old userland
# (AlmaLinux 8, glibc 2.28), so what comes out runs on distro
# generations the host's own toolchain could not serve — but more
# importantly, the Tcl/Tk install tree the extensions link against
# bakes ABSOLUTE paths into tclConfig.sh at core-configure time. Built
# in the box those paths are the box's (/w/work/...), and an extension
# configured against them from outside gets a -L pointing at nothing.
# So the extension build has to happen where the core build happened.
#
#   WHALEBUILD=../whalebuild ./kit/so.sh      -> kit/so/
#
# Set PODMAN if your podman is a wrapper script (cbuild.sh honors it).
# Paths must not contain spaces: cbuild.sh word-splits CBUILD_OPTS.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
WHALEBUILD=${WHALEBUILD:-$ROOT/../whalebuild}
if [ ! -x "$WHALEBUILD/cbuild.sh" ]; then
    echo "so.sh: no whalebuild checkout at $WHALEBUILD (set WHALEBUILD=)" >&2
    exit 2
fi
WHALEBUILD=$(cd "$WHALEBUILD" && pwd)
OUT=$HERE/so
mkdir -p "$OUT"

# treectrl — a whalebuild recipe, so whalebuild builds it: it owns the
# pinned source, the patches and the pkgIndex, and its `so` command
# lays the result out as a ready package directory.
( cd "$WHALEBUILD" && ./cbuild.sh linux so treectrl )
rm -rf "$OUT/treectrl"
cp -a "$WHALEBUILD/work-linux/linux/so/treectrl" "$OUT/"

# tkwmx — ours, and it has its own configure (which has always been
# able to do this: stubs on both legs, see the top of ./configure).
# What it needs from here is only to run in the same box, against the
# same install tree. It builds a COPY of the checkout so a kit build
# never disturbs the developer's own config.mk and .so.
( cd "$WHALEBUILD" && CBUILD_OPTS="-v $ROOT:/tk9wm:ro -v $OUT:/out" \
    ./cbuild.sh linux -- sh -c 'rm -rf /tmp/tkwmx-build \
	&& cp -a /tk9wm /tmp/tkwmx-build && cd /tmp/tkwmx-build \
	&& ./configure --with-tcl=/w/work/linux/install/lib --disable-static \
	&& make clean && make libtkwmx.so && cp libtkwmx.so /out/' )

ls -l "$OUT" "$OUT/treectrl"
