"""YANC 1.4: build date in Help, Boot from Choose volume, Esc leaves the KEGS list, Quit to BASIC."""
import os, re, shutil
from harness import Emu, BIN, FakeKegs
from setup_vols import setup

fails = []
def check(cond, what):
    print(('ok   ' if cond else 'FAIL ') + what)
    if not cond: fails.append(what)
UP, DN, RET, ESC, TAB = '\x0b', '\x0a', '\r', '\x1b', '\t'
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

def emu(prefix='/SYSDISK/', kegs=False, tweak=None):
    vols = setup()
    if tweak: tweak(vols)
    e = Emu(BIN, vols, prefix)
    if kegs:
        host = '/tmp/kegsdisks10'
        shutil.rmtree(host, ignore_errors=True)
        os.makedirs(os.path.join(host, 'GAMES'))
        open(os.path.join(host, 'Karateka.dsk'), 'wb').truncate(143360)
        open(os.path.join(host, 'GAMES', 'Zork.dsk'), 'wb').truncate(143360)
        e.kegs = FakeKegs(host)
        e.kegs.drives = {0x61: '/x/Sysdisk.po'}
    e.run([])
    return e
scr = lambda e: '\n'.join(e.screen())

# ---- 1. Help shows the build date after the version
date = re.search(r'BUILD_DATE\s+"([^"]+)"', open(os.path.join(ROOT, 'build', 'version.inc')).read()).group(1) \
    if os.path.exists(os.path.join(ROOT, 'build', 'version.inc')) else '?'
e = emu(); e.run(['1'])
check(re.fullmatch(r'\d\d-[A-Z][a-z][a-z]-\d{4}', date) is not None, 'build date looks like 15-Nov-2026: %r' % date)
check(('YANC v1.4 %s - Yet Another Norton Commander' % date) in e.screen()[3], 'help line 1: version and date')

# ---- 2. Choose volume: non-ProDOS drives are listed, B boots the highlighted drive
def sig(e, slot):
    e.mem.m[0xC001 + slot*256] = 0x20; e.mem.m[0xC003 + slot*256] = 0x00; e.mem.m[0xC005 + slot*256] = 0x03
def volbox(bad=None, kegs=False, sigs=(5, 6, 7)):
    e = emu(kegs=kegs)
    e.baddrives = dict(bad or {})
    for s_ in sigs: sig(e, s_)
    e.run(['2'])
    return e
FOOT = 'Enter=Select  B=Boot  Esc=Cancel'
e = volbox({0x50: 0x52})
s = scr(e)
check('S5,D1  (not a ProDOS disk)' in s, 'non-ProDOS disk ($52) listed with its drive')
check('S6,D1  /SYSDISK' in s and 'S7,D1  /HARD1' in s, 'ProDOS volumes still listed')
check(FOOT in s, 'footer names the keys')
e.run([DN, DN, DN, RET])
check('Not a ProDOS disk - press B to boot it' in scr(e), 'Return on a non-ProDOS row: error')
e.run([' '])
check('Choose volume' not in scr(e) and e.booted is None, 'error closes the box, nothing booted')
e = volbox({0x50: 0x27}); e.run([DN, DN, DN, 'b'])
check(e.booted == 0xC500, 'B boots a copy-protected disk ($27) in S5,D1: %r' % (e.booted,))
check(not e.store80, 'boot leaves 80STORE off')
e = volbox(); e.run(['B'])
check(e.booted == 0xC600, 'B on a ProDOS volume in S6,D1 boots slot 6: %r' % (e.booted,))
e = volbox(); e.run([DN, DN, 'b'])
check('Only drive 1 of a slot can be booted' in scr(e) and e.booted is None, 'B on drive 2: error')
e = volbox({0x20: 0x52}); e.run([DN, DN, DN, 'b'])
check('This drive cannot be booted' in scr(e) and e.booted is None, 'B on a slot without boot firmware: error')
e = volbox({0xD0: 0x52}); e.run([DN, DN, DN, 'b'])
check('Only drive 1' in scr(e) and e.booted is None, 'B on a non-ProDOS disk in drive 2: error')
e = volbox({0x50: 0x28, 0x40: 0x2F})
check('S5,D1' not in scr(e) and 'S4,D1' not in scr(e), 'empty / missing drives ($28, $2F) are not listed')
e = volbox(kegs=True); e.run([DN, DN, DN, 'b'])
check('Choose volume' in scr(e) and e.booted is None, 'B on the KEGS disk images row does nothing')
e.run([RET])
check('KEGS:/' in e.screen()[0], 'KEGS row still opens the images list')
e = volbox({0x50: 0x52}, kegs=True); e.run([DN] * 4 + [RET])
check('KEGS:/' in e.screen()[0], 'KEGS row comes after the non-ProDOS rows')
many = {u: 0x52 for u in (0x10, 0x20, 0x40, 0x50, 0x90, 0xA0, 0xB0, 0xC0, 0xD0, 0xF0, 0x30)}
e = volbox(many, kegs=True)
L = e.screen()
check(sum('(not a ProDOS disk)' in l for l in L) == 11 and any('KEGS disk images...' in l for l in L),
      '14 drives + KEGS row all shown')
