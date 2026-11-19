import sys

from kittens.tui.handler import result_handler

# kitty re-execs kittens but caches their imports.
sys.modules.pop("zmx_kitten", None)

from zmx_kitten import remote_context, run_zmx, sanitize


def main(args):
    return ""


def tab_sessions(tab):
    found = []
    seen = set()
    for window in tab.windows:
        host, session, _ = remote_context(window)
        if session and (host, session) not in seen:
            seen.add((host, session))
            found.append((host, session))
    return found


# zmx has no rename; a label is the closest durable substitute.
def label_sessions(boss, found, title):
    # zmx labels allow only alnum, -, _, . — no spaces.
    label = sanitize(title)
    if not label:
        return
    errors = []
    for host, session in found:
        _, err = run_zmx(host, ["set", session, f"title={label}"])
        if err:
            errors.append(f"{session}: {err}")
    if errors:
        boss.show_error("Could not label session(s)", "\n".join(errors))


def rename_tab(boss, tab):
    found = tab_sessions(tab)
    current = (tab.name or tab.title).strip()

    def apply(new_title):
        if not new_title:
            return
        tab.set_title(new_title)
        if found:
            label_sessions(boss, found, new_title)

    boss.get_line(
        "New tab title:",
        apply,
        prompt="> ",
        initial_value=current,
    )


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return
    tab = window.tabref() or boss.active_tab
    if tab is not None:
        rename_tab(boss, tab)
