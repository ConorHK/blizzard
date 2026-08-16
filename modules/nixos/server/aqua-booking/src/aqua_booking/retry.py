"""Bounded, decorrelated-jitter retry for surviving the 07:00 booking herd.

Only transient failures (5xx, 429, connection timeouts/resets) are retried, and
only until a shared wall-clock deadline. Backoff is decorrelated jitter so our
attempts spread out and desynchronise from everyone else's retry storm rather
than hammering in lockstep; the server's Retry-After is honoured when present.
"""

from __future__ import annotations

import random
import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import TypeVar

_TRANSIENT_STATUSES = frozenset({429, 500, 502, 503, 504})

T = TypeVar("T")


def transient_status(code: int) -> bool:
    return code in _TRANSIENT_STATUSES


@dataclass(frozen=True)
class RetrySettings:
    budget_seconds: float
    base_seconds: float
    max_backoff_seconds: float
    max_retry_after_seconds: float


class RetryPolicy:
    """A single wall-clock budget shared across every retry in one run."""

    def __init__(
        self,
        settings: RetrySettings,
        now: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
    ):
        self.settings = settings
        self._now = now
        self._sleep = sleep
        self._deadline = now() + settings.budget_seconds
        self._prev = settings.base_seconds

    def time_left(self) -> float:
        return self._deadline - self._now()

    def _next_backoff(self) -> float:
        # Decorrelated jitter (AWS "Exponential Backoff and Jitter").
        upper = max(self.settings.base_seconds, self._prev * 3)
        delay = min(self.settings.max_backoff_seconds, random.uniform(self.settings.base_seconds, upper))
        self._prev = delay
        return delay

    def wait(self, retry_after: float | None = None) -> bool:
        """Sleep before the next attempt; return False when the budget is spent."""
        if self.time_left() <= 0:
            return False
        if retry_after is not None:
            delay = min(retry_after, self.settings.max_retry_after_seconds)
        else:
            delay = self._next_backoff()
        delay = min(delay, self.time_left())
        if delay > 0:
            self._sleep(delay)
        return self.time_left() > 0


def call_with_retry(policy: RetryPolicy, fn: Callable[[], T], retryable: tuple[type[Exception], ...]) -> T:
    """Run fn, retrying transient failures until the shared budget is spent."""
    while True:
        try:
            return fn()
        except retryable as exc:
            if not policy.wait(getattr(exc, "retry_after", None)):
                raise
