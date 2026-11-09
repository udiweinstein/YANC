import os, filecmp
from harness import Emu, BIN, render_png
from setup_vols import setup
vols = setup()
big = os.urandom(150000)
open(os.path.join(vols['HARD1']['path'],'BIG'),'wb').write(big)
open(os.path.join(vols['HARD1']['path'],'MED'),'wb').write(os.urandom(70000))
e = Emu(BIN, vols, '/HARD1/')
e.meta[os.path.join(vols['HARD1']['path'],'MED')]=dict(type=0xFC,aux=0x0801,access=0xE3,cdate=0x1234,ctime=0,mdate=0x5A2B,mtime=0x0C1E)
UP,DN,LT,RT,RET,ESC,TAB='\x0b','\x0a','\x08','\x15','\r','\x1b','\t'
def step(keys, name=None, show=False):
    e.run(list(keys))
    if show: e.show(name)
    if name: render_png(e, f'/tmp/{name}.png')
step('')
# right panel -> BLANK
step(TAB+'2'+DN+DN+RET+TAB)
step('M5y')                      # copy MED (70000 bytes, type BAS)
m = e.meta[os.path.join(vols['BLANK']['path'],'MED')]
print('MED identical:', filecmp.cmp(os.path.join(vols['HARD1']['path'],'MED'), os.path.join(vols['BLANK']['path'],'MED'), shallow=False), {k:hex(v) for k,v in m.items()})
step('B5y','full',True)         # BIG should not fit
step(' ')
print('BLANK', os.listdir(vols['BLANK']['path']))
# tag dir + files and copy: dir skipped note
step('D '+'F  '+'5y', 'skipnote', True)
step(' ', 'final', True)
