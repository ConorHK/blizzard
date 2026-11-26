"""Capture Hyprland workspaces, shown or hidden, as small PNGs.

Usage: ws-thumbs [--width PX] DIR [NAME...]

Captures the named workspaces, or all of them, to DIR/NAME-<ms>.png and
prints a JSON object mapping each name to its new path. A fresh file name
per shot makes image widgets that cache by path reload it.
"""

import argparse
import json
import mmap
import os
import sys
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

from PIL import Image
from pywayland.client import Display
from ws_thumbs_protocols.ext_image_copy_capture_v1 import ExtImageCopyCaptureManagerV1
from ws_thumbs_protocols.ext_workspace_v1 import (
    ExtWorkspaceHandleV1Proxy,
    ExtWorkspaceManagerV1,
    ExtWorkspaceManagerV1Proxy,
)
from ws_thumbs_protocols.hyprland_workspace_image_capture_source_v1 import (
    HyprlandWorkspaceImageCaptureSourceManagerV1,
)
from ws_thumbs_protocols.wayland import WlRegistryProxy, WlShm

MODE_EVERYTHING = 1
# wl_shm formats that are BGRA bytes in memory on little-endian hosts.
FORMATS = {0: "BGRA", 1: "BGRX"}
GLOBALS = (
    WlShm,
    ExtWorkspaceManagerV1,
    ExtImageCopyCaptureManagerV1,
    HyprlandWorkspaceImageCaptureSourceManagerV1,
)

Globals = dict[type, Any]


class CaptureError(Exception):
    """A capture step failed in a way worth telling the user."""


def bind_globals(display: Display) -> Globals:
    """Bind every protocol the capture needs, or fail naming the missing ones."""
    found: Globals = {}

    def on_global(
        registry: WlRegistryProxy, name: int, interface: str, version: int
    ) -> None:
        for cls in GLOBALS:
            if interface == cls.name:
                found[cls] = registry.bind(name, cls, min(version, cls.version))

    registry = display.get_registry()
    registry.dispatcher["global"] = on_global
    display.roundtrip()
    missing = [cls.name for cls in GLOBALS if cls not in found]
    if missing:
        raise CaptureError(f"compositor lacks {', '.join(missing)}")
    return found


def list_workspaces(
    display: Display, manager: ExtWorkspaceManagerV1Proxy
) -> dict[str, ExtWorkspaceHandleV1Proxy]:
    """Return every ext-workspace handle by workspace name."""
    handles = []
    names: dict[ExtWorkspaceHandleV1Proxy, str] = {}

    def on_workspace(
        _: ExtWorkspaceManagerV1Proxy, handle: ExtWorkspaceHandleV1Proxy
    ) -> None:
        handles.append(handle)
        handle.dispatcher["name"] = names.__setitem__

    manager.dispatcher["workspace"] = on_workspace
    # The first roundtrip announces handles, the second their names.
    display.roundtrip()
    display.roundtrip()
    return {names[h]: h for h in handles if h in names}


def wait_until(display: Display, done: Callable[[], object]) -> None:
    """Dispatch compositor events until done() is truthy."""
    while not done():
        if display.dispatch(block=True) == -1:
            raise CaptureError("compositor connection lost")


def capture_image(
    display: Display, found: Globals, handle: ExtWorkspaceHandleV1Proxy
) -> Image.Image:
    """Copy one frame of the workspace into shared memory and return it."""
    source = found[HyprlandWorkspaceImageCaptureSourceManagerV1].create_source(
        handle, MODE_EVERYTHING
    )
    session = found[ExtImageCopyCaptureManagerV1].create_session(source, 0)
    info: dict[str, Any] = {"formats": []}
    session.dispatcher["buffer_size"] = lambda _, w, h: info.update(size=(w, h))
    session.dispatcher["shm_format"] = lambda _, f: info["formats"].append(f)
    session.dispatcher["done"] = lambda _: info.update(done=True)
    session.dispatcher["stopped"] = lambda _: info.update(done=True, stopped=True)
    wait_until(display, lambda: "done" in info)
    if "stopped" in info:
        raise CaptureError("capture session stopped")

    fmt = next((f for f in FORMATS if f in info["formats"]), None)
    if fmt is None:
        raise CaptureError(f"no supported shm format in {info['formats']}")
    width, height = info["size"]
    stride = width * 4
    length = stride * height

    fd = os.memfd_create("ws-thumbs")
    try:
        os.ftruncate(fd, length)
        pool = found[WlShm].create_pool(fd, length)
        buffer = pool.create_buffer(0, width, height, stride, fmt)
        frame = session.create_frame()
        result: dict[str, Any] = {}
        frame.dispatcher["ready"] = lambda _: result.update(ok=True)
        frame.dispatcher["failed"] = lambda _, r: result.update(ok=False, reason=r)
        frame.attach_buffer(buffer)
        frame.damage_buffer(0, 0, width, height)
        frame.capture()
        wait_until(display, lambda: result)
        if not result["ok"]:
            raise CaptureError(f"capture failed, reason {result['reason']}")
        with mmap.mmap(fd, length) as data:
            image = Image.frombuffer(
                "RGBA", (width, height), bytes(data), "raw", FORMATS[fmt], 0, 1
            )
        for proxy in (frame, buffer, pool, session, source):
            proxy.destroy()
    finally:
        os.close(fd)
    return image


def save_thumb(image: Image.Image, directory: Path, name: str, width: int) -> Path:
    """Write a scaled copy under a fresh name, keeping one older shot for widgets still on it."""
    directory.mkdir(parents=True, exist_ok=True)
    image.thumbnail((width, width))
    path = directory / f"{name}-{time.time_ns() // 1_000_000}.png"
    tmp = path.with_suffix(".tmp")
    image.save(tmp, format="PNG")
    tmp.rename(path)
    shots = sorted(directory.glob(f"{name}-*.png"), key=lambda p: p.stat().st_mtime)
    for old in shots[:-2]:
        old.unlink(missing_ok=True)
    return path


def main() -> int:
    """Capture the workspaces and print where each thumbnail went."""
    parser = argparse.ArgumentParser(prog="ws-thumbs", description=__doc__)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("dir", type=Path)
    parser.add_argument("names", nargs="*")
    args = parser.parse_args()

    display = Display()
    display.connect()
    paths = {}
    try:
        found = bind_globals(display)
        workspaces = list_workspaces(display, found[ExtWorkspaceManagerV1])
        for name in args.names or sorted(workspaces):
            if name not in workspaces:
                print(f"ws-thumbs: no workspace named {name}", file=sys.stderr)
                continue
            image = capture_image(display, found, workspaces[name])
            paths[name] = str(save_thumb(image, args.dir, name, args.width))
        found[ExtWorkspaceManagerV1].stop()
        display.roundtrip()
    except CaptureError as err:
        print(f"ws-thumbs: {err}", file=sys.stderr)
        return 1
    finally:
        display.disconnect()
    print(json.dumps(paths))
    return 0 if paths or not args.names else 1


if __name__ == "__main__":
    sys.exit(main())
