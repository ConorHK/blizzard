"""Book (or waitlist) the classes scheduled for the release-horizon day.

The 07:00 release is a thundering herd, so the whole acquire runs under one
wall-clock retry budget: transient failures (5xx/429/timeouts) and a class that
has not propagated to the feed yet are retried with decorrelated jitter; a
booking POST that errored is only ever retried after re-checking my_booking, so
a lost response can never turn into a double booking.

A day can hold several classes. They share one sign-in, one feed per sweep and
one budget, but each is resolved on its own: a class that never appears, or that
fails outright, costs the others nothing.
"""

from __future__ import annotations

import argparse
import json
import os
from dataclasses import dataclass
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

from .api import ApiError, BookingApi, GymClass, TransientApiError, waitlist_position
from .auth import Authenticator, Credentials, TransientAuthError
from .config import Config, ScheduledClass, load_secrets
from .log import log, setup
from .notify import notify
from .retry import RetryPolicy, RetrySettings, call_with_retry
from .store import Store


@dataclass
class _Target:
    """One scheduled class, and what this run has done about it so far."""

    entry: ScheduledClass
    label: str
    # Sticky: a booking POST went out at some point and may have landed.
    posted: bool = False
    # The last booking POST that failed transiently, if it has not been resolved.
    error: TransientApiError | None = None


def _find_match(classes, entry, tz, target_date) -> GymClass | None:
    for gym_class in classes:
        if gym_class.title != entry.class_name:
            continue
        local = datetime.fromisoformat(gym_class.from_date).astimezone(tz)
        if local.date() == target_date and local.strftime("%H:%M") == entry.time:
            return gym_class
    return None


def _listing(classes, tz) -> str:
    return "; ".join(
        f"{datetime.fromisoformat(c.from_date).astimezone(tz).strftime('%H:%M')} {c.title}"
        for c in sorted(classes, key=lambda c: c.from_date)
    )


def _record_and_notify(store, target, match, position, recovered=False) -> None:
    suffix = " (recovered after a retry)" if recovered else ""
    name = target.entry.class_name
    if position is None:
        store.mark(match.sfid, match.title, match.from_date, "booked")
        log.info("result: booked %s (%s) — confirmed seat%s", match.sfid, target.label, suffix)
        notify(f"{name} booked", f"{target.label} — confirmed seat{suffix}", priority=4, tags="swimmer")
    else:
        store.mark(match.sfid, match.title, match.from_date, f"waitlist:{position}")
        log.warning(
            "result: waitlisted %s (%s) at position %s%s", match.sfid, target.label, position, suffix
        )
        notify(
            f"{name} waitlisted",
            f"{target.label} was full — you're #{position} on the waitlist{suffix}",
            priority=4,
            tags="hourglass",
        )


def _settle(args, target, match, store, api) -> bool:
    """Act on one target against the current feed. True => not resolved yet."""
    # A fresh sweep supersedes whatever the last one failed with.
    target.error = None

    if match is None:
        # The class may not have propagated to the feed yet; give it a moment.
        return True

    log.info(
        "match: %s sfid=%s from=%s is_full=%s",
        target.label, match.sfid, match.from_date, match.is_full,
    )
    log.debug("my_booking=%s", match.my_booking)
    if args.dry_run:
        log.debug("raw item %s", json.dumps(match.raw)[:600])

    if store.was_booked(match.sfid):
        log.info(
            "%s already handled previously (cancellations are honoured); not rebooking", match.sfid
        )
        return False

    if match.my_booking is not None:
        if target.posted:
            _record_and_notify(store, target, match, waitlist_position({}, match), recovered=True)
        else:
            log.info("%s already booked outside this service; not rebooking", match.sfid)
            if not args.dry_run:
                store.mark(match.sfid, match.title, match.from_date, "pre-existing")
        return False

    if args.dry_run:
        state = "FULL, would join waitlist" if match.is_full else "would book a seat"
        log.info("dry-run: %s sfid=%s (%s)", target.label, match.sfid, state)
        return False

    log.info("booking %s (%s)", match.sfid, target.label)
    try:
        response = api.book(match.sfid)
        # INFO, not DEBUG: this is the evidence for the seat/waitlist call.
        log.info("booking response: %s", json.dumps(response)[:400])
    except TransientApiError as exc:
        # The POST may have landed; the next sweep re-checks my_booking before it
        # would ever POST again, so a lost response cannot double-book.
        target.posted = True
        target.error = exc
        log.warning("booking %s failed transiently (%s)", target.label, exc)
        return True

    _record_and_notify(store, target, match, waitlist_position(response, match))
    return False


