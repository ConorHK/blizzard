"""Shows a page in Herdr's canvas sidebar beside this agent's terminal.

Usage: herdr-show < page.json, where the page is {"title": ..., "blocks": [...]};
herdr-show --clear empties the canvas. The canvas mod reads the file and label written here.
"""

import json
import os
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import NoReturn
from urllib.parse import urlparse

from PIL import Image

HC = "@hc@"
MAX_DOC = 256 * 1024
# The canvas fetches an image as base64 through an 8 MiB pipe.
MAX_IMAGE = 5 * 1024 * 1024
IMAGES = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"}
MARKDOWN = {".md", ".markdown", ".txt", ""}
TYPES = {"heading", "markdown", "doc", "image", "stats", "table", "list", "progress", "code"}


def fail(message: str) -> NoReturn:
    """Print why nothing was shown and exit."""
    print(f"Not shown: {message}", file=sys.stderr)
    sys.exit(1)


def check(blocks: list[dict]) -> None:
    """Refuse unknown block types and links that are not https."""
    for b, block in enumerate(blocks):
        if block.get("type") not in TYPES:
            fail(f"block {b}: unknown type {block.get('type')!r}")
        for i, item in enumerate(block.get("items") or []):
            link = item.get("link")
            if link is not None and urlparse(link).scheme != "https":
                fail(f"block {b} item {i}: links must be https URLs")


def pixels(source: Path) -> dict:
    """Return the image size the canvas needs to keep its shape."""
    if source.suffix.lower() == ".svg":
        return {}
    with Image.open(source) as img:
        return {"width": img.width, "height": img.height}


def resolve(blocks: list[dict], folder: Path, terminal: str, stamp: str) -> list[dict]:
    """Turn doc and image blocks into what the canvas draws without reading files itself."""
    out = []
    for i, block in enumerate(blocks):
        kind = block["type"]
        if kind not in ("doc", "image"):
            out.append(block)
            continue
        if not block.get("path"):
            fail(f"block {i}: {kind} needs a path")
        source = Path(block["path"]).expanduser().resolve()
        ext = source.suffix.lower()
        size = source.stat().st_size
        if kind == "doc":
            if size > MAX_DOC:
                fail(f"block {i}: {block['path']} is over {MAX_DOC // 1024} KB")
            text = source.read_text()
            if ext in MARKDOWN:
                out.append({"type": "markdown", "text": text})
            else:
                out.append({"type": "code", "text": text, "language": ext[1:]})
            continue
        if ext not in IMAGES:
            fail(f"block {i}: {block['path']} is not a PNG, JPEG, GIF, WebP or SVG")
        if size > MAX_IMAGE:
            fail(f"block {i}: {block['path']} is over {MAX_IMAGE // 1024 // 1024} MB")
        # A copy beside the page, so the canvas only ever reads this folder.
        name = f"{terminal}.{stamp}.{i}{ext}"
        (folder / name).write_bytes(source.read_bytes())
        out.append({"type": "image", "file": name, "text": block.get("text"), **pixels(source)})
    return out


def prune(folder: Path, terminal: str, keep: set[str]) -> None:
    """Remove this terminal's image copies, except the ones in keep."""
    for path in folder.glob(f"{terminal}.*"):
        if path.suffix not in (".json", ".tmp") and path.name not in keep:
            path.unlink(missing_ok=True)


def label(terminal: str, value: str) -> None:
    """Set the label the canvas watches; a new value opens it while this terminal has focus."""
    subprocess.run([HC, "label", terminal, f"pi.ui={value}"], capture_output=True, timeout=5, check=False)  # noqa: S603


def clear(page: Path, folder: Path, terminal: str) -> None:
    """Remove the page and its images, then close the canvas."""
    page.unlink(missing_ok=True)
    prune(folder, terminal, set())
    label(terminal, "")


def main() -> None:
    """Write the page from stdin, or clear it."""
    terminal = os.environ.get("HC_TERMINAL_ID")
    if not terminal:
        fail("no Herdr terminal, so no canvas")
    state = os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state"
    folder = Path(state) / "pi-ui"
    folder.mkdir(parents=True, exist_ok=True)
    page = folder / f"{terminal}.json"

    if sys.argv[1:] == ["--clear"]:
        clear(page, folder, terminal)
        return
    try:
        body = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        fail(f"stdin is not JSON: {e}")
    title, blocks = body.get("title"), body.get("blocks")
    if not isinstance(title, str) or not isinstance(blocks, list):
        fail('stdin needs {"title": string, "blocks": [...]}')
    if not blocks:
        clear(page, folder, terminal)
        print("Canvas cleared.")
        return

    check(blocks)
    updated = datetime.now(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    stamp = "".join(c for c in updated if c.isdigit())
    resolved = resolve(blocks, folder, terminal, stamp)
    prune(folder, terminal, {b["file"] for b in resolved if "file" in b})
    tmp = page.with_suffix(".json.tmp")
    tmp.write_text(json.dumps({"updated": updated, "title": title, "blocks": resolved}))
    # A rename keeps the canvas from reading half a file.
    tmp.replace(page)
    label(terminal, updated)
    print(f"Shown in Herdr's canvas ({len(blocks)} blocks).")


if __name__ == "__main__":
    main()
