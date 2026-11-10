"""ProDOS volumes backed by disk images, with ProDOS 8 MLI semantics, for the test harness.

ImgEmu runs YANC.SYSTEM with every volume a real ProDOS block image, so block-level code
(extended files, boot order) and MLI calls see the same disk.  Like ProDOS 8, OPEN and
DESTROY refuse extended files (storage type 5) with error $4B.
fsck() checks a volume: every block used once, the bitmap matching, file counts right."""
import math
from harness import Emu, DATE, TIME

BS = 512

class PVol:
    def __init__(self, img):
        self.img = img

    # ---- blocks / bitmap ----
    def blk(self, b): return self.img[b * BS:(b + 1) * BS]
    def put(self, b, data): self.img[b * BS:(b + 1) * BS] = bytes(data).ljust(BS, b'\0')
    def w16(self, o): return self.img[o] | (self.img[o + 1] << 8)
    def s16(self, o, v): self.img[o] = v & 0xFF; self.img[o + 1] = (v >> 8) & 0xFF
    @property
    def total(self): return self.w16(2 * BS + 4 + 0x25)
    @property
    def bmstart(self): return self.w16(2 * BS + 4 + 0x23)
    def isfree(self, b): return bool(self.img[self.bmstart * BS + b // 8] & (0x80 >> (b % 8)))
    def setfree(self, b, free):
        o = self.bmstart * BS + b // 8
        if free: self.img[o] |= 0x80 >> (b % 8)
        else: self.img[o] &= ~(0x80 >> (b % 8)) & 0xFF
    def nfree(self): return sum(1 for b in range(self.total) if self.isfree(b))
    def alloc(self):
        for b in range(self.total):
            if self.isfree(b):
                self.setfree(b, False); self.put(b, b''); return b
        raise IOError(0x48)
    def free(self, b):
        assert not self.isfree(b), 'double free %d' % b
        self.setfree(b, True)

    # ---- directories ----
    def dirblocks(self, key):
        b = key
        while b:
            yield b
            b = self.w16(b * BS + 2)
    def entries(self, key):
        """(entry offset in image) for every used file entry of the directory"""
        for b in self.dirblocks(key):
            for i in range(13):
                o = b * BS + 4 + i * 39
                st = self.img[o] >> 4
                if self.img[o] and st not in (0xE, 0xF):
                    yield o
    def name(self, o): return bytes(self.img[o + 1:o + 1 + (self.img[o] & 0xF)]).decode()
    def lookup(self, comps):
        """comps = path below the volume. -> (dirkey, entry offset) ; dirkey of root = 2"""
        dk = 2
        for i, c in enumerate(comps):
            for o in self.entries(dk):
                if self.name(o) == c: break
            else:
                return dk, None, (0x46 if i == len(comps) - 1 else 0x44)
            if i == len(comps) - 1: return dk, o, 0
            if self.img[o] >> 4 != 0xD: return dk, None, 0x44
            dk = self.w16(o + 0x11)
        return dk, None, 0x46
    def hdr(self, dk): return dk * BS + 4
    def newentry(self, dk):
        for b in self.dirblocks(dk):
            for i in range(13):
                o = b * BS + 4 + i * 39
                if self.img[o] == 0 and not (b == dk and i == 0): return o
        if dk == 2: raise IOError(0x49)
        last = list(self.dirblocks(dk))[-1]
        nb = self.alloc()
        self.s16(last * BS + 2, nb); self.s16(nb * BS, last)
        # parent entry of the subdirectory grows
        h = self.hdr(dk); pb = self.w16(h + 0x23); pe = self.img[h + 0x25]
        po = pb * BS + 4 + (pe - 1) * 39
        self.s16(po + 0x13, self.w16(po + 0x13) + 1)
        eof = self.w16(po + 0x15) + BS; self.s16(po + 0x15, eof)
        return nb * BS + 4

    # ---- file data ----
    def datablocks(self, st, key, eof):
        n = (eof + BS - 1) // BS
        if st == 1: return [key][:max(n, 1)]
        if st == 2:
            ib = self.blk(key); return [ib[i] | (ib[256 + i] << 8) for i in range(256)][:n]
        mb = self.blk(key); out = []
        for j in range(128):
            ik = mb[j] | (mb[256 + j] << 8)
            ib = self.blk(ik) if ik else bytes(BS)
            out += [ib[i] | (ib[256 + i] << 8) for i in range(256)]
        return out[:n]
    def readfork(self, st, key, eof):
        d = bytearray()
        for b in self.datablocks(st, key, eof): d += self.blk(b) if b else bytes(BS)
        return bytes(d[:eof])
    def forkblocks(self, st, key):
        """all blocks of a fork (index blocks included)"""
        if st == 1: return [key]
        if st == 2: ib = self.blk(key); return [key] + [b for b in (ib[i] | (ib[256 + i] << 8) for i in range(256)) if b]
        if st == 3:
            out = [key]; mb = self.blk(key)
            for j in range(128):
                ik = mb[j] | (mb[256 + j] << 8)
                if ik: out += self.forkblocks(2, ik)
            return out
        raise ValueError(st)
    def writefork(self, data):
        """allocate a fresh fork for data -> (storage type, key, blocks used)"""
        n = max(1, (len(data) + BS - 1) // BS)
        need = 1 if len(data) <= BS else (n + 1 if n <= 256 else n + 1 + (n + 255) // 256)
        if need > self.nfree(): raise IOError(0x48)
        if len(data) <= BS:
            k = self.alloc(); self.put(k, data); return 1, k, 1
        blocks = []
        for i in range(n):
            b = self.alloc(); self.put(b, data[i * BS:(i + 1) * BS]); blocks.append(b)
        def index(bl):
            k = self.alloc(); ib = bytearray(BS)
            for i, b in enumerate(bl): ib[i] = b & 0xFF; ib[256 + i] = b >> 8
            self.put(k, ib); return k
        if n <= 256: return 2, index(blocks), n + 1
        idx = [index(blocks[j:j + 256]) for j in range(0, n, 256)]
        return 3, index(idx), n + 1 + len(idx)

    # ---- whole-volume check ----
    def fsck(self):
        owner = {}
        def mark(b, who):
            assert 0 < b < self.total, '%s: bad block %d' % (who, b)
            assert b not in owner, 'block %d used by %s and %s' % (b, owner[b], who)
            owner[b] = who
        for b in (0, 1): owner[b] = 'boot'
        nbm = (self.total + 4095) // 4096
        for b in range(self.bmstart, self.bmstart + nbm): mark(b, 'bitmap')
        files = []
        def walk(dk, path):
            n = 0
            for b in self.dirblocks(dk): mark(b, path or '/')
            for o in self.entries(dk):
                n += 1
                st = self.img[o] >> 4; nm = path + '/' + self.name(o); key = self.w16(o + 0x11)
                if st == 0xD:
                    walk(key, nm)
                elif st == 5:
                    mark(key, nm + ' (ext key)'); kb = self.blk(key); used = 1
                    for f, off in (('data', 0), ('rsrc', 256)):
                        fst = kb[off]; fk = kb[off + 1] | (kb[off + 2] << 8)
                        if fst:
                            for x in self.forkblocks(fst, fk): mark(x, nm + ' ' + f); used += 1
                    assert used == self.w16(o + 0x13), '%s blocks used %d, really %d' % (nm, self.w16(o + 0x13), used)
                    files.append(nm)
                else:
                    bl = self.forkblocks(st, key)
                    for x in bl: mark(x, nm)
                    assert len(bl) == self.w16(o + 0x13), '%s blocks used' % nm
                    files.append(nm)
            fc = self.w16(self.hdr(dk) + 0x21)
            assert fc == n, '%s file count %d, really %d' % (path or '/', fc, n)
        walk(2, '')
        for b in range(self.total):
            assert self.isfree(b) == (b not in owner), 'block %d: bitmap %s, %s' % (b, 'free' if self.isfree(b) else 'used', owner.get(b, 'unused'))
        return files

def blank(volname, total):
    img = bytearray(total * BS)
    v = PVol(img)
    for b in range(2, 6):
        v.s16(b * BS, b - 1 if b > 2 else 0); v.s16(b * BS + 2, b + 1 if b < 5 else 0)
    h = 2 * BS + 4
    img[h] = 0xF0 | len(volname); img[h + 1:h + 1 + len(volname)] = volname.encode()
    img[h + 0x1E] = 0xC3; img[h + 0x1F] = 0x27; img[h + 0x20] = 0x0D
    v.s16(h + 0x23, 6); v.s16(h + 0x25, total)
    nbm = (total + 4095) // 4096
    for b in range(6 + nbm, total): v.setfree(b, True)
    return img

class ImgEmu(Emu):
    """vols: name -> dict(unit=..., img=bytearray)"""
    def vol(self, path):
        comps = [c for c in path.split('/') if c]
        if not comps or comps[0] not in self.vols: return None, comps
        return PVol(self.vols[comps[0]]['img']), comps

    def mli_C5(self, p):
        buf = self.rw(p + 2); o = 0
        for name, v in self.vols.items():
            self.wb(buf + o, v['unit'] | len(name))
            self.mem.m[buf + o + 1:buf + o + 1 + len(name)] = name.encode(); o += 16
        self.wb(buf + o, 0); return 0
    def mli_C6(self, p):
        path = self.rpath(self.rw(p + 1)); v, comps = self.vol(path)
        if v is None: return 0x45
        self.prefix = path.rstrip('/') + '/'; return 0

    def mli_C4(self, p):   # GET_FILE_INFO
        v, comps = self.vol(self.rpath(self.rw(p + 1)))
        if v is None: return 0x45
        if len(comps) == 1:
            h = v.hdr(2)
            self.wb(p + 3, v.img[h + 0x1E]); self.wb(p + 4, 0x0F); self.ww(p + 5, v.total); self.wb(p + 7, 0x0F)
            self.ww(p + 8, v.total - v.nfree())
            for o in (10, 12, 14, 16): self.ww(p + o, 0)
            return 0
        dk, o, err = v.lookup(comps[1:])
        if err: return err
        img = v.img
        self.wb(p + 3, img[o + 0x1E]); self.wb(p + 4, img[o + 0x10]); self.mem.m[p + 5:p + 7] = img[o + 0x1F:o + 0x21]
        self.wb(p + 7, img[o] >> 4); self.mem.m[p + 8:p + 10] = img[o + 0x13:o + 0x15]
        self.mem.m[p + 10:p + 14] = img[o + 0x21:o + 0x25]; self.mem.m[p + 14:p + 18] = img[o + 0x18:o + 0x1C]
        return 0

    def mli_C3(self, p):   # SET_FILE_INFO (any storage type)
        v, comps = self.vol(self.rpath(self.rw(p + 1)))
        if v is None: return 0x45
        dk, o, err = v.lookup(comps[1:])
        if err: return err
        img = v.img
        img[o + 0x1E] = self.rd(p + 3); img[o + 0x10] = self.rd(p + 4); img[o + 0x1F:o + 0x21] = self.mem.m[p + 5:p + 7]
        img[o + 0x21:o + 0x25] = self.mem.m[p + 10:p + 14]
        return 0

    def mli_C0(self, p):   # CREATE
        v, comps = self.vol(self.rpath(self.rw(p + 1)))
        if v is None: return 0x45
        if not all(self.validname(c) for c in comps): return 0x40
        dk, o, err = v.lookup(comps[1:])
        if not err: return 0x47
        if err != 0x46: return err
        try:
            st = self.rd(p + 7)
            o = v.newentry(dk); k = v.alloc()
            img = v.img; nm = comps[-1]
            img[o:o + 39] = bytes(39)
            img[o] = ((0xD if st == 0xD else 1) << 4) | len(nm); img[o + 1:o + 1 + len(nm)] = nm.encode()
            img[o + 0x10] = self.rd(p + 4); v.s16(o + 0x11, k); v.s16(o + 0x13, 1)
            cd = self.rw(p + 8) or DATE; ct = self.rw(p + 10) or TIME
            v.s16(o + 0x18, cd); v.s16(o + 0x1A, ct); img[o + 0x1E] = self.rd(p + 3)
            img[o + 0x1F:o + 0x21] = self.mem.m[p + 5:p + 7]; v.s16(o + 0x21, DATE); v.s16(o + 0x23, TIME)
            v.s16(o + 0x25, dk)
            if st == 0xD:
                v.s16(o + 0x15, BS)
                h = k * BS + 4
                img[h] = 0xE0 | len(nm); img[h + 1:h + 1 + len(nm)] = nm.encode(); img[h + 0x10] = 0x75
                img[h + 0x1E] = 0xC3; img[h + 0x1F] = 0x27; img[h + 0x20] = 0x0D
                eb = (o // BS); v.s16(h + 0x23, eb); img[h + 0x25] = (o - eb * BS - 4) // 39 + 1; img[h + 0x26] = 0x27
            hd = v.hdr(dk); v.s16(hd + 0x21, v.w16(hd + 0x21) + 1)
        except IOError as e:
            return e.args[0]
        return 0

    def mli_C1(self, p):   # DESTROY
        v, comps = self.vol(self.rpath(self.rw(p + 1)))
        if v is None: return 0x45
        dk, o, err = v.lookup(comps[1:])
        if err: return err
        img = v.img; st = img[o] >> 4; key = v.w16(o + 0x11)
        if any(r.get('ent') == (id(v.img), o) for r in self.refs.values()): return 0x50
        if st not in (1, 2, 3, 0xD): return 0x4A   # what ProDOS 8 2.x really returns
        if not img[o + 0x1E] & 0x80: return 0x4E
        if st == 0xD:
            if v.w16(key * BS + 4 + 0x21): return 0x4E
            for b in list(v.dirblocks(key)): v.free(b)
        else:
            for b in v.forkblocks(st, key): v.free(b)
        img[o] = 0
        hd = v.hdr(dk); v.s16(hd + 0x21, v.w16(hd + 0x21) - 1)
        return 0

    def mli_C2(self, p):   # RENAME
        a = self.rpath(self.rw(p + 1)); b = self.rpath(self.rw(p + 3))
        v, ca = self.vol(a); _, cb = self.vol(b)
        if v is None: return 0x45
        if not all(self.validname(c) for c in cb): return 0x40
        if ca[:-1] != cb[:-1]: return 0x40
        dk, o, err = v.lookup(ca[1:])
        if err: return err
        if not v.lookup(cb[1:])[2]: return 0x47
        nm = cb[-1]; v.img[o] = (v.img[o] & 0xF0) | len(nm); v.img[o + 1:o + 16] = nm.encode().ljust(15, b'\0')
        return 0

    def mli_C8(self, p):   # OPEN
        v, comps = self.vol(self.rpath(self.rw(p + 1)))
        if v is None: return 0x45
        iobuf = self.rw(p + 3)
        assert iobuf & 0xFF == 0 and iobuf + 1024 <= 0xBF00, 'bad io buffer'
        if len(comps) == 1:
            data = bytearray(); [data.extend(v.blk(b)) for b in v.dirblocks(2)]; ent = None; isdir = True
        else:
            dk, o, err = v.lookup(comps[1:])
            if err: return err
            st = v.img[o] >> 4; key = v.w16(o + 0x11)
            if st == 0xD:
                data = bytearray(); [data.extend(v.blk(b)) for b in v.dirblocks(key)]; isdir = True
            elif st in (1, 2, 3):
                data = bytearray(v.readfork(st, key, v.w16(o + 0x15) | (v.img[o + 0x17] << 16))); isdir = False
            else:
                return 0x4B
            ent = (id(v.img), o)
        for r in range(1, 9):
            if r not in self.refs: break
        else: return 0x42
        self.refs[r] = dict(h=comps, data=data, mark=0, isdir=isdir, ent=ent, v=v, o=None if ent is None else ent[1])
        self.wb(p + 5, r); return 0

    def mli_CB(self, p):   # WRITE: rewrite the file's blocks after each call
        r = self.refs.get(self.rd(p + 1))
        if r is None: return 0x43
        if r['isdir']: return 0x4E
        buf, req = self.rw(p + 2), self.rw(p + 4)
        v, o = r['v'], r['o']
        new = bytearray(r['data']); new[r['mark']:r['mark'] + req] = bytes(self.mem.m[buf:buf + req])
        st = v.img[o] >> 4; key = v.w16(o + 0x11); old = v.forkblocks(st, key)
        avail = v.nfree() + len(old)
        n = max(1, (len(new) + BS - 1) // BS)
        need = 1 if len(new) <= BS else (n + 1 if n <= 256 else n + 1 + (n + 255) // 256)
        if need > avail: self.ww(p + 6, 0); return 0x48
        for b in old: v.free(b)
        st, key, used = v.writefork(bytes(new))
        v.img[o] = (st << 4) | (v.img[o] & 0xF); v.s16(o + 0x11, key); v.s16(o + 0x13, used)
        v.s16(o + 0x15, len(new) & 0xFFFF); v.img[o + 0x17] = len(new) >> 16
        r['data'] = new; r['mark'] += req
        self.ww(p + 6, req); return 0

    def mli_CA(self, p):
        return Emu.mli_CA(self, p)

def addfile(img, path, data, ftype=6, aux=0, access=0xE3):
    """create a plain file with the MLI emulation's own code"""
    v = PVol(img); comps = [c for c in path.split('/') if c]
    dk, o, err = v.lookup(comps[1:])
    assert err == 0x46, err
    o = v.newentry(dk); st, k, used = v.writefork(data); nm = comps[-1]
    img[o:o + 39] = bytes(39); img[o] = (st << 4) | len(nm); img[o + 1:o + 1 + len(nm)] = nm.encode()
    img[o + 0x10] = ftype; v.s16(o + 0x11, k); v.s16(o + 0x13, used)
    v.s16(o + 0x15, len(data) & 0xFFFF); img[o + 0x17] = len(data) >> 16
    v.s16(o + 0x18, DATE); v.s16(o + 0x1A, TIME); img[o + 0x1E] = access; v.s16(o + 0x1F, aux)
    v.s16(o + 0x21, DATE); v.s16(o + 0x23, TIME); v.s16(o + 0x25, dk)
    hd = v.hdr(dk); v.s16(hd + 0x21, v.w16(hd + 0x21) + 1)
    return o

def addext(img, path, data, rsrc, ftype=0xB3, aux=0xDB07, access=0xE3, finfo=b''):
    """create an extended file the way the GS/OS ProDOS FST does"""
    v = PVol(img)
    o = addfile(img, path, b'', ftype, aux, access)
    for b in v.forkblocks(1, v.w16(o + 0x11)): v.free(b)
    kb = bytearray(BS); used = 1
    for off, d in ((0, data), (256, rsrc)):
        st, k, u = v.writefork(d)
        kb[off] = st; kb[off + 1:off + 3] = k.to_bytes(2, 'little'); kb[off + 3:off + 5] = u.to_bytes(2, 'little')
        kb[off + 5:off + 8] = len(d).to_bytes(3, 'little'); used += u
    kb[8:8 + len(finfo)] = finfo
    key = v.alloc(); v.put(key, kb)
    img[o] = 0x50 | (img[o] & 0xF); v.s16(o + 0x11, key); v.s16(o + 0x13, used); v.s16(o + 0x15, BS); img[o + 0x17] = 0
    return o

def readext(img, path):
    """-> (data fork, resource fork, key block) of an extended file"""
    v = PVol(img); comps = [c for c in path.split('/') if c]
    dk, o, err = v.lookup(comps[1:])
    assert not err, (path, err)
    assert img[o] >> 4 == 5, '%s is not extended' % path
    kb = v.blk(v.w16(o + 0x11)); out = []
    for off in (0, 256):
        st = kb[off]; k = kb[off + 1] | (kb[off + 2] << 8); eof = int.from_bytes(kb[off + 5:off + 8], 'little')
        out.append(v.readfork(st, k, eof) if st else b'')
    return out[0], out[1], bytes(kb)

def entry(img, path):
    v = PVol(img); comps = [c for c in path.split('/') if c]
    dk, o, err = v.lookup(comps[1:])
    return None if err else bytes(img[o:o + 39])
