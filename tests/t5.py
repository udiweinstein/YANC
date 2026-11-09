import os
from harness import Emu, BIN
from setup_vols import setup
# SYS program: writes $5A to $0300, then MLI QUIT
quitprog = bytes([0xA9,0x5A,0x8D,0x00,0x03, 0x20,0x00,0xBF,0x65,0x0B,0x20, 0,0, 4,0,0,0,0,0,0])
# fake BASIC.SYSTEM: JMP $2050, $EE $EE, buflen $41, buffer ... ; at $2050: write $77 to $300 and quit
bs = bytearray(0x80); bs[0:3]=bytes([0x4C,0x50,0x20]); bs[3]=0xEE; bs[4]=0xEE; bs[5]=0x41
bs[0x50:0x50+len(quitprog)] = bytes([0xA9,0x77])+quitprog[2:5]+bytes([0x20,0x00,0xBF,0x65,0x60,0x20])
bs[0x60:0x67]=bytes([4,0,0,0,0,0,0])
def fresh():
    vols = setup()
    d = vols['SYSDISK']['path']
    open(os.path.join(d,'GAMES','RUNME.SYS'),'wb').write(quitprog)
    open(os.path.join(d,'BASIC.SYSTEM'),'wb').write(bs)
    open(os.path.join(d,'GAMES','HELLO.BAS'),'wb').write(b'\x01\x08')
    e = Emu(BIN, vols, '/SYSDISK/')
    for n in ('GAMES/RUNME.SYS','BASIC.SYSTEM'):
        e.meta[os.path.join(d,n)] = dict(type=0xFF,aux=0x2000,access=0xC3,cdate=0,ctime=0,mdate=0,mtime=0)
    e.meta[os.path.join(d,'GAMES/HELLO.BAS')] = dict(type=0xFC,aux=0x801,access=0xC3,cdate=0,ctime=0,mdate=0,mtime=0)
    return e
e = fresh(); e.run(['G','\r','R','\r'])
print('SYS: quit', e.quit, 'marker', hex(e.mem.m[0x300]), 'prefix', e.prefix, '80col store', e.store80)
e = fresh(); e.run(['G','\r','H','\r'])
n=e.mem.m[0x2005+1]
print('BAS: quit', e.quit, 'marker', hex(e.mem.m[0x300]), 'startup path:', bytes(e.mem.m[0x2007:0x2007+e.mem.m[0x2006]]), 'prefix', e.prefix)
# no BASIC.SYSTEM anywhere -> error box
e = fresh(); os.remove('/tmp/ncvols/SYSDISK/BASIC.SYSTEM'); e.run(['G','\r','H','\r']); print([l for l in e.screen() if 'BASIC' in l])
# TXT -> viewer
e = fresh(); e.run(['R','\r']); print(e.screen()[0][:40])
e = fresh(); e.run(['G','\r','R','\r']); print('$280:', bytes(e.mem.m[0x281:0x281+e.mem.m[0x280]]))
