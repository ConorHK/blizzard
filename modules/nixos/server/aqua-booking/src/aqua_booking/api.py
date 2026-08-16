"""Thin client for Nuffield's APIM booking gateway (member tier)."""

from __future__ import annotations

import email.utils
import json
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone

from .config import Config
from .retry import transient_status


class ApiError(Exception):
    pass


class TransientApiError(ApiError):
    """A retryable failure (5xx/429/timeout); may carry a Retry-After hint."""

    def __init__(self, message: str, retry_after: float | None = None):
        super().__init__(message)
        self.retry_after = retry_after


class SchemaDrift(Exception):
    """The response parsed but did not have the shape we book against."""


def _retry_after_seconds(exc: urllib.error.HTTPError) -> float | None:
    raw = exc.headers.get("Retry-After") if exc.headers else None
    if not raw:
        return None
    try:
        return float(raw)
    except ValueError:
        pass
    try:
        when = email.utils.parsedate_to_datetime(raw)
    except (TypeError, ValueError):
        return None
    return max(0.0, (when - datetime.now(when.tzinfo or timezone.utc)).total_seconds())


@dataclass(frozen=True)
class GymClass:
    sfid: str
    title: str
    from_date: str
    is_full: bool
    members_on_waiting_list: int
    my_booking: dict | None
    raw: dict


class BookingApi:
    def __init__(self, config: Config, token: str):
        self.cfg = config
        self.token = token

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.token}",
            "Ocp-Apim-Subscription-Key": self.cfg.api.subscription_key,
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": self.cfg.api.user_agent,
            "Origin": self.cfg.api.origin,
            "Referer": self.cfg.api.origin + "/",
            "X-Transaction-Id": str(uuid.uuid4()),
            "Device-Time": str(int(time.time() * 1000)),
        }

    def _call(self, method: str, path: str, body: dict | None = None) -> dict | list:
        url = f"{self.cfg.api.base}member/1.0/{path}"
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, headers=self._headers(), method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as exc:
            detail = f"{method} {path} -> {exc.code}: {exc.read()[:300]!r}"
            if transient_status(exc.code):
                raise TransientApiError(detail, _retry_after_seconds(exc)) from exc
            raise ApiError(detail) from exc
        except (urllib.error.URLError, TimeoutError) as exc:
            # Connection refused/reset or a read timeout — herd noise; retryable.
            raise TransientApiError(f"{method} {path} failed: {exc}") from exc

    def bookable_items(self, from_iso: str, to_iso: str) -> list[GymClass]:
        query = urllib.parse.urlencode(
            {"location": self.cfg.facility_id, "from_date": from_iso, "to_date": to_iso}
        )
        payload = self._call("GET", f"bookable_items/gym/?{query}")
        if not isinstance(payload, dict) or "items" not in payload:
            raise SchemaDrift(f"bookable_items had no 'items': {str(payload)[:200]}")
        classes = []
        for item in payload["items"]:
            try:
                classes.append(
                    GymClass(
                        sfid=item["sfid"],
                        title=item["title"],
                        from_date=item["from_date"],
                        is_full=bool(item.get("is_full")),
                        members_on_waiting_list=int(item.get("members_on_waiting_list") or 0),
                        my_booking=item.get("my_booking"),
                        raw=item,
                    )
                )
            except (KeyError, TypeError) as exc:
                raise SchemaDrift(f"unexpected class shape: {exc}: {str(item)[:200]}") from exc
        return classes

    def book(self, sfid: str) -> dict:
        payload = self._call("POST", "bookings/gym/", {"reservation": sfid})
        if not isinstance(payload, dict):
            raise SchemaDrift(f"booking response was not an object: {str(payload)[:200]}")
        return payload


def waitlist_position(booking_response: dict, gym_class: GymClass) -> int | None:
    """None => a confirmed seat; an int => that position on the waitlist."""
    for source in (booking_response, booking_response.get("my_booking") or {}, gym_class.my_booking or {}):
        if isinstance(source, dict) and source.get("waitlist_position") is not None:
            return int(source["waitlist_position"])
    return None
