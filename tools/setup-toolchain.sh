#!/bin/sh
# Builds the toolchain for the MEGA65 GEOS build into tools/local:
#   - cc65 (git master: ca65/ld65 with 45GS02/4510 support)
#   - grc65 pinned to cc65 ab0eb4fe5 (Feb 2024). Newer grc65 versions (from
#     July 2025) emit __VLIRn_BLOCKS__ / per-record symbols that the linker
#     configs in this repo do not define.
#   - Exomizer 2.x (loader/uncrunch.s expects the 2.x stream format)
#   - pucrunch
# Disk images can be written with tools/mkdisk.py (no VICE needed) for the
# d81-update target; the full "make" image build needs VICE's c1541.
#
# Usage:  sh tools/setup-toolchain.sh
#         . tools/env.sh
#         make d81-update C1541="python3 tools/mkdisk.py"
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/local/src"
BIN="$HERE/local/bin"
mkdir -p "$SRC" "$BIN"
cd "$SRC"

[ -d cc65 ] || git clone https://github.com/cc65/cc65.git
make -C cc65 -j4 bin
make -C cc65/libsrc -j4 TARGETS="none geos-cbm"
cp cc65/bin/ca65 cc65/bin/ld65 cc65/bin/cl65 cc65/bin/cc65 cc65/bin/ar65 "$BIN/"

[ -d cc65-grc ] || git -C cc65 worktree add ../cc65-grc ab0eb4fe5
make -C cc65-grc -j4 bin
cp cc65-grc/bin/grc65 "$BIN/"

[ -d exomizer ] || git clone --depth 1 https://github.com/bitshifters/exomizer.git
make -C exomizer/exomizer2/src CFLAGS="-O2 -fcommon"
cp exomizer/exomizer2/src/exomizer "$BIN/"

[ -d pucrunch ] || git clone --depth 1 https://github.com/mist64/pucrunch.git
make -C pucrunch
cp pucrunch/pucrunch "$BIN/"

cat > "$HERE/env.sh" <<EOF
export PATH="$BIN:\$PATH"
export CC65_HOME="$SRC/cc65"
EOF
echo "Toolchain ready. Run: . tools/env.sh && make d81-update C1541=\"python3 tools/mkdisk.py\""
