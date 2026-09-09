import sys

from kittens.tui.handler import result_handler

# kitty re-execs kittens but caches their imports.
sys.modules.pop("zmx_kitten", None)

from zmx_kitten import family, kill_sessions, list_sessions, remote_context


def main(args):
    return ""


def host_label(host):
    return host or "local"


def count_label(names):
    return "1 session" if len(names) == 1 else f"{len(names)} sessions"


def group_sessions(hosts):
    groups = {}
    titles = {}
    errors = []
    for host in hosts:
        sessions, err = list_sessions(host)
        if err:
            errors.append(f"{host_label(host)}: {err}")
        for name, title in sessions:
            groups.setdefault((host, family(name)), []).append(name)
            if title:
                titles[(host, name)] = title
    return groups, titles, errors


def build_entries(groups, titles):
    entries = []
    for key in sorted(groups):
        host, base = key
        names = sorted(groups[key])
        distinct = sorted({titles[(host, n)] for n in names if (host, n) in titles})
        suffix = f" [{', '.join(distinct)}]" if distinct else ""
        entries.append(
            ((host, names), f"{base} - {count_label(names)} on {host_label(host)}{suffix}")
        )
    for host in sorted({h for h, _ in groups}):
        keys = [k for k in groups if k[0] == host]
        if len(keys) < 2:
            continue
        every = sorted(name for k in keys for name in groups[k])
        entries.append(((host, every), f"everything on {host_label(host)} - {count_label(every)}"))
    return entries


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return

    host, _, _ = remote_context(window)
    groups, titles, errors = group_sessions([""] + ([host] if host else []))

    if not groups:
        boss.show_error("No sessions", "\n".join(errors) or "zmx has no sessions")
        return

    def kill(confirmed, chosen):
        if not confirmed:
            return
        target, names = chosen
        err = kill_sessions(target, names)
        if err:
            boss.show_error("Could not kill sessions", err)

    def pick(chosen):
        if not chosen:
            return
        target, names = chosen
        listed = "\n".join(f"  {name}" for name in names)
        boss.confirm(
            f"Kill {count_label(names)} on {host_label(target)}?\n\n{listed}\n",
            kill,
            chosen,
            window=window,
        )

    boss.choose_entry(
        "Kill zmx sessions:", build_entries(groups, titles), pick, subtitle="; ".join(errors)
    )
