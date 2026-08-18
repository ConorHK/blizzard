"""Runtime configuration, in two halves.

The public half is generated as JSON by the NixOS module and lands in the world
-readable store. The private half — login, which gym, and which times — comes
from the agenix secret, so a public repo never records where someone swims and
when. Anything identifying belongs in the secret, not in an option default.
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


class ConfigError(Exception):
    pass


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
        raise ConfigError("schedule must map weekday names to HH:MM times")
    schedule = {str(day).lower(): time for day, time in raw["schedule"].items()}
    unknown = sorted(set(schedule) - set(WEEKDAYS))
    if unknown:
        raise ConfigError(f"schedule has non-weekday keys: {', '.join(unknown)}")
    malformed = sorted(day for day, time in schedule.items() if not _HH_MM.match(str(time)))
    if malformed:
        raise ConfigError(f"schedule times must be HH:MM: {', '.join(malformed)}")
    return raw | {"schedule": schedule}


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
    class_name: str
    timezone: str
    release_horizon_days: int
    schedule: dict[str, str]
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
            schedule=secrets["schedule"],
            class_name=raw["className"],
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
