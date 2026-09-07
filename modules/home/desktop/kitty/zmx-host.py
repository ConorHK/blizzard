import os
import re
import sys

from kittens.tui.handler import result_handler

# kitty re-execs kittens but caches their imports.
sys.modules.pop("zmx_kitten", None)

from zmx_kitten import HELPER, is_local, open_command, sanitize

SSH_CONFIG = os.path.expanduser("~/.ssh/config")

HOST_LINE = re.compile(r"^\s*Host\s+(.+)$", re.IGNORECASE)

LAN_ALIAS = re.compile(r"-local$")


def main(args):
    return ""


def known_hosts():
    names = []
    try:
        with open(SSH_CONFIG) as config:
            for line in config:
                found = HOST_LINE.match(line)
                if not found:
                    continue
                for name in found.group(1).split():
                    if "*" not in name and "?" not in name and name not in names:
                        names.append(name)
    except OSError:
        pass
    return names


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    hosts = known_hosts()
    if not hosts:
        boss.show_error("No hosts", f"{SSH_CONFIG} lists no usable Host entries")
        return

    window = boss.window_id_map.get(target_window_id)

    def start(host, base):
        launch = ["launch", "--type=tab", f"--tab-title={base}"]
        if not is_local(host):
            launch.append(f"--var=remote_host={host}")
        launch += ["--"] + open_command(host, [HELPER, "--base", base, "--new-family"])
        boss.call_remote_control(window, tuple(launch))

    def pick(host):
        if not host:
            return
        # Both aliases reach one machine.
        default = LAN_ALIAS.sub("", host)

        def named(answer):
            if answer:
                start(host, sanitize(answer) or default)

        boss.get_line(
            f"Name the session on {host}:",
            named,
            window=window,
            initial_value=default,
            window_title="New zmx session",
        )

    boss.choose_entry("Open a zmx session on:", ((h, h) for h in hosts), pick)
