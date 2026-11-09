import os
from harness import Emu, BIN, render_png
from setup_vols import setup
vols = setup()
e = Emu(BIN, vols, '/SYSDISK/')
UP,DN,LT,RT,RET,ESC,TAB,DEL='\x0b','\x0a','\x08','\x15','\r','\x1b','\t','\x7f'
def step(keys, name=None, show=False):
    e.run(list(keys))
    if show: e.show(name)
    if name: render_png(e, f'/tmp/{name}.png')
def ls(v,*p): return sorted(os.listdir(os.path.join(vols[v]['path'],*p)))
step('')
# copy README.TXT to HARD1 twice -> overwrite prompt
step('R5y')
step('5y', 'overwrite', True)
step('n')
# copy all games: + tag all, copy, then 'A' all on second time
step(DN+RET+'+5y')
print('HARD1', ls('HARD1'))
step('5y','ovr2',False); step('a')
# move KARATEKA (cursor) to /HARD1/DOCS via full path
step('K6\x18/HARD1/DOCS/\r','moved',True)
print('GAMES', ls('SYSDISK','GAMES'), 'DOCS', ls('HARD1','DOCS'))
# delete non-empty dir DOCS on HARD1
step(TAB+'D8y','notempty',True)
step(' ')
# locked file
e.meta[os.path.join(vols['HARD1']['path'],'FILE03')]=dict(type=6,aux=0,access=0x21,cdate=0,ctime=0,mdate=0,mtime=0)
step('\x12')  # reread
step('F'+DN+DN+DN+'8y','locked',True)
step('y')
print('HARD1 has FILE03?', 'FILE03' in ls('HARD1'))
# scrolling + page down / OA end
step(RT+RT, 'pgdn', True)
step([('OA',0x0B)],'home')
step([('OA',0x0A)],'end',True)
# disk full: copy big file to BLANK (280 blocks)
open(os.path.join(vols['HARD1']['path'],'BIG'),'wb').write(os.urandom(150000))
step('\x12B')
e.run(['2']); e.run([DN,DN,RET])  # right... active panel is right(HARD1): choose BLANK there? 
step(TAB+'2'+DN+DN+RET+TAB+'B5y','full',True)
step(' ')
print('BLANK', ls('BLANK'))
step('9','sorted',True)
