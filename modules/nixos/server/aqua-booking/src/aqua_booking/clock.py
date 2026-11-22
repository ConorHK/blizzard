"""Every time and randomness source the acquire reads, so a test can swap them."""

from __future__ import annotations

import random
import time
from datetime import datetime, tzinfo


class Clock:
    def __init__(self, rng: random.Random | None = None):
        self.rng = rng or random.Random()

    def now(self, tz: tzinfo) -> datetime:
        return datetime.now(tz)

    def monotonic(self) -> float:
        return time.monotonic()

    def sleep(self, seconds: float) -> None:
        time.sleep(seconds)
