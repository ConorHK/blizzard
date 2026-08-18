"""Pure-logic tests for the parts the VM test cannot reach cheaply."""

from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from zoneinfo import ZoneInfo

from aqua_booking.api import GymClass, waitlist_position
from aqua_booking.config import ConfigError, load_secrets
from aqua_booking.retry import RetryPolicy, RetrySettings
from aqua_booking.run import _find_match
from aqua_booking.store import Store

LONDON = ZoneInfo("Europe/London")
CFG = SimpleNamespace(class_name="Aqua Aerobics")
WHEN = "2026-08-24T10:15:00+00:00"


def _cls(
    from_date: str,
    title: str = "Aqua Aerobics",
    is_full: bool = False,
    my_booking: dict | None = None,
) -> GymClass:
    return GymClass(
        sfid="S1", title=title, from_date=from_date, is_full=is_full, my_booking=my_booking
    )


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


class LoadSecrets(unittest.TestCase):
    """The schedule used to be checked by a Nix assertion at build time. It is a
    runtime secret now, so a typo has to fail loudly here instead."""

    def _write(self, payload) -> Path:
        path = Path(tempfile.mkdtemp()) / "secrets.json"
        path.write_text(payload if isinstance(payload, str) else json.dumps(payload))
        return path

    def _valid(self, **overrides) -> dict:
        return {
            "username": "someone@example.com",
            "password": "hunter2",
            "facilityId": "F1",
            "gymName": "Somewhere",
            "schedule": {"monday": "11:15"},
        } | overrides

    def test_reads_a_valid_secret(self):
        secrets = load_secrets(self._write(self._valid()))
        self.assertEqual(secrets["schedule"], {"monday": "11:15"})
        self.assertEqual(secrets["gymName"], "Somewhere")

    def test_weekday_keys_are_lowercased(self):
        secrets = load_secrets(self._write(self._valid(schedule={"Monday": "11:15"})))
        self.assertEqual(secrets["schedule"], {"monday": "11:15"})

    def test_rejects_a_non_weekday_key(self):
        with self.assertRaisesRegex(ConfigError, "non-weekday"):
            load_secrets(self._write(self._valid(schedule={"tuseday": "11:15"})))

    def test_rejects_a_malformed_time(self):
        with self.assertRaisesRegex(ConfigError, "HH:MM"):
            load_secrets(self._write(self._valid(schedule={"monday": "25:00"})))

    def test_rejects_a_missing_field(self):
        payload = self._valid()
        del payload["gymName"]
        with self.assertRaisesRegex(ConfigError, "gymName"):
            load_secrets(self._write(payload))

    def test_names_the_superseded_format(self):
        # The migration failure mode: the secret is still KEY=value lines.
        with self.assertRaisesRegex(ConfigError, "KEY=value"):
            load_secrets(self._write("NUFFIELD_USERNAME=a\nNUFFIELD_PASSWORD=b\n"))


class WaitlistPosition(unittest.TestCase):
    """Regression: a confirmed booking was announced as waitlist #1. The booking's
    own status decides; a position alongside a confirmed status is not a place in
    a queue, and class-level fullness says nothing either way."""

    def test_a_confirmed_status_beats_a_position(self):
        response = {"my_booking": {"status": "Booked", "waitlist_position": 1}}
        self.assertIsNone(waitlist_position(response, _cls(WHEN)))

    def test_a_full_class_can_still_hold_a_confirmed_booking(self):
        # Observed live: is_full is about remaining seats, not about this booking.
        response = {"my_booking": {"status": "Booked", "waitlist_position": None}}
        self.assertIsNone(waitlist_position(response, _cls(WHEN, is_full=True)))

    def test_a_waitlist_status_reports_its_position(self):
        response = {"my_booking": {"status": "Waitlist", "waitlist_position": 3}}
        self.assertEqual(waitlist_position(response, _cls(WHEN, is_full=True)), 3)

    def test_a_position_without_a_status_is_believed(self):
        self.assertEqual(waitlist_position({"waitlist_position": "2"}, _cls(WHEN)), 2)

    def test_zero_is_not_a_waitlist_place(self):
        self.assertIsNone(waitlist_position({"waitlist_position": 0}, _cls(WHEN)))

    def test_falls_back_to_the_feed_entry(self):
        booked = _cls(WHEN, my_booking={"waitlist_position": 4})
        self.assertEqual(waitlist_position({}, booked), 4)

    def test_the_feed_entry_status_is_honoured(self):
        booked = _cls(WHEN, is_full=True, my_booking={"status": "Booked", "waitlist_position": None})
        self.assertIsNone(waitlist_position({}, booked))


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
