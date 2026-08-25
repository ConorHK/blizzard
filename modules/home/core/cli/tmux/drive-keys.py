"""Drive a real tmux client over a pty, so keys go through the key tables.

Everything else about the config can be read back out of the server; whether a
keystroke actually lands on the right binding can only be shown by typing it.
"""

import os
import pty
import subprocess
import sys
import time

CONF, FAKE_NVIM, SESH = sys.argv[1], sys.argv[2], sys.argv[3]
SESSION = "drive"
KEYLOG = os.path.join(os.getcwd(), "nvim-keys")

C_B, C_H, C_L, C_T = b"\x02", b"\x08", b"\x0c", b"\x14"

failures = []


def tmux(*args):
    done = subprocess.run(["tmux", *args], capture_output=True, text=True, check=False)
    if done.returncode != 0:
        raise SystemExit(f"tmux {' '.join(args)} failed: {done.stderr.strip()}")
    return done.stdout.strip()


def state(fmt, target=SESSION):
    return tmux("display-message", "-p", "-t", target, fmt)


def expect(what, predicate, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            print(f"ok   {what}")
            return
        time.sleep(0.1)
    failures.append(what)
    print(f"FAIL {what}")


def expect_stable(what, predicate, settle=1.5):
    """For the checks that assert a key did *not* do something."""
    time.sleep(settle)
    if predicate():
        print(f"ok   {what}")
    else:
        failures.append(what)
        print(f"FAIL {what}")


def keys_seen_by_nvim():
    try:
        with open(KEYLOG, encoding="ascii") as log:
            return log.read().split()
    except FileNotFoundError:
        return []


# Pane 1 runs an "editor" that should keep C-hjkl, pane 2 yields them to tmux.
# `exec` so the pane's foreground process is the command and not the shell.
tmux("-f", CONF, "new-session", "-d", "-x", "80", "-y", "24", "-s", SESSION, f"exec {FAKE_NVIM} {KEYLOG}")
tmux("split-window", "-h", "-t", f"{SESSION}:1", "exec sleep 600")

primary, secondary = pty.openpty()
client = subprocess.Popen(
    ["tmux", "attach-session", "-t", SESSION],
    stdin=secondary,
    stdout=secondary,
    stderr=secondary,
    env={**os.environ, "TERM": "xterm-256color"},
)
os.close(secondary)


def press(*keys):
    for key in keys:
        os.write(primary, key)
        time.sleep(0.05)


try:
    expect("a client attaches", lambda: state("#{session_attached}") == "1")

    print("\n# C-hjkl against a pane that yields them")
    expect("the plain pane is focused", lambda: state("#{pane_index}") == "2")
    press(C_H)
    expect("C-h moves focus left out of a plain pane", lambda: state("#{pane_index}") == "1")

    print("\n# C-hjkl against a pane that owns them")
    press(C_L)
    expect("C-l reaches an editor instead of tmux", lambda: "0c" in keys_seen_by_nvim())
    expect_stable("C-l leaves focus alone in an editor", lambda: state("#{pane_index}") == "1")

    print("\n# the prefix")
    press(C_T, b"z")
    expect("C-t z zooms the pane", lambda: state("#{window_zoomed_flag}") == "1")
    press(C_T, b"z")
    expect("C-t z unzooms it", lambda: state("#{window_zoomed_flag}") == "0")

    press(C_B, b"z")
    expect_stable("C-b is no longer the prefix", lambda: state("#{window_zoomed_flag}") == "0")

    print("\n# splitting")
    width = int(state("#{pane_width}"))
    panes = int(state("#{window_panes}"))
    press(C_T, b"v")
    expect("C-t v adds a pane", lambda: int(state("#{window_panes}")) == panes + 1)
    expect("C-t v splits left/right", lambda: int(state("#{pane_width}")) < width)

    print("\n# the session picker")
    picker_primary, picker_secondary = pty.openpty()
    picker = subprocess.Popen(
        [SESH],
        stdin=picker_secondary,
        stdout=picker_secondary,
        stderr=picker_secondary,
        env={k: v for k, v in os.environ.items() if k != "TMUX"} | {"TERM": "xterm-256color"},
    )
    os.close(picker_secondary)
    expect(
        "sesh attaches to the session that is already running",
        lambda: state("#{session_attached}") == "2",
    )
    picker.kill()
    os.close(picker_primary)
finally:
    os.close(primary)
    client.kill()
    subprocess.run(["tmux", "kill-server"], check=False, capture_output=True)

if failures:
    print(f"\n{len(failures)} check(s) failed:")
    for failure in failures:
        print(f"  - {failure}")
    raise SystemExit(1)

print("\nall checks passed")
