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

print('FAILED:', fails or 'none')
