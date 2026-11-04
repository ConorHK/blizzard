"""Trace a creeper OTB's 15px strike into square outlines, which macOS draws."""

import sys
from collections.abc import Iterator

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.removeOverlaps import removeOverlaps
from fontTools.ttLib.tables._g_l_y_f import Glyph
from fontTools.ttLib.tables.BitmapGlyphMetrics import (
    BigGlyphMetrics,
    SmallGlyphMetrics,
)
from fontTools.ttLib.tables.E_B_D_T_ import BitmapGlyph

Metrics = BigGlyphMetrics | SmallGlyphMetrics

PPEM = 15


def runs(bits: int, width: int) -> Iterator[tuple[int, int]]:
    """Yield the start and end of each lit run in a row of pixels."""
    start = None
    for x in range(width + 1):
        lit = x < width and bits >> (width - 1 - x) & 1
        if lit and start is None:
            start = x
        elif not lit and start is not None:
            yield start, x
            start = None


def bearings(metrics: Metrics) -> tuple[int, int]:
    """Read x and y bearings from big or small glyph metrics."""
    if isinstance(metrics, BigGlyphMetrics):
        return metrics.horiBearingX, metrics.horiBearingY
    return metrics.BearingX, metrics.BearingY


def trace(glyph: BitmapGlyph, metrics: Metrics, unit: int) -> Glyph:
    """Draw each lit run of the bitmap as one clockwise rectangle."""
    pen = TTGlyphPen(None)
    x0, y0 = bearings(metrics)
    for r in range(metrics.height):
        row = glyph.getRow(r, metrics=metrics)
        bits = int.from_bytes(row, "big") >> (len(row) * 8 - metrics.width)
        top = (y0 - r) * unit
        for start, end in runs(bits, metrics.width):
            left = (x0 + start) * unit
            right = (x0 + end) * unit
            pen.moveTo((left, top - unit))
            pen.lineTo((left, top))
            pen.lineTo((right, top))
            pen.lineTo((right, top - unit))
            pen.closePath()
    return pen.glyph()


def main() -> int:
    """Swap the bitmap tables of the font in argv[1] for outlines in argv[2]."""
    src, dst = sys.argv[1:3]
    font = TTFont(src)
    unit = font["head"].unitsPerEm // PPEM
    strike = next(s for s in font["EBLC"].strikes if s.bitmapSizeTable.ppemY == PPEM)
    bitmaps = font["EBDT"].strikeData[font["EBLC"].strikes.index(strike)]
    # Fixed-size glyphs keep their metrics in the index, the rest in the glyph.
    shared = {
        name: table.metrics
        for table in strike.indexSubTables
        if hasattr(table, "metrics")
        for name in table.names
    }
    glyf = newTable("glyf")
    glyf.glyphOrder = font.getGlyphOrder()
    glyf.glyphs = {
        name: trace(bitmaps[name], shared.get(name) or bitmaps[name].metrics, unit)
        if name in bitmaps
        else TTGlyphPen(None).glyph()
        for name in glyf.glyphOrder
    }
    font["glyf"], font["loca"] = glyf, newTable("loca")
    for tag in ("EBDT", "EBLC", "EBSC", "BDF "):
        if tag in font:
            del font[tag]
    # Joined squares leave no seams once antialiased.
    removeOverlaps(font)
    for name in font.getGlyphOrder():
        glyph = glyf[name]
        glyph.recalcBounds(glyf)
        advance, _ = font["hmtx"][name]
        font["hmtx"][name] = (advance, getattr(glyph, "xMin", 0))
    font.save(dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
