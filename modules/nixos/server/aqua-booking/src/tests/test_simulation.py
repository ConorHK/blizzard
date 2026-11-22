"""Seeded simulation of whole acquire runs against a fake gym on virtual time.

Each seed draws a gym, a schedule, a start time and a fault mix, runs _acquire,
then checks properties that must hold for every seed. Replay one seed with
AQUA_SIM_SEED=<n>; widen the sweep with AQUA_SIM_SEEDS=<count>.
"""

from __future__ import annotations

import argparse
import logging
import math
import os
import random
import tempfile
import unittest
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from unittest import mock
from zoneinfo import ZoneInfo

from aqua_booking.api import ApiError, GymClass, TransientApiError
from aqua_booking.auth import TransientAuthError
from aqua_booking.clock import Clock
from aqua_booking.config import WEEKDAYS, Api, Auth, Config, Retry, ScheduledClass
from aqua_booking.run import _RELEASE_SLACK, _acquire
from aqua_booking.store import Store

LONDON = ZoneInfo("Europe/London")
RELEASE = time(7, 0)
HORIZON_DAYS = 7
RETRY = Retry(600.0, 1.0, 5.0, 30.0, 15.0)
TITLES = ("Aqua Aerobics", "Spin", "Yoga")
SLOTS = ("09:15", "11:15", "18:30")
FIRST_DAY = date(2026, 1, 1)


class SimClock(Clock):
    """Virtual time in seconds since the run started."""

    def __init__(self, start: datetime, rng: random.Random):
        super().__init__(rng)
        self.start = start
        self.t = 0.0

    def now(self, tz):
        return (self.start + timedelta(seconds=self.t)).astimezone(tz)

    def monotonic(self):
        return self.t

    def sleep(self, seconds):
        if seconds < 0:
            raise AssertionError(f"negative sleep {seconds}")
        self.t += seconds


@dataclass
class SimClass:
    sfid: str
    title: str
    slot: str
    from_date: str
    seats: int
    waitlist: int
    visible_at: float
    my_booking: dict | None = None
    landed: int = 0

    def snapshot(self) -> GymClass:
        held = dict(self.my_booking) if self.my_booking else None
        return GymClass(self.sfid, self.title, self.from_date, self.seats == 0, held)


class World:
    """One seed's gym, schedule and faults; the gym side is driven by its own rng."""

    def __init__(self, seed: int):
        rng = self.rng = random.Random(seed)
        day = FIRST_DAY + timedelta(days=rng.randrange(730))
        release = datetime.combine(day, RELEASE, LONDON)
        # The timer fires two minutes early; manual reruns land after release.
        offset = rng.uniform(-150, -1) if rng.random() < 0.8 else rng.uniform(0, 900)
        self.clock = SimClock(
            (release + timedelta(seconds=offset)).astimezone(timezone.utc),
            random.Random(f"client-{seed}"),
        )
        self.release_t = -offset
        self.opens_t = self.release_t + rng.uniform(-1.0, 5.0)
        self.fault = rng.choice((0.0, 0.05, 0.2, 0.5))
        self.dry_run = rng.random() < 0.1

        target_day = day + timedelta(days=HORIZON_DAYS)
        pairs = [(t, s) for t in TITLES for s in SLOTS]
        rng.shuffle(pairs)
        wanted = pairs[: rng.choice((0, 1, 1, 2, 3))]
        self.schedule = {
            name: tuple(ScheduledClass(slot, title) for title, slot in wanted) for name in WEEKDAYS
        }

        self.classes: dict[str, SimClass] = {}
        self.preheld: set[str] = set()
        self.ledgered: set[str] = set()
        for i, (title, slot) in enumerate(pairs[: len(wanted) + rng.randrange(3)]):
            if i < len(wanted) and rng.random() < 0.1:
                continue
            local = datetime.combine(target_day, time.fromisoformat(slot), LONDON)
            cls = SimClass(
                sfid=f"S{i}",
                title=title,
                slot=slot,
                from_date=local.astimezone(timezone.utc).isoformat(),
                seats=rng.choice((0, 0, 1, 3, 20)),
                waitlist=rng.randrange(6),
                visible_at=rng.choice(
                    (
                        -1.0,
                        rng.uniform(0, max(self.release_t, 0)),
                        self.release_t + rng.uniform(0, 120),
                        self.release_t + rng.uniform(300, 1200),
                        math.inf,
                    )
                ),
            )
            roll = rng.random()
            if roll < 0.1:
                cls.my_booking = {"status": "Booked"}
                self.preheld.add(cls.sfid)
            elif roll < 0.2:
                self.ledgered.add(cls.sfid)
            self.classes[cls.sfid] = cls

        self.posts: list[tuple[str, float]] = []
        self.duplicates: list[str] = []
        self.early_landings: list[str] = []

    def config(self, state_dir: Path) -> Config:
        return Config(
            facility_id="F1",
            gym_name="Sim",
            timezone="Europe/London",
            release_horizon_days=HORIZON_DAYS,
            release_time=RELEASE,
            schedule=self.schedule,
            api=Api("http://sim/", "key", "agent", "http://origin"),
            auth=Auth("http://sim/", "t", "p", "c", "s", "r"),
            retry=RETRY,
            state_dir=state_dir,
        )

    def spend(self) -> bool:
        """Advance by one request's latency. True => it timed out."""
        herd = 0 <= self.clock.t - self.opens_t < 60
        latency = self.rng.uniform(0.5, 20.0) if herd else self.rng.uniform(0.05, 1.0)
        if latency > RETRY.request_timeout_seconds:
            self.clock.t += RETRY.request_timeout_seconds
            return True
        self.clock.t += latency
        return False


