import os
import sys
import time

from kitty.config import atomic_save
from kitty.constants import config_dir
from kitty.fast_data_types import add_timer
from kitty.utils import log_error

# Watchers get no sys.path help.
if config_dir not in sys.path:
    sys.path.append(config_dir)

from zmx_kitten import AUTOSAVE_DIR, SESSION_DIR, rewrite_launch

SUFFIX = ".kitty-session"

INTERVAL = 60

KEEP_DAYS = 7

KEEP_FILES = 40

state = {"path": "", "last": ""}


# Autosaves once lived beside named saves.
def sweep_legacy():
    for name in os.listdir(SESSION_DIR):
        if name.startswith("auto-") and name.endswith(SUFFIX):
            os.replace(
                os.path.join(SESSION_DIR, name), os.path.join(AUTOSAVE_DIR, name)
            )


# Age by mtime; a long run keeps its file.
def prune():
    found = []
    for name in os.listdir(AUTOSAVE_DIR):
        path = os.path.join(AUTOSAVE_DIR, name)
        if not name.endswith(SUFFIX) or not name.startswith("autosave-"):
            continue
        if path == state["path"]:
            continue
        try:
            found.append((os.path.getmtime(path), path))
        except OSError:
            continue
    found.sort()
    cutoff = time.time() - KEEP_DAYS * 86400
    stale = [path for when, path in found if when < cutoff]
    fresh = [path for when, path in found if when >= cutoff]
    for path in stale + fresh[: max(0, len(fresh) - KEEP_FILES)]:
        try:
            os.remove(path)
        except OSError:
            continue


def save(boss):
    try:
        lines = boss.serialize_state_as_session(state["path"])
        text = "\n".join(rewrite_launch(line) for line in lines)
        if not text.strip() or text == state["last"]:
            return
        atomic_save(text.encode(), state["path"])
        state["last"] = text
    except Exception as err:
        log_error(f"kitty session autosave failed: {err}")


# One file per kitty process, never reused.
def on_load(boss, data):
    stamp = time.strftime("%Y-%m-%d-%H%M%S")
    state["path"] = os.path.join(AUTOSAVE_DIR, f"autosave-{stamp}{SUFFIX}")
    try:
        os.makedirs(AUTOSAVE_DIR, exist_ok=True)
        sweep_legacy()
        prune()
    except OSError as err:
        log_error(f"kitty session autosave setup failed: {err}")
    add_timer(lambda timer_id: save(boss), INTERVAL, True)


def on_quit(boss, window, data):
    save(boss)
