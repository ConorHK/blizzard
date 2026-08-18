"""Azure AD B2C auth: the scripted sign-in, mirroring what the booking site does.

No ROPC policy is published for this tenant, so a login replays the interactive
SelfAsserted flow with curl-equivalent requests (verified: no CAPTCHA). The site
uses the implicit flow, so the access token arrives in the fragment of the final
redirect: there is no code to redeem, and no refresh token to keep. Redeeming a
code is not an option — /auth/callback/ is registered as a confidential client,
so the token endpoint answers AADB2C90079 without a client secret.
"""

from __future__ import annotations

import http.cookiejar
import json
import re
import secrets
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass

from .config import Config
from .retry import transient_status


class AuthError(Exception):
    pass


class TransientAuthError(AuthError):
    """A retryable auth failure (5xx, timeout, connection reset)."""


@dataclass(frozen=True)
class Credentials:
    username: str
    password: str

    @staticmethod
    def from_secrets(values: dict) -> Credentials:
        return Credentials(values["username"], values["password"])


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Hand 3xx responses back unfollowed so the token can be read out of the
    Location header (returning the response, not None, or urllib raises)."""

    def http_error_302(self, req, fp, code, msg, headers):  # noqa: ANN001, ANN201
        return fp

    http_error_301 = http_error_303 = http_error_307 = http_error_308 = http_error_302


class Authenticator:
    def __init__(self, config: Config, credentials: Credentials):
        self.cfg = config
        self.creds = credentials
        self.b2c = f"{config.auth.instance}{config.auth.tenant}/{config.auth.policy}"

    def access_token(self) -> str:
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(jar), _NoRedirect
        )
        csrf, trans_id = self._begin_authorize(opener)
        self._submit_credentials(opener, csrf, trans_id)
        return self._collect_token(opener, csrf, trans_id)

    def _open(self, opener, req):
        try:
            return opener.open(req, timeout=30)
        except urllib.error.HTTPError as exc:
            if transient_status(exc.code):
                raise TransientAuthError(f"{req.full_url} -> {exc.code}") from exc
            raise AuthError(f"{req.full_url} -> {exc.code}: {exc.read()[:200]!r}") from exc
        except (urllib.error.URLError, TimeoutError) as exc:
            raise TransientAuthError(f"{req.full_url} failed: {exc}") from exc

    def _begin_authorize(self, opener) -> tuple[str, str]:
        params = urllib.parse.urlencode(
            {
                "client_id": self.cfg.auth.client_id,
                "redirect_uri": self.cfg.auth.redirect_uri,
                "response_type": "token id_token",
                "scope": self.cfg.auth.scope,
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
                "Email": self.creds.username,
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

    def _collect_token(self, opener, csrf: str, trans_id: str) -> str:
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
        fragment = urllib.parse.parse_qs(urllib.parse.urlparse(location).fragment)
        token = fragment.get("access_token", [None])[0]
        if not token:
            # Never echo the fragment itself; on a partial success it holds an id_token.
            detail = fragment.get("error_description") or fragment.get("error") or ["no access_token"]
            raise AuthError(f"sign-in redirect carried no access token: {detail[0]}")
        return token


def _first(pattern: str, text: str, what: str) -> str:
    match = re.search(pattern, text)
    if not match:
        raise AuthError(f"could not find {what} on the sign-in page")
    return match.group(1)
