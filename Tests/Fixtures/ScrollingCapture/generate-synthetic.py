"""Generate only the checked-in synthetic PNG fixture, using Python's standard library.
No screen capture. Coordinates describe a document independent of the stitcher.
"""
import json
import pathlib
import struct
import zlib

ROOT = pathlib.Path(__file__).resolve().parent / 'synthetic-sticky'
WIDTH = 240
MASK = (1 << 64) - 1


def row(y):
    pixels = bytearray()
    for x in range(WIDTH):
        value = ((y // 8) * 0x9e3779b97f4a7c15 & MASK) ^ (x // 16)
        value = ((value ^ (value >> 30)) * 0xbf58476d1ce4e5b9) & MASK
        value = ((value ^ (value >> 27)) * 0x94d049bb133111eb) & MASK
        value ^= value >> 31
        pixels.extend((value & 255, (value >> 8) & 255, (value >> 16) & 255, 255))
    return bytes(pixels)


def png(name, rows):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    raw = b''.join(b'\x00' + r for r in rows)
    header = struct.pack('>IIBBBBB', WIDTH, len(rows), 8, 6, 0, 0, 0)
    (ROOT / name).write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header)
                            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


ROOT.mkdir(parents=True, exist_ok=True)
for index, offset in enumerate([0, 80, 160]):
    png(f'frame-{index}.png', [bytes([11, 22, 33, 255]) * WIDTH] * 31
        + [row(y) for y in range(offset, offset + 400)]
        + [bytes([44, 55, 66, 255]) * WIDTH] * 27)
png('reference.png', [row(y) for y in range(560)])
manifest = {
    'version': 1,
    'provenance': {'kind': 'synthetic', 'source': 'generate-synthetic.py; deterministic coloured cells; no screen content',
                   'authorization': 'ticket 34 synthetic fixture', 'osBuild': 'not applicable; generated PNG bytes'},
    'frames': [{'file': f'frame-{i}.png', 'expectedVerticalStep': 80} for i in range(3)],
    'reference': 'reference.png', 'expectedWidth': WIDTH, 'expectedHeight': 560, 'heightTolerance': 0,
    'uniqueBands': [{'referenceRow': y, 'height': 16} for y in range(0, 560, 16)]
}
(ROOT / 'sequence.json').write_text(json.dumps(manifest, indent=2) + '\n')