check(any(FOOT in l for l in L[:23]) and '1Help' in L[23], 'full box: footer shown, key bar untouched')
e.run([DN] * 14 + [RET])
check('KEGS:/' in e.screen()[0], 'full box: last row reachable')

# ---- 3. KEGS disk images: Esc at the top folder goes back to the ProDOS directory
def kegslist(extra=()):
    e = emu(kegs=True)
    e.run(['G', RET])                       # left panel: /SYSDISK/GAMES
    e.run(['2', DN, DN, DN, RET] + list(extra))
    return e
e = kegslist()
check('KEGS:/' in e.screen()[0] and 'Eject' in e.screen()[23], '(setup) panel shows the KEGS list')
e.run([ESC])
check('/SYSDISK/GAMES' in e.screen()[0] and 'KEGS:' not in e.screen()[0], 'Esc at KEGS:/ returns to /SYSDISK/GAMES')
check('ZORK' in scr(e) and 'Karateka.dsk' not in scr(e), 'the ProDOS files are listed again')
check('5Copy' in e.screen()[23] and 'Eject' not in e.screen()[23], 'normal key bar is back')
e.run([ESC])
check('/SYSDISK' in e.screen()[0] and 'GAMES' not in e.screen()[0], 'Esc again: parent directory, as in any ProDOS panel')
e = kegslist(['G', RET])                    # into the GAMES sub-folder of the images
check('KEGS:/GAMES' in e.screen()[0], '(setup) in an images sub-folder')
e.run([ESC])
check('KEGS:/' in e.screen()[0] and 'KEGS:/GAMES' not in e.screen()[0], 'Esc in a sub-folder goes up one level first')
e.run([ESC])
check('/SYSDISK/GAMES' in e.screen()[0], 'then back to the ProDOS directory')
e = kegslist(['2', DN, DN, DN, RET, ESC])   # choosing the list twice keeps the first saved directory
check('/SYSDISK/GAMES' in e.screen()[0], 'opening the list again from the list still returns to ProDOS')
e = kegslist(['\x7f'])
check('/SYSDISK/GAMES' in e.screen()[0], 'Delete works like Esc')
e = emu('/HARD1/DOCS/', kegs=True)
e.run(['2', DN, DN, DN, RET])
shutil.rmtree(os.path.join(e.vols['HARD1']['path'], 'DOCS'))
e.run([ESC])
check('/SYSDISK' in e.screen()[0] and 'KEGS:' not in e.screen()[0] and 'YANC.SYSTEM' in scr(e),
      'saved directory gone: first volume instead')
e = emu(kegs=True)
e.run([TAB, '2', DN, DN, DN, RET, ESC])
check('/HARD1' in e.screen()[0] and 'KEGS:' not in e.screen()[0], 'right panel has its own saved directory')

# ---- 4. Quit (0): to BASIC.SYSTEM when it is in the directory YANC started from
BASIC = bytes([0x20, 0x00, 0xBF, 0x65, 0x06, 0x20, 0x04, 0, 0, 0, 0, 0, 0])   # JSR MLI / QUIT
def with_basic(vols):
    open(os.path.join(vols['SYSDISK']['path'], 'BASIC.SYSTEM'), 'wb').write(BASIC)
def opens(e): return [c for c in e.mlilog if c[0] == 0xC8]
e = emu(tweak=with_basic)
e.run([TAB, '0']); n0 = len(opens(e))
check('Do you want to quit YANC?' in scr(e), 'Quit still asks first')
e.run(['y'])
check(bytes(e.mem.m[0x2000:0x2000 + len(BASIC)]) == BASIC and e.quit, 'Quit loads and runs BASIC.SYSTEM')
check(e.prefix == '/SYSDISK/', 'prefix is the start directory, not the active panel (/HARD1): %r' % e.prefix)
check(bytes(e.mem.m[0x281:0x281 + e.mem.m[0x280]]) == b'/SYSDISK/BASIC.SYSTEM', '$280 names BASIC.SYSTEM')
check(not e.store80, '40-column text screen for BASIC')
e = emu(tweak=with_basic, kegs=True)
e.run(['2', DN, DN, DN, RET, '0', 'y'])
check(bytes(e.mem.m[0x2000:0x2000 + len(BASIC)]) == BASIC and e.prefix == '/SYSDISK/',
      'Quit from a KEGS panel: BASIC.SYSTEM, prefix /SYSDISK/: %r' % e.prefix)
e = emu()
e.run(['0']); n0 = len(opens(e)); e.run(['y'])
check(e.quit and len(opens(e)) == n0,
      'no BASIC.SYSTEM: ProDOS QUIT as before')
e = emu(tweak=with_basic)
e.run(['0', 'n'])
check(not e.quit and '/SYSDISK' in e.screen()[0], 'N: stays in YANC')
e = emu(tweak=with_basic)
e.meta[os.path.join(e.vols['SYSDISK']['path'], 'BASIC.SYSTEM')] = dict(type=0x04, aux=0, access=0xE3, cdate=0, ctime=0, mdate=0, mtime=0)
e.run(['0']); n0 = len(opens(e)); e.run(['y'])
check(e.quit and len(opens(e)) == n0, 'a BASIC.SYSTEM that is not a SYS file is not run')

print('FAILED:', fails or 'none')
