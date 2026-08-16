"""Persistent ledger of class instances we have already acted on.

Keyed by the class sfid so a user cancellation is a durable override: once an
sfid is recorded, the runner never books it again even if the live booking has
since been cancelled.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


class Store:
    def __init__(self, state_dir: Path):
        self.path = state_dir / "booked.jsonl"

    def _entries(self) -> list[dict]:
        try:
            raw = self.path.read_text()
        except FileNotFoundError:
            return []
        return [json.loads(line) for line in raw.splitlines() if line.strip()]

    def was_booked(self, sfid: str) -> bool:
        return any(entry.get("sfid") == sfid for entry in self._entries())

    def mark(self, sfid: str, title: str, from_date: str, result: str) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        entries = [e for e in self._entries() if e.get("sfid") != sfid]
        entries.append(
            {
                "sfid": sfid,
                "title": title,
                "from_date": from_date,
                "result": result,
                "recorded_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        self._write(entries)

    def prune_before(self, cutoff: datetime) -> None:
        """Drop entries for classes that have already happened, keeping it small."""
        kept = []
        for entry in self._entries():
            try:
                when = datetime.fromisoformat(entry["from_date"])
            except (KeyError, ValueError):
                kept.append(entry)
                continue
            if when >= cutoff:
                kept.append(entry)
        self._write(kept)

    def _write(self, entries: list[dict]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text("".join(json.dumps(e) + "\n" for e in entries))
        tmp.replace(self.path)
