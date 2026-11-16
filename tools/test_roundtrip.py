#!/usr/bin/env python3
"""Round trips of every piece on real game files (no game runs): RomFS read, zstd (plain and with the game's dictionary), SARC unpack/repack, BYML parse/edit, and the
CLI's set/get through an overlay folder. Usage: test_roundtrip.py <scratch folder> <RomFS.img> <archive path> [<inner file> <field> <value>] [-- more archives...]
Each archive is given as path[::inner::field::value]; with an inner file and field, the CLI test sets that value, reads it back and undoes it."""
import hashlib
import os
import shutil
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ultra   # noqa: E402
import ultra_byml   # noqa: E402
import ultra_romfs   # noqa: E402
import ultra_sarc   # noqa: E402
import ultra_zstd   # noqa: E402

fails = 0
def check(what, ok, detail=''):
    global fails
    fails += not ok
    print(f'  {"ok  " if ok else "FAIL"} {what}' + (f'  ({detail})' if detail else ''))

def sha(b): return hashlib.sha256(b).hexdigest()[:16]

def test_archive(scratch, romfs, spec):
    path, *cli = spec.split('::')
    print(f'== {path}')
    raw = romfs.read(path)
    check('RomFS read: size as the index says', len(raw) == romfs.idx[romfs.norm(path)][2], f'{len(raw)} bytes, sha {sha(raw)}')
    data, zdict = raw, None
    if raw[:4] == b'\x28\xb5\x2f\xfd':
        info = ultra_zstd.frame_info(raw)
        if info['dict_id']: zdict = ultra_zstd.dict_for(path, romfs.dicts())
        data = ultra_zstd.decompress(raw, zdict)
        again = ultra_zstd.compress(data, raw, zdict)
        info2 = ultra_zstd.frame_info(again)
        check('zstd: decompress, compress like the original, decompress = the same bytes', ultra_zstd.decompress(again, zdict) == data,
              f'{len(raw)} -> {len(data)} -> {len(again)} bytes')
        same = {k: (info[k], info2[k]) for k in info if k != 'window_size'}
        check('zstd: frame parameters kept (content size, checksum, dict id, single segment; window not larger)',
              all(x == y for x, y in same.values()) and (info['single_segment'] or info2['window_size'] <= info['window_size']),
              f'original {info}, new {info2}')
    sarc = None
    if data[:4] == b'SARC':
        sarc = ultra_sarc.Sarc(data)
        rp = sarc.repack()
        check('SARC: unpack + repack unchanged = the original byte for byte', rp == data, f'{len(sarc.nodes)} members, sha {sha(rp)} / {sha(data)}')
        # a member that grows by 4 bytes: the later members move, keep their alignment and content
        order = sorted(range(len(sarc.nodes)), key=lambda i: sarc.nodes[i][2])
        mid = order[len(order) // 2]; name = sarc.names()[mid]
        grown = sarc.repack({name: sarc.get(name) + b'\0\0\0\0'})
        g = ultra_sarc.Sarc(grown)
        keep = all(g.get(n) == sarc.get(n) for n in sarc.names() if n != name) and g.get(name) == sarc.get(name) + b'\0\0\0\0'
        def align(off):
            a = 1
            while a < 0x2000 and off % (a * 2) == 0: a *= 2
            return a
        aligned = all((g.doff + g.nodes[i][2]) % align(sarc.doff + sarc.nodes[i][2]) == 0 for i in range(len(sarc.nodes)))
        unmoved = all(g.nodes[i][2] == sarc.nodes[i][2] for i in order[:order.index(mid) + 1])
        check('SARC: a member grown by 4 bytes: every member intact, earlier ones unmoved, every one at least as aligned as before', keep and aligned and unmoved,
              f'grew {name}, archive {len(data)} -> {len(grown)}')
        members = {n: b for n, b in sarc.files().items() if b[:2] in (b'YB', b'BY')}
    else:
        members = {'-': data} if data[:2] in (b'YB', b'BY') else {}
    ok = errs = 0; nscal = 0
    for n, b in members.items():
        try:
            y = ultra_byml.Byml(b); nscal += len(y.slots); ok += y.bytes() == b
        except Exception as e:
            errs += 1
            if errs <= 3: print(f'    {n}: {e}')
    if members:
        check('BYML: every member parses and writes back byte for byte', ok == len(members) and not errs, f'{ok}/{len(members)} files, {nscal} editable values, {errs} errors')
    if cli:
        inner, field, value = cli
        b = ultra_byml.Byml(sarc.get(inner) if sarc else data)
        old = b.get(field); before = b.bytes()
        b.set(field, value); changed = [i for i in range(len(before)) if before[i] != b.bytes()[i]]
        check(f'BYML: set {field} {old} -> {b.get(field)} changes only that value\'s bytes', len(b.bytes()) == len(before) and len(changed) <= 8, f'{len(changed)} bytes differ')
        b.set(field, old)
        check('BYML: setting it back = the original', b.bytes() == before)
        ov = os.path.join(scratch, 'overlay')
        shutil.rmtree(ov, ignore_errors=True)
        img = romfs.img
        rc = ultra.main(['set', img, path, inner, field, value, '--overlay', ov])
        out_file = os.path.join(ov, romfs.norm(path))
        check('CLI set: overlay file written at the RomFS path', rc == 0 and os.path.isfile(out_file), out_file)
        a2 = ultra.Archive(romfs, path, ov)
        b2 = ultra_byml.Byml(a2.member(inner))
        want = ultra_byml.Byml(sarc.get(inner) if sarc else data); want.set(field, value)
        check('CLI get: the overlay holds the new value', a2.from_overlay and b2.get(field) == want.get(field), f'{field} = {b2.get(field)}')
        diff = [i for i, (x, y) in enumerate(zip(a2.data, data)) if x != y] if len(a2.data) == len(data) else None
        check('CLI set: the decompressed overlay differs from the game\'s file only in that value', diff is not None and len(diff) <= 8,
              f'{len(diff) if diff is not None else "size changed"} bytes differ of {len(data)}')
        rc = ultra.main(['set', img, path, inner, field, str(old), '--overlay', ov])
        a3 = ultra.Archive(romfs, path, ov)
        check('CLI set back to the old value (starting from the overlay): decompressed = the game\'s file', a3.data == data)

def test_restbl(scratch, romfs, archive):
    import ultra_restbl
    tp = ultra_restbl.table_path(romfs.idx)
    print(f'== RESTBL {tp}')
    raw = romfs.read(tp)
    data = ultra_zstd.decompress(raw)
    t = ultra_restbl.Restbl(data)
    check('RESTBL: parses, writes back byte for byte', t.bytes() == data, f'{t.ncrc} CRC entries, {t.nname} name entries, {len(data)} B')
    again = ultra_zstd.compress(t.bytes(), raw)
    check('RESTBL: zstd round trip with the original frame parameters', ultra_zstd.decompress(again) == data and ultra_zstd.frame_info(again)['dict_id'] == ultra_zstd.frame_info(raw)['dict_id'])
    arc = ultra.Archive(romfs, archive)
    e = t.get(archive)
    check(f'RESTBL: entry of {ultra_restbl.key(archive)} covers the game\'s file', e is not None and e >= arc.original_size, f'entry {e}, file {arc.original_size} B decompressed, {e - arc.original_size if e else "-"} B to spare')
    old = e; t.set(archive, e + 1); t.set(archive, old)
    check('RESTBL: set and set back = the original', t.bytes() == data)
    ov = os.path.join(scratch, 'overlay-restbl'); shutil.rmtree(ov, ignore_errors=True)
    rc = ultra.RestblCheck(romfs, ov)
    try: rc.check(archive, arc.original_size, e + 100, False); refused = False
    except SystemExit: refused = True
    check('RESTBL: a file 100 B over its entry is refused without --restbl', refused)
    note = rc.check(archive, arc.original_size, e + 100, True); written = rc.write()
    t2 = ultra_restbl.Restbl(ultra_zstd.decompress(open(written, 'rb').read()))
    want = e + 100 + (e - arc.original_size)
    diff = [i for i, (x, y) in enumerate(zip(t2.bytes(), data)) if x != y]
    check('RESTBL: with --restbl the table in the overlay holds the raised entry, nothing else changed', t2.get(archive) == want and len(diff) <= 4, f'{note}; {written}')


def test_shared(scratch, romfs, archive, inner, field, value):
    print(f'== shared node: {inner} {field}')
    arc = ultra.Archive(romfs, archive)
    b = ultra_byml.Byml(arc.member(inner))
    sh = b.sharers(field)
    check('BYML: the shared node is found', bool(sh), f'shared with {sh}')
    try: b.set(field, value); refused = False
    except ultra_byml.BymlError: refused = True
    check('BYML: set without shared=True is refused', refused)
    before = b.bytes(); b.set(field, value, shared=True)
    check('BYML: with shared=True every sharer reads the new value, one slot changed',
          all(b.get(p) == b.get(field) for p in sh) and sum(x != y for x, y in zip(before, b.bytes())) <= 4, f'{field} and {len(sh)} more = {b.get(field)}')


if __name__ == '__main__':
    args = sys.argv[1:]
    scratch, img = args[0], args[1]
    romfs = ultra_romfs.RomFS(img)
    print(f'RomFS {img}: {len(romfs.idx)} entries; zstd dictionaries: {sorted(romfs.dicts()) or "none"}')
    for spec in args[2:]:
        if spec.startswith('restbl='): test_restbl(scratch, romfs, spec[7:])
        elif spec.startswith('shared='): test_shared(scratch, romfs, *spec[7:].split('::'))
        else: test_archive(scratch, romfs, spec)
    print(f'{"ALL OK" if not fails else f"{fails} FAILED"}')
    sys.exit(1 if fails else 0)
