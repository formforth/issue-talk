import io
import json
import unittest
from unittest.mock import patch

from oauth_broker import Configuration, RejectRedirects, exchange, make_application


class BrokerTests(unittest.TestCase):
    def call(self, payload, sender=None, **overrides):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        env = {
            "PATH_INFO": "/token",
            "REQUEST_METHOD": "POST",
            "CONTENT_TYPE": "application/json",
            "CONTENT_LENGTH": str(len(body)),
            "wsgi.input": io.BytesIO(body),
        }
        env.update(overrides)
        responses = []
        app = make_application(
            Configuration("fixture-client", "fixture-secret"), sender or self.sender
        )
        result = b"".join(
            app(env, lambda status, headers: responses.append((status, dict(headers))))
        )
        return responses[0], json.loads(result)

    @staticmethod
    def sender(config, fields):
        return {
            "access_token": "fixture-access",
            "token_type": "bearer",
            "unexpected": config.client_secret,
        }

    def test_exchange_is_no_store_and_filters_unexpected_fields(self):
        response, data = self.call(
            {
                "grant_type": "authorization_code",
                "code": "one-use-code",
                "code_verifier": "a" * 43,
            }
        )
        self.assertEqual(response[0], "200 OK")
        self.assertEqual(response[1]["Cache-Control"], "no-store")
        self.assertNotIn("unexpected", data)
        self.assertNotIn("fixture-secret", json.dumps(data))

    def test_rejects_weak_pkce_duplicate_keys_and_client_override(self):
        for payload in [
            {"grant_type": "authorization_code", "code": "x", "code_verifier": "short"},
            {
                "grant_type": "authorization_code",
                "code": "x",
                "code_verifier": "a" * 43,
                "client_id": "other",
            },
            b'{"grant_type":"refresh_token","refresh_token":"a","refresh_token":"b"}',
        ]:
            response, _ = self.call(
                payload, sender=lambda *_: self.fail("Must not contact GitHub")
            )
            self.assertEqual(response[0], "400 Bad Request")

    def test_explicit_refresh_grant_and_provider_errors(self):
        response, _ = self.call(
            {"grant_type": "refresh_token", "refresh_token": "fixture-refresh"}
        )
        self.assertEqual(response[0], "200 OK")
        response, data = self.call(
            {"grant_type": "refresh_token", "refresh_token": "fixture-refresh"},
            sender=lambda *_: {
                "error": "bad_refresh_token",
                "error_description": "private",
            },
        )
        self.assertEqual(response[0], "401 Unauthorized")
        self.assertEqual(data, {"error": "authorization_failed"})

    def test_size_and_content_type_are_bounded(self):
        self.assertEqual(
            self.call({}, CONTENT_LENGTH="99999")[0][0], "413 Content Too Large"
        )
        self.assertEqual(
            self.call({}, CONTENT_TYPE="text/plain")[0][0], "415 Unsupported Media Type"
        )

    def test_redirects_cannot_forward_client_secret(self):
        self.assertIsNone(
            RejectRedirects().redirect_request(
                None, None, 307, None, None, "https://evil.test"
            )
        )
        response = io.BytesIO(
            b'{"access_token":"fixture-access","token_type":"bearer"}'
        )
        with patch("urllib.request.build_opener") as builder:
            builder.return_value.open.return_value.__enter__.return_value = response
            exchange(
                Configuration("fixture-client", "fixture-secret"),
                {
                    "grant_type": "authorization_code",
                    "code": "fixture-code",
                    "code_verifier": "a" * 43,
                },
            )
            request = builder.return_value.open.call_args.args[0]
            self.assertEqual(
                request.full_url, "https://github.com/login/oauth/access_token"
            )
            self.assertIn(b"code_verifier=", request.data)
            self.assertIn(b"redirect_uri=issuetalk", request.data)


if __name__ == "__main__":
    unittest.main()