def _give_up(args, target, weekday, target_date, gym_name) -> bool:
    """Report a target the budget ran out on. True => the run has failed."""
    name = target.entry.class_name
    if target.error is not None:
        # We POSTed, never got an answer, and never got back to check. Let the
        # unit fail so OnFailure pages with the journal attached.
        log.error("booking %s never confirmed: %s", target.label, target.error)
        return True
    if target.posted:
        msg = f"{target.label} disappeared from the feed after a booking attempt — check the booking site"
        log.error(msg)
        if not args.dry_run:
            notify(f"{name}: check needed", msg, priority=4, tags="warning")
        return False
    msg = f"No {name} at {target.entry.time} on {weekday} {target_date} at {gym_name} — schedule change?"
    log.warning(msg)
    if not args.dry_run:
        notify(f"{name}: nothing to book", msg, priority=2, tags="calendar")
    return False


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
    if not args.dry_run and code == 0:
        store.record_run()
    return code


def _acquire(args, cfg, tz, policy, auth, store) -> int:
    now = datetime.now(tz)
    target_date = (now + timedelta(days=cfg.release_horizon_days)).date()
    weekday = target_date.strftime("%A").lower()
    entries = cfg.schedule.get(weekday, ())
    if not entries:
        log.info("nothing scheduled for %s (%s); nothing to do", weekday, target_date)
        return 0

    targets = [
        _Target(entry, f"{cfg.gym_name} {weekday.capitalize()} {entry.time} {entry.class_name}")
        for entry in entries
    ]
    log.info(
        "targets on %s %s at %s: %s",
        weekday,
        target_date,
        cfg.gym_name,
        ", ".join(f"{t.entry.class_name} at {t.entry.time}" for t in targets),
    )

    token = call_with_retry(policy, auth.access_token, (TransientAuthError,))
    log.debug("signed in (%.0fs budget left)", policy.time_left())
    api = BookingApi(cfg, token)
    day_start = datetime.combine(target_date, time(0, 0), tz)
    day_end = datetime.combine(target_date, time(23, 59, 59), tz)

    if not args.dry_run:
        store.prune_before(datetime.now(tz) - timedelta(days=1))

    pending = targets
    failed = False
    attempt = 0

    while True:
        attempt += 1
        try:
            classes = api.bookable_items(day_start.isoformat(), day_end.isoformat())
            log.debug("attempt %d: %d classes in the feed", attempt, len(classes))
            if args.dry_run:
                # A schedule entry has to name a class exactly, so list what is on.
                log.debug("feed: %s", _listing(classes, tz))
        except TransientApiError as exc:
            log.warning(
                "discovery failed transiently (%s); %.0fs budget left", exc, policy.time_left()
            )
            if policy.wait(exc.retry_after):
                continue
            raise

        unresolved = []
        for target in pending:
            match = _find_match(classes, target.entry, tz, target_date)
            try:
                if _settle(args, target, match, store, api):
                    unresolved.append(target)
            except ApiError:
                # One class refused outright; the rest of the day still gets a go.
                log.exception("booking %s failed", target.label)
                failed = True
        pending = unresolved
        if not pending:
            break

        hints = [
            t.error.retry_after
            for t in pending
            if t.error is not None and t.error.retry_after is not None
        ]
        if policy.wait(max(hints) if hints else None):
            log.info(
                "%d target(s) unresolved; retrying (%.0fs left)", len(pending), policy.time_left()
            )
            continue

        for target in pending:
            failed = _give_up(args, target, weekday, target_date, cfg.gym_name) or failed
        break

    return 1 if failed else 0
