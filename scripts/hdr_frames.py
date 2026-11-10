"""Synthetic, correctly encoded BT.2020 HLG/PQ 10-bit YCbCr frames.

No downloaded/user media. PQ levels are absolute nits; HLG uses scene-relative
levels normalized by 1000, not a display-luminance calibration. Binary frame
numbers, neutral steps and primary patches check Apple's SDR conversion.
"""
import array
import math
import sys

mode, count = sys.argv[1], int(sys.argv[2])
width, height = 160, 96

def transfer(nits):
    if mode == "hlg":
        scene = nits / 1000
        a, b, c = 0.17883277, 0.28466892, 0.55991073
        return math.sqrt(3 * scene) if scene <= 1 / 12 else a * math.log(12 * scene - b) + c
    m1, m2, c1, c2, c3 = 2610 / 16384, 2523 / 32, 3424 / 4096, 2413 / 128, 2392 / 128
    power = (nits / 10000) ** m1
    return ((c1 + c2 * power) / (1 + c3 * power)) ** m2

def yuv(rgb):
    r, g, b = map(transfer, rgb)
    y = 0.2627 * r + 0.6780 * g + 0.0593 * b
    return tuple(round(max(0, min(1023, v))) for v in
                 (64 + 876 * y, 512 + 896 * (b - y) / (2 * (1 - 0.0593)),
                  512 + 896 * (r - y) / (2 * (1 - 0.2627))))

greys = [yuv((level,) * 3) for level in (0, 2, 10, 40, 100, 200, 400, 1000)]
colors = [yuv(rgb) for rgb in ((1000, 0, 0), (0, 1000, 0), (0, 0, 1000), (100, 100, 100))]
for number in range(count):
    planes = [array.array("H") for _ in range(3)]
    for y in range(height):
        for x in range(width):
            if y < 32:
                pixel = greys[7 if number & (1 << (x // 20)) else 0]
            elif y < 40:
                pixel = greys[0]
            elif y < 64:
                pixel = greys[x // 20]
            else:
                pixel = colors[x // 40]
            for plane, value in zip(planes, pixel):
                plane.append(value)
    for plane in planes:
        if sys.byteorder != "little":
            plane.byteswap()
        sys.stdout.buffer.write(plane.tobytes())
