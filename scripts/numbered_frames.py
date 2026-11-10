"""Stream synthetic RGB frames using only Python's standard library.

Top eight blocks encode the frame number in binary; the lower digits are a
small built-in bitmap font. No font package, private media or drawtext filter.
"""
import sys

digits = [
    ["111", "101", "101", "101", "111"],
    ["010", "110", "010", "010", "111"],
    ["111", "001", "111", "100", "111"],
    ["111", "001", "111", "001", "111"],
    ["101", "101", "111", "001", "001"],
    ["111", "100", "111", "001", "111"],
    ["111", "100", "111", "101", "111"],
    ["111", "001", "010", "010", "010"],
    ["111", "101", "111", "101", "111"],
    ["111", "101", "111", "001", "111"],
]
for number in range(int(sys.argv[1])):
    pixels = bytearray([56] * (160 * 96 * 3))
    for y in range(32):
        for x in range(160):
            offset = (y * 160 + x) * 3
            level = 255 if number & (1 << (x // 20)) else 0
            pixels[offset:offset + 3] = bytes([level]) * 3
    for column, digit in enumerate(str(number)):
        for row, line in enumerate(digits[int(digit)]):
            for cell, filled in enumerate(line):
                if filled == "1":
                    for dy in range(4):
                        for dx in range(4):
                            x, y = 10 + column * 16 + cell * 4 + dx, 55 + row * 4 + dy
                            offset = (y * 160 + x) * 3
                            pixels[offset:offset + 3] = b"\xff\xff\xff"
    sys.stdout.buffer.write(pixels)
