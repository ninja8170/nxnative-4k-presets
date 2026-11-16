#!/bin/bash
# Switch a game's graphics preset: preset.sh <mkw|oot> <off|high|ultra|4k|4k-tfx>   (4k, 4k-tfx: oot only)
#   4k-tfx: oot-4k's base at 2/3 scale (2560x1440 rendered) upscaled to 3840x2160 by MetalFX's temporal scaler (oot-4k-tfx.env: DM_UPSCALER=metalfx-temporal)
#
# A preset: copies overlays/<game>-<preset>/ (made by build.sh) to <BASE>/<title ID>/ultra/<preset>/ (a stable place the app reads from) and puts that folder first
#   in DM_ROMFS_OVERLAY in <BASE>/<title ID>/env.txt (made when missing). Other overlay folders already listed stay after it, in order (Ocarina of Time's romfs-fix).
#   A preset may also carry env lines: <OVERLAYS>/<game>-<preset>.env, KEY=VALUE per line (oot-4k.env: DM_HEAP_EXTRA=1600, as its HeapDef grows Graphics by 1,575 MB and
#   fails at boot without it). Each is written with a marker comment of its own above it, and every switch (to another preset or off) takes the marked lines out first,
#   so only this script's lines change: a line of the same key the user wrote (no marker) is kept, and then ours is not added (the first line wins in the launcher).
#   Before a preset with env lines is installed, the app's host must know each key (strings of <APP>/Contents/MacOS/dmhost), or the preset is refused: "rebuild the app first".
#   A word-like value (letters, digits, '-', '_': metalfx-temporal) must be in the host's strings too, as an old host knows DM_UPSCALER but not that value.
# off: takes this game's ultra/ folders out of DM_ROMFS_OVERLAY (the line goes when nothing else is left, else it keeps the rest: romfs-fix for Ocarina of Time) and the
#   marked env lines. The copied presets stay under ultra/ (delete the folder by hand to free the space).
# env.txt keeps every other line and comment (DM_HDR_PEAK, romfs-fix and the rest); it is backed up to env.txt.bak-<date-time> first. Only the first DM_ROMFS_OVERLAY line
# is changed: the Mac launcher (dm/mac/launcher.c env_file) uses the first line for a variable, takes the value as it is to the end of the line (no quotes: a path with
# spaces goes in as it is), and the host splits it at ':' (dm/host/hle_fs.c). A variable set in the launch environment wins over env.txt.
# The game reads it at its next start; quit the game first.
#
# Environment: BASE (default ~/Library/Application Support/nxnative), OVERLAYS (default the overlays folder beside this script), APP (default the game's app in /Applications):
# override them to test on copies.
set -euo pipefail

BASE="${BASE:-$HOME/Library/Application Support/nxnative}"
OVERLAYS="${OVERLAYS:-$(cd "$(dirname "$0")" && pwd)/overlays}"
usage() { echo "usage: preset.sh <mkw|oot> <off|high|ultra|4k|4k-tfx>   (4k, 4k-tfx: oot only; BASE=$BASE)" >&2; exit 2; }
[ $# -eq 2 ] || usage
case "$1" in
    mkw) TITLE=0400C3F00006E000; DEFAPP="/Applications/Mario Kart World.app" ;;
    oot) TITLE=0400486024DEC000; DEFAPP="/Applications/The Legend of Zelda - Ocarina of Time.app" ;;
    *) usage ;;
