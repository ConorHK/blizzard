"""Runtime configuration, in two halves.

The public half is generated as JSON by the NixOS module and lands in the world
-readable store. The private half — login, which gym, and which classes at which
times — comes from the agenix secret, so a public repo never records where
someone swims and when. Anything identifying belongs in the secret, not in an
option default.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

WEEKDAYS = (
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
)
_HH_MM = re.compile(r"^([01][0-9]|2[0-3]):[0-5][0-9]$")
_ENTRY_KEYS = frozenset({"time", "className"})


class ConfigError(Exception):
    pass


@dataclass(frozen=True)
class ScheduledClass:
    """One class to acquire on a given weekday."""

    time: str
    class_name: str


def _entry(day: str, raw: object) -> dict:
    """A schedule entry is "HH:MM", or {"time", "className"} to name the class."""
    if isinstance(raw, str):
        raw = {"time": raw}
    if not isinstance(raw, dict):
        raise ConfigError(f"{day} has a schedule entry that is neither a time nor an object: {raw!r}")
    unknown = sorted(set(raw) - _ENTRY_KEYS)
    if unknown:
        # Silently ignoring a typo here would book the wrong class, or none.
        raise ConfigError(f"{day} has unknown schedule entry keys: {', '.join(unknown)}")
    when = raw.get("time")
    if not isinstance(when, str) or not _HH_MM.match(when):
        raise ConfigError(f"{day} has a schedule time that is not HH:MM: {when!r}")
    class_name = raw.get("className")
    if class_name is not None and (not isinstance(class_name, str) or not class_name.strip()):
        raise ConfigError(f"{day} has an empty className at {when}")
    return {"time": when, "className": class_name.strip() if class_name else None}


def _day(day: str, raw: object) -> list[dict]:
    entries = [_entry(day, item) for item in (raw if isinstance(raw, list) else [raw])]
    seen = set()
    for entry in entries:
        key = (entry["time"], entry["className"])
        if key in seen:
            named = entry["className"] or "the default class"
            raise ConfigError(f"{day} schedules {named} at {entry['time']} twice")
        seen.add(key)
    # Earliest first, so the log and the notifications read in class order.
    return sorted(entries, key=lambda entry: (entry["time"], entry["className"] or ""))


def load_secrets(path: str | Path) -> dict:
    """Read and validate the private half. Nix used to check the schedule at
    build time; it is a runtime secret now, so the checks moved here."""
    text = Path(path).read_text()
    try:
        raw = json.loads(text)
    except json.JSONDecodeError as exc:
        hint = " (this is the old KEY=value format — it is JSON now)" if "=" in text else ""
        raise ConfigError(f"{path} is not valid JSON{hint}: {exc}") from exc
    if not isinstance(raw, dict):
        raise ConfigError(f"{path} must hold a JSON object")
    missing = [
        key
        for key in ("username", "password", "facilityId", "gymName", "schedule")
        if not raw.get(key)
    ]
    if missing:
        raise ConfigError(f"{path} is missing {', '.join(missing)}")
    if not isinstance(raw["schedule"], dict):
        raise ConfigError("schedule must map weekday names to the classes booked that day")
    schedule = {str(day).lower(): value for day, value in raw["schedule"].items()}
    unknown = sorted(set(schedule) - set(WEEKDAYS))
    if unknown:
        raise ConfigError(f"schedule has non-weekday keys: {', '.join(unknown)}")
    return raw | {"schedule": {day: _day(day, value) for day, value in schedule.items()}}


def schedule_with_default(
    schedule: dict[str, list[dict]], default_class: str
) -> dict[str, tuple[ScheduledClass, ...]]:
    """Resolve entries that named only a time against the public default class."""
    return {
        day: tuple(
            ScheduledClass(entry["time"], entry["className"] or default_class) for entry in entries
        )
        for day, entries in schedule.items()
    }


@dataclass(frozen=True)
class Api:
    base: str
    subscription_key: str
    user_agent: str
    origin: str


@dataclass(frozen=True)
class Auth:
    instance: str
    tenant: str
    policy: str
    client_id: str
    scope: str
    redirect_uri: str


@dataclass(frozen=True)
class Retry:
    budget_seconds: float
    base_seconds: float
    max_backoff_seconds: float
    max_retry_after_seconds: float


@dataclass(frozen=True)
class Config:
    facility_id: str
    gym_name: str
    timezone: str
    release_horizon_days: int
    schedule: dict[str, tuple[ScheduledClass, ...]]
    api: Api
    auth: Auth
    retry: Retry
    state_dir: Path

    @staticmethod
    def load(path: str | Path, secrets: dict) -> Config:
        raw = json.loads(Path(path).read_text())
        return Config(
            facility_id=secrets["facilityId"],
            gym_name=secrets["gymName"],
            schedule=schedule_with_default(secrets["schedule"], raw["className"]),
            timezone=raw["timezone"],
            release_horizon_days=raw["releaseHorizonDays"],
            api=Api(
                base=raw["api"]["base"].rstrip("/") + "/",
                subscription_key=raw["api"]["subscriptionKey"],
                user_agent=raw["api"]["userAgent"],
                origin=raw["api"]["origin"],
            ),
            auth=Auth(
                instance=raw["auth"]["instance"].rstrip("/") + "/",
                tenant=raw["auth"]["tenant"],
                policy=raw["auth"]["policy"],
                client_id=raw["auth"]["clientId"],
                scope=raw["auth"]["scope"],
                redirect_uri=raw["auth"]["redirectUri"],
            ),
            retry=Retry(
                budget_seconds=float(raw["retry"]["budgetSeconds"]),
                base_seconds=float(raw["retry"]["baseSeconds"]),
                max_backoff_seconds=float(raw["retry"]["maxBackoffSeconds"]),
                max_retry_after_seconds=float(raw["retry"]["maxRetryAfterSeconds"]),
            ),
            state_dir=Path(raw["stateDir"]),
        )
