#!/usr/bin/env python3
"""
Minimal c1541 replacement for the GEOS/Mega65 build.

Reads c1541-style commands from stdin (one per line), exactly like the
Makefile pipes them into VICE's c1541:

    echo format geos,00 d81 geos.d81 | mkdisk.py
    echo write compressed.prg geos   | mkdisk.py geos.d81
    echo 'delete geos "geos kernal"' | mkdisk.py geos.d81

Supported image types: .d64 (35 tracks) and .d81.
Supported commands: format, write, delete, dir.
Not supported: geoswrite (use VICE's c1541 for that).

Use it with:  make C1541="python3 tools/mkdisk.py"
"""
import os
import shlex
import sys

PETSCII_PAD = 0xA0


def d64_spt(track):
    if track <= 17:
        return 21
    if track <= 24:
        return 19
    if track <= 30:
        return 18
    return 17


class Image:
    def __init__(self, path, kind=None):
        self.path = path
        self.kind = kind or os.path.splitext(path)[1].lower().lstrip(".")
        if self.kind not in ("d64", "d81"):
            raise SystemExit(f"mkdisk: unsupported image type: {path}")
        if self.kind == "d81":
            self.tracks, self.dirtrack = 80, 40
        else:
            self.tracks, self.dirtrack = 35, 18
        self.data = bytearray(self.size())
        if os.path.exists(path):
            with open(path, "rb") as f:
                raw = f.read()
            if len(raw) < self.size():
                raise SystemExit(f"mkdisk: {path} is too small for a {self.kind}")
            self.data[:] = raw[: self.size()]

    # --- geometry ---------------------------------------------------------
    def spt(self, track):
        return 40 if self.kind == "d81" else d64_spt(track)

    def size(self):
        return sum(self.spt(t) for t in range(1, self.tracks + 1)) * 256

    def offset(self, track, sector):
        if not (1 <= track <= self.tracks) or not (0 <= sector < self.spt(track)):
            raise SystemExit(f"mkdisk: illegal track/sector {track}/{sector}")
        return (sum(self.spt(t) for t in range(1, track)) + sector) * 256

    def sector(self, track, sector):
        o = self.offset(track, sector)
        return memoryview(self.data)[o:o + 256]

    # --- BAM --------------------------------------------------------------
    def bam_entry(self, track):
        """Return (buffer, offset of free count, offset of bitmap, bitmap bytes)."""
        if self.kind == "d64":
            return self.sector(18, 0), 4 * track, 4 * track + 1, 3
        if track <= 40:
            return self.sector(40, 1), 0x10 + 6 * (track - 1), 0x11 + 6 * (track - 1), 5
        return self.sector(40, 2), 0x10 + 6 * (track - 41), 0x11 + 6 * (track - 41), 5

    def is_free(self, track, sector):
        buf, _, bm, _ = self.bam_entry(track)
        return bool(buf[bm + sector // 8] & (1 << (sector % 8)))

    def set_used(self, track, sector, used=True):
        buf, cnt, bm, _ = self.bam_entry(track)
        bit = 1 << (sector % 8)
        if used and buf[bm + sector // 8] & bit:
            buf[bm + sector // 8] &= ~bit & 0xFF
            buf[cnt] -= 1
        elif not used and not buf[bm + sector // 8] & bit:
            buf[bm + sector // 8] |= bit
            buf[cnt] += 1

    def track_order(self):
        """Allocate outward from the directory track, like the CBM DOS."""
        d = self.dirtrack
        for i in range(1, self.tracks):
            for t in (d - i, d + i):
                if 1 <= t <= self.tracks:
                    yield t

    def alloc(self, track_hint=None):
        for t in self.track_order():
            if t == self.dirtrack:
                continue
            for s in range(self.spt(t)):
                if self.is_free(t, s):
                    self.set_used(t, s)
                    return t, s
        raise SystemExit("mkdisk: disk full")

    def blocks_free(self):
        total = 0
        for t in range(1, self.tracks + 1):
            if t == self.dirtrack:
                continue
            buf, cnt, _, _ = self.bam_entry(t)
            total += buf[cnt]
        return total

    # --- format -----------------------------------------------------------
    def format(self, name, ident):
        self.data[:] = bytes(self.size())
        name_b = petscii(name, 16)
        id_b = petscii(ident, 2)
        if self.kind == "d81":
            hdr = self.sector(40, 0)
            hdr[0:3] = bytes([40, 3, 0x44])
            hdr[4:0x14] = name_b
            hdr[0x14:0x16] = bytes([PETSCII_PAD] * 2)
            hdr[0x16:0x18] = id_b
            hdr[0x18:0x1D] = bytes([PETSCII_PAD, 0x33, 0x44, PETSCII_PAD, PETSCII_PAD])
            for sec, link in ((1, (40, 2)), (2, (0, 0xFF))):
                b = self.sector(40, sec)
                b[0:8] = bytes([link[0], link[1], 0x44, 0xBB, id_b[0], id_b[1], 0xC0, 0])
                first = 1 if sec == 1 else 41
                for t in range(first, first + 40):
                    _, cnt, bm, _ = self.bam_entry(t)
                    b[cnt] = 40
                    b[bm:bm + 5] = b"\xff" * 5
        else:
            bam = self.sector(18, 0)
            bam[0:4] = bytes([18, 1, 0x41, 0])
            for t in range(1, 36):
                n = d64_spt(t)
                bam[4 * t] = n
                bits = (1 << n) - 1
                bam[4 * t + 1:4 * t + 4] = bits.to_bytes(3, "little")
            bam[0x90:0xA0] = name_b
            bam[0xA0:0xA2] = bytes([PETSCII_PAD] * 2)
            bam[0xA2:0xA4] = id_b
            bam[0xA4:0xAB] = bytes([PETSCII_PAD, 0x32, 0x41] + [PETSCII_PAD] * 4)
        d = self.dirtrack
        first_dir = 3 if self.kind == "d81" else 1
        for s in range(first_dir + 1):
            if self.kind == "d64" and s == 0:
                self.set_used(d, 0)
            else:
                self.set_used(d, s)
        self.sector(d, first_dir)[0:2] = bytes([0, 0xFF])

    # --- directory --------------------------------------------------------
    def dir_sectors(self):
        t, s = (40, 3) if self.kind == "d81" else (18, 1)
        seen = set()
        while t and (t, s) not in seen:
            seen.add((t, s))
            yield t, s
            b = self.sector(t, s)
            t, s = b[0], b[1]

    def entries(self):
        for t, s in self.dir_sectors():
            b = self.sector(t, s)
            for i in range(8):
                yield b, i * 32

    def find(self, name):
        want = petscii(name, 16)
        for b, o in self.entries():
            if b[o + 2] & 0x07 and bytes(b[o + 5:o + 21]) == want:
                return b, o
        return None

    def free_entry(self):
        for b, o in self.entries():
            if b[o + 2] == 0:
                return b, o
        # extend directory on the directory track
        last = list(self.dir_sectors())[-1]
        for s in range(self.spt(self.dirtrack)):
            if self.is_free(self.dirtrack, s):
                self.set_used(self.dirtrack, s)
                self.sector(*last)[0:2] = bytes([self.dirtrack, s])
                nb = self.sector(self.dirtrack, s)
                nb[:] = bytes(256)
                nb[0:2] = bytes([0, 0xFF])
                return nb, 0
        raise SystemExit("mkdisk: directory full")

    # --- files ------------------------------------------------------------
    def write(self, src, name, ftype=0x82):
        with open(src, "rb") as f:
            payload = f.read()
        if self.find(name):
            raise SystemExit(f"mkdisk: file '{name}' already exists")
        chunks = [payload[i:i + 254] for i in range(0, len(payload), 254)] or [b""]
        blocks = [self.alloc() for _ in chunks]
        for i, (chunk, (t, s)) in enumerate(zip(chunks, blocks)):
            b = self.sector(t, s)
            b[:] = bytes(256)
            if i + 1 < len(blocks):
                b[0:2] = bytes(blocks[i + 1])
            else:
                b[0:2] = bytes([0, len(chunk) + 1])
            b[2:2 + len(chunk)] = chunk
        b, o = self.free_entry()
        b[o + 2:o + 32] = bytes(30)
        b[o + 2] = ftype
        b[o + 3:o + 5] = bytes(blocks[0])
        b[o + 5:o + 21] = petscii(name, 16)
        b[o + 30:o + 32] = len(blocks).to_bytes(2, "little")

    def delete(self, name):
        hit = self.find(name)
        if not hit:
            return False
        b, o = hit
        t, s = b[o + 3], b[o + 4]
        seen = set()
        while t and (t, s) not in seen:
            seen.add((t, s))
            self.set_used(t, s, False)
            nxt = self.sector(t, s)
            t, s = nxt[0], nxt[1]
        b[o + 2] = 0
        return True

    def listing(self):
        for b, o in self.entries():
            if b[o + 2] & 0x07:
                n = bytes(b[o + 5:o + 21]).rstrip(bytes([PETSCII_PAD])).decode("latin-1").lower()
                print(f'{int.from_bytes(b[o+30:o+32], "little"):<5}"{n}"')
        print(f"{self.blocks_free()} blocks free.")

    def save(self):
        with open(self.path, "wb") as f:
            f.write(self.data)


def petscii(text, length):
    raw = text.upper().encode("latin-1")[:length]
    return raw + bytes([PETSCII_PAD] * (length - len(raw)))


def main():
    image = Image(sys.argv[1]) if len(sys.argv) > 1 else None
    for line in sys.stdin:
        args = shlex.split(line)
        if not args:
            continue
        cmd, rest = args[0].lower(), args[1:]
        if cmd == "format":
            name, _, ident = rest[0].partition(",")
            if len(rest) >= 3:
                image = Image(rest[2], rest[1].lower())
            if image is None:
                raise SystemExit("mkdisk: format needs an image")
            image.format(name, ident or "00")
        elif cmd == "write":
            if image is None:
                raise SystemExit("mkdisk: no image attached")
            image.write(rest[0], rest[1] if len(rest) > 1 else os.path.basename(rest[0]))
        elif cmd == "delete":
            for n in rest:
                image.delete(n)
        elif cmd in ("dir", "list"):
            image.listing()
        else:
            raise SystemExit(f"mkdisk: unsupported command '{cmd}' (use VICE c1541)")
        image.save()


if __name__ == "__main__":
    main()
