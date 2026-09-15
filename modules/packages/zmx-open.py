import argparse
import base64
import os
import re
import subprocess
import sys
import urllib.parse

SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*://[^/]*")

TIMEOUT = 5


def zmx(args):
    try:
        done = subprocess.run(
            ["zmx", *args], capture_output=True, text=True, timeout=TIMEOUT
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return done.stdout if done.returncode == 0 else ""


def parse_args():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--attach")
    parser.add_argument("--base")
    parser.add_argument("--from", dest="from_session")
    parser.add_argument("--cwd")
    parser.add_argument("--new-family", action="store_true")
    return parser.parse_args()


def short_sessions():
    names = [line.strip() for line in zmx(["ls", "--short"]).splitlines()]
    return [name for name in names if name]


def family_taken(sessions, base):
    prefix = base + "."
    for name in sessions:
        suffix = name[len(prefix):]
        if name.startswith(prefix) and suffix.isdigit():
            return True
    return False


def fresh_base(sessions, base):
    if not family_taken(sessions, base):
        return base
    suffix = 2
    while family_taken(sessions, f"{base}-{suffix}"):
        suffix += 1
    return f"{base}-{suffix}"


def next_session(sessions, base):
    index = 1
    while f"{base}.{index}" in sessions:
        index += 1
    return f"{base}.{index}"


# kitty never sees OSC 7; zmx tracks it per session.
def from_cwd(want):
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
                return os.readlink(f"/proc/{pid}/cwd")
            except OSError:
                pass
        return ""
    return ""


def user_var(name, value):
    data = base64.b64encode(value.encode()).decode()
    return f"\033]1337;SetUserVar={name}={data}\007"


def main():
    opts = parse_args()
    cwd = opts.cwd or ""
    if opts.attach:
        session = opts.attach
    else:
        sessions = short_sessions()
        base = opts.base or os.uname().nodename.split(".", 1)[0]
        if opts.from_session:
            cwd = from_cwd(opts.from_session)
        if opts.new_family:
            base = fresh_base(sessions, base)
        session = next_session(sessions, base)

    if not os.path.isdir(cwd):
        cwd = os.environ.get("HOME", "/")

    # Escapes precede the exec; zmx would eat them.
    sys.stdout.write(
        f"\033]2;{session}\007"
        + user_var("zmx_session", session)
        + user_var("remote_host", os.uname().nodename)
    )
    sys.stdout.flush()
    os.chdir(cwd)
    os.execvp("zmx", ["zmx", "attach", session])


if __name__ == "__main__":
    main()
