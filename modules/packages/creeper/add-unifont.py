"""Add the Unifont glyphs a creeper 8x15 BDF lacks, cut to 15 rows, as an OTB."""

import sys
import tempfile
import unicodedata
from pathlib import Path

import fontforge
from fontTools.ttLib import TTFont

# Unifont's whole BMP and Plane 1 overflow a 65535-glyph font, so skip the
# CJK and Hangul blocks, which Noto CJK draws well, and Private Use, which
# belongs to Nerd Font icons.
SKIP = [(0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xAC00, 0xD7A3), (0xE000, 0xF8FF)]
KEEP_ABOVE = (0x1F000, 0x1FFFF)
ROWS = 16


def wanted(cp: int) -> bool:
    """Say whether a codepoint sits in a block worth taking."""
    if cp > 0xFFFF and not KEEP_ABOVE[0] <= cp <= KEEP_ABOVE[1]:
        return False
    return not any(lo <= cp <= hi for lo, hi in SKIP)


def center_ink(rows: list[str]) -> tuple[list[str], int, int]:
    """Crop 16px rows to their ink and center it on one 8px cell.

    Returns the rows, their width and the x offset, which goes negative when
    the ink is wider than the cell and spills into its neighbours.
    """
    bits = [int(row, 16) for row in rows]
    ink = 0
    for row in bits:
        ink |= row
    if not ink:
        return ["00"] * len(rows), 8, 0
    left = 15 - ink.bit_length() + 1
    right = 15 - (ink & -ink).bit_length() + 1
    width = right - left + 1
    pad = -width % 8
    digits = (width + pad) // 4
    cropped = [f"{(row >> (15 - right)) << pad:0{digits}X}" for row in bits]
    return cropped, width, (8 - width) // 2


def glyph(cp: int, rows: list[str], width: int, xoff: int = 0, advance: int = 0) -> str:
    """Write one BDF glyph, dropping a blank edge row to fit a 15px cell."""
    blank = "0" * len(rows[0])
    rows = rows[:-1] if rows[0] != blank and rows[-1] == blank else rows[1:]
    # FontForge maps Plane 1 glyphs in the cmap only under AGL names.
    name = f"uni{cp:04X}" if cp <= 0xFFFF else f"u{cp:X}"
    advance = advance or width
    return "\n".join(
        [
            f"STARTCHAR {name}",
            f"ENCODING {cp}",
            f"SWIDTH {advance * 60} 0",
            f"DWIDTH {advance} 0",
            f"BBX {width} 15 {xoff} -3",
            "BITMAP",
            *rows,
            "ENDCHAR",
        ]
    )


bdf, otb, out, *hexes = sys.argv[1:]
have = set(TTFont(otb).getBestCmap())
added = []
for path in hexes:
    for line in Path(path).read_text().splitlines():
        cp, bits = line.split(":")
        cp = int(cp, 16)
        step = len(bits) // ROWS
        if cp in have or not wanted(cp):
            continue
        rows = [bits[i : i + step] for i in range(0, len(bits), step)]
        char = chr(cp)
        # A 16px glyph on a one-cell character gets centered on its cell, so
        # wide symbols spill evenly; script glyphs are left to fallback.
        if step == 4 and unicodedata.east_asian_width(char) not in ("W", "F"):
            if not unicodedata.category(char).startswith("S"):
                continue
            entry = glyph(cp, *center_ink(rows), advance=8)
        else:
            entry = glyph(cp, rows, step * 4)
        have.add(cp)
        added.append(entry)

lines = Path(bdf).read_text().splitlines()
for i, line in enumerate(lines):
    if line.startswith("FONT "):
        lines[i] = line.replace("ISO8859-1", "ISO10646-1")
    elif line.startswith("CHARSET_REGISTRY "):
        lines[i] = 'CHARSET_REGISTRY "ISO10646"'
    elif line.startswith("CHARS "):
        lines[i] = f"CHARS {int(line.split()[1]) + len(added)}"
end = lines.index("ENDFONT")

# fonttosfnt drops Plane 1, so FontForge writes the OTB.
with tempfile.TemporaryDirectory() as tmp:
    merged = Path(tmp) / "merged.bdf"
    merged.write_text("\n".join(lines[:end] + added + lines[end:]) + "\n")
    font = fontforge.open(str(merged))
    font.encoding = "UnicodeFull"
    font.generate(out, bitmap_type="otb")
