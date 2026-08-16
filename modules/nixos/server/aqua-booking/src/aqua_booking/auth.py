"""Azure AD B2C auth: rolling refresh token, scripted login as the fallback.

No ROPC policy is published for this tenant, so a full login replays the
interactive SelfAsserted flow with curl-equivalent requests (verified: no
CAPTCHA). Once logged in, the rotating refresh token keeps us in without
touching the password again.
"""

from __future__ import annotations

import base64
import hashlib
import http.cookiejar
import json
import re
import secrets
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from .config import Config
from .retry import transient_status


class AuthError(Exception):
    pass


class TransientAuthError(AuthError):
    """A retryable auth failure (token endpoint 5xx, timeout, connection reset)."""


@dataclass(frozen=True)
class Credentials:
    username: str
    password: str

    @staticmethod
    def load(path: str | Path) -> Credentials:
        values: dict[str, str] = {}
        for line in Path(path).read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip()
        try:
            return Credentials(values["NUFFIELD_USERNAME"], values["NUFFIELD_PASSWORD"])
        except KeyError as exc:
            raise AuthError(f"credentials file missing {exc}") from exc


def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Hand 3xx responses back unfollowed so the auth code can be read out of
    the Location header (returning the response, not None, or urllib raises)."""

    def http_error_302(self, req, fp, code, msg, headers):  # noqa: ANN001, ANN201
        return fp

    http_error_301 = http_error_303 = http_error_307 = http_error_308 = http_error_302


class Authenticator:
    def __init__(self, config: Config, credentials: Credentials):
        self.cfg = config
        self.creds = credentials
        self.b2c = f"{config.auth.instance}{config.auth.tenant}/{config.auth.policy}"
        self._token_file = config.state_dir / "refresh_token"

    def access_token(self) -> str:
        refresh = self._stored_refresh()
        if refresh:
            try:
                return self._exchange({"grant_type": "refresh_token", "refresh_token": refresh})
            except TransientAuthError:
                raise  # server hiccup, not a bad token — let the caller retry
            except AuthError:
                pass  # the refresh token is genuinely invalid — log in afresh
        return self._login()

    def _stored_refresh(self) -> str | None:
        try:
            return self._token_file.read_text().strip() or None
        except FileNotFoundError:
            return None

    def _persist_refresh(self, token: str) -> None:
        self.cfg.state_dir.mkdir(parents=True, exist_ok=True)
        tmp = self._token_file.with_suffix(".tmp")
        tmp.write_text(token)
        tmp.chmod(0o600)
        tmp.replace(self._token_file)

    def _exchange(self, grant: dict[str, str]) -> str:
        body = {
            "client_id": self.cfg.auth.client_id,
            "scope": self.cfg.auth.scope,
            **grant,
        }
        data = urllib.parse.urlencode(body).encode()
        req = urllib.request.Request(
            f"{self.b2c}/oauth2/v2.0/token",
            data=data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                payload = json.loads(resp.read())
        except urllib.error.HTTPError as exc:
            detail = f"token endpoint {exc.code}: {exc.read()[:200]!r}"
            if transient_status(exc.code):
                raise TransientAuthError(detail) from exc
            raise AuthError(detail) from exc
        except (urllib.error.URLError, TimeoutError) as exc:
            raise TransientAuthError(f"token endpoint failed: {exc}") from exc
        if "access_token" not in payload:
            raise AuthError(f"token response had no access_token: {payload}")
        if payload.get("refresh_token"):
            self._persist_refresh(payload["refresh_token"])
        return payload["access_token"]

    def _login(self) -> str:
        verifier = _b64url(secrets.token_bytes(48))
        challenge = _b64url(hashlib.sha256(verifier.encode()).digest())
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(jar), _NoRedirect
        )

        csrf, trans_id = self._begin_authorize(opener, challenge)
        self._submit_credentials(opener, csrf, trans_id)
        code = self._collect_code(opener, csrf, trans_id)
        return self._exchange(
            {
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": self.cfg.auth.redirect_uri,
                "code_verifier": verifier,
            }
        )

    def _open(self, opener, req):
        try:
            return opener.open(req, timeout=30)
        except urllib.error.HTTPError as exc:
            if transient_status(exc.code):
                raise TransientAuthError(f"{req.full_url} -> {exc.code}") from exc
            raise AuthError(f"{req.full_url} -> {exc.code}: {exc.read()[:200]!r}") from exc
        except (urllib.error.URLError, TimeoutError) as exc:
            raise TransientAuthError(f"{req.full_url} failed: {exc}") from exc

    def _begin_authorize(self, opener, challenge: str) -> tuple[str, str]:
        params = urllib.parse.urlencode(
            {
                "client_id": self.cfg.auth.client_id,
                "redirect_uri": self.cfg.auth.redirect_uri,
                "response_type": "code",
                "scope": self.cfg.auth.scope,
                "response_mode": "query",
                "code_challenge": challenge,
                "code_challenge_method": "S256",
                "state": secrets.token_hex(8),
                "nonce": secrets.token_hex(8),
            }
        )
        req = urllib.request.Request(
            f"{self.b2c}/oauth2/v2.0/authorize?{params}",
            headers={"User-Agent": self.cfg.api.user_agent},
        )
        with self._open(opener, req) as resp:
            html = resp.read().decode("utf-8", "replace")
        csrf = _first(r'"csrf":"(.*?)"', html, "csrf")
        trans_id = _first(r'"transId":"(.*?)"', html, "transId")
        return csrf, trans_id

    def _submit_credentials(self, opener, csrf: str, trans_id: str) -> None:
        query = urllib.parse.urlencode({"tx": trans_id, "p": self.cfg.auth.policy})
        body = urllib.parse.urlencode(
            {
                "request_type": "RESPONSE",
                "signInName": self.creds.username,
                "password": self.creds.password,
            }
        ).encode()
        req = urllib.request.Request(
            f"{self.b2c}/SelfAsserted?{query}",
            data=body,
            headers={
                "User-Agent": self.cfg.api.user_agent,
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "X-CSRF-TOKEN": csrf,
                "X-Requested-With": "XMLHttpRequest",
            },
        )
        with self._open(opener, req) as resp:
            payload = json.loads(resp.read())
        if str(payload.get("status")) != "200":
            raise AuthError(f"login rejected: {payload}")

    def _collect_code(self, opener, csrf: str, trans_id: str) -> str:
        query = urllib.parse.urlencode(
            {
                "rememberMe": "false",
                "csrf_token": csrf,
                "tx": trans_id,
                "p": self.cfg.auth.policy,
            }
        )
        req = urllib.request.Request(
            f"{self.b2c}/api/CombinedSigninAndSignup/confirmed?{query}",
            headers={"User-Agent": self.cfg.api.user_agent},
        )
        with self._open(opener, req) as resp:
            location = resp.headers.get("Location", "")
        parsed = urllib.parse.urlparse(location)
        code = urllib.parse.parse_qs(parsed.query).get("code", [None])[0]
        if not code:
            raise AuthError(f"no auth code in redirect: {location!r}")
        return code


def _first(pattern: str, text: str, what: str) -> str:
    match = re.search(pattern, text)
    if not match:
        raise AuthError(f"could not find {what} on the sign-in page")
    return match.group(1)
