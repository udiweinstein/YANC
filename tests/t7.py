import os, subprocess
from harness import Emu, BIN
from setup_vols import setup
import sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from mkpo import mkimage
AC = ['java','-jar','/tmp/ac/ac.jar']
def build(order, fn):
    files = []
    for n in order:
        t = 0xFF if n.endswith('.SYSTEM') or n == 'PRODOS' else 0x06
        files.append((n, (n*300).encode()[:2000+len(n)*37], t, 0x2000 if t==0xFF else 0))
    mkimage(fn, 'BOOTVOL', files, total=1600)
    return bytearray(open(fn,'rb').read())
def listing(fn):
    out = subprocess.run(AC+['-l',fn],capture_output=True,text=True).stdout.split('\n')
    return [l.split()[0] for l in out[1:] if l.strip() and not l.startswith('ProDOS')]
def test(order, target, keys_extra=''):
    fn = '/tmp/boot.po'
    vols = setup(); img = build(order, fn)
    vols['BOOTVOL'] = dict(unit=0x50, path=None, total=1600, img=img)
    e = Emu(BIN, vols, '/BOOTVOL/')
    first = target[0]
    e.run([first]); 
    # move cursor to the exact target via search repeats
    for _ in range(30):
        name = [l for l in e.screen() if 'SUB-DIR' not in l][19][2:17].strip()
        if name == target: break
        e.run([first])
    e.run(['4','b'])
    msg = [l[14:66].strip() for l in e.screen()[9:12] if l[14:66].strip()]
    e.run([' '])
    open(fn,'wb').write(vols['BOOTVOL']['img'])
    lst = listing(fn)
    ok = all(subprocess.run(AC+['-g',fn,n],capture_output=True).stdout == (n*300).encode()[:2000+len(n)*37] for n in order)
    print(f'{target:16s} -> {msg}  blocks written {e.blockwrites}')
    print('   before:', [n for n in order if n.endswith('.SYSTEM')], '\n   after: ', [n for n in lst if n.endswith('.SYSTEM')], 'contents ok:', ok, 'same set:', sorted(lst)==sorted(order))
# 20 files: first .SYSTEM in block 2, target in block 3 (two-block swap)
order = ['PRODOS','BASIC.SYSTEM','LAUNCHER.SYSTEM'] + [f'F{i:02d}' for i in range(12)] + ['QUIT.SYSTEM','SETTINGS','YANC.SYSTEM','ZZ']
test(order, 'YANC.SYSTEM')
# same block swap
test(['PRODOS','BASIC.SYSTEM','README','YANC.SYSTEM'], 'YANC.SYSTEM')
# already first
test(['PRODOS','YANC.SYSTEM','BASIC.SYSTEM'], 'YANC.SYSTEM')
# not a .SYSTEM file -> error
test(['PRODOS','YANC.SYSTEM','SETTINGS'], 'SETTINGS')
