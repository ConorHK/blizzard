"""Levelled logging, formatted for journald.

Each line carries both a visible level and the syslog priority systemd parses
off the front, so the journal reads cleanly and `journalctl -p warning -u
aqua-booking` narrows to the runs that did not get a seat.
"""

from __future__ import annotations

import logging
import sys

_PRIORITY = {
    logging.DEBUG: 7,
    logging.INFO: 6,
    logging.WARNING: 4,
    logging.ERROR: 3,
    logging.CRITICAL: 2,
}

log = logging.getLogger("aqua-booking")


class _JournaldFormatter(logging.Formatter):
    """systemd strips the <N> prefix and keeps it as the entry's priority."""

    def format(self, record: logging.LogRecord) -> str:
        priority = _PRIORITY.get(record.levelno, 6)
        text = super().format(record)
        return "\n".join(f"<{priority}>{line}" for line in text.splitlines())


def setup(debug: bool = False) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(_JournaldFormatter("%(levelname)-7s %(message)s"))
    logging.basicConfig(
        level=logging.DEBUG if debug else logging.INFO,
        handlers=[handler],
        force=True,
    )
