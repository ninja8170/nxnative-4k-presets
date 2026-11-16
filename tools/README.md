# Tools

These tools edit a game's BYML settings in place and write the changed files into a RomFS overlay folder, which nxnative reads first through `DM_ROMFS_OVERLAY`. Run them with `python3` (3.10 or newer, with `pip install zstandard`); nothing extra needs installing (zstandard is already in that venv). The RomFS image is read through nxnative's own reader, `romfs_image.py`, taken from `~/nxnative-mkw/dm/tools` (set `NXNATIVE_TOOLS` to use another checkout); that checkout is not changed.

## Commands

```
ultra.py ls    <RomFS.img> <archive path> [<inner file>] [--overlay DIR]
ultra.py get   <RomFS.img> <archive path> <inner file> <field path> [--overlay DIR]
ultra.py set   <RomFS.img> <archive path> <inner file> <field path> <value> [...] --overlay DIR [--shared] [--restbl]
ultra.py apply <RomFS.img> <spec.tsv> --overlay DIR [--restbl]
```

`ultra.py --help` documents the arguments. In short:

- **inner file:** `-` when the archive is a loose BYML.
- **field path:** keys and array indexes joined by `/`. A hash-keyed dictionary's keys are written in hex, e.g. `0x2ebeca77`.
- **`--shared`:** needed to set a value whose BYML node other paths share. The change reaches all of them.
- **`--restbl`:** when a rebuilt file would exceed its resource-size-table entry, raise that entry and write the table into the overlay too. Without it, such an edit fails.
- **Where edits start:** `set` starts from the overlay's copy when there is one, so several sets add up. `apply` always starts from the game's own files.

## Modules

| Module | What it does |
|---|---|
| `ultra_romfs.py` | Reads files from the RomFS image, and the game's zstd dictionaries (`Pack/ZsDic.pack.zs`). |
| `ultra_zstd.py` | Plain or dictionary zstd. Compresses with the original frame's parameters. |
| `ultra_sarc.py` | SARC unpack and repack. An unchanged archive repacks to the original byte for byte; a member that changes size moves the members after it, which keep their alignment. |
| `ultra_byml.py` | BYML v2–v7 parsing (including v7 hash dictionaries), in-place edits, and detection of shared nodes. |
| `ultra_restbl.py` | RESTBL v1, the resource size table: lookup, entry changes, byte-identical writing. |

## Tests

`test_roundtrip.py <scratch> <RomFS.img> <specs…>` runs round trips on real files. It never runs a game.