esac
case "$2" in off|high|ultra) PRESET=$2 ;; 4k|4k-tfx) [ "$1" = oot ] || usage; PRESET=$2 ;; *) usage ;; esac
GAME=$1
APP="${APP:-$DEFAPP}"
DIR="$BASE/$TITLE"
[ -d "$DIR" ] || { echo "preset.sh: $DIR does not exist: start the game's app once first" >&2; exit 1; }
ENV="$DIR/env.txt"
ULTRA="$DIR/ultra"
DEST=""
ENVFILE=""
if [ "$PRESET" != off ]; then
    SRC="$OVERLAYS/$GAME-$PRESET"
    [ -d "$SRC" ] && [ -n "$(find "$SRC" -type f -print -quit)" ] || { echo "preset.sh: no overlay at $SRC" >&2; exit 1; }
    if [ -f "$OVERLAYS/$GAME-$PRESET.env" ]; then
        ENVFILE="$OVERLAYS/$GAME-$PRESET.env"
        HOST="$APP/Contents/MacOS/dmhost"
        [ -f "$HOST" ] || { echo "preset.sh: no host at $HOST: the $PRESET preset needs it to check its switches; set APP=<the game's .app>" >&2; exit 1; }
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in ''|'#'*) continue ;; esac
            key=${line%%=*}; val=${line#*=}
            grep -q "$key" <(strings "$HOST") || { echo "preset.sh: the app's host ($HOST) does not know $key, which the $PRESET preset depends on (oot 4k fails at boot without DM_HEAP_EXTRA): rebuild the app first" >&2; exit 1; }
            if [[ "$val" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]; then   # a word value (metalfx-temporal): an older host knows the key but not the value
                grep -qx -- "$val" <(strings "$HOST" | tr -c 'A-Za-z0-9_\n-' '\n') || { echo "preset.sh: the app's host ($HOST) does not know the value $val of $key, which the $PRESET preset sets: rebuild the app first" >&2; exit 1; }
            fi
        done < "$ENVFILE"
        echo "checked the app's host knows the switches of $ENVFILE"
    fi
    DEST="$ULTRA/$PRESET"
    mkdir -p "$DEST"
    rsync -a --delete "$SRC/" "$DEST/"
    echo "copied $SRC -> $DEST ($(find "$DEST" -type f | wc -l | tr -d ' ') files)"
fi
if [ -f "$ENV" ]; then
    BAK="$ENV.bak-$(date +%Y%m%d-%H%M%S)"
    cp -p "$ENV" "$BAK"
    echo "backed up env.txt -> $BAK"
fi
# The env.txt edit: in Python for exact line handling (comments, missing final newline, values with spaces)
ENV="$ENV" ULTRA="$ULTRA" DEST="$DEST" ENVFILE="$ENVFILE" GAME="$GAME" PRESET="$PRESET" python3 - <<'EOF'
import os
env, ultra, dest, envfile = os.environ['ENV'], os.environ['ULTRA'], os.environ['DEST'], os.environ['ENVFILE']
MARK = '# Graphics preset (preset.sh; "preset.sh <game> off" takes it out)'
EMARK = '# preset.sh env line'   # the marker above each env line a preset added; "<EMARK> (<game> <preset>; ...)"
lines = open(env).read().splitlines() if os.path.exists(env) else []
def key_of(l):
    s = l.strip()
    return s.split('=', 1)[0].strip() if not s.startswith('#') and '=' in s else None
# 1. this script's env lines out (a marker and the line under it)
kept, removed, i = [], [], 0
while i < len(lines):
    if lines[i].startswith(EMARK) and i + 1 < len(lines) and key_of(lines[i + 1]):
        removed.append(lines[i + 1]); i += 2; continue
    kept.append(lines[i]); i += 1
lines = kept
# 2. DM_ROMFS_OVERLAY: this game's ultra/ folders out, the preset's first
key = 'DM_ROMFS_OVERLAY'
at = next((i for i, l in enumerate(lines) if key_of(l) == key), None)
old = lines[at].split('=', 1)[1].strip() if at is not None else ''
ours = ultra.rstrip('/') + '/'
rest = [p for p in old.split(':') if p and not (p.rstrip('/') + '/').startswith(ours)]
new = ([dest] if dest else []) + rest
if at is None:
    if new: lines += [MARK, f'{key}={":".join(new)}']
else:
    if new: lines[at] = f'{key}={":".join(new)}'
    else:
        del lines[at]
        if at > 0 and lines[at - 1] == MARK: del lines[at - 1]
# 3. the preset's env lines in, each under its marker, unless the user set that key themselves
added, skipped = [], []
if envfile:
    for l in open(envfile).read().splitlines():
        k = key_of(l)
        if not k: continue
        user = next((x for x in lines if key_of(x) == k), None)
        if user is not None: skipped.append((l, user)); continue
        lines += [f'{EMARK} ({os.environ["GAME"]} {os.environ["PRESET"]}; switching preset or off takes it out)', l.strip()]
        added.append(l.strip())
if not lines:   # nothing left (Mario Kart World off): no env.txt, as before the first preset; the backup keeps the last one
    if os.path.exists(env): os.remove(env)
else:
    tmp = env + '.tmp'
    with open(tmp, 'w') as f: f.write('\n'.join(lines) + '\n')
    os.replace(tmp, env)
print(f'{key}: {old or "(none)"} -> {":".join(new) or "(none)"}')
for l in removed: print(f'env line removed (this script\'s): {l}')
for l in added: print(f'env line added: {l}')
for l, u in skipped: print(f'env line not added: {l} (env.txt already sets it, not by this script: {u}; that one is used)')
EOF
if [ -f "$ENV" ]; then echo "env.txt now ($ENV):"; sed 's/^/  | /' "$ENV"; else echo "env.txt now: none (nothing left in it)"; fi
