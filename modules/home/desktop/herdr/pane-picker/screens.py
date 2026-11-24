"""Print each terminal's history and screen as lines of styled text, one JSON line each.

`hc attach --observe` draws a terminal in its colors, and neither resizes it nor types into it.
It wants a tty, so each terminal is read through its own pty, up to the end of its first paint.
"""

import argparse
import json
import os
import pty
import re
import select
import signal
import sys
import time

HC = "@hc@"
DEADLINE_S = 2
# hc asks the viewer what it is before it paints, and waits a while when nothing answers.
DEVICE_QUERY = b"\x1b[c"
DEVICE_ANSWER = b"\x1b[?62;22c"
# The paint ends where the core puts the cursor back, after it resets the tab stops.
PAINT = re.compile(rb"\x1b\[3g.*?\x1b\[\d+;\d+H", re.DOTALL)
# A CSI sequence, a string sequence up to its terminator, any other escape, a line end, a control.
TOKEN = re.compile(
    r"\x1b\[([0-9;:?<=>!]*)[ -/]*([@-~])|\x1b[\]P_^X].*?(?:\x07|\x1b\\)|\x1b[ -/]*[0-~]|\r\n|[\x00-\x1f\x7f]",
    re.DOTALL,
)
PRIVATE = re.compile(r"[?<=>!]")
CURSOR = re.compile(r"\d+;\d+")
ON = {1: "bold", 2: "dim", 3: "italic", 4: "underline", 7: "reverse", 9: "strike", 21: "underline"}
OFF = {23: ["italic"], 24: ["underline"], 27: ["reverse"], 29: ["strike"], 39: ["fg"], 49: ["bg"], 22: ["bold", "dim"]}
EXTENDED = {38: "fg", 48: "bg", 58: None}
CUBE = [0, 95, 135, 175, 215, 255]


def rgb(index: int) -> int | str:
    """Return a palette color: the theme's 16 by index, the rest as xterm draws them."""
    if index < 16:
        return index
    if index >= 232:
        return "#" + f"{8 + 10 * (index - 232):02x}" * 3
    cell = index - 16
    return "#" + "".join(f"{CUBE[level]:02x}" for level in (cell // 36, cell // 6 % 6, cell % 6))


def extended(parts: list[str], i: int) -> tuple[int | str | None, int]:
    """Read the color after 38, 48 or 58, and count the later parts it took.

    `5;n` and `2;r;g;b` come as parts of their own, or inside the same part with colons, where
    a color space may sit before the three channels.
    """
    inside = parts[i].split(":")[1:]
    args = inside or parts[i + 1:]
    try:
        if args[:1] == ["5"]:
            return rgb(int(args[1])), 0 if inside else 2
        if args[:1] == ["2"]:
            channels = inside[-3:] if inside else args[1:4]
            return "#" + "".join(f"{int(c):02x}" for c in channels), 0 if inside else 4
    except (IndexError, ValueError):
        pass
    return None, 0


def styled(style: dict, params: str) -> dict:
    """Return the style after one SGR sequence."""
    style = dict(style)
    parts = params.split(";")
    i = 0
    while i < len(parts):
        code = int(parts[i].split(":")[0] or 0)
        if code == 0:
            style.clear()
        elif code in ON:
            style[ON[code]] = not parts[i].endswith(":0")
        elif code in OFF:
            for key in OFF[code]:
                style.pop(key, None)
        elif 30 <= code <= 37 or 90 <= code <= 97:
            style["fg"] = code - 30 if code < 90 else code - 82
        elif 40 <= code <= 47 or 100 <= code <= 107:
            style["bg"] = code - 40 if code < 100 else code - 92
        elif code in EXTENDED:
            color, used = extended(parts, i)
            if EXTENDED[code] and color is not None:
                style[EXTENDED[code]] = color
            i += used
        i += 1
    return {key: value for key, value in style.items() if value is not False}


def parse(paint: str) -> dict:
    """Split a paint into lines of runs, each `[text, index into styles]`.

    `screen` is the line the screen starts on, after the history, and `texts` is every line
    without its styles. What follows the paint is the program's later output, and is left out.
    """
    styles: list[dict] = [{}]
    known = {"{}": 0}
    lines: list[list] = [[]]
    style: dict = {}
    screen = None
    at = 0

    def write(text: str) -> None:
        if not text:
            return
        key = json.dumps(style, sort_keys=True)
        if key not in known:
            known[key] = len(styles)
            styles.append(style)
        line = lines[-1]
        if line and line[-1][1] == known[key]:
            line[-1][0] += text
        else:
            line.append([text, known[key]])

    for token in TOKEN.finditer(paint):
        write(paint[at:token.start()])
        at = token.end()
        params, final = token.group(1), token.group(2)
        if token.group(0) == "\r\n":
            lines.append([])
        elif final == "m" and not PRIVATE.search(params):
            style = styled(style, params)
        elif final == "g" and params == "3":
            # The core resets the tab stops just before it draws the screen.
            screen = len(lines) - 1
        elif final == "H" and screen is not None and CURSOR.fullmatch(params):
            break
    else:
        write(paint[at:])
    texts = ["".join(text for text, _ in line).rstrip() for line in lines]
    return {"screen": screen or 0, "styles": styles, "lines": lines, "texts": texts}


class Viewer:
    """One `hc attach --observe` on a pty, read until its first paint is whole."""

    def __init__(self, address: str, history: int) -> None:
        """Start hc on a new pty."""
        self.address = address
        self.seen = b""
        self.paint: bytes | None = None
        self.answered = False
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execv(HC, [HC, "attach", "--observe", "--history", str(history), address])  # noqa: S606
        # Later viewers must not hold this pty open.
        os.set_inheritable(self.fd, False)

    def read(self) -> bool:
        """Take what hc wrote, and stop it once the paint is whole. False when hc has gone."""
        try:
            data = os.read(self.fd, 65536)
        except OSError:
            return False
        if not data:
            return False
        if self.paint is not None:
            return True
        self.seen += data
        if not self.answered and DEVICE_QUERY in self.seen:
            os.write(self.fd, DEVICE_ANSWER)
            self.answered = True
        end = PAINT.search(self.seen)
        if end:
            self.paint = self.seen[:end.end()]
            os.kill(self.pid, signal.SIGTERM)
        return True

    def close(self) -> None:
        """Make sure hc has gone."""
        done, _ = os.waitpid(self.pid, os.WNOHANG)
        if not done:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        os.close(self.fd)

    def result(self) -> dict:
        """Return the terminal's lines, or what hc said in place of a paint."""
        if self.paint is not None:
            return {"terminal": self.address, **parse(self.paint.decode("utf-8", "replace"))}
        said = " ".join(filter(None, parse(self.seen.decode("utf-8", "replace"))["texts"]))
        return {"terminal": self.address, "error": said or "hc attach drew nothing"}


def main() -> None:
    """Read every terminal named on the command line at once."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", type=int, default=0, help="lines of history above the screen")
    parser.add_argument("terminals", nargs="+", help="addresses such as t7 or machine/t7")
    args = parser.parse_args()

    viewers = {v.fd: v for v in (Viewer(t, args.history) for t in args.terminals)}
    reading = set(viewers)
    deadline = time.monotonic() + DEADLINE_S
    while reading and time.monotonic() < deadline:
        ready, _, _ = select.select(list(reading), [], [], 0.1)
        reading -= {fd for fd in ready if not viewers[fd].read()}
    for viewer in viewers.values():
        viewer.close()
        sys.stdout.write(json.dumps(viewer.result(), separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
