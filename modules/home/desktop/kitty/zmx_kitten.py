import os
import re
import shlex
import socket
import subprocess

from kitty.utils import path_from_osc7_url

HELPER = "zmx-open"

TIMEOUT = 5

# ssh options that consume the next argument.
SSH_VALUE_FLAGS = frozenset("bcDEeFIiJLlmOopQRSWw")

ZMX_ATTACH = re.compile(r"(?:^|[/\s])zmx\s+(?:attach|a)\s+(\S+)")

SESSION_INDEX = re.compile(r"\.\d+$")

SESSION_DIR = os.path.expanduser("~/.local/share/kitty/sessions")

AUTOSAVE_DIR = os.path.join(SESSION_DIR, "autosave")

UNSERIALIZE = "kitty-unserialize-data="

HOST_VAR = re.compile(r"^--var=remote_host=(.+)$")

SESSION_VAR = re.compile(r"^--var=zmx_session=(.+)$")


def short_host(name):
    return name.split(".", 1)[0]


def is_local(host):
    return not host or short_host(host) == short_host(socket.gethostname())


def sanitize(name):
    kept = "".join(c if (c.isalnum() or c in "_-") else "-" for c in name)
    return kept.strip("-")[:48]


def family(session):
    return SESSION_INDEX.sub("", session)


# A login shell finds the helper on PATH.
def remote_script(remote):
    guard = f'command -v {HELPER} >/dev/null 2>&1 || exec "$SHELL" -l'
    return f"{guard}; exec {shlex.join(remote)}"


# ssh joins argv without quoting, so pre-join it.
def ssh_command(host, remote):
    return ["ssh", "-t", host, shlex.join(["/bin/sh", "-lc", remote_script(remote)])]


def open_command(host, open_args):
    return open_args if is_local(host) else ssh_command(host, open_args)


def split_flags(tokens):
    index = 1
    while index < len(tokens):
        token = tokens[index]
        if not token.startswith("-") and not token.startswith(UNSERIALIZE):
            break
        index += 1
    return tokens[:index], tokens[index:]


# Replayed panes must reattach, not spawn a sibling.
def rewrite_launch(line):
    if not line.startswith("launch "):
        return line
    flags, _ = split_flags(shlex.split(line))
    host = session = ""
    for token in flags:
        found = HOST_VAR.match(token)
        if found:
            host = found.group(1)
        found = SESSION_VAR.match(token)
        if found:
            session = found.group(1)
    if not session:
        return line
    return shlex.join(flags + open_command(host, [HELPER, "--attach", session]))


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
    local = short_host(socket.gethostname())
    # zmx-open reports its own host, even locally.
    host = window.user_vars.get("remote_host", "")
    if short_host(host) == local:
        host = ""
    session = window.user_vars.get("zmx_session", "")
    cwd = ""

    osc_host, osc_path = reported_cwd(window)
    if not host and osc_host and osc_host != local:
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

    if not session and osc_host == (host or local):
        cwd = osc_path

    return host, session, cwd


# Queries need no tty, unlike open_command.
def zmx_command(host, args):
    argv = ["zmx"] + list(args)
    if is_local(host):
        return argv
    remote = shlex.join(["/bin/sh", "-lc", shlex.join(argv)])
    return ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=3", host, remote]


def run_zmx(host, args):
    try:
        done = subprocess.run(
            zmx_command(host, args), capture_output=True, text=True, timeout=TIMEOUT
        )
    except (OSError, subprocess.SubprocessError) as err:
        return "", str(err)
    if done.returncode != 0:
        return done.stdout, (done.stderr or done.stdout).strip() or "zmx failed"
    return done.stdout, ""


def list_sessions(host):
    out, err = run_zmx(host, ["ls"])
    names = []
    for line in out.splitlines():
        fields = dict(f.split("=", 1) for f in line.strip().split("\t") if "=" in f)
        name = fields.get("name")
        if name:
            names.append(name)
    # Empty list means none, not failure.
    return (names, "") if names else ([], err)


def kill_sessions(host, names):
    return run_zmx(host, ["kill"] + list(names))[1]
