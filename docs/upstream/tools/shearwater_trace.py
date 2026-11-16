# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Copyright (C) 2026 Egbert de Pauw
"""Decode a libdivecomputer BLE trace of a Shearwater Petrel download.

The input is a text trace with one BLE frame per line, as in Anchorline's
test/fixtures/raw/subsurface2.combined.txt:

    W (10 bytes): 01 00 ff 01 04 00 22 80 10 c0
    R (18 bytes): 01 00 01 ff 0c 00 62 80 10 42 ...

"W" is host to dive computer, "R" is dive computer to host. Each frame
starts with the 2-byte BLE header [nframes, index], followed by SLIP data.

For every download session (0x35 init, 0x36 blocks, 0x37 quit) this
prints the requested address and size, the payload length of every block,
whether each length is a multiple of 9 bytes (needed by libdc's
shearwater_common_decompress_lre), in which block the LRE end marker
falls, and how the session ended.

With --dump DIR it also writes, for use with petrel_replay.c:
    DIR/<address>.lre       the raw compressed stream of each dive
    DIR/<address>.bin       the decompressed dive (LRE, then XOR)
    DIR/manifest.bin        all manifest pages, concatenated

Usage: python3 -I shearwater_trace.py TRACE [--dump DIR]
"""
import os
import sys

END, ESC, ESC_END, ESC_ESC = 0xC0, 0xDB, 0xDC, 0xDD


def frames(path):
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line[:1] not in ('W', 'R') or ':' not in line:
                continue
            yield line[0], bytes(int(x, 16) for x in line.split(':', 1)[1].split())


def packets(path):
    """Yield (direction, payload) for every complete SLIP packet."""
    buf = {'W': bytearray(), 'R': bytearray()}
    esc = {'W': False, 'R': False}
    for d, frame in frames(path):
        for c in frame[2:]:  # skip the BLE [nframes, index] header
            if c == END:
                if buf[d]:
                    p = bytes(buf[d])
                    buf[d] = bytearray()
                    # FF 01 / 01 FF, length + 1, 00, payload
                    assert p[2] - 1 == len(p) - 4, 'bad length byte'
                    yield d, p[4:]
                continue
            if c == ESC:
                esc[d] = True
                continue
            if esc[d]:
                c = END if c == ESC_END else ESC if c == ESC_ESC else c
                esc[d] = False
            buf[d].append(c)


def lre(data, strict=False):
    """Decode like libdc. Returns (bytes, bit offset of end marker or None).

    strict=True applies libdc's check that the input is a whole number of
    9-bit values, and returns None if it is not.
    """
    nbits = len(data) * 8
    if strict and nbits % 9:
        return None
    out = bytearray()
    offset = 0
    while offset + 9 <= nbits:
        i, bit = divmod(offset, 8)
        word = (data[i] << 8) | (data[i + 1] if i + 1 < len(data) else 0)
        value = (word >> (16 - (bit + 9))) & 0x1FF
        if value & 0x100:
            out.append(value & 0xFF)
        elif value == 0:
            return bytes(out), offset
        else:
            out.extend(bytes(value))
        offset += 9
    return bytes(out), None


def main():
    path = sys.argv[1]
    dump = sys.argv[sys.argv.index('--dump') + 1] if '--dump' in sys.argv else None
    if dump:
        os.makedirs(dump, exist_ok=True)
    pk = list(packets(path))
    manifest = bytearray()
    i = 0
    while i < len(pk):
        d, p = pk[i]
        if d == 'W' and p[0] == 0x22:
            print(f'RDBI {p[1]:02x}{p[2]:02x} -> {pk[i + 1][1][3:].hex()}')
            i += 2
        elif d == 'W' and p[0] == 0x35:
            compressed = bool(p[1] & 0x10)
            address = int.from_bytes(p[3:7], 'big')
            size = int.from_bytes(p[7:10], 'big')
            init = pk[i + 1][1]
            i += 2
            blocks, ending = [], 'trace ends'
            while i < len(pk):
                d2, q = pk[i]
                if d2 == 'W' and q[0] == 0x36 and i + 1 < len(pk):
                    blocks.append(pk[i + 1][1])
                    i += 2
                elif d2 == 'W' and q[0] == 0x37:
                    ending = f'quit -> {pk[i + 1][1].hex()}'
                    i += 2
                    break
                else:
                    break
            naks = [b.hex() for b in blocks if b[0] == 0x7F]
            data = [b[2:] for b in blocks if b[0] == 0x76]
            lengths = sorted({len(b) for b in data})
            not9 = sum(1 for b in data if len(b) % 9)
            line = (f'{address:08x} size={size:#x} compressed={compressed} init={init.hex()} '
                    f'blocks={len(data)} lengths={lengths} not_multiple_of_9={not9} '
                    f'naks={naks} end={ending}')
            raw = b''.join(data)
            if compressed:
                marker = None
                for k, b in enumerate(data):  # per block, as libdc does
                    r = lre(b, strict=True)
                    if r is None:
                        marker = f'block {k + 1} rejected by the 9-bit check'
                        break
                    if r[1] is not None:
                        marker = f'block {k + 1} of {len(data)}'
                        break
                out, _ = lre(raw)
                line += f' | end marker in {marker} | decompressed={len(out)}'
                if dump:
                    x = bytearray(out)
                    for j in range(32, len(x)):
                        x[j] ^= x[j - 32]
                    with open(os.path.join(dump, f'{address:08x}.lre'), 'wb') as f:
                        f.write(raw)
                    with open(os.path.join(dump, f'{address:08x}.bin'), 'wb') as f:
                        f.write(x)
            else:
                manifest += raw
            print(line)
        else:
            i += 1
    if dump and manifest:
        with open(os.path.join(dump, 'manifest.bin'), 'wb') as f:
            f.write(manifest)


if __name__ == '__main__':
    main()
