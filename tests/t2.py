import os
from harness import Emu, BIN, render_png
from setup_vols import setup
vols = setup()
e = Emu(BIN, vols, '/SYSDISK/')
e.meta[os.path.join(vols['SYSDISK']['path'],'YANC.SYSTEM')] = dict(type=0xFF,aux=0x2000,access=0xC3,cdate=0,ctime=0,mdate=0,mtime=0)
UP,DN,LT,RT,RET,ESC,TAB,DEL='\x0b','\x0a','\x08','\x15','\r','\x1b','\t','\x7f'
def step(keys, name=None, show=False):
    e.run(list(keys))
    if show: e.show(name)
    if name: render_png(e, f'/tmp/{name}.png')
os.makedirs('/tmp/shots', exist_ok=True)
step('', 'start')
step(DN, 'down')                       # cursor on GAMES
step(RET, 'games', True)               # enter GAMES
step(' '+' ', 'tagged', True)          # tag CHOPLIFTER, KARATEKA
step('5', 'copydlg', True)
step('y', 'aftercopy', True)
print(sorted(os.listdir(vols['HARD1']['path'])))
step(ESC, 'parent', True)              # back to /SYSDISK, cursor on GAMES
step('R', 'readme')                    # quick search -> README.TXT
step('3', 'view', True)
step(' ', 'view2', True)
step('h', 'hex', True)
step(ESC, 'back')
step(TAB, 'tab')
step('7', 'mkdlg')
step('newdir\r', 'mkdir', True)
print(sorted(os.listdir(vols['HARD1']['path'])))
step('6', 'rendlg', True)
step('\x18NEWNAME\r', 'renamed', True)
print(sorted(os.listdir(vols['HARD1']['path'])))
step('8', 'deldlg', True)
step('y', 'deleted', True)
print(sorted(os.listdir(vols['HARD1']['path'])))
step('2', 'vol', True)
step(DN+DN+RET, 'blank', True)
step('1', 'help', True)
step(' ', None)
step('\x13', 'swap', True)
step('0', 'quitdlg', True)
step('y')
print('quit', e.quit)
