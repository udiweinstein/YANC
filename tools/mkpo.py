"""Create a ProDOS-formatted .po image containing YANC.SYSTEM (type $FF, aux $2000)."""
import sys, math
def date(y, m, d): return ((y % 100) << 9) | (m << 5) | d
def mkimage(out, volname, files, total=280):
    img = bytearray(total * 512)
    used = set(range(0, 7))                        # boot 0-1, dir 2-5, bitmap 6
    nxt = [7]
    def alloc():
        b = nxt[0]; nxt[0] += 1; used.add(b); return b
    D = date(26, 11, 9); T = (18 << 8) | 0
    entries = []
    for name, data, ftype, aux in files:
        nblk = max(1, math.ceil(len(data) / 512))
        if nblk == 1:
            key = alloc(); img[key*512:key*512+len(data)] = data; st = 1; bu = 1
        else:
            assert nblk <= 256
            key = alloc(); st = 2; bu = nblk + 1
            for i in range(nblk):
                b = alloc()
                img[b*512:b*512+512] = data[i*512:(i+1)*512].ljust(512, b'\0')
                img[key*512+i] = b & 0xFF; img[key*512+256+i] = b >> 8
        e = bytearray(39)
        e[0] = (st << 4) | len(name); e[1:1+len(name)] = name.encode()
        e[0x10] = ftype; e[0x11:0x13] = key.to_bytes(2,'little'); e[0x13:0x15] = bu.to_bytes(2,'little')
        e[0x15:0x18] = len(data).to_bytes(3,'little')
        e[0x18:0x1A] = D.to_bytes(2,'little'); e[0x1A:0x1C] = T.to_bytes(2,'little')
        e[0x1E] = 0xE3; e[0x1F:0x21] = aux.to_bytes(2,'little')
        e[0x21:0x23] = D.to_bytes(2,'little'); e[0x23:0x25] = T.to_bytes(2,'little')
        e[0x25:0x27] = (2).to_bytes(2,'little')
        entries.append(e)
    for i, b in enumerate(range(2, 6)):
        o = b * 512
        img[o:o+2] = (b - 1 if b > 2 else 0).to_bytes(2,'little')
        img[o+2:o+4] = (b + 1 if b < 5 else 0).to_bytes(2,'little')
    h = bytearray(39)
    h[0] = 0xF0 | len(volname); h[1:1+len(volname)] = volname.encode()
    h[0x18:0x1A] = D.to_bytes(2,'little'); h[0x1A:0x1C] = T.to_bytes(2,'little')
    h[0x1E] = 0xC3; h[0x1F] = 0x27; h[0x20] = 0x0D
    h[0x21:0x23] = len(entries).to_bytes(2,'little'); h[0x23:0x25] = (6).to_bytes(2,'little')
    h[0x25:0x27] = total.to_bytes(2,'little')
    slots = [h] + entries
    for i, e in enumerate(slots):
        blk = 2 + i // 13; off = blk*512 + 4 + (i % 13) * 39
        img[off:off+39] = e
    for b in range(total):
        if b not in used:
            img[6*512 + b // 8] |= 0x80 >> (b % 8)
    open(out, 'wb').write(img)
if __name__ == '__main__':
    nc = open('YANC.SYSTEM','rb').read()
    readme = open('README.TXT','rb').read() if len(sys.argv) > 2 else None
    files = [('YANC.SYSTEM', nc, 0xFF, 0x2000)]
    if readme: files.append(('README', readme, 0x04, 0))
    mkimage(sys.argv[1], 'YANC', files)
