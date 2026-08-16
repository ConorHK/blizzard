"""Pure-logic tests for the parts the VM test cannot reach cheaply."""

from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from zoneinfo import ZoneInfo

from aqua_booking.api import GymClass
from aqua_booking.retry import RetryPolicy, RetrySettings
from aqua_booking.run import _find_match
from aqua_booking.store import Store

LONDON = ZoneInfo("Europe/London")
CFG = SimpleNamespace(class_name="Aqua Aerobics")


def _cls(from_date: str, title: str = "Aqua Aerobics") -> GymClass:
    return GymClass(sfid="S1", title=title, from_date=from_date, is_full=False, my_booking=None)


class FindMatchTz(unittest.TestCase):
    """The API hands back absolute instants; matching happens in London local time."""

    def test_matches_across_bst(self):
        # 11:15 London on a summer date is 10:15Z.
        match = _find_match(
            [_cls("2026-08-24T10:15:00+00:00")], CFG, LONDON, datetime(2026, 8, 24).date(), "11:15"
        )
        self.assertIsNotNone(match)

    def test_matches_across_gmt(self):
        # The same wall-clock class in winter is 11:15Z.
        match = _find_match(
            [_cls("2026-11-23T11:15:00+00:00")], CFG, LONDON, datetime(2026, 11, 23).date(), "11:15"
        )
        self.assertIsNotNone(match)

    def test_does_not_match_the_wrong_offset(self):
        # 11:15Z in summer is 12:15 London and must not satisfy an 11:15 target.
        match = _find_match(
            [_cls("2026-08-24T11:15:00+00:00")], CFG, LONDON, datetime(2026, 8, 24).date(), "11:15"
        )
        self.assertIsNone(match)

    def test_ignores_other_classes(self):
        match = _find_match(
            [_cls("2026-08-24T10:15:00+00:00", title="Spin")],
            CFG,
            LONDON,
            datetime(2026, 8, 24).date(),
            "11:15",
        )
        self.assertIsNone(match)

    def test_horizon_lands_on_the_right_date_over_the_switch(self):
        # BST -> GMT falls on 2026-10-25; +7 days must stay calendar-exact.
        now = datetime(2026, 10, 22, 7, 0, tzinfo=LONDON)
        self.assertEqual((now + timedelta(days=7)).date(), datetime(2026, 10, 29).date())


class StorePrune(unittest.TestCase):
    def setUp(self):
        self.store = Store(Path(tempfile.mkdtemp()))
        self.cutoff = datetime(2026, 8, 20, 12, 0, tzinfo=timezone.utc)

    def test_naive_from_date_does_not_wedge_the_run(self):
        # Regression: comparing naive to aware raised TypeError, and because
        # pruning runs first, one bad row killed every later run permanently.
        self.store.mark("S1", "Aqua Aerobics", "2026-08-24T11:15:00", "booked")
        self.store.prune_before(self.cutoff)
        self.assertTrue(self.store.was_booked("S1"))

    def test_naive_from_date_still_prunes_when_past(self):
        self.store.mark("S1", "Aqua Aerobics", "2026-08-01T11:15:00", "booked")
        self.store.prune_before(self.cutoff)
        self.assertFalse(self.store.was_booked("S1"))

    def test_aware_entries_are_kept_and_dropped_on_the_cutoff(self):
        self.store.mark("KEEP", "Aqua Aerobics", "2026-08-24T11:15:00+01:00", "booked")
        self.store.mark("DROP", "Aqua Aerobics", "2026-08-01T11:15:00+01:00", "booked")
        self.store.prune_before(self.cutoff)
        self.assertTrue(self.store.was_booked("KEEP"))
        self.assertFalse(self.store.was_booked("DROP"))

    def test_unparseable_from_date_is_kept(self):
        self.store.mark("S1", "Aqua Aerobics", "not-a-date", "booked")
        self.store.prune_before(self.cutoff)
        self.assertTrue(self.store.was_booked("S1"))

    def test_mark_is_idempotent_per_sfid(self):
        self.store.mark("S1", "Aqua Aerobics", "2026-08-24T11:15:00+01:00", "booked")
        self.store.mark("S1", "Aqua Aerobics", "2026-08-24T11:15:00+01:00", "waitlist:2")
        self.assertEqual(len(self.store._entries()), 1)

    def test_record_run_writes_the_heartbeat(self):
        self.assertFalse(self.store.heartbeat.exists())
        self.store.record_run()
        self.assertTrue(self.store.heartbeat.exists())


class Retry(unittest.TestCase):
    def _policy(self, budget=10.0, base=1.0, max_backoff=5.0, max_retry_after=30.0):
        self.clock = [0.0]
        self.slept = []

        def sleep(seconds):
            self.slept.append(seconds)
            self.clock[0] += seconds

        return RetryPolicy(
            RetrySettings(budget, base, max_backoff, max_retry_after),
            now=lambda: self.clock[0],
            sleep=sleep,
        )

    def test_stops_once_the_budget_is_spent(self):
        policy = self._policy(budget=2.0)
        while policy.wait():
            pass
        self.assertLessEqual(sum(self.slept), 2.0)

    def test_never_sleeps_past_the_deadline(self):
        policy = self._policy(budget=3.0)
        policy.wait(retry_after=60.0)
        self.assertLessEqual(sum(self.slept), 3.0)

    def test_retry_after_is_capped(self):
        policy = self._policy(budget=1000.0, max_retry_after=30.0)
        policy.wait(retry_after=9999.0)
        self.assertEqual(self.slept, [30.0])

    def test_backoff_is_capped(self):
        policy = self._policy(budget=1000.0, max_backoff=5.0)
        for _ in range(20):
            policy.wait()
        self.assertTrue(all(delay <= 5.0 for delay in self.slept), self.slept)


if __name__ == "__main__":
    unittest.main()
