import os
import re
import shlex
import socket

from kittens.tui.handler import result_handler
from kitty.utils import path_from_osc7_url

HELPER = "zmx-open"

# ssh options that consume the next argument.
SSH_VALUE_FLAGS = frozenset("bcDEeFIiJLlmOopQRSWw")

ZMX_ATTACH = re.compile(r"(?:^|[/\s])zmx\s+(?:attach|a)\s+(\S+)")

SESSION_INDEX = re.compile(r"\.\d+$")


# A login shell finds the helper on PATH.
def remote_script(remote):
    guard = f'command -v {HELPER} >/dev/null 2>&1 || exec "$SHELL" -l'
    return f"{guard}; exec {shlex.join(remote)}"


def main(args):
    return ""


def short_host(name):
    return name.split(".", 1)[0]


def reported_cwd(window):
    url = window.screen.last_reported_cwd
    if not url:
        return "", ""
    if isinstance(url, bytes):
        url = url.decode("utf-8", "replace")
    _, _, rest = url.partition("//")
    return short_host(rest.split("/", 1)[0]), path_from_osc7_url(url)


def ssh_destination(cmdline):
    args = cmdline[1:]
    index = 0
    while index < len(args):
        arg = args[index]
        if not arg.startswith("-"):
            return arg.rsplit("@", 1)[-1]
        if not arg.startswith("--") and len(arg) == 2 and arg[1] in SSH_VALUE_FLAGS:
            index += 2
        else:
            index += 1
    return ""


def remote_context(window):
    host = window.user_vars.get("remote_host", "")
    session = window.user_vars.get("zmx_session", "")
    cwd = ""

    osc_host, osc_path = reported_cwd(window)
    if not host and osc_host and osc_host != short_host(socket.gethostname()):
        host = osc_host

    for process in window.child.foreground_processes:
        cmdline = process.get("cmdline") or []
        if not cmdline:
            continue
        joined = " ".join(cmdline)
        if not session:
            match = ZMX_ATTACH.search(joined)
            if match:
                session = match.group(1)
        if not host and os.path.basename(cmdline[0]) == "ssh":
            host = ssh_destination(cmdline)

    if host and not session and osc_host == host:
        cwd = osc_path

    return host, session, cwd


def sanitize(name):
    kept = "".join(c if (c.isalnum() or c in "_-") else "-" for c in name)
    return kept.strip("-")[:48]


def base_name(window, boss, session):
    if session:
        return SESSION_INDEX.sub("", session)
    tab = window.tabref() or boss.active_tab
    return sanitize(tab.effective_title if tab else "") or "kitty"


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    location = args[1] if len(args) > 1 else "split"
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return

    host, session, cwd = remote_context(window)

    launch = ["launch"]
    if location == "tab":
        launch.append("--type=tab")
    else:
        launch += ["--type=window", f"--location={location}"]

    if not host:
        if location != "tab":
            launch.append("--cwd=current")
        boss.call_remote_control(window, tuple(launch))
        return

    remote = [HELPER, "--base", base_name(window, boss, session)]
    if session:
        remote += ["--from", session]
    elif cwd:
        remote += ["--cwd", cwd]
    if location == "tab":
        remote.append("--new-family")

    launch.append(f"--var=remote_host={host}")
    launch += ["--", "ssh", "-t", host, shlex.join(["/bin/sh", "-lc", remote_script(remote)])]
    boss.call_remote_control(window, tuple(launch))