class SimAuth:
    def __init__(self, world: World):
        self.world = world

    def access_token(self):
        if self.world.spend() or self.world.rng.random() < self.world.fault:
            raise TransientAuthError("sim auth 503")
        return "TOKEN"


class SimApi:
    def __init__(self, world: World):
        self.world = world

    def _transient(self) -> TransientApiError:
        hint = self.world.rng.choice((None, None, self.world.rng.uniform(0, 60), 9999.0))
        return TransientApiError("sim 503/429", hint)

    def bookable_items(self, from_iso, to_iso):
        w = self.world
        if w.spend():
            raise TransientApiError("sim GET timeout")
        if w.rng.random() < w.fault:
            raise self._transient()
        lo, hi = datetime.fromisoformat(from_iso), datetime.fromisoformat(to_iso)
        return [
            c.snapshot()
            for c in w.classes.values()
            if c.visible_at <= w.clock.t and lo <= datetime.fromisoformat(c.from_date) <= hi
        ]

    def book(self, sfid):
        w = self.world
        w.posts.append((sfid, w.clock.t))
        timed_out = w.spend()
        cls = w.classes[sfid]
        if w.clock.t < w.opens_t:
            raise ApiError("sim POST -> 400: not open")
        if cls.my_booking is not None:
            w.duplicates.append(sfid)
            raise ApiError("sim POST -> 409: already booked")
        if timed_out and w.rng.random() < 0.5:
            raise TransientApiError("sim POST timeout before landing")
        if not timed_out and w.rng.random() < w.fault / 2:
            raise self._transient()
        if cls.seats > 0:
            cls.seats -= 1
            record = {"status": "Booked", "waitlist_position": None}
        else:
            cls.waitlist += 1
            record = {"status": "Waitlisted", "waitlist_position": cls.waitlist}
        cls.my_booking = record
        cls.landed += 1
        if timed_out:
            raise TransientApiError("sim POST timeout after landing")
        if w.rng.random() < w.fault / 2:
            raise TransientApiError("sim POST response lost")
        return dict(record) if w.rng.random() < 0.5 else {"my_booking": dict(record)}


def _expected_result(cls: SimClass) -> str:
    if cls.my_booking["status"] == "Booked":
        return "booked"
    return f"waitlist:{cls.my_booking['waitlist_position']}"


def simulate(seed: int) -> list[str]:
    """Run one seed. Returns the properties it broke."""
    return run_world(World(seed))


