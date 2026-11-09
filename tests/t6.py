import os
from harness import Emu, BIN
from setup_vols import setup
vols=setup(); e=Emu(BIN,vols,'/HARD1/')
h=lambda n: os.path.join(vols['HARD1']['path'],n)
e.run(['F','\x0a',' ',' ','4'])   # tag FILE01, FILE02
e.show('dlg')
e.run(['l'])
print('acc', hex(e.fmeta(h('FILE01'))['access']), hex(e.fmeta(h('FILE02'))['access']))
print('\n'.join(l for l in e.screen()[2:7]))
e.run(['8','y']); print([l for l in e.screen() if 'locked' in l])
e.run(['n','n'])
e.run(['\x0b','4','u']); print('after unlock FILE02?', hex(e.fmeta(h('FILE02'))['access']), hex(e.fmeta(h('FILE01'))['access']))
print('\n'.join(l for l in e.screen()[2:7]))
