import sys

from kittens.tui.handler import result_handler

# kitty re-execs kittens but caches their imports.
sys.modules.pop("zmx_kitten", None)

from zmx_kitten import HELPER, open_command, remote_context


def main(args):
    return ""


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    location = args[1] if len(args) > 1 else "split"
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return

    host, session, cwd = remote_context(window)
    # A local pane escapes the remote context.
    if location == "local" and host:
        host = session = cwd = ""

    launch = ["launch"]
    if location == "tab":
        launch.append("--type=tab")
    else:
        where = "split" if location == "local" else location
        launch += ["--type=window", f"--location={where}"]

    # zmx-open names the session after the project.
    open_args = [HELPER]
    if session:
        open_args += ["--from", session]
    elif cwd:
        open_args += ["--cwd", cwd]

    if host:
        launch.append(f"--var=remote_host={host}")
    launch += ["--"] + open_command(host, open_args)
    boss.call_remote_control(window, tuple(launch))
