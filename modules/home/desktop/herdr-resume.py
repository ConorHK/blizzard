"""Restart pi and Claude sessions in herdr terminals that a core restart turned back into shells.

herdr-core keeps a lost terminal (reboot, core crash) as a fresh shell in the same tab, with the
same address and labels, but never reruns its program. Each run snapshots the terminals that run a
resumable agent; a terminal from the snapshot that now has a new shell gets its resume command.
"""

import json
import shlex
import subprocess
import sys
import time
from pathlib import Path

HC = "@hc@"
STATE = Path.home() / ".local" / "state" / "herdr-resume" / "agents.json"
KEEP_S = 7 * 86400
# The label that holds each agent's session, and the command that reopens it.
AGENTS = {
    "pi": ("pi.session", lambda s: ["pi", "--session", s]),
    "claude": ("claude.session", lambda s: ["claude", "--resume", s]),
}


def log(msg):
    print(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}", file=sys.stderr, flush=True)


def hc(*args, timeout=30):
    r = subprocess.run(
        [HC, *args, "--json"], capture_output=True, text=True, timeout=timeout
    )
    if r.returncode != 0:
        return None
    return json.loads(r.stdout)


def snapshot_entry(info, agent):
    label, _ = AGENTS[agent]
    session = (info.get("labels") or {}).get(label)
    if not session:
        return None
    cwd = (info.get("foreground") or {}).get("cwd") or info.get("cwd")
    return {"agent": agent, "pid": info["pid"], "session": session, "cwd": cwd}


def resume(address, entry):
    _, command = AGENTS[entry["agent"]]
    line = " ".join(shlex.quote(part) for part in command(entry["session"]))
    if entry.get("cwd"):
        line = f"cd {shlex.quote(entry['cwd'])} && {line}"
    r = subprocess.run(
        [HC, "send", address, line], capture_output=True, text=True, timeout=60
    )
    log(f"{address}: {line} -> exit {r.returncode} {r.stderr.strip()}")


def main():
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
        agent = t.get("agent")
        old = prev.get(address)
        if agent in AGENTS:
            info = hc("get", address)
            entry = info and snapshot_entry(info, agent)
            if entry:
                out[address] = {**entry, "seen": now}
            continue
        if not old or t.get("state") != "live":
            continue
        info = hc("get", address)
        # Same shell as before: the agent quit on purpose, so it stays closed.
        if not info or info.get("pid") == old["pid"]:
            continue
        resume(address, old)
        out[address] = {**old, "pid": info["pid"], "seen": now}
    # Terminals on a machine that is away now come back with it.
    for address, old in prev.items():
        if address not in live and now - old.get("seen", 0) < KEEP_S:
            out[address] = old
    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(out, indent=1))
    tmp.replace(STATE)


if __name__ == "__main__":
    main()
