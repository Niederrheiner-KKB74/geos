#!/usr/bin/env python3
"""End-to-end check of a GEOS65 boot image: extract AUTOBOOT.C65 from the
D81, run its real Exomizer decruncher in a minimal 6502 emulator, and
compare the unpacked $5000-$FFFF with kernal_combined.prg.

usage: check-boot-image.py image.d81 kernal_combined.prg kernel.map
(make d81-check). Exits with status 1 if the unpacked kernal differs.
"""
import importlib.util
import os
import re
import sys

spec = importlib.util.spec_from_file_location(
    "mk", os.path.join(os.path.dirname(os.path.abspath(__file__)), "mkdisk.py"))
mk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mk)


def read_file(img, name):
    b, o = img.find(name)
    t, s = b[o + 3], b[o + 4]
    out = b""
    while True:
        x = img.sector(t, s)
        if x[0] == 0:
            return out + bytes(x[2:x[1] + 1])
        out += bytes(x[2:])
        t, s = x[0], x[1]


class CPU:
    def __init__(self, mem):
        self.m = mem
        self.a = self.x = self.y = 0
        self.sp = 0xFF
        self.c = self.z = self.n = self.v = 0
        self.pc = 0

    # --- helpers
    def rd(self, a):
        return self.m[a & 0xFFFF]

    def wr(self, a, v):
        self.m[a & 0xFFFF] = v & 0xFF

    def rd16(self, a):
        return self.rd(a) | self.rd(a + 1) << 8

    def zp16(self, a):
        return self.rd(a & 0xFF) | self.rd((a + 1) & 0xFF) << 8

    def push(self, v):
        self.wr(0x100 + self.sp, v)
        self.sp = (self.sp - 1) & 0xFF

    def pop(self):
        self.sp = (self.sp + 1) & 0xFF
        return self.rd(0x100 + self.sp)

    def nz(self, v):
        v &= 0xFF
        self.z = int(v == 0)
        self.n = v >> 7
        return v

    def p(self):
        return self.n << 7 | self.v << 6 | 0x30 | self.z << 1 | self.c

    def setp(self, v):
        self.n, self.v, self.z, self.c = v >> 7 & 1, v >> 6 & 1, v >> 1 & 1, v & 1

    # --- addressing: returns effective address
    def ea(self, mode):
        pc = self.pc
        if mode == "imm":
            self.pc += 1
            return pc
        if mode == "zp":
            self.pc += 1
            return self.rd(pc)
        if mode == "zpx":
            self.pc += 1
            return (self.rd(pc) + self.x) & 0xFF
        if mode == "zpy":
            self.pc += 1
            return (self.rd(pc) + self.y) & 0xFF
        if mode == "abs":
            self.pc += 2
            return self.rd16(pc)
        if mode == "abx":
            self.pc += 2
            return (self.rd16(pc) + self.x) & 0xFFFF
        if mode == "aby":
            self.pc += 2
            return (self.rd16(pc) + self.y) & 0xFFFF
        if mode == "izx":
            self.pc += 1
            return self.zp16(self.rd(pc) + self.x)
        if mode == "izy":
            self.pc += 1
            return (self.zp16(self.rd(pc)) + self.y) & 0xFFFF
        raise ValueError(mode)

    def adc(self, v):
        r = self.a + v + self.c
        self.v = int(((self.a ^ r) & (v ^ r) & 0x80) != 0)
        self.c = int(r > 0xFF)
        self.a = self.nz(r)

    def cmp(self, reg, v):
        r = reg - v
        self.c = int(r >= 0)
        self.nz(r)

    def step(self):
        op = self.rd(self.pc)
        self.pc += 1
        if op not in OPS:
            raise RuntimeError(f"unsupported opcode {op:02X} at {self.pc - 1:04X}")
        name, mode = OPS[op]
        getattr(self, "op_" + name)(mode)

    # --- instructions
    def op_lda(self, m): self.a = self.nz(self.rd(self.ea(m)))
    def op_ldx(self, m): self.x = self.nz(self.rd(self.ea(m)))
    def op_ldy(self, m): self.y = self.nz(self.rd(self.ea(m)))
    def op_sta(self, m): self.wr(self.ea(m), self.a)
    def op_stx(self, m): self.wr(self.ea(m), self.x)
    def op_sty(self, m): self.wr(self.ea(m), self.y)
    def op_adc(self, m): self.adc(self.rd(self.ea(m)))
    def op_sbc(self, m): self.adc(self.rd(self.ea(m)) ^ 0xFF)
    def op_and(self, m): self.a = self.nz(self.a & self.rd(self.ea(m)))
    def op_ora(self, m): self.a = self.nz(self.a | self.rd(self.ea(m)))
    def op_eor(self, m): self.a = self.nz(self.a ^ self.rd(self.ea(m)))
    def op_cmp(self, m): self.cmp(self.a, self.rd(self.ea(m)))
    def op_cpx(self, m): self.cmp(self.x, self.rd(self.ea(m)))
    def op_cpy(self, m): self.cmp(self.y, self.rd(self.ea(m)))

    def op_bit(self, m):
        v = self.rd(self.ea(m))
        self.z = int((self.a & v) == 0)
        self.n, self.v = v >> 7 & 1, v >> 6 & 1

    def _rmw(self, m, f):
        if m == "acc":
            self.a = self.nz(f(self.a))
        else:
            a = self.ea(m)
            self.wr(a, self.nz(f(self.rd(a))))

    def op_asl(self, m):
        def f(v):
            self.c = v >> 7
            return v << 1 & 0xFF
        self._rmw(m, f)

    def op_lsr(self, m):
        def f(v):
            self.c = v & 1
            return v >> 1
        self._rmw(m, f)

    def op_rol(self, m):
        def f(v):
            c = self.c
            self.c = v >> 7
            return (v << 1 | c) & 0xFF
        self._rmw(m, f)

    def op_ror(self, m):
        def f(v):
            c = self.c
            self.c = v & 1
            return v >> 1 | c << 7
        self._rmw(m, f)

    def op_inc(self, m): self._rmw(m, lambda v: (v + 1) & 0xFF)
    def op_dec(self, m): self._rmw(m, lambda v: (v - 1) & 0xFF)
    def op_inx(self, m): self.x = self.nz(self.x + 1)
    def op_iny(self, m): self.y = self.nz(self.y + 1)
    def op_dex(self, m): self.x = self.nz(self.x - 1)
    def op_dey(self, m): self.y = self.nz(self.y - 1)
    def op_tax(self, m): self.x = self.nz(self.a)
    def op_tay(self, m): self.y = self.nz(self.a)
    def op_txa(self, m): self.a = self.nz(self.x)
    def op_tya(self, m): self.a = self.nz(self.y)
    def op_tsx(self, m): self.x = self.nz(self.sp)
    def op_txs(self, m): self.sp = self.x
    def op_pha(self, m): self.push(self.a)
    def op_pla(self, m): self.a = self.nz(self.pop())
    def op_php(self, m): self.push(self.p())
    def op_plp(self, m): self.setp(self.pop())
    def op_clc(self, m): self.c = 0
    def op_sec(self, m): self.c = 1
    def op_clv(self, m): self.v = 0
    def op_cld(self, m): pass
    def op_sei(self, m): pass
    def op_cli(self, m): pass
    def op_nop(self, m): pass

    def op_jmp(self, m):
        a = self.rd16(self.pc)
        self.pc = self.rd16(a) if m == "ind" else a

    def op_jsr(self, m):
        t = self.rd16(self.pc)
        r = self.pc + 1
        self.push(r >> 8)
        self.push(r & 0xFF)
        self.pc = t

    def op_rts(self, m):
        lo = self.pop()
        self.pc = (self.pop() << 8 | lo) + 1

    def _br(self, cond):
        off = self.rd(self.pc)
        self.pc += 1
        if cond:
            self.pc = (self.pc + (off - 256 if off & 0x80 else off)) & 0xFFFF

    def op_bcc(self, m): self._br(not self.c)
    def op_bcs(self, m): self._br(self.c)
    def op_beq(self, m): self._br(self.z)
    def op_bne(self, m): self._br(not self.z)
    def op_bmi(self, m): self._br(self.n)
    def op_bpl(self, m): self._br(not self.n)
    def op_bvc(self, m): self._br(not self.v)
    def op_bvs(self, m): self._br(self.v)


