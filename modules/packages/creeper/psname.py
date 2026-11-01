"""Add the PostScript name fontdb requires to a font."""

import sys

from fontTools.ttLib import TTFont

src, dst, name = sys.argv[1:4]
font = TTFont(src)
font["name"].setName(name, 6, 3, 1, 0x409)
font.save(dst)
