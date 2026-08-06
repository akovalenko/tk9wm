#!/bin/sh
# so.sh — build the binary parts a kit needs, as stubs-linked shared
# libraries: Tk itself, the tkwmx shim and treectrl.
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

# Tk itself, shared, stubs-linked, Xft — the reason the kit line
# breathes again: a stock tclkit draws core X fonts, so the kit brings
# its own Tk and loads it first (see mkkit.sh). Built from whalebuild's
# pinned tk tree, in the box, against the box's install — same law as
# the shim below. -Bsymbolic pins the library's internal references to
# its own definitions: a tclkit that carries a static Tk exports the
# whole public Tk API into the dynamic table, and without the pin the
# loader would resolve our calls into the built-in core-fonts Tk.
# --disable-xss: all it feeds is `tk inactive`, which neither the stock
# tclkits nor whale support either (no libXss in anyone's NEEDED).
# --disable-zipfs: the default build glues a zip of tk_library onto the
# .so and mounts it from Tk_Init — self-contained, but only when loaded
# by its real path. Out of a starkit the core loads a TEMP COPY and
# unlinks it before Tk_Init runs, so the tail is unreachable exactly
# where this .so lives; the scripts travel as plain files in the kit
# instead (main.tcl sets tk_library), and the tail would be dead weight.
( cd "$WHALEBUILD" && CBUILD_OPTS="-v $OUT:/out" \
    ./cbuild.sh linux -- sh -c 'rm -rf /tmp/tk-shared /tmp/tk-install \
	&& cp -a /w/work/cache/tk /tmp/tk-shared && cd /tmp/tk-shared/unix \
	&& ./configure --enable-shared --enable-xft --disable-xss \
	    --disable-zipfs --prefix=/tmp/tk-install \
	    --with-tcl=/w/work/linux/install/lib LDFLAGS=-Wl,-Bsymbolic \
	    >/out/tk-build.log 2>&1 \
	&& make -j"$(nproc)" >>/out/tk-build.log 2>&1 \
	&& make install-binaries install-libraries >>/out/tk-build.log 2>&1 \
	&& rm -rf /out/tk9.0 \
	&& cp /tmp/tk-install/lib/libtcl9tk9.0.so /out/ \
	&& cp -a /tmp/tk-install/lib/tk9.0 /out/tk9.0' ) \
    || { tail -30 "$OUT/tk-build.log"; exit 1; }
rm -f "$OUT/tk-build.log"

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

# Both come out carrying DWARF: whalebuild compiles with -gdwarf-4 by
# default, and our own build inherits the same taste. That is right for
# a build tree and wrong for a kit, which is a thing one hands to
# somebody — the debug info is most of its weight (treectrl 3.4M -> 545K,
# the shim 230K -> 61K). --strip-debug and not a bare strip: the dynamic
# symbol table is what a `load` resolves against, and it stays. Tk gets
# the same treatment for consistency's sake, though its own configure
# never adds -g — and stripping it is only safe at all because
# --disable-zipfs left no zip tail for strip's ELF rewrite to drop.
strip --strip-debug "$OUT/libtkwmx.so" "$OUT"/treectrl/*.so \
    "$OUT/libtcl9tk9.0.so"

ls -l "$OUT" "$OUT/treectrl"
