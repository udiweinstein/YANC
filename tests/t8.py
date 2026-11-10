"""Extended (forked) files: copy, overwrite, move, delete, locked delete, disk full."""
import os
from harness import BIN
from p8img import ImgEmu, PVol, blank, addfile, addext, readext, entry

RET, ESC, TAB, DN = '\r', '\x1b', '\t', '\x0a'
fails = []
def check(cond, what):
    print(('ok   ' if cond else 'FAIL ') + what)
    if not cond: fails.append(what)

def rnd(n, seed):
    import random
    r = random.Random(seed); return bytes(r.getrandbits(8) for _ in range(n))

FINFO = bytes([0x12, 1]) + b'TEXTpdos' + bytes(8) + bytes([0x12, 2]) + bytes(16)
files = {   # name: (data, rsrc)
    'SYS.RES': (rnd(1000, 1), rnd(70000, 2)),
    'ICON':    (b'', rnd(300, 3)),
    'BIGEXT':  (rnd(200000, 4), rnd(5000, 5)),
}
def mkgs():
    img = blank('GS', 1600)
    for n, (d, r) in files.items(): addext(img, '/GS/' + n, d, r, finfo=FINFO)
    addfile(img, '/GS/PLAIN', rnd(3000, 6))
    from p8img import ImgEmu as _E
    return img

gs = mkgs()
# a subdirectory with an extended file: create through the MLI emulation
vols = {'GS': dict(unit=0x50, img=gs), 'HD': dict(unit=0x70, img=blank('HD', 4000))}
e = ImgEmu(BIN, vols, '/GS/')
# make /GS/SYSTEM and /HD/APPS with the emulated CREATE
def mkdir(path):
    import struct
    a = 0x9000
    e.mem.m[a] = len(path); e.mem.m[a + 1:a + 1 + len(path)] = path.encode()
    p = 0x9100; e.mem.m[p:p + 12] = bytes([7, a & 0xFF, a >> 8, 0xC3, 0x0F, 0, 0, 0x0D, 0, 0, 0, 0])
    assert e.mli_C0(p) == 0
mkdir('/GS/SYSTEM'); mkdir('/HD/APPS')
start = (rnd(2000, 7), rnd(900, 8))
addext(gs, '/GS/SYSTEM/START', *start, ftype=0xB3, aux=0xDB07, finfo=FINFO)
PVol(gs).fsck(); PVol(vols['HD']['img']).fsck()
startblks = entry(gs, '/GS/SYSTEM/START')[0x13]; gsfree0 = PVol(gs).nfree(); hdfree0 = PVol(vols['HD']['img']).nfree()

def ok_ext(img, path, d, r, what):
    try:
        dd, rr, kb = readext(img, path)
        check(dd == d and rr == r and kb[8:8 + len(FINFO)] == FINFO, what)
    except AssertionError as x:
        check(False, '%s (%s)' % (what, x))
def fsck(name):
    try:
        fl = PVol(vols[name]['img']).fsck(); check(True, 'fsck ' + name); return fl
    except AssertionError as x:
        check(False, 'fsck %s: %s' % (name, x)); return []
def screen_has(s): return any(s in l for l in e.screen())
def cur():
    for row in e.cells()[2:19]:
        for c0 in (1, 41):
            if row[c0+1][1] and row[c0+5][1]:
                return ''.join(ch for ch, inv, mt in row[c0+1:c0+16]).strip()
def goto(name):
    for _ in range(20):
        if cur() == name: return
        e.run([name[0]])
    raise RuntimeError('cannot reach ' + name + ' at ' + str(cur()))

