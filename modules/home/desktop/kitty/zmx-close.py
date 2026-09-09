import sys

from kittens.tui.handler import result_handler

# kitty re-execs kittens but caches their imports.
sys.modules.pop("zmx_kitten", None)

from zmx_kitten import kill_sessions, remote_context


def main(args):
    return ""


def tab_sessions(tab):
    found = []
    for window in tab.windows:
        host, session, _ = remote_context(window)
        if session:
            found.append((host, session))
    return found


def kill_all(found):
    by_host = {}
    for host, session in found:
        by_host.setdefault(host, []).append(session)
    errors = []
    for host, names in by_host.items():
        err = kill_sessions(host, names)
        if err:
            errors.append(err)
    return "\n".join(errors)


def close_tab(boss, tab):
    found = tab_sessions(tab)
    if not found:
        boss.close_tab(tab)
        return

    def pick(choice):
        if not choice:
            return
        if choice == "kill":
            err = kill_all(found)
            if err:
                boss.show_error("Could not kill sessions", err)
                return
        for window in list(tab.windows):
            boss.mark_window_for_close(window)

    count = len(found)
    label = "1 session" if count == 1 else f"{count} sessions"
    boss.choose_entry(
        f"Close tab holding {label}:",
        [("detach", "Detach all - keep the sessions"), ("kill", f"Kill {label}")],
        pick,
        subtitle=", ".join(session for _, session in found),
    )


def close_window(boss, window):
    host, session, _ = remote_context(window)
    if not session:
        boss.close_window_with_confirmation()
        return

    def pick(choice):
        if not choice:
            return
        if choice == "kill":
            err = kill_sessions(host, [session])
            if err:
                boss.show_error("Could not kill session", err)
                return
        boss.mark_window_for_close(window)

    where = f" on {host}" if host else ""
    boss.choose_entry(
        f"Close pane attached to {session}{where}:",
        [("detach", "Detach - keep the session"), ("kill", f"Kill {session}")],
        pick,
    )


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    scope = args[1] if len(args) > 1 else "window"
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return
    if scope == "tab":
        tab = window.tabref() or boss.active_tab
        if tab is not None:
            close_tab(boss, tab)
    else:
        close_window(boss, window)
