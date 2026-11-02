"""Give a creeper 8x15 bitmap font whole-pixel metrics and a PostScript name."""

import sys

from fontTools.ttLib import TTFont

# 64 units per pixel, so the 15px strike lands every glyph on whole pixels.
UNIT = 64
WIDTH, ASCENT, DESCENT = 8 * UNIT, 12 * UNIT, 3 * UNIT

src, dst, name = sys.argv[1:4]
font = TTFont(src)
font["head"].unitsPerEm = 15 * UNIT
font["head"].yMax, font["head"].yMin = ASCENT, -DESCENT
font["head"].xMin, font["head"].xMax = 0, WIDTH
hhea = font["hhea"]
hhea.ascent, hhea.descent, hhea.lineGap = ASCENT, -DESCENT, 0
hhea.advanceWidthMax = WIDTH
os2 = font["OS/2"]
os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = ASCENT, -DESCENT, 0
os2.usWinAscent, os2.usWinDescent = ASCENT, DESCENT
os2.xAvgCharWidth = WIDTH
for glyph in font["hmtx"].metrics:
    font["hmtx"][glyph] = (WIDTH, 0)
font["name"].setName(name, 6, 3, 1, 0x409)
font.save(dst)
