#!/bin/bash
# Build the presets from YOUR OWN game files: build.sh <mkw|oot> <RomFS.img>
#   RomFS.img is the one nxnative's build extracted from your dump:
#     <work dir>/<title ID>_build/extract/<version>/RomFS.img
#   Writes overlays/<game>-<preset>/ for every preset of that game (and copies its env lines), checking every edited value
#   against your game first: a different game version is refused rather than patched blindly.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="${PYTHON:-python3}"
[ $# -eq 2 ] || { echo "usage: build.sh <mkw|oot> <RomFS.img>" >&2; exit 2; }
GAME=$1; IMG=$2
[ -f "$IMG" ] || { echo "build.sh: no file $IMG" >&2; exit 1; }
case "$GAME" in mkw) PRESETS="ultra" ;; oot) PRESETS="high ultra 4k 4k-tfx" ;; *) echo "usage: build.sh <mkw|oot> <RomFS.img>" >&2; exit 2 ;; esac
"$PY" -c 'import zstandard' 2>/dev/null || { echo "build.sh: $PY needs the zstandard package: $PY -m pip install zstandard" >&2; exit 1; }
[ -f "${NXNATIVE_TOOLS:-$HOME/nxnative/dm/tools}/romfs_image.py" ] || { echo "build.sh: set NXNATIVE_TOOLS to your nxnative checkout's dm/tools (default ~/nxnative/dm/tools)" >&2; exit 1; }
mkdir -p "$HERE/overlays"
for p in $PRESETS; do
    out="$HERE/overlays/$GAME-$p"; rm -rf "$out"
    echo "== $GAME $p"
    "$PY" "$HERE/tools/ultra.py" apply "$IMG" "$HERE/specs/$GAME-$p.tsv" --overlay "$out" --restbl
    if [ -f "$HERE/env/$GAME-$p.env" ]; then cp "$HERE/env/$GAME-$p.env" "$HERE/overlays/$GAME-$p.env"; fi
done
echo "done: switch with ./preset.sh $GAME <preset>   (quit the game first)"
