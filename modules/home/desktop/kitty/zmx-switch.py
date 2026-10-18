import json
import os
import re
import shlex
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

from kittens.tui.handler import result_handler

# kitty re-execs kittens but caches their imports.
sys.modules.pop("zmx_kitten", None)

from zmx_kitten import HELPER, TIMEOUT, is_local, open_command, short_host

SSH_CONFIG = os.path.expanduser("~/.ssh/config")

HOST_LINE = re.compile(r"^\s*Host\s+(.+)$", re.IGNORECASE)

LAN_ALIAS = re.compile(r"-local$")

COMMAND_WIDTH = 24


def known_hosts():
    names = []
    try:
        with open(SSH_CONFIG) as config:
            for line in config:
                found = HOST_LINE.match(line)
                if not found:
                    continue
                for name in found.group(1).split():
                    if "*" in name or "?" in name:
                        continue
                    # Both aliases reach one machine.
                    name = LAN_ALIAS.sub("", name)
                    if name not in names and not is_local(name):
                        names.append(name)
    except OSError:
        pass
    return names


def list_command(host):
    if is_local(host):
        return [HELPER, "--list"]
    remote = shlex.join(["/bin/sh", "-lc", f"{HELPER} --list"])
    return ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=3", host, remote]


def query(host):
    try:
        done = subprocess.run(
            list_command(host), capture_output=True, text=True, timeout=TIMEOUT
        )
        return {"host": host, "sessions": json.loads(done.stdout)["sessions"]}
    except OSError, subprocess.SubprocessError, ValueError, KeyError:
        return {"host": host, "sessions": [], "error": True}


# Runs in the overlay, so slow hosts never block kitty.
def main(args):
    print("Querying zmx sessions...")
    hosts = [""] + known_hosts()
    with ThreadPoolExecutor(max_workers=len(hosts)) as pool:
        reports = list(pool.map(query, hosts))
    return json.dumps(reports)


def age(created):
    seconds = max(0, int(time.time()) - created)
    for unit, size in (("d", 86400), ("h", 3600), ("m", 60)):
        if seconds >= size:
            return f"{seconds // size}{unit}"
    return "now"


def command_text(argv):
    if not argv:
        return ""
    words = [os.path.basename(argv[0]).lstrip("-")] + argv[1:]
    text = " ".join(words)
    if len(text) > COMMAND_WIDTH:
        text = text[: COMMAND_WIDTH - 3] + "..."
    return text


def where(entry, host):
    path = entry.get("cwd", "")
    home = entry.get("home", "")
    if home and (path == home or path.startswith(home + "/")):
        path = "~" + path[len(home) :]
    cwd_host = entry.get("cwd_host", "")
    if cwd_host and cwd_host != host:
        return f"{cwd_host}:{path}"
    return path


def label(entry, host):
    name = entry["name"]
    if entry.get("title"):
        name = f"{name} [{entry['title']}]"
    mark = "*" if entry.get("clients") else " "
    command = command_text(entry.get("command") or [])
    return (
        f"{mark} {name:<20} {command:<{COMMAND_WIDTH}} "
        f"{where(entry, host)}  {age(entry.get('created', 0))}"
    )


# Detached sessions are the ones worth finding.
def ordered(sessions):
    return sorted(
        sessions, key=lambda s: (bool(s.get("clients")), -s.get("created", 0))
    )


def build_entries(reports):
    local = short_host(os.uname().nodename)
    entries = []
    for report in reports:
        host = report["host"]
        shown = host or local
        state = " (unreachable)" if report.get("error") else ""
        entries.append((None, f"{shown}{state}"))
        for entry in ordered(report["sessions"]):
            entries.append((("attach", host, entry["name"]), label(entry, shown)))
        entries.append((("new", host, ""), "+ new session"))
    return entries


def find_window(boss, host, name):
    for window in boss.all_windows:
        if window.user_vars.get("zmx_session") != name:
            continue
        owner = window.user_vars.get("remote_host", "")
        if is_local(host) and is_local(owner):
            return window
        if not is_local(host) and short_host(owner) == short_host(host):
            return window
    return None


@result_handler()
def handle_result(args, answer, target_window_id, boss):
    if not answer:
        return
    window = boss.window_id_map.get(target_window_id)

    def pick(choice):
        if not choice:
            return
        action, host, name = choice
        if action == "attach":
            existing = find_window(boss, host, name)
            if existing is not None:
                boss.set_active_window(existing, switch_os_window_if_needed=True)
                return
            open_args = [HELPER, "--attach", name]
        else:
            open_args = [HELPER]
        launch = ["launch", "--type=tab"]
        if not is_local(host):
            launch.append(f"--var=remote_host={host}")
        launch += ["--"] + open_command(host, open_args)
        boss.call_remote_control(window, tuple(launch))

    boss.choose_entry(
        "Switch to a zmx session:",
        build_entries(json.loads(answer)),
        pick,
        subtitle="* attached somewhere",
    )
