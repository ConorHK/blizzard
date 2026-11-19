import os
import sys

from kittens.tui.handler import result_handler
from kitty.config import atomic_save

# kitty re-execs kittens but caches their imports.
sys.modules.pop("zmx_kitten", None)

from zmx_kitten import SESSION_DIR, rewrite_launch


def main(args):
    return ""


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    name = args[1] if len(args) > 1 else (boss.active_session or "default")
    path = os.path.join(SESSION_DIR, f"{name}.kitty-session")
    try:
        lines = [rewrite_launch(line) for line in boss.serialize_state_as_session(path)]
        os.makedirs(SESSION_DIR, exist_ok=True)
        atomic_save("\n".join(lines).encode(), path)
    except Exception as err:
        boss.show_error("Could not save session", f"{path}\n\n{err}")
