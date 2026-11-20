"""Bring back herdr terminals that a core restart turned back into shells.

herdr-core keeps a lost terminal (reboot, core crash) as a fresh shell in the same tab, with the
same address and labels, but never reruns its program or replays its screen. Each run snapshots
every terminal: agents get their resume command, local shells get their text written back.
"""

import json
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path

HC = "@hc@"
STATE = Path.home() / ".local" / "state" / "herdr-resume" / "agents.json"
SCREENS = STATE.parent / "screens"
SCREEN_LINES = "2000"
KEEP_S = 7 * 86400
# The label that holds each agent's session, and the command that reopens it.
AGENTS = {
    "pi": ("pi.session", lambda s: ["pi", "--session", s]),
    "claude-code": ("claude.session", lambda s: ["claude", "--resume", s]),
}


def log(msg: str) -> None:
    """Print one timestamped line to stderr, which launchd or journald keeps."""
    print(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}", file=sys.stderr, flush=True)


def hc(*args: str, timeout: int = 30) -> dict | None:
    """Run hc with --json and parse its answer, or None if it failed."""
    r = subprocess.run(  # noqa: S603
        [HC, *args, "--json"],
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    if r.returncode != 0:
        return None
    return json.loads(r.stdout)


def snapshot_entry(info: dict, agent: str) -> dict | None:
    """Return what reopens this terminal's agent: its session, pid and folder."""
    label, _ = AGENTS[agent]
    session = (info.get("labels") or {}).get(label)
    if not session:
        return None
    cwd = (info.get("foreground") or {}).get("cwd") or info.get("cwd")
    return {"agent": agent, "pid": info["pid"], "session": session, "cwd": cwd}


def resume(address: str, entry: dict) -> bool:
    """Type the agent's resume command into the shell that replaced it."""
    _, command = AGENTS[entry["agent"]]
    line = " ".join(shlex.quote(part) for part in command(entry["session"]))
    if entry.get("cwd"):
        line = f"cd {shlex.quote(entry['cwd'])} && {line}"
    r = subprocess.run(  # noqa: S603
        [HC, "send", address, line],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    log(f"{address}: {line} -> exit {r.returncode} {r.stderr.strip()}")
    return r.returncode == 0


def save_screen(address: str) -> None:
    """Save the terminal's screen and history as plain text, private to the user."""
    read = hc("read", address, "--lines", SCREEN_LINES)
    if read is None:
        return
    SCREENS.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = SCREENS / f"{address}.txt"
    tmp = path.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(read.get("text") or "")
    tmp.replace(path)


def pane_tty(pid: int) -> str | None:
    """Return the tty device of the shell running in a pane."""
    try:
        return str(Path(f"/proc/{pid}/fd/0").readlink())
    except OSError:
        pass
    r = subprocess.run(  # noqa: S603
        ["/bin/ps", "-o", "tty=", "-p", str(pid)],
        capture_output=True,
        text=True,
        check=False,
    )
    tty = r.stdout.strip()
    if r.returncode != 0 or not tty or tty.startswith("?"):
        return None
    return f"/dev/{tty}"


def restore_screen(address: str, pid: int) -> None:
    """Write the saved text into the new shell's tty, then redraw its prompt."""
    try:
        text = (SCREENS / f"{address}.txt").read_text().rstrip("\n")
    except OSError:
        return
    tty = pane_tty(pid)
    if not text or not tty or not tty.startswith("/dev/"):
        return
    # The shell may have turned off output newline translation, so send CR LF.
    body = text.replace("\n", "\r\n")
    with Path(tty).open("w") as f:
        f.write(f"\x1b[H\x1b[2J\x1b[2m{body}\r\n-- restored after restart --\x1b[0m\r\n")
    hc("keys", address, "enter")
    log(f"{address}: restored {body.count(chr(10)) + 1} lines")


def main() -> None:
    """Snapshot live terminals, and bring back the ones that restarted."""
    listing = hc("ls")
    if listing is None:
        return  # herdr-core is not up yet; keep the last snapshot for when it is
    try:
        prev = json.loads(STATE.read_text())
    except (OSError, ValueError):
        prev = {}
    now = time.time()
    live = {t["address"]: t for t in listing.get("terminals") or []}
    out = {}
    for address, t in live.items():
        if t.get("state") != "live":
            continue
        info = hc("get", address)
        if not info:
            continue
        old = prev.get(address)
        # A lost terminal has no pid until its new shell starts, so wait for the next run.
        if info.get("pid") is None:
            if old:
                out[address] = old
            continue
        agent = t.get("agent")
        local = not t.get("machine")
        if old and info["pid"] != old["pid"] and agent not in AGENTS:
            if old.get("agent"):
                if not resume(address, old):
                    out[address] = old
                    continue
            elif local:
                restore_screen(address, info["pid"])
            out[address] = {**old, "pid": info["pid"], "seen": now}
            continue
        entry = snapshot_entry(info, agent) if agent in AGENTS else None
        if entry:
            out[address] = {**entry, "seen": now}
            continue
        out[address] = {"pid": info["pid"], "seen": now}
        if local:
            save_screen(address)
    # Terminals on a machine that is away now come back with it.
    for address, old in prev.items():
        if address not in live and now - old.get("seen", 0) < KEEP_S:
            out[address] = old
    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(out, indent=1))
    tmp.replace(STATE)
    if SCREENS.is_dir():
        for path in SCREENS.glob("*.txt"):
            if path.stem not in out or out[path.stem].get("agent"):
                path.unlink()


if __name__ == "__main__":
    main()
