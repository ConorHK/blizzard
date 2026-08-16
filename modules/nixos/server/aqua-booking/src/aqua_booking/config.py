"""Runtime configuration, generated as JSON by the NixOS module."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


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
    success_topic: str

    @staticmethod
    def load(path: str | Path) -> Config:
        raw = json.loads(Path(path).read_text())
        return Config(
            facility_id=raw["facilityId"],
            gym_name=raw["gymName"],
            class_name=raw["className"],
            timezone=raw["timezone"],
            release_horizon_days=raw["releaseHorizonDays"],
            schedule={k.lower(): v for k, v in raw["schedule"].items()},
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
            success_topic=raw["successTopic"],
        )
