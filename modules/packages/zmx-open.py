"""Open, reattach or list zmx sessions for kitty panes."""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import urllib.parse
from os import uname
from pathlib import Path

SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*://([^/]*)")

TIMEOUT = 5

REPO_MARKERS = (".git", ".jj")

# ssh options that consume the next argument.
SSH_VALUE_FLAGS = frozenset("bcDEeFIiJLlmOopQRSWw")


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
    parser.add_argument("--list", action="store_true")
    return parser.parse_args()


def short_host() -> str:
    """Return this host's short name."""
    return uname().nodename.split(".", 1)[0]


def sanitize(name: str) -> str:
    """Keep characters zmx accepts; dots mark slots."""
    kept = "".join(c if c.isalnum() or c in "_-" else "-" for c in name)
    return kept.strip("-")[:32]


def project_name(directory: Path) -> str:
    """Name a directory by its repo root."""
    home = Path.home()
    for candidate in (directory, *directory.parents):
        if candidate in {home, Path("/")}:
            break
        if any((candidate / marker).exists() for marker in REPO_MARKERS):
            return sanitize(candidate.name) or "home"
    if directory in {home, Path("/")}:
        return "home"
    return sanitize(directory.name) or "home"


def sessions() -> list[dict[str, str]]:
    """Parse zmx ls into one dict per session."""
    found = []
    for line in zmx(["ls"]).splitlines():
        fields = {}
        for field in line.lstrip("\u2192 ").split("\t"):
            key, sep, value = field.partition("=")
            if sep:
                fields[key] = value
        if fields.get("name"):
            found.append(fields)
    return found


def split_cwd(url: str) -> tuple[str, str]:
    """Split an OSC 7 cwd into host and path."""
    match = SCHEME.match(url)
    if not match:
        return "", url
    host = match.group(1).split(".", 1)[0]
    path = url.removeprefix(match.group(0))
    return host, urllib.parse.unquote(path)


def proc_text(pid: str, name: str) -> str:
    """Read a /proc file, or empty."""
    try:
        return Path(f"/proc/{pid}/{name}").read_text()
    except OSError:
        return ""


def proc_stat(pid: str) -> list[str]:
    """Return stat fields after the comm field."""
    return proc_text(pid, "stat").rpartition(")")[2].split()


def foreground(pid: str) -> list[str]:
    """Return argv of the shell's foreground job."""
    stat = proc_stat(pid)
    if len(stat) < 6 or stat[5] in {stat[2], "-1"}:
        return []
    # The job's leader has pid equal to pgid.
    argv = proc_text(stat[5], "cmdline").split("\0")
    return [arg for arg in argv if arg]


def ssh_destination(argv: list[str]) -> str:
    """Return the host an ssh argv connects to."""
    if not argv or Path(argv[0]).name != "ssh":
        return ""
    args = argv[1:]
    index = 0
    while index < len(args):
        arg = args[index]
        if not arg.startswith("-"):
            return arg.rsplit("@", 1)[-1]
        valued = len(arg) == 2 and arg[1] in SSH_VALUE_FLAGS
        index += 2 if valued else 1
    return ""


def live_cwd(fields: dict[str, str]) -> tuple[str, str]:
    """Resolve where a session's shell is now."""
    host, path = split_cwd(fields.get("cwd", ""))
    if path.startswith("/"):
        return host or short_host(), path
    pid = fields.get("pid", "")
    try:
        return short_host(), str(Path(f"/proc/{pid}/cwd").readlink())
    except OSError:
        return "", ""


def describe(fields: dict[str, str]) -> dict[str, object]:
    """Report one session for the switcher."""
    argv = foreground(fields.get("pid", ""))
    cwd_host, path = live_cwd(fields)
    created = fields.get("created", "")
    clients = fields.get("clients", "")
    return {
        "name": fields["name"],
        "clients": int(clients) if clients.isdigit() else 0,
        "created": int(created) if created.isdigit() else 0,
        "title": fields.get("title", ""),
        "command": argv,
        "ssh": ssh_destination(argv),
        "cwd_host": cwd_host,
        "cwd": path,
        "home": str(Path.home()),
    }


def report() -> None:
    """Print every session as JSON."""
    payload = {
        "host": short_host(),
        "sessions": [describe(fields) for fields in sessions()],
    }
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")


def from_cwd(want: str) -> str:
    """Resolve the local cwd of a session."""
    for fields in sessions():
        if fields["name"] == want:
            host, path = live_cwd(fields)
            return path if host == short_host() else ""
    return ""


def next_session(names: set[str], base: str) -> str:
    """Pick the first unused slot for the base."""
    index = 1
    while f"{base}.{index}" in names:
        index += 1
    return f"{base}.{index}"


def user_var(name: str, value: str) -> str:
    """Build a kitty SetUserVar escape."""
    data = base64.b64encode(value.encode()).decode()
    return f"\033]1337;SetUserVar={name}={data}\007"


def main() -> None:
    """Open or reattach a pane session, then exec zmx."""
    opts = parse_args()
    if opts.list:
        report()
        return
    cwd = opts.cwd or ""
    if opts.from_session:
        cwd = from_cwd(opts.from_session)
    directory = Path(cwd) if cwd else Path.cwd()
    if not directory.is_dir():
        directory = Path.home()

    if opts.attach:
        session = opts.attach
    else:
        names = {fields["name"] for fields in sessions()}
        base = sanitize(opts.base or "") or project_name(directory)
        session = next_session(names, base)

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
