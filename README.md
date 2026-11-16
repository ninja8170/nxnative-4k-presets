# nxnative 4K / HDR presets

Graphics presets for two Switch 2 games running natively on Apple silicon Macs through [nxnative](https://github.com/seedds/nxnative):

- **The Legend of Zelda: Ocarina of Time**: native 4K output, with MetalFX temporal upscaling for a locked 60 fps.
- **Mario Kart World 1.8.0**: native 4K races at 60 fps.

**This repo contains no game files.** Each preset is a recipe (`specs/*.tsv`): which setting in which game file, its stock value, and the new value. `build.sh` applies the recipes to **your own** dump and writes the changed files into an overlay folder, which nxnative loads in place of the originals. Every stock value is checked first, so a different game version is refused rather than patched blindly.

## Needs

1. **The engine changes:** my nxnative fork's `4k-hdr-temporal` branch: https://github.com/ninja8170/nxnative/tree/4k-hdr-temporal.
   - The 4K presets depend on its switches: `DM_DISPLAY_BUFFER`, `DM_HEAP_EXTRA` and `DM_UPSCALER=metalfx-temporal`.
   - So do its two code patches that lift Zelda's hard-coded 2560×1440 window.
   - `preset.sh` checks the app knows those switches before it installs a 4K preset.
2. **Your own game apps,** built from your own dumps with that branch:
   - Zelda: title version v131072.
   - Mario Kart World: 1.8.0 (v917504).
3. **Python 3.10+** with `pip install zstandard`.
4. **`NXNATIVE_TOOLS`** pointing at your checkout's `dm/tools` folder. The default is `~/nxnative/dm/tools`.

## Use

```
# 1. Build the presets from your own RomFS (nxnative's build extracts it to <work dir>/<title ID>_build/extract/<version>/RomFS.img)
./build.sh oot /path/to/0400486024DEC000_build/extract/v131072/RomFS.img
./build.sh mkw /path/to/0400C3F00006E000_build/extract/v917504/RomFS.img

# 2. Switch (quit the game first; it reads the change at its next start)
./preset.sh oot 4k-tfx      # Zelda: 4K with MetalFX temporal upscaling (recommended)
./preset.sh mkw ultra       # Mario Kart World: native 4K
./preset.sh oot off         # back to stock
```

`preset.sh` edits only its own lines in the game's `~/Library/Application Support/nxnative/<title ID>/env.txt`. It backs that file up first.

## Presets

| Game | Preset | What it does |
|---|---|---|
| Zelda | `high` | Native 2560×1440 scene, sharper shadows drawn further, better ambient occlusion and reflections, and a larger render-target memory pool (fixes an out-of-memory crash near water) |
| Zelda | `ultra` | `high` plus denser grass, cleaner and full-resolution ambient occlusion |
| Zelda | `4k` | 3840×2160 output with the scene rendered at full 4K. Sharpest, but drops below 60 fps in heavy areas (Castle Town ~44, Zora's Domain ~48, Kakariko ~53 on an M4 Max) |
| Zelda | **`4k-tfx`** | 3840×2160 output, scene rendered at 2560×1440 and rebuilt to 4K by MetalFX temporal upscaling (camera motion vectors, sub-pixel jitter, reactive mask). Locked 60 fps |
| Mario Kart World | `ultra` | Native 3840×2160 render, with the game's memory budgets rebalanced to fit |

## Measured (M4 Max MacBook Pro)

**Zelda `4k-tfx`, GPU time per frame** (native 4K → temporal; the 60 fps budget is 16.7 ms):

| Area | Native 4K | Temporal |
|---|---|---|
| Hyrule Field | 15.1 ms | 12.2 ms |
| Kakariko | 17.3 ms | 12.7 ms |
| Castle Town | 20.4 ms | 14.2 ms |
| Zora's Domain | 17.4 ms | 12.7 ms |

A 25-minute soak in Hyrule Field: 60.0 fps, 95% of frames within 16.8 ms, no crashes.

**Mario Kart World `ultra`:** 59.9 fps in a race at 3840×2160, GPU 9.0 ms per frame (8.2 ms at the stock 1440p), 4 of 4 clean boots.

## Files

- `specs/`: the recipes. Columns are explained in `tools/README.md`.
- `tools/`: BYML/SARC/zstd/RESTBL editing (`ultra.py ls|get|set|apply`).
- `env/`: the engine switches each 4K preset needs.
- `build.sh`, `preset.sh`: build and switch.

Built on nxnative by seedds (MIT). Play only games you own, from your own dumps.
