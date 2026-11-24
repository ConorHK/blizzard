"""Tests for the pane picker's reading of a terminal's paint."""

import unittest

from screens import parse, rgb

ESC = "\x1b"
# What hc attach --observe --history writes: the history, line feeds that push it off the
# viewer's screen, then the screen after the tab stops, the cursor, and whatever comes later.
PAINT = "".join(
    [
        f"{ESC}]10;?{ESC}\\{ESC}[c{ESC}[!p{ESC}[=0;1u{ESC}[?1049l{ESC}[H{ESC}[2J",
        f"old {ESC}[0m{ESC}[1m{ESC}[38;2;135;175;175mline{ESC}[0m\r\n",
        "second   \r\n",
        "\n\n\n",
        f"{ESC}[H{ESC}[2J{ESC}[?25l{ESC}[3g{ESC}[9G{ESC}H{ESC}[H",
        f"{ESC}[0m{ESC}[48;5;236m  {ESC}[0m{ESC}[31m{ESC}[48;5;236mred{ESC}[0m plain\r\n",
        f"{ESC}[0m{ESC}[3m{ESC}[4:3m{ESC}[38:2::1:2:3mfancy{ESC}[22;23;24;39m{ESC}[>4;2m done\r\n",
        f"{ESC}[0m{ESC}[7m{ESC}[92mlast{ESC}[0m",
        f"{ESC}[3;5H{ESC}]2;title{ESC}\\{ESC}[?1004h",
        f"{ESC}[1A{ESC}[Kspinner",
    ]
)


def runs(parsed: dict, line: int) -> list:
    """Return one line's runs with their styles in place of the indexes."""
    return [(text, parsed["styles"][style]) for text, style in parsed["lines"][line]]


class ParseTest(unittest.TestCase):
    """A paint becomes lines of styled runs."""

    def test_history_and_screen(self) -> None:
        """The history comes first, and later output is left out."""
        parsed = parse(PAINT)
        self.assertEqual(parsed["texts"], ["old line", "second", "  red plain", "fancy done", "last"])
        self.assertEqual(parsed["screen"], 2)

    def test_styles(self) -> None:
        """Each run keeps the style that was set when it was written."""
        parsed = parse(PAINT)
        self.assertEqual(runs(parsed, 0), [("old ", {}), ("line", {"bold": True, "fg": "#87afaf"})])
        self.assertEqual(
            runs(parsed, 2),
            [("  ", {"bg": "#303030"}), ("red", {"fg": 1, "bg": "#303030"}), (" plain", {})],
        )
        self.assertEqual(
            runs(parsed, 3),
            [("fancy", {"italic": True, "underline": True, "fg": "#010203"}), (" done", {})],
        )
        self.assertEqual(runs(parsed, 4), [("last", {"reverse": True, "fg": 10})])

    def test_styles_are_shared(self) -> None:
        """Runs in one style point at one entry."""
        parsed = parse(f"{ESC}[31ma{ESC}[0m b {ESC}[31mc")
        self.assertEqual(parsed["lines"], [[["a", 1], [" b ", 0], ["c", 1]]])
        self.assertEqual(parsed["styles"], [{}, {"fg": 1}])

    def test_runs_join(self) -> None:
        """Text on both sides of a sequence that changes no style is one run."""
        self.assertEqual(parse(f"a{ESC}[?25lb{ESC}]2;title{ESC}\\c")["lines"], [[["abc", 0]]])

    def test_no_history(self) -> None:
        """A paint may start at the screen."""
        parsed = parse(f"{ESC}[H{ESC}[2J{ESC}[3g{ESC}[H{ESC}[0mone\r\ntwo{ESC}[2;4H")
        self.assertEqual(parsed["texts"], ["one", "two"])
        self.assertEqual(parsed["screen"], 0)

    def test_bad_color(self) -> None:
        """A color with parts missing changes nothing."""
        self.assertEqual(parse(f"{ESC}[38;5mx")["styles"], [{}])


class RgbTest(unittest.TestCase):
    """Palette colors follow xterm."""

    def test_palette(self) -> None:
        """The first 16 stay indexes for the theme, the rest become colors."""
        self.assertEqual(
            [rgb(n) for n in (1, 15, 16, 196, 231, 232, 244, 255)],
            [1, 15, "#000000", "#ff0000", "#ffffff", "#080808", "#808080", "#eeeeee"],
        )


if __name__ == "__main__":
    unittest.main()
