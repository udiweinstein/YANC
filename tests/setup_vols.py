import os, shutil
from harness import BIN
def setup(root='/tmp/ncvols'):
    shutil.rmtree(root, ignore_errors=True)
    d1 = os.path.join(root, 'SYSDISK'); hd = os.path.join(root, 'HARD1'); d2 = os.path.join(root, 'BLANK')
    for d in (d1, hd, d2): os.makedirs(d)
    open(os.path.join(d1, 'YANC.SYSTEM'), 'wb').write(open(BIN,'rb').read())
    open(os.path.join(d1, 'PRODOS'), 'wb').write(bytes(17128))
    open(os.path.join(d1, 'README.TXT'), 'wb').write(('\r'.join(f'Line {i:03d}: The quick brown fox jumps over the lazy dog.\tTAB' for i in range(60))+'\r').encode())
    os.makedirs(os.path.join(d1, 'GAMES'))
    for n in ['ZORK', 'CHOPLIFTER', 'KARATEKA', 'LODE.RUNNER']:
        open(os.path.join(d1, 'GAMES', n), 'wb').write(os.urandom(3000 + len(n)*100))
    os.makedirs(os.path.join(d1, 'EMPTYDIR'))
    for i in range(25):
        open(os.path.join(hd, f'FILE{i:02d}'), 'wb').write(os.urandom(100*i))
    os.makedirs(os.path.join(hd, 'DOCS', 'SUB'))
    open(os.path.join(hd, 'DOCS', 'NOTE.TXT'), 'wb').write(b'Hello from a subdir\r')
    vols = {'SYSDISK': dict(unit=0x60, path=d1, total=280),
            'HARD1': dict(unit=0x70, path=hd, total=1600),
            'BLANK': dict(unit=0xE0, path=d2, total=280)}
    return vols
