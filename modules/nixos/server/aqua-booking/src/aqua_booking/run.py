"""Book (or waitlist) the target Aqua Aerobics class for the day.

The 07:00 release is a thundering herd, so the whole acquire runs under one
wall-clock retry budget: transient failures (5xx/429/timeouts) and a class that
has not propagated to the feed yet are retried with decorrelated jitter; a
booking POST that errored is only ever retried after re-checking my_booking, so
a lost response can never turn into a double booking.
"""

from __future__ import annotations

import argparse
import os
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

from .api import BookingApi, GymClass, TransientApiError, waitlist_position
from .auth import Authenticator, Credentials, TransientAuthError
from .config import Config
from .notify import notify
from .retry import RetryPolicy, RetrySettings, call_with_retry
from .store import Store


def _find_match(classes, cfg, tz, target_date, scheduled) -> GymClass | None:
    for gym_class in classes:
        if gym_class.title != cfg.class_name:
            continue
        local = datetime.fromisoformat(gym_class.from_date).astimezone(tz)
        if local.date() == target_date and local.strftime("%H:%M") == scheduled:
            return gym_class
    return None


def _record_and_notify(store, cfg, match, label, position, recovered=False) -> None:
    suffix = " (recovered after a retry)" if recovered else ""
    if position is None:
        store.mark(match.sfid, match.title, match.from_date, "booked")
        notify(f"{cfg.class_name} booked", f"{label} — confirmed seat{suffix}", priority=4, tags="swimmer")
    else:
        store.mark(match.sfid, match.title, match.from_date, f"waitlist:{position}")
        notify(
            f"{cfg.class_name} waitlisted",
            f"{label} was full — you're #{position} on the waitlist{suffix}",
            priority=4,
            tags="hourglass",
        )


def main() -> int:
    parser = argparse.ArgumentParser(prog="aqua-booking")
    parser.add_argument("--config", default=os.environ.get("AQUA_CONFIG"))
    parser.add_argument("--credentials", default=os.environ.get("AQUA_CREDENTIALS"))
    parser.add_argument("--dry-run", action="store_true", help="discover only; never book or notify")
    parser.add_argument("--login-only", action="store_true", help="authenticate and exit")
    args = parser.parse_args()

    cfg = Config.load(args.config)
    tz = ZoneInfo(cfg.timezone)
    policy = RetryPolicy(
        RetrySettings(
            cfg.retry.budget_seconds,
            cfg.retry.base_seconds,
            cfg.retry.max_backoff_seconds,
            cfg.retry.max_retry_after_seconds,
        )
    )

    auth = Authenticator(cfg, Credentials.load(args.credentials))
    if args.login_only:
        call_with_retry(policy, auth.access_token, (TransientAuthError,))
        print("auth ok")
        return 0

    now = datetime.now(tz)
    target_date = (now + timedelta(days=cfg.release_horizon_days)).date()
    weekday = target_date.strftime("%A").lower()
    scheduled = cfg.schedule.get(weekday)
    if not scheduled:
        print(f"no class scheduled for {weekday} ({target_date}); nothing to do")
        return 0

    print(f"target: {cfg.class_name} on {weekday} {target_date} at {scheduled} ({cfg.gym_name})")

    token = call_with_retry(policy, auth.access_token, (TransientAuthError,))
    api = BookingApi(cfg, token)
    day_start = datetime.combine(target_date, time(0, 0), tz)
    day_end = datetime.combine(target_date, time(23, 59, 59), tz)

    store = Store(cfg.state_dir)
    store.prune_before(datetime.now(tz) - timedelta(days=1))

    label = f"{cfg.gym_name} {weekday.capitalize()} {scheduled}"
    booked_this_run = False

    while True:
        try:
            classes = api.bookable_items(day_start.isoformat(), day_end.isoformat())
        except TransientApiError as exc:
            print(f"discovery failed transiently ({exc}); {policy.time_left():.0f}s budget left")
            if policy.wait(exc.retry_after):
                continue
            raise

        match = _find_match(classes, cfg, tz, target_date, scheduled)

        if match is None:
            # The class may not have propagated to the feed yet; give it a moment.
            if policy.wait():
                print(f"target not in the feed yet; retrying ({policy.time_left():.0f}s left)")
                continue
            msg = f"No {cfg.class_name} at {scheduled} on {weekday} {target_date} at {cfg.gym_name} — schedule change?"
            print(msg)
            if not args.dry_run:
                notify(f"{cfg.class_name}: nothing to book", msg, priority=2, tags="calendar")
            return 0

        if store.was_booked(match.sfid):
            print(f"{match.sfid} already handled previously (cancellations are honoured); not rebooking")
            return 0

        if match.my_booking is not None:
            if booked_this_run:
                _record_and_notify(store, cfg, match, label, waitlist_position({}, match), recovered=True)
            else:
                print(f"{match.sfid} already booked outside this service; recording, not rebooking")
                store.mark(match.sfid, match.title, match.from_date, "pre-existing")
            return 0

        if args.dry_run:
            state = "FULL, would join waitlist" if match.is_full else "would book a seat"
            print(f"dry-run: {label} sfid={match.sfid} ({state})")
            return 0

        try:
            response = api.book(match.sfid)
        except TransientApiError as exc:
            # The POST may have landed; the next loop re-checks my_booking before
            # it would ever POST again, so a lost response cannot double-book.
            booked_this_run = True
            print(f"booking failed transiently ({exc}); {policy.time_left():.0f}s budget left")
            if policy.wait(exc.retry_after):
                continue
            raise

        _record_and_notify(store, cfg, match, label, waitlist_position(response, match))
        return 0
