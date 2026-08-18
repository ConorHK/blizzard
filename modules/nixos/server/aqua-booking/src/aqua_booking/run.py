"""Book (or waitlist) the target Aqua Aerobics class for the day.

The 07:00 release is a thundering herd, so the whole acquire runs under one
wall-clock retry budget: transient failures (5xx/429/timeouts) and a class that
has not propagated to the feed yet are retried with decorrelated jitter; a
booking POST that errored is only ever retried after re-checking my_booking, so
a lost response can never turn into a double booking.
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

from .api import BookingApi, GymClass, TransientApiError, waitlist_position
from .auth import Authenticator, Credentials, TransientAuthError
from .config import Config, load_secrets
from .log import log, setup
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
        log.info("result: booked %s — confirmed seat%s", match.sfid, suffix)
        notify(f"{cfg.class_name} booked", f"{label} — confirmed seat{suffix}", priority=4, tags="swimmer")
    else:
        store.mark(match.sfid, match.title, match.from_date, f"waitlist:{position}")
        log.warning("result: waitlisted %s at position %s%s", match.sfid, position, suffix)
        notify(
            f"{cfg.class_name} waitlisted",
            f"{label} was full — you're #{position} on the waitlist{suffix}",
            priority=4,
            tags="hourglass",
        )


def main() -> int:
    parser = argparse.ArgumentParser(prog="aqua-booking")
    parser.add_argument("--config", default=os.environ.get("AQUA_CONFIG"))
    parser.add_argument("--secrets", default=os.environ.get("AQUA_SECRETS"))
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="discover only; never book, notify or touch the ledger (still authenticates)",
    )
    parser.add_argument("--login-only", action="store_true", help="authenticate and exit")
    parser.add_argument("--verbose", action="store_true", help="log at debug level")
    args = parser.parse_args()

    # A dry run exists to be read, so it is verbose by default.
    setup(debug=args.verbose or args.dry_run)

    secrets = load_secrets(args.secrets)
    cfg = Config.load(args.config, secrets)
    tz = ZoneInfo(cfg.timezone)
    policy = RetryPolicy(
        RetrySettings(
            cfg.retry.budget_seconds,
            cfg.retry.base_seconds,
            cfg.retry.max_backoff_seconds,
            cfg.retry.max_retry_after_seconds,
        )
    )

    auth = Authenticator(cfg, Credentials.from_secrets(secrets))
    if args.login_only:
        call_with_retry(policy, auth.access_token, (TransientAuthError,))
        log.info("auth ok")
        return 0

    store = Store(cfg.state_dir)
    code = _acquire(args, cfg, tz, policy, auth, store)
    if not args.dry_run:
        store.record_run()
    return code


def _acquire(args, cfg, tz, policy, auth, store) -> int:
    now = datetime.now(tz)
    target_date = (now + timedelta(days=cfg.release_horizon_days)).date()
    weekday = target_date.strftime("%A").lower()
    scheduled = cfg.schedule.get(weekday)
    if not scheduled:
        log.info("no class scheduled for %s (%s); nothing to do", weekday, target_date)
        return 0

    log.info(
        "target: %s on %s %s at %s (%s)",
        cfg.class_name, weekday, target_date, scheduled, cfg.gym_name,
    )

    token = call_with_retry(policy, auth.access_token, (TransientAuthError,))
    log.debug("signed in (%.0fs budget left)", policy.time_left())
    api = BookingApi(cfg, token)
    day_start = datetime.combine(target_date, time(0, 0), tz)
    day_end = datetime.combine(target_date, time(23, 59, 59), tz)

    if not args.dry_run:
        store.prune_before(datetime.now(tz) - timedelta(days=1))

    label = f"{cfg.gym_name} {weekday.capitalize()} {scheduled}"
    booked_this_run = False
    attempt = 0

    while True:
        attempt += 1
        try:
            classes = api.bookable_items(day_start.isoformat(), day_end.isoformat())
            log.debug("attempt %d: %d classes in the feed", attempt, len(classes))
        except TransientApiError as exc:
            log.warning(
                "discovery failed transiently (%s); %.0fs budget left", exc, policy.time_left()
            )
            if policy.wait(exc.retry_after):
                continue
            raise

        match = _find_match(classes, cfg, tz, target_date, scheduled)

        if match is None:
            # The class may not have propagated to the feed yet; give it a moment.
            if policy.wait():
                log.info("target not in the feed yet; retrying (%.0fs left)", policy.time_left())
                continue
            if booked_this_run:
                # A POST went out and the class then vanished: it may have landed.
                msg = f"{label} disappeared from the feed after a booking attempt — check the booking site"
                log.error(msg)
                if not args.dry_run:
                    notify(f"{cfg.class_name}: check needed", msg, priority=4, tags="warning")
                return 0
            msg = f"No {cfg.class_name} at {scheduled} on {weekday} {target_date} at {cfg.gym_name} — schedule change?"
            log.warning(msg)
            if not args.dry_run:
                notify(f"{cfg.class_name}: nothing to book", msg, priority=2, tags="calendar")
            return 0

        log.info(
            "match: sfid=%s from=%s is_full=%s", match.sfid, match.from_date, match.is_full
        )
        log.debug("my_booking=%s", match.my_booking)
        if args.dry_run:
            log.debug("raw item %s", json.dumps(match.raw)[:600])

        if store.was_booked(match.sfid):
            log.info(
                "%s already handled previously (cancellations are honoured); not rebooking",
                match.sfid,
            )
            return 0

        if match.my_booking is not None:
            if booked_this_run:
                _record_and_notify(store, cfg, match, label, waitlist_position({}, match), recovered=True)
            else:
                log.info("%s already booked outside this service; not rebooking", match.sfid)
                if not args.dry_run:
                    store.mark(match.sfid, match.title, match.from_date, "pre-existing")
            return 0

        if args.dry_run:
            state = "FULL, would join waitlist" if match.is_full else "would book a seat"
            log.info("dry-run: %s sfid=%s (%s)", label, match.sfid, state)
            return 0

        log.info("booking %s", match.sfid)
        try:
            response = api.book(match.sfid)
            # INFO, not DEBUG: this is the evidence for the seat/waitlist call.
            log.info("booking response: %s", json.dumps(response)[:400])
        except TransientApiError as exc:
            # The POST may have landed; the next loop re-checks my_booking before
            # it would ever POST again, so a lost response cannot double-book.
            booked_this_run = True
            log.warning(
                "booking failed transiently (%s); %.0fs budget left", exc, policy.time_left()
            )
            if policy.wait(exc.retry_after):
                continue
            raise

        _record_and_notify(store, cfg, match, label, waitlist_position(response, match))
        return 0
