"""Minimal WSGI code-exchange service; deploy behind HTTPS, never inside the iOS app."""

import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Configuration:
    client_id: str
    client_secret: str = field(repr=False)
    redirect_uri: str = "issuetalk://oauth/callback"

    @classmethod
    def environment(cls):
        client_id = os.environ.get("GITHUB_CLIENT_ID", "")
        secret = os.environ.get("GITHUB_CLIENT_SECRET", "")
        if not client_id or not secret:
            raise ValueError(
                "Configure the OAuth application credentials on the server"
            )
        return cls(client_id, secret)


class RejectRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def exchange(configuration, fields):
    payload = dict(
        fields,
        client_id=configuration.client_id,
        client_secret=configuration.client_secret,
    )
    if fields["grant_type"] == "authorization_code":
        payload.pop("grant_type")
        payload["redirect_uri"] = configuration.redirect_uri
    request = urllib.request.Request(
        "https://github.com/login/oauth/access_token",
        data=urllib.parse.urlencode(payload).encode(),
        headers={
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    opener = urllib.request.build_opener(RejectRedirects())
    with opener.open(request, timeout=15) as response:
        raw = response.read(16_385)
        if len(raw) > 16_384:
            raise ValueError("Oversized response")
        return json.loads(raw)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate field")
        result[key] = value
    return result


def validated_fields(data):
    if not isinstance(data, dict):
        raise TypeError("Expected an object")
    if data.get("grant_type") == "authorization_code":
        if set(data) != {"grant_type", "code", "code_verifier"}:
            raise ValueError("Unexpected fields")
        if not isinstance(data["code"], str) or not 1 <= len(data["code"]) <= 512:
            raise ValueError("Invalid code")
        verifier = data["code_verifier"]
        if not isinstance(verifier, str) or not re.fullmatch(
            r"[A-Za-z0-9._~-]{43,128}", verifier
        ):
            raise ValueError("Invalid PKCE verifier")
    elif data.get("grant_type") == "refresh_token":
        if set(data) != {"grant_type", "refresh_token"}:
            raise ValueError("Unexpected fields")
        token = data["refresh_token"]
        if not isinstance(token, str) or not 1 <= len(token) <= 2048:
            raise ValueError("Invalid refresh token")
    else:
        raise ValueError("Unsupported grant")
    return data


def make_application(configuration, sender=exchange):
    def application(environ, start_response):
        def respond(status, data):
            body = json.dumps(data).encode()
            start_response(
                status,
                [
                    ("Content-Type", "application/json"),
                    ("Cache-Control", "no-store"),
                    ("Pragma", "no-cache"),
                    ("Content-Length", str(len(body))),
                ],
            )
            return [body]

        if (
            environ.get("PATH_INFO") == "/health"
            and environ.get("REQUEST_METHOD") == "GET"
        ):
            return respond("200 OK", {"ok": True})
        if environ.get("PATH_INFO") != "/token":
            return respond("404 Not Found", {"error": "not_found"})
        if environ.get("REQUEST_METHOD") != "POST":
            return respond("405 Method Not Allowed", {"error": "method_not_allowed"})
        try:
            length = int(environ.get("CONTENT_LENGTH", "0"))
        except (ValueError, TypeError):
            length = 0
        if not 0 < length <= 8192:
            return respond("413 Content Too Large", {"error": "invalid_size"})
        if environ.get("CONTENT_TYPE", "").split(";")[0] != "application/json":
            return respond("415 Unsupported Media Type", {"error": "json_required"})
        try:
            raw = environ["wsgi.input"].read(length)
            fields = validated_fields(json.loads(raw, object_pairs_hook=unique_object))
        except (ValueError, TypeError, UnicodeError):
            return respond("400 Bad Request", {"error": "invalid_request"})
        try:
            result = sender(configuration, fields)
            if not isinstance(result, dict) or "error" in result:
                return respond("401 Unauthorized", {"error": "authorization_failed"})
            if (
                not isinstance(result.get("access_token"), str)
                or not result["access_token"]
            ):
                raise ValueError("Invalid response")
            if str(result.get("token_type", "")).lower() != "bearer":
                raise ValueError("Invalid response")
            allowed = {
                "access_token",
                "token_type",
                "scope",
                "expires_in",
                "refresh_token",
                "refresh_token_expires_in",
            }
            return respond(
                "200 OK",
                {key: value for key, value in result.items() if key in allowed},
            )
        except (OSError, ValueError, urllib.error.URLError):
            # Do not log the request, client secret, authorization code, or token response.
            return respond("502 Bad Gateway", {"error": "upstream_unavailable"})

    return application


def application(environ, start_response):
    return make_application(Configuration.environment())(environ, start_response)