OPS = {}
def _ops(name, **modes):
    for mode, code in modes.items():
        OPS[code] = (name, mode)

_ops("lda", imm=0xA9, zp=0xA5, zpx=0xB5, abs=0xAD, abx=0xBD, aby=0xB9, izx=0xA1, izy=0xB1)
_ops("ldx", imm=0xA2, zp=0xA6, zpy=0xB6, abs=0xAE, aby=0xBE)
_ops("ldy", imm=0xA0, zp=0xA4, zpx=0xB4, abs=0xAC, abx=0xBC)
_ops("sta", zp=0x85, zpx=0x95, abs=0x8D, abx=0x9D, aby=0x99, izx=0x81, izy=0x91)
_ops("stx", zp=0x86, zpy=0x96, abs=0x8E)
_ops("sty", zp=0x84, zpx=0x94, abs=0x8C)
for nm, base in (("ora", 0x00), ("and", 0x20), ("eor", 0x40), ("adc", 0x60), ("cmp", 0xC0), ("sbc", 0xE0)):
    _ops(nm, izx=base + 1, zp=base + 5, imm=base + 9, abs=base + 0xD, izy=base + 0x11,
         zpx=base + 0x15, aby=base + 0x19, abx=base + 0x1D)
_ops("cpx", imm=0xE0, zp=0xE4, abs=0xEC)
_ops("cpy", imm=0xC0, zp=0xC4, abs=0xCC)
_ops("bit", zp=0x24, abs=0x2C)
for nm, base in (("asl", 0x00), ("rol", 0x20), ("lsr", 0x40), ("ror", 0x60)):
    _ops(nm, zp=base + 6, acc=base + 0xA, abs=base + 0xE, zpx=base + 0x16, abx=base + 0x1E)
