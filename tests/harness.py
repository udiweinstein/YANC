"""Test harness: 65C02 (py65) + Apple IIc 80-col text screen + simulated ProDOS MLI
backed by host directories.  Not an Apple II emulator - just enough to exercise NC."""
import os, sys, shutil
BIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "release", "YANC.SYSTEM")
from py65.devices.mpu65c02 import MPU

DATE = ((26 << 9) | (11 << 5) | 9)          # 09-NOV-26
TIME = (18 << 8) | 30

class Mem:
    def __init__(self, emu):
        self.emu = emu
        self.m = bytearray(65536)
        self.aux = bytearray(0x400)
    def __len__(self): return 65536
    def __getitem__(self, a):
        if 0xC000 <= a <= 0xC0FF:
            return self.emu.io(a, None)
        if 0x400 <= a < 0x800 and self.emu.store80 and self.emu.page2:
            return self.aux[a - 0x400]
        return self.m[a]
    def __setitem__(self, a, v):
        if 0xC000 <= a <= 0xC0FF:
            self.emu.io(a, v); return
        if 0x400 <= a < 0x800 and self.emu.store80 and self.emu.page2:
            self.aux[a - 0x400] = v; return
        self.m[a] = v

def rowaddr(r): return 0x400 + (r % 8) * 0x80 + (r // 8) * 0x28

MT = {0x40:'', 0x41:'', 0x44:'✓', 0x45:'✔', 0x4C:'‾', 0x5A:'▕', 0x5F:'▏', 0x53:'─'}

class Emu:
    def __init__(self, binpath, vols, prefix):
        self.mem = Mem(self)
        self.cpu = MPU(memory=self.mem)
        code = open(binpath, 'rb').read()
        self.mem.m[0x2000:0x2000 + len(code)] = code
        self.cpu.pc = 0x2000
        for a in (0xFE84,0xFB2F,0xFE93,0xFE89,0xFC58,0xFDED): self.mem.m[a]=0x60
        self.cpu.sp = 0xFF
        self.store80 = False; self.page2 = False
        self.keys = []; self.idle = 0; self.quit = False
        self.vols = vols                      # name -> dict(unit, path, total)
        self.prefix = prefix
        self.meta = {}
        self.refs = {}
        self.mlilog = []
        self.blockwrites = []

    # ---------------- IO -----------------
    def io(self, a, v):
        if a == 0xC000:
            if v is not None: self.store80 = False; return
            if self.keys:
                k = self.keys[0]
                return (k[1] if isinstance(k, tuple) else ord(k)) | 0x80
            self.idle += 1
            return 0
        if a == 0xC010:
            if self.keys: self.keys.pop(0)
            return 0
        if a == 0xC061:
            if self.keys and isinstance(self.keys[0], tuple): return 0x80
            return 0
        if a == 0xC001 and v is not None: self.store80 = True
        if a == 0xC054: self.page2 = False
        if a == 0xC055: self.page2 = True
        return 0

    def run(self, keys=(), maxsteps=20_000_000):
        self.keys.extend(keys)
        steps = 0
        self.idle = 0
        while steps < maxsteps and not self.quit:
            if self.cpu.pc == 0xBF00:
                self.mli()
                continue
            if self.mem.m[self.cpu.pc] == 0x42:     # WDM: 2-byte NOP on 65C02
                if getattr(self, 'kegs', None) and self.mem.m[self.cpu.pc + 1] == 0x58:
                    self.kegs.call(self)
                self.cpu.pc = (self.cpu.pc + 2) & 0xFFFF
                continue
            if self.mem.m[self.cpu.pc] == 0x00 and self.cpu.pc != 0xBF00:
                raise RuntimeError('BRK at %04X' % self.cpu.pc)
            self.cpu.step()
            steps += 1
            if self.idle > 3 and not self.keys:
                return steps
        if not self.quit:
            raise RuntimeError('ran out of steps, pc=%04X' % self.cpu.pc)
        return steps

    # --------------- screen ---------------
    def screen(self):
        out = []
        for r in range(24):
            base = rowaddr(r) - 0x400
            line = ''
            for c in range(80):
                b = self.mem.aux[base + c // 2] if c % 2 == 0 else self.mem.m[0x400 + base + c // 2]
                line += self.decode(b)[0]
            out.append(line)
        return out

    def cells(self):
        res = []
        for r in range(24):
            base = rowaddr(r) - 0x400
            row = []
            for c in range(80):
                b = self.mem.aux[base + c // 2] if c % 2 == 0 else self.mem.m[0x400 + base + c // 2]
                row.append(self.decode(b))
            res.append(row)
        return res

    @staticmethod
    def decode(b):
        if b >= 0x80: return (chr(b & 0x7F), False, False)
        if b < 0x20: return (chr(b + 0x40), True, False)
        if b < 0x40: return (chr(b), True, False)
        if b < 0x60: return (MT.get(b, '?'), False, True)
        return (chr(b), True, False)

    def show(self, title=''):
        print('=' * 82, title)
        for l in self.screen(): print('|' + l + '|')

    # --------------- MLI ------------------
    def rd(self, a): return self.mem.m[a]
    def rw(self, a): return self.mem.m[a] | (self.mem.m[a + 1] << 8)
    def wb(self, a, v): self.mem.m[a] = v & 0xFF
    def ww(self, a, v): self.mem.m[a] = v & 0xFF; self.mem.m[a + 1] = (v >> 8) & 0xFF

    def mli(self):
        cpu = self.cpu
        sp = cpu.sp
        ret = self.mem.m[0x100 + ((sp + 1) & 0xFF)] | (self.mem.m[0x100 + ((sp + 2) & 0xFF)] << 8)
        cpu.sp = (sp + 2) & 0xFF
        cmd = self.rd(ret + 1)
        parm = self.rw(ret + 2)
        cpu.pc = (ret + 4) & 0xFFFF
        try:
            err = getattr(self, 'mli_%02X' % cmd)(parm)
        except AttributeError:
            raise RuntimeError('MLI call %02X not emulated' % cmd)
        self.mlilog.append((cmd, err))
        if err:
            cpu.a = err; cpu.p |= 1; cpu.p &= ~2
        else:
            cpu.a = 0; cpu.p &= ~1; cpu.p |= 2

    def rpath(self, a):
        n = self.rd(a)
        s = bytes(self.mem.m[a + 1:a + 1 + n]).decode('ascii').upper()
        if not s.startswith('/'):
            s = self.prefix.rstrip('/') + '/' + s
        return s

    def host(self, p):
        comps = [c for c in p.split('/') if c]
        if not comps: return None, None, comps
        v = self.vols.get(comps[0])
        if v is None: return None, None, comps
        return v, os.path.join(v['path'], *comps[1:]), comps

    @staticmethod
    def validname(c):
        return 1 <= len(c) <= 15 and c[0].isalpha() and all(ch.isalnum() or ch == '.' for ch in c) and c.isascii()

    def fmeta(self, h):
        m = self.meta.get(h)
        if m is None:
            ext = os.path.splitext(h)[1].upper()
            t = {'.TXT': 4, '.SYS': 0xFF, '.BAS': 0xFC}.get(ext, 6)
            if os.path.isdir(h): t = 0x0F
            m = dict(type=t, aux=0x2000 if t == 6 else 0, access=0xC3, cdate=DATE, ctime=TIME, mdate=DATE, mtime=TIME)
            self.meta[h] = m
        return m

    def blocks(self, h):
        if os.path.isdir(h):
            n = len(os.listdir(h))
            return (n + 1 + 12) // 13
        sz = os.path.getsize(h)
        d = max(1, (sz + 511) // 512)
        if sz <= 512: return 1
        if sz <= 128 * 1024: return d + 1
        return d + (d + 255) // 256 + 1

    def volused(self, v):
        tot = 6
        for root, dirs, files in os.walk(v['path']):
            tot += self.blocks(root) if root != v['path'] else 4
            for f in files: tot += self.blocks(os.path.join(root, f))
        return tot

    def dirdata(self, h, comps):
        names = sorted(os.listdir(h))
        ents = []
        for nm in names:
            hp = os.path.join(h, nm)
            m = self.fmeta(hp)
            if os.path.isdir(hp): st = 0xD
            else:
                sz = os.path.getsize(hp)
                st = 1 if sz <= 512 else (2 if sz <= 128 * 1024 else 3)
            e = bytearray(39)
            e[0] = (st << 4) | len(nm)
            e[1:1 + len(nm)] = nm.encode()
            e[0x10] = m['type']
            e[0x11] = 0x77
            b = self.blocks(hp); e[0x13] = b & 0xFF; e[0x14] = b >> 8
            sz = (self.blocks(hp) * 512) if os.path.isdir(hp) else os.path.getsize(hp)
            e[0x15] = sz & 0xFF; e[0x16] = (sz >> 8) & 0xFF; e[0x17] = sz >> 16
            e[0x18:0x1A] = m['cdate'].to_bytes(2, 'little'); e[0x1A:0x1C] = m['ctime'].to_bytes(2, 'little')
            e[0x1E] = m['access']
            e[0x1F:0x21] = m['aux'].to_bytes(2, 'little')
            e[0x21:0x23] = m['mdate'].to_bytes(2, 'little'); e[0x23:0x25] = m['mtime'].to_bytes(2, 'little')
            ents.append(e)
        hdr = bytearray(39)
        nm = comps[-1]
        hdr[0] = ((0xF if len(comps) == 1 else 0xE) << 4) | len(nm)
        hdr[1:1 + len(nm)] = nm.encode()
        hdr[0x1F] = 0x27; hdr[0x20] = 0x0D
        hdr[0x21] = len(ents) & 0xFF; hdr[0x22] = len(ents) >> 8
        allents = [hdr] + ents
        nblk = max(1, (len(allents) + 12) // 13)
        data = bytearray()
        for b in range(nblk):
            blk = bytearray(512)
            chunk = allents[b * 13:(b + 1) * 13]
            for i, e in enumerate(chunk):
                blk[4 + i * 39:4 + (i + 1) * 39] = e
            data += blk
        return data

    # ---- image-backed volumes (root directory + block I/O only) ----
    def imgvol(self, path):
        comps = [c for c in path.split('/') if c]
        v = self.vols.get(comps[0]) if comps else None
        return v if v and v.get('img') is not None else None, comps

    def imgdir(self, v):
        img = v['img']; out = bytearray(); b = 2
        while b:
            out += img[b*512:(b+1)*512]; b = int.from_bytes(img[b*512+2:b*512+4], 'little')
        return out

    def unitvol(self, unit):
        for v in self.vols.values():
            if v['unit'] == unit & 0xF0: return v

    def mli_80(self, p):   # READ_BLOCK
        v = self.unitvol(self.rd(p + 1)); buf = self.rw(p + 2); b = self.rw(p + 4)
        if v is None or v.get('img') is None: return 0x28
        self.mem.m[buf:buf+512] = v['img'][b*512:(b+1)*512]; return 0

    def mli_81(self, p):   # WRITE_BLOCK
        v = self.unitvol(self.rd(p + 1)); buf = self.rw(p + 2); b = self.rw(p + 4)
        if v is None or v.get('img') is None: return 0x28
        v['img'][b*512:(b+1)*512] = bytes(self.mem.m[buf:buf+512]); self.blockwrites.append(b); return 0

    # ON_LINE
    def mli_C5(self, p):
        buf = self.rw(p + 2)
        o = 0
        for name, v in self.vols.items():
            self.wb(buf + o, v['unit'] | len(name))
            self.mem.m[buf + o + 1:buf + o + 1 + len(name)] = name.encode()
            o += 16
        self.wb(buf + o, 0)
        return 0

    def mli_C6(self, p):   # SET_PREFIX
        path = self.rpath(self.rw(p + 1))
        v, h, comps = self.host(path)
        if v is None or not os.path.isdir(h): return 0x44
        self.prefix = path.rstrip('/') + '/'
        return 0

    def mli_C7(self, p):   # GET_PREFIX
        buf = self.rw(p + 1)
        s = self.prefix
        self.wb(buf, len(s)); self.mem.m[buf + 1:buf + 1 + len(s)] = s.encode()
        return 0

    def mli_C4(self, p):   # GET_FILE_INFO
        path = self.rpath(self.rw(p + 1))
        iv, comps = self.imgvol(path)
        if iv is not None:
            if len(comps) != 1: return 0x46
            img = iv['img']; tot = int.from_bytes(img[2*512+4+0x25:2*512+4+0x27], 'little')
            free = sum(bin(x).count('1') for x in img[6*512:6*512+(tot+7)//8])
            self.wb(p+3,0xC3); self.wb(p+4,0x0F); self.ww(p+5,tot); self.wb(p+7,0x0F); self.ww(p+8,tot-free)
            for o in (10,12,14,16): self.ww(p+o,0)
            return 0
        v, h, comps = self.host(path)
        if v is None: return 0x45
        if not os.path.exists(h): return 0x46 if os.path.isdir(os.path.dirname(h)) else 0x44
        if len(comps) == 1:
            self.wb(p + 3, 0xC3); self.wb(p + 4, 0x0F); self.ww(p + 5, v['total']); self.wb(p + 7, 0x0F)
            self.ww(p + 8, self.volused(v)); self.ww(p + 10, DATE); self.ww(p + 12, TIME)
            self.ww(p + 14, DATE); self.ww(p + 16, TIME)
            return 0
        m = self.fmeta(h)
        st = 0x0D if os.path.isdir(h) else (1 if os.path.getsize(h) <= 512 else 2)
        self.wb(p + 3, m['access']); self.wb(p + 4, m['type']); self.ww(p + 5, m['aux']); self.wb(p + 7, st)
        self.ww(p + 8, self.blocks(h)); self.ww(p + 10, m['mdate']); self.ww(p + 12, m['mtime'])
        self.ww(p + 14, m['cdate']); self.ww(p + 16, m['ctime'])
        return 0

    def mli_C3(self, p):   # SET_FILE_INFO
        path = self.rpath(self.rw(p + 1))
        v, h, comps = self.host(path)
        if v is None or not os.path.exists(h): return 0x46
        m = self.fmeta(h)
        m.update(access=self.rd(p + 3), type=self.rd(p + 4), aux=self.rw(p + 5), mdate=self.rw(p + 10), mtime=self.rw(p + 12))
        return 0

    def mli_C0(self, p):   # CREATE
        path = self.rpath(self.rw(p + 1))
        v, h, comps = self.host(path)
        if v is None: return 0x45
        if not all(self.validname(c) for c in comps): return 0x40
        if os.path.exists(h): return 0x47
        if not os.path.isdir(os.path.dirname(h)): return 0x44
        if v.get('wp'): return 0x2B
        st = self.rd(p + 7)
        if st == 0x0D: os.mkdir(h)
        else: open(h, 'wb').close()
        cd = self.rw(p + 8) or DATE
        self.meta[h] = dict(type=self.rd(p + 4), aux=self.rw(p + 5), access=self.rd(p + 3), cdate=cd,
                            ctime=self.rw(p + 10), mdate=cd, mtime=TIME)
        return 0

    def mli_C1(self, p):   # DESTROY
        path = self.rpath(self.rw(p + 1))
        v, h, comps = self.host(path)
        if v is None or not os.path.exists(h): return 0x46
        if any(r['h'] == h for r in self.refs.values()): return 0x50
        m = self.fmeta(h)
        if not m['access'] & 0x80: return 0x4E
        if os.path.isdir(h):
            if os.listdir(h): return 0x4E
            os.rmdir(h)
        else: os.remove(h)
        self.meta.pop(h, None)
        return 0

    def mli_C2(self, p):   # RENAME
        a = self.rpath(self.rw(p + 1)); b = self.rpath(self.rw(p + 3))
        va, ha, ca = self.host(a); vb, hb, cb = self.host(b)
        if va is None or not os.path.exists(ha): return 0x46
        if not all(self.validname(c) for c in cb): return 0x40
        if ca[:-1] != cb[:-1]: return 0x40
        if os.path.exists(hb): return 0x47
        os.rename(ha, hb); self.meta[hb] = self.meta.pop(ha, self.fmeta(hb))
        return 0

    def mli_C8(self, p):   # OPEN
        path = self.rpath(self.rw(p + 1))
        iv, comps = self.imgvol(path)
        if iv is not None:
            if len(comps) != 1: return 0x46
            for r in range(1, 9):
                if r not in self.refs: break
            self.refs[r] = dict(h='img', data=self.imgdir(iv), mark=0, isdir=True, dirty=False, vol=iv)
            self.wb(p + 5, r); return 0
        v, h, comps = self.host(path)
        if v is None: return 0x45
        if not os.path.exists(h): return 0x46
        iobuf = self.rw(p + 3)
        assert iobuf & 0xFF == 0 and iobuf + 1024 <= 0xBF00, 'bad io buffer'
        for r in range(1, 9):
            if r not in self.refs: break
        else: return 0x42
        if os.path.isdir(h): data = self.dirdata(h, comps); isdir = True
        else: data = bytearray(open(h, 'rb').read()); isdir = False
        self.refs[r] = dict(h=h, data=data, mark=0, isdir=isdir, dirty=False, vol=v)
        self.wb(p + 5, r)
        return 0

    def mli_CA(self, p):   # READ
        r = self.refs.get(self.rd(p + 1))
        if r is None: return 0x43
        buf, req = self.rw(p + 2), self.rw(p + 4)
        assert buf + req <= 0xBF00
        d = r['data'][r['mark']:r['mark'] + req]
        if not d and req: self.ww(p + 6, 0); return 0x4C
        self.mem.m[buf:buf + len(d)] = d
        r['mark'] += len(d)
        self.ww(p + 6, len(d))
        return 0

    def mli_CB(self, p):   # WRITE
        r = self.refs.get(self.rd(p + 1))
        if r is None: return 0x43
        buf, req = self.rw(p + 2), self.rw(p + 4)
        d = bytes(self.mem.m[buf:buf + req])
        v = r['vol']
        newsz = max(len(r['data']), r['mark'] + req)
        extra = (newsz + 511) // 512 - (len(r['data']) + 511) // 512
        if self.volused(v) + extra > v['total']:
            self.ww(p + 6, 0); return 0x48
        r['data'][r['mark']:r['mark'] + req] = d
        r['mark'] += req; r['dirty'] = True
        open(r['h'], 'wb').write(r['data'])
        self.ww(p + 6, req)
        return 0

    def mli_CC(self, p):   # CLOSE
        ref = self.rd(p + 1)
        if ref == 0: self.refs.clear(); return 0
        if ref not in self.refs: return 0x43
        del self.refs[ref]
        return 0

    def mli_CE(self, p):   # SET_MARK
        r = self.refs.get(self.rd(p + 1))
        if r is None: return 0x43
        m = self.rd(p + 2) | (self.rd(p + 3) << 8) | (self.rd(p + 4) << 16)
        if m > len(r['data']): return 0x4D
        r['mark'] = m
        return 0

    def mli_65(self, p):
        self.quit = True
        return 0


def render_png(emu, fn):
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 14)
    cw, ch = 9, 18
    img = Image.new('RGB', (80 * cw + 20, 24 * ch + 20), (0, 0, 0))
    d = ImageDraw.Draw(img)
    fg = (230, 230, 230)
    for r, row in enumerate(emu.cells()):
        for c, (chr_, inv, mt) in enumerate(row):
            x, y = 10 + c * cw, 10 + r * ch
            if inv:
                d.rectangle([x, y, x + cw - 1, y + ch - 1], fill=fg)
            col = (0, 0, 0) if inv else fg
            if mt:
                if chr_ == '▕': d.line([x + cw - 2, y, x + cw - 2, y + ch], fill=fg, width=2)
                elif chr_ == '▏': d.line([x + 1, y, x + 1, y + ch], fill=fg, width=2)
                elif chr_ == '‾': d.line([x, y + 1, x + cw, y + 1], fill=fg, width=2)
                else: d.text((x, y), chr_, font=font, fill=col)
            elif chr_ == '_':
                d.line([x, y + ch - 2, x + cw, y + ch - 2], fill=col, width=2)
            else:
                d.text((x, y), chr_, font=font, fill=col)
    img.save(fn)


class FakeKegs:
    """The KEGS disk image API (WDM $58,$EA), backed by a host folder."""
    def __init__(self, folder):
        self.folder = folder
        self.drives = {}            # slot*16+drive -> host path
        self.calls = []
        self.on_mount = None        # (emu, sd, path) -> called after MOUNT
        self.last = []
    def _get(self, emu, a): return emu.mem.m[a & 0xFFFF]
    def _put(self, emu, a, v): emu.mem.m[a & 0xFFFF] = v & 0xFF
    def _name(self, emu, a, name):
        n = name[:27]
        self._put(emu, a, len(n))
        for i in range(27):
            self._put(emu, a + 1 + i, ord(n[i]) if i < len(n) else 0)
    def _drive_with(self, path):
        for sd, p in self.drives.items():
            if p == path: return sd
        return 0
    def call(self, emu):
        cpu = emu.cpu
        cmd, blk = cpu.a, cpu.x | (cpu.y << 8)
        g = lambda o: self._get(emu, blk + o)
        res, err = 0, False
        import os
        if cmd == 0:
            res, cpu.x = ord('K'), 1
            self.calls.append(('id',))
        elif cmd == 1:
            buf, mx, ln = g(0) | g(1) << 8, g(2), g(3)
            sub = bytes(g(4 + i) for i in range(ln)).decode()
            d = os.path.join(self.folder, sub)
            self.calls.append(('list', sub))
            if '..' in sub or not os.path.isdir(d):
                res, err = 2, True
            else:
                ents = []
                for n in os.listdir(d):
                    if n.startswith('.'): continue
                    full = os.path.join(d, n)
                    if os.path.isdir(full): ents.append((1, n, full))
                    elif n.lower().endswith(('.po', '.dsk', '.2mg', '.hdv', '.woz')): ents.append((2, n, full))
                ents.sort(key=lambda e: (e[0], e[1].lower()))
                self.last = ents
                for i, (k, n, full) in enumerate(ents[:mx]):
                    e = buf + i * 32
                    kb = 0 if k == 1 else min((os.path.getsize(full) + 1023) >> 10, 65535)
                    self._put(emu, e, k); self._put(emu, e + 1, 0 if k == 1 else self._drive_with(full))
                    self._put(emu, e + 2, kb); self._put(emu, e + 3, kb >> 8)
                    self._name(emu, e + 4, n)
                res = min(len(ents), mx)
        elif cmd == 2:
            idx, sd, prot = g(0), g(1), g(2)
            self.calls.append(('mount', idx, sd, prot))
            k, n, full = self.last[idx]
            if sd == 0:
                sz = os.path.getsize(full)
                slot = 6 if sz <= 250000 else (5 if sz <= 1700000 else 7)
                sd = next((slot * 16 + d for d in (1, 2) if slot * 16 + d not in self.drives
                           and slot * 16 + d != prot),
                          next(slot * 16 + d for d in (1, 2) if slot * 16 + d != prot))
            self.drives = {a: b for a, b in self.drives.items() if b != full}
            self.drives[sd] = full
            if self.on_mount: self.on_mount(emu, sd, full)
            res = sd
        elif cmd == 3:
            sd = g(1)
            self.calls.append(('eject', sd))
            self.drives.pop(sd, None)
            res = sd
        elif cmd == 4:
            buf = g(0) | g(1) << 8
            order = [0x51, 0x52, 0x61, 0x62] + [0x71 + i for i in range(8)]
            for i, sd in enumerate(order):
                e = buf + i * 32
                p = self.drives.get(sd)
                self._put(emu, e, sd); self._put(emu, e + 1, 1 if p else 0)
                self._put(emu, e + 2, 0); self._put(emu, e + 3, 0)
                self._name(emu, e + 4, os.path.basename(p) if p else '')
            res = 12
            self.calls.append(('drives',))
        else:
            res, err = 1, True
        cpu.a = res & 0xFF
        cpu.p = (cpu.p | 1) if err else (cpu.p & ~1)
