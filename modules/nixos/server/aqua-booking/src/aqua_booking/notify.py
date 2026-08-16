"""Success/info notifications via the repo's alert-send, aimed at the ntfy
success topic. Errors are not sent here — the systemd OnFailure template pages
the alert module when the process exits non-zero.
"""

from __future__ import annotations

import os
import subprocess


def notify(title: str, message: str, priority: int = 3, tags: str = "swimmer") -> None:
    alert_send = os.environ.get("ALERT_SEND", "alert-send")
    env = dict(os.environ)
    topic_file = os.environ.get("AQUA_SUCCESS_TOPIC_FILE")
    if topic_file:
        env["ALERT_TOPIC_FILE"] = topic_file
    try:
        subprocess.run(
            [alert_send, title, message, str(priority), tags],
            env=env,
            check=False,
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"notify failed: {exc}")