e.run([])
check(screen_has('SYS.RES        +'), "'+' marks extended files")
# 1. copy one extended file
goto('SYS.RES'); e.run(list('5y'))
ok_ext(vols['HD']['img'], '/HD/SYS.RES', *files['SYS.RES'], 'copy SYS.RES: both forks + Finder info')
en = entry(vols['HD']['img'], '/HD/SYS.RES'); src = entry(gs, '/GS/SYS.RES')
check(en[0x10] == src[0x10] and en[0x1F:0x21] == src[0x1F:0x21] and en[0x1E] == src[0x1E], 'type, aux, access kept')
fsck('HD'); fsck('GS')
# 2. same again -> overwrite an extended file
e.run(list('5y')); check(screen_has('exists'), 'overwrite prompt'); e.run(['y'])
ok_ext(vols['HD']['img'], '/HD/SYS.RES', *files['SYS.RES'], 'overwrite SYS.RES')
fsck('HD')
# 3. tag all, copy, overwrite all
e.run(list('+5y')); e.run(['a'])
for n in files: ok_ext(vols['HD']['img'], '/HD/' + n, *files[n], 'copy all: ' + n)
check(entry(vols['HD']['img'], '/HD/PLAIN') is not None, 'copy all: PLAIN')
hdf = fsck('HD'); fsck('GS')
check(not any('YANCTMP' in f for f in hdf), 'no temporary files left')
e.run(['-'])
# 4. subdirectory: copy START to HD, then move it to /HD/APPS
goto('SYSTEM'); e.run([RET]); goto('START'); e.run(list('5y'))
ok_ext(vols['HD']['img'], '/HD/START', *start, 'copy from a subdirectory')
goto('START'); e.run(list('6') + ['\x18'] + list('/HD/APPS') + [RET])
ok_ext(vols['HD']['img'], '/HD/APPS/START', *start, 'move into /HD/APPS')
check(entry(gs, '/GS/SYSTEM/START') is None, 'move removed the source')
fsck('HD'); fsck('GS')
# 5. delete on HD: BIGEXT, then everything copied there
e.run([TAB]); e.run(['\x12'])
before = PVol(vols['HD']['img']).nfree()
goto('BIGEXT'); e.run(list('8y'))
check(entry(vols['HD']['img'], '/HD/BIGEXT') is None, 'delete BIGEXT')
fsck('HD')
print('   freed', PVol(vols['HD']['img']).nfree() - before, 'blocks')
# 6. locked extended file
img = vols['HD']['img']; v = PVol(img); dk, o, err = v.lookup(['ICON']); img[o + 0x1E] = 0x01
e.run(['\x12']); check(screen_has('ICON           *'), "'*' wins over '+' for locked")
goto('ICON'); e.run(list('8y')); check(screen_has('locked'), 'locked prompt'); e.run(['y'])
check(entry(img, '/HD/ICON') is None, 'delete locked extended file')
fsck('HD')
# 7. delete the rest on HD and in /HD/APPS -> all blocks free again
e.run(list('+8y'))
goto('APPS'); e.run([RET]); goto('START'); e.run(list('8y'))
fl = fsck('HD')
check(PVol(img).nfree() == hdfree0, 'HD back to %d free blocks (now %d)' % (hdfree0, PVol(img).nfree()))
fsck('GS')
check(PVol(gs).nfree() == gsfree0 + startblks, 'GS: START freed (%d -> %d)' % (gsfree0, PVol(gs).nfree()))

# 8. disk full while copying
vols2 = {'GS': dict(unit=0x50, img=mkgs()), 'TINY': dict(unit=0x60, img=blank('TINY', 280))}
addfile(vols2['TINY']['img'], '/TINY/FILLER', rnd(80000, 9))
e = ImgEmu(BIN, vols2, '/GS/'); vols = vols2
t0 = PVol(vols2['TINY']['img']).nfree()
e.run([]); goto('BIGEXT'); e.run(list('5y'))
check(screen_has('full'), 'disk full reported')
e.run([' '])
fl = fsck('TINY')
check(fl == ['/FILLER'] and PVol(vols2['TINY']['img']).nfree() == t0, 'disk full: nothing left behind %s' % fl)
goto('ICON'); e.run(list('5y'))
ok_ext(vols2['TINY']['img'], '/TINY/ICON', *files['ICON'], 'after disk full, a smaller copy works')
fsck('TINY')
e.show('end')
print('\nFAILED:', fails if fails else 'none')