def run_world(w: World) -> list[str]:
    sent: list[tuple[str, str]] = []
    with tempfile.TemporaryDirectory() as tmp, mock.patch(
        "aqua_booking.run.notify", lambda title, message, **_: sent.append((title, message))
    ):
        store = Store(Path(tmp))
        for sfid in sorted(w.ledgered):
            c = w.classes[sfid]
            store.mark(sfid, c.title, c.from_date, "cancelled-by-user")
        before = store.path.read_bytes() if store.path.exists() else b""
        try:
            code = _acquire(
                argparse.Namespace(dry_run=w.dry_run),
                w.config(Path(tmp)),
                LONDON,
                SimAuth(w),
                store,
                connect=lambda cfg, token: SimApi(w),
                clock=w.clock,
            )
        except (TransientApiError, TransientAuthError):
            code = None
        ledger = {e["sfid"]: e["result"] for e in store._entries()}
        after = store.path.read_bytes() if store.path.exists() else b""

    broken = []
    posted = {sfid for sfid, _ in w.posts}
    if w.duplicates:
        broken.append(f"POSTed onto a held booking: {w.duplicates}")
    early = [(s, round(t, 2)) for s, t in w.posts if t < w.release_t]
    if early:
        broken.append(f"POSTed before release at t={w.release_t:.2f}: {early}")
    if posted & w.ledgered:
        broken.append(f"rebooked a ledgered class: {sorted(posted & w.ledgered)}")

    if w.dry_run:
        if w.posts or sent or after != before:
            broken.append("dry run wrote, posted or notified")
        return broken

    for cls in w.classes.values():
        if cls.landed == 0:
            continue
        label = f"{cls.slot} {cls.title}"
        flagged = any("check needed" in t and label in m for t, m in sent)
        recorded = ledger.get(cls.sfid)
        if recorded is None and code == 0 and not flagged:
            broken.append(f"{label}: booking landed, run exited 0, nothing recorded or sent")
        if recorded is not None and recorded != _expected_result(cls):
            broken.append(f"{label}: ledger says {recorded}, gym says {_expected_result(cls)}")
        waitlist_notes = [m for t, m in sent if t.endswith("waitlisted") and label in m]
        want = 1 if recorded and recorded.startswith("waitlist") else 0
        if len(waitlist_notes) != want:
            broken.append(f"{label}: {len(waitlist_notes)} waitlist notifications, want {want}")

    for sfid, result in ledger.items():
        if result.startswith(("booked", "waitlist")) and w.classes[sfid].landed == 0:
            broken.append(f"{sfid}: ledger says {result} but nothing landed")

    targets = sum(len(v) for v in w.schedule.values()) // len(WEEKDAYS)
    starts = max(0.0, w.release_t + _RELEASE_SLACK.total_seconds())
    limit = starts + RETRY.budget_seconds + (targets + 2) * RETRY.request_timeout_seconds
    if w.clock.t > limit:
        broken.append(f"ran {w.clock.t:.0f}s, limit {limit:.0f}s")

    if w.fault == 0 and w.release_t > 0:
        for sfid, cls in w.classes.items():
            wanted = any(
                e.class_name == cls.title and e.time == cls.slot for e in w.schedule[WEEKDAYS[0]]
            )
            calm = cls.visible_at <= w.release_t and sfid not in w.preheld | w.ledgered
            if wanted and calm and ledger.get(sfid) is None:
                broken.append(f"{cls.slot} {cls.title}: calm run did not book it")
    return broken


class Simulation(unittest.TestCase):
    def setUp(self):
        logger = logging.getLogger("aqua-booking")
        logger.disabled = True
        self.addCleanup(setattr, logger, "disabled", False)

    def test_seeded_runs_hold_every_property(self):
        if "AQUA_SIM_SEED" in os.environ:
            seeds = [int(os.environ["AQUA_SIM_SEED"])]
        else:
            seeds = range(int(os.environ.get("AQUA_SIM_SEEDS", "2000")))
        failures = {}
        for seed in seeds:
            try:
                broken = simulate(seed)
            except Exception as exc:  # noqa: BLE001
                broken = [f"raised {type(exc).__name__}: {exc}"]
            if broken:
                failures[seed] = broken
        report = "\n".join(
            f"seed {seed}: {'; '.join(msgs)}" for seed, msgs in list(failures.items())[:10]
        )
        if failures:
            self.fail(f"{len(failures)} seeds failed\n{report}")

    def test_same_seed_same_run(self):
        def trace(seed):
            w = World(seed)
            broken = run_world(w)
            return broken, w.posts, w.clock.t, [(c.sfid, c.my_booking) for c in w.classes.values()]

        for seed in range(20):
            self.assertEqual(trace(seed), trace(seed), seed)


if __name__ == "__main__":
    unittest.main()
