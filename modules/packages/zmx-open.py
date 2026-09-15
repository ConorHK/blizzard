"""Open or reattach a zmx session for a kitty pane."""

import argparse
import base64
import os
import re
import subprocess
import sys
import urllib.parse
from os import uname
from pathlib import Path

SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*://[^/]*")

TIMEOUT = 5


def zmx(args: list[str]) -> str:
    """Run zmx and return stdout, or empty on failure."""
    try:
        done = subprocess.run(  # noqa: S603
            ["zmx", *args],  # noqa: S607
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
            check=False,
        )
    except OSError, subprocess.SubprocessError:
        return ""
    return done.stdout if done.returncode == 0 else ""


def parse_args() -> argparse.Namespace:
    """Parse the zmx-open command line."""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--attach")
    parser.add_argument("--base")
    parser.add_argument("--from", dest="from_session")
    parser.add_argument("--cwd")
    parser.add_argument("--new-family", action="store_true")
    return parser.parse_args()


def short_sessions() -> list[str]:
    """List live session names."""
    names = [line.strip() for line in zmx(["ls", "--short"]).splitlines()]
    return [name for name in names if name]


def family_taken(sessions: list[str], base: str) -> bool:
    """Report whether any session belongs to the family."""
    prefix = base + "."
    for name in sessions:
        suffix = name.removeprefix(prefix)
        if suffix.isdigit() and name.startswith(prefix):
            return True
    return False


def fresh_base(sessions: list[str], base: str) -> str:
    """Pick a base name outside every existing family."""
    if not family_taken(sessions, base):
        return base
    suffix = 2
    while family_taken(sessions, f"{base}-{suffix}"):
        suffix += 1
    return f"{base}-{suffix}"


def next_session(sessions: list[str], base: str) -> str:
    """Pick the first unused session slot for the base."""
    index = 1
    while f"{base}.{index}" in sessions:
        index += 1
    return f"{base}.{index}"


def from_cwd(want: str) -> str:
    """Resolve the cwd zmx tracked for a session."""
    for line in zmx(["ls"]).splitlines():
        fields = line.split("\t")
        if fields[0].partition("=")[2] != want:
            continue
        values = {}
        for field in fields[1:]:
            key, sep, value = field.partition("=")
            if sep:
                values[key] = value
        path = urllib.parse.unquote(SCHEME.sub("", values.get("cwd", "")))
        if path.startswith("/"):
            return path
        pid = values.get("pid", "")
        if pid:
            try:
                return str(Path(f"/proc/{pid}/cwd").readlink())
            except OSError:
                pass
        return ""
    return ""


def user_var(name: str, value: str) -> str:
    """Build a kitty SetUserVar escape."""
    data = base64.b64encode(value.encode()).decode()
    return f"\033]1337;SetUserVar={name}={data}\007"


def main() -> None:
    """Open or reattach a pane session, then exec zmx."""
    opts = parse_args()
    cwd = opts.cwd or ""
    if opts.attach:
        session = opts.attach
    else:
        sessions = short_sessions()
        base = opts.base or uname().nodename.split(".", 1)[0]
        if opts.from_session:
            cwd = from_cwd(opts.from_session)
        if opts.new_family:
            base = fresh_base(sessions, base)
        session = next_session(sessions, base)

    directory = Path(cwd)
    if not cwd or not directory.is_dir():
        directory = Path.home()

    # Escapes precede the exec; zmx would eat them.
    sys.stdout.write(
        f"\033]2;{session}\007"
        + user_var("zmx_session", session)
        + user_var("remote_host", uname().nodename),
    )
    sys.stdout.flush()
    os.chdir(directory)
    os.execvp("zmx", ["zmx", "attach", session])  # noqa: S606, S607


if __name__ == "__main__":
    main()