_ops("inc", zp=0xE6, zpx=0xF6, abs=0xEE, abx=0xFE)
_ops("dec", zp=0xC6, zpx=0xD6, abs=0xCE, abx=0xDE)
for nm, code in (("inx", 0xE8), ("iny", 0xC8), ("dex", 0xCA), ("dey", 0x88), ("tax", 0xAA),
                 ("tay", 0xA8), ("txa", 0x8A), ("tya", 0x98), ("tsx", 0xBA), ("txs", 0x9A),
                 ("pha", 0x48), ("pla", 0x68), ("php", 0x08), ("plp", 0x28), ("clc", 0x18),
                 ("sec", 0x38), ("clv", 0xB8), ("cld", 0xD8), ("sei", 0x78), ("cli", 0x58),
                 ("nop", 0xEA), ("rts", 0x60)):
    OPS[code] = (nm, "imp")
_ops("jmp", abs=0x4C, ind=0x6C)
_ops("jsr", abs=0x20)
for nm, code in (("bpl", 0x10), ("bmi", 0x30), ("bvc", 0x50), ("bvs", 0x70), ("bcc", 0x90),
                 ("bcs", 0xB0), ("bne", 0xD0), ("beq", 0xF0)):
    OPS[code] = (nm, "rel")


def main():
    img = mk.Image(sys.argv[1])
    prg = read_file(img, "AUTOBOOT.C65")
    combined = open(sys.argv[2], "rb").read()
    mapf = open(sys.argv[3]).read()
    uncr = int(re.search(r"uncruncher\s+([0-9A-F]{6})", mapf).group(1), 16)

    mem = bytearray(0x10000)
    load = prg[0] | prg[1] << 8
    mem[load:load + len(prg) - 2] = prg[2:]
    cpu = CPU(mem)
    cpu.pc = uncr
    cpu.push(0xFF)          # return to $FFFF+1 -> stop marker
    cpu.push(0xFE)
    steps = 0
    while cpu.pc != 0xFFFF:
        cpu.step()
        steps += 1
        if steps > 50_000_000:
            raise SystemExit("decruncher did not finish")
    want = combined[2:]
    got = bytes(mem[0x5000:0x5000 + len(want)])
    diff = sum(a != b for a, b in zip(got, want))
    print(f"AUTOBOOT.C65 load ${load:04X}, uncruncher ${uncr:04X}, {steps} steps")
    print(f"unpacked $5000-${0x5000 + len(want) - 1:04X} == kernal_combined.prg: {diff == 0} ({diff} bytes differ)")
    print("jump table $C2F5:", got[0xC2F5 - 0x5000:0xC2FE - 0x5000].hex(" "))
    if diff:
        sys.exit(1)


if __name__ == "__main__":
    main()
