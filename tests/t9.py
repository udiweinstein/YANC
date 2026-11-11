"""KEGS disk images panel (FakeKegs simulates the KEGS API)."""
import os, shutil
from harness import Emu, BIN, render_png, FakeKegs
from setup_vols import setup

fails = []
def check(cond, what):
    print(('ok   ' if cond else 'FAIL ') + what)
    if not cond: fails.append(what)

host = '/tmp/kegsdisks'
shutil.rmtree(host, ignore_errors=True)
os.makedirs(os.path.join(host, 'GAMES'))
for n, sz in [('Karateka.dsk', 143360), ('AllStar.2mg', 819264), ('AppleWorks3_Hebrew.po', 819200),
              ('Hard1.hdv', 33554432 // 8), ('PrintShop.dsk', 143360), ('notes.txt', 10)]:
    open(os.path.join(host, n), 'wb').truncate(sz)
open(os.path.join(host, 'GAMES', 'Zork.dsk'), 'wb').truncate(143360)

vols = setup()
e = Emu(BIN, vols, '/SYSDISK/')
e.kegs = FakeKegs(host)
e.kegs.drives = {0x61: '/x/Sysdisk.po', 0x71: '/x/Hard1.hdv', 0x62: '/x/Blank.po'}
kvol = os.path.join('/tmp/ncvols', 'KARATEKA'); os.makedirs(kvol, exist_ok=True)
open(os.path.join(kvol, 'KARATEKA.SYSTEM'), 'wb').write(bytes(5000))
def on_mount(emu, sd, path):        # the inserted disk replaces BLANK in S6,D2
    if sd == 0x62 and path.endswith('Karateka.dsk'):
        emu.vols.pop('BLANK', None)
        emu.vols['KARATEKA'] = dict(unit=0xE0, path=kvol, total=280)
e.kegs.on_mount = on_mount
UP, DN, RET, ESC, TAB = '\x0b', '\x0a', '\r', '\x1b', '\t'
scr = lambda: '\n'.join(e.screen())
def step(keys, name=None):
    e.run(list(keys))
    if name:
        render_png(e, f'/tmp/shots/{name}.png')
os.makedirs('/tmp/shots', exist_ok=True)

step('')
check(('id',) in e.kegs.calls, 'detects KEGS at start')
step('2', 'k_vol')
check('KEGS disk images...' in scr(), 'volume box offers KEGS disk images')
step(DN * 3 + RET, 'k_panel')            # 3 volumes in setup -> 4th row
s = scr()
check('KEGS:/' in s and 'Karateka.dsk' in s and 'GAMES' in s, 'KEGS panel lists images and folders')
check('notes.txt' not in s, 'non-image files hidden')
check('<DIR>' in s and '140K' in s, 'sizes and folders shown')
check('Eject' in e.screen()[23], 'key bar shows Eject')
step('K', 'k_search')                    # jump to Karateka
step(RET, 'k_insert')
s = scr()
check('Insert disk' in s and 'S6,D1' in s and 'S6,D2' in s, 'insert box offers S6 drives')
check('Auto' not in s and 'S5,D1' not in s and 'S7,D1' not in s, 'only the 5.25" slot is offered')
check('(YANC runs from here)' in s, 'YANC drive marked')        # SYSDISK unit $60 -> S6,D1
step(RET, 'k_inserted')                  # Auto
m = [c for c in e.kegs.calls if c[0] == 'mount']
check(m and m[-1][2] == 0x62 and m[-1][3] == 0x61, 'MOUNT into S6,D2 (cursor skips YANC drive): %r' % (m[-1:],))
check(e.kegs.drives.get(0x62, '').endswith('Karateka.dsk'), 'Karateka went to S6,D2 (S6,D1 is YANC)')
s = scr()
check('/KARATEKA' in e.screen()[0] and 'KARATEKA.SYSTEM' in s, 'panel opened the inserted disk')
step('2' + DN * 3 + RET, 'k_panel2')       # back to the KEGS images
s = scr()
check('Karateka.dsk' in s and 'S6,D2' in s, 'images list shows the drive')
step('K', None)
step('8', 'k_ejectdlg')
check('Eject disk' in scr(), 'eject dialog')
step('y', 'k_ejected')
check(('eject', 0x62) in e.kegs.calls and 0x62 not in e.kegs.drives, 'ejected S6,D2')
step('G' + RET, 'k_games')               # enter GAMES
s = scr()
check('KEGS:/GAMES' in s and 'Zork.dsk' in s and '<UP>' in s, 'sub-folder with UP row')
step(ESC, 'k_back')
s = scr()
check('KEGS:/GAMES' not in s and 'Karateka.dsk' in s, 'back in the images folder')
step('A' + RET, 'k_insert35')           # AllStar.2mg (3.5") -> S5 drives
s = scr()
check('S5,D1' in s and 'S5,D2' in s and 'S6,D1' not in s, '3.5" image offers S5 drives only')
step(ESC)
step('H' + RET, 'k_inserthd')           # Hard1.hdv -> S7 drives
s = scr()
check('S7,D1' in s and 'S7,D2' in s and 'S5,D1' not in s, 'hard disk offers S7 drives only')
step(ESC)
step(TAB + '5', 'k_copyto')              # other panel copies into KEGS -> error
check('other panel is KEGS images' in scr(), 'copy to KEGS panel refused')
step(' ' + TAB + '2' + RET, 'k_back_to_vol')   # back to a ProDOS volume in the KEGS panel
s = scr()
check('KEGS:/' not in e.screen()[0] , 'panel back to ProDOS')
print('FAILED:', fails if fails else 'none')
