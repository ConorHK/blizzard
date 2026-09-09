import socket
import sys

from kittens.tui.handler import result_handler

# kitty re-execs kittens but caches their imports.
sys.modules.pop("zmx_kitten", None)

from zmx_kitten import HELPER, family, open_command, remote_context, sanitize, short_host


def main(args):
    return ""


def base_name(window, boss, session):
    if session:
        return family(session)
    tab = window.tabref() or boss.active_tab
    return sanitize(tab.effective_title if tab else "") or "kitty"


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    location = args[1] if len(args) > 1 else "split"
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return

    # A local tab escapes the pane's remote context.
    local = location == "local"
    tab = local or location == "tab"
    host, session, cwd = ("", "", "") if local else remote_context(window)

    launch = ["launch"]
    if tab:
        launch.append("--type=tab")
    else:
        launch += ["--type=window", f"--location={location}"]

    if local:
        base = sanitize(short_host(socket.gethostname())) or "kitty"
    else:
        base = base_name(window, boss, session)

    open_args = [HELPER, "--base", base]
    if session:
        open_args += ["--from", session]
    elif cwd:
        open_args += ["--cwd", cwd]
    if tab:
        open_args.append("--new-family")

    if host:
        launch.append(f"--var=remote_host={host}")
    launch += ["--"] + open_command(host, open_args)
    boss.call_remote_control(window, tuple(launch))
