"""Tests for scripts/logins/codex_plan_proxy.py against a fake upstream. Run: python3 -m unittest discover -s tests"""
import base64
import http.client
import http.server
import importlib.util
import ipaddress
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_module(state_dir):
    os.environ["CODEX_PROXY_STATE"] = state_dir
    os.environ["CODEX_PROXY_BACKUP"] = ""
    spec = importlib.util.spec_from_file_location("codex_plan_proxy", ROOT / "scripts/logins/codex_plan_proxy.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class FakeUpstream(http.server.BaseHTTPRequestHandler):
    """Stands in for api.openai.com: accepts only the bearer token in `valid`, streams SSE on /v1/responses."""
    protocol_version = "HTTP/1.1"
    valid = "access-2"
    seen = []

    def log_message(self, *_):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        FakeUpstream.seen.append({"path": self.path, "auth": self.headers.get("Authorization"),
                                  "x-api-key": self.headers.get("X-Api-Key"), "body": body})
        if self.headers.get("Authorization") != f"Bearer {self.valid}":
            payload = b'{"error":{"code":"invalid_token"}}'
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        for event in (b"event: response.created\ndata: {}\n\n", b"event: response.completed\ndata: {}\n\n"):
            self.wfile.write(b"%x\r\n%s\r\n" % (len(event), event))
            self.wfile.flush()
            time.sleep(0.05)
        self.wfile.write(b"0\r\n\r\n")

    def do_GET(self):
        payload = b'{"models":[]}'
        self.send_response(200 if self.headers.get("Authorization") == f"Bearer {self.valid}" else 401)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def serve(handler):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class ProxyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.mod = load_module(self.tmp)
        FakeUpstream.seen = []
        self.upstream = serve(FakeUpstream)
        up_port = self.upstream.server_address[1]
        # route "HTTPS to api.openai.com" to the fake upstream
        self.mod.http.client.HTTPSConnection = lambda host, timeout=None: http.client.HTTPConnection("127.0.0.1", up_port, timeout=10)
        self.refreshes = []

        def fake_http_json(url, form=None):
            if form and form.get("grant_type") == "refresh_token":
                self.refreshes.append(dict(form))
                if form["refresh_token"] != f"refresh-{len(self.refreshes)}":
                    raise self.mod.OAuthError(400, "refresh_token_reused")
                n = len(self.refreshes) + 1
                return {"access_token": f"access-{n}", "refresh_token": f"refresh-{n}", "expires_in": 3600,
                        "scope": "chatgpt.tokens.use.direct offline_access"}
            raise AssertionError(f"unexpected request to {url}")

        self.mod.http_json = fake_http_json
        self.mod.discovery = lambda: {"token_endpoint": "https://auth.example/token"}
        self.mod.write_credentials({
            "email": "user@example.com", "client_id": "oaiapp_test", "access_token": "access-1",
            "refresh_token": "refresh-1", "scopes": ["chatgpt.tokens.use.direct"],
            "expires_at": int(time.time()) + 3600, "saved_at_epoch": int(time.time())})
        self.tokens = self.mod.Tokens()
        self.proxy = serve(self.mod.make_handler(self.tokens, ipaddress.ip_network("127.0.0.0/8")))
        self.port = self.proxy.server_address[1]

    def tearDown(self):
        for server in (self.proxy, self.upstream):
            server.shutdown()
            server.server_close()
        shutil.rmtree(self.tmp)

    def request(self, method, path, body=None, headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.request(method, path, body=body, headers=headers or {})
        res = conn.getresponse()
        data = res.read()
        conn.close()
        return res, data

    def test_rejected_token_is_refreshed_once_and_request_is_replayed(self):
        res, data = self.request("POST", "/v1/responses", body=b'{"model":"m","stream":true}',
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer from-sandbox",
                                          "X-Api-Key": "kept"})
        self.assertEqual(res.status, 200)
        self.assertIn(b"response.completed", data)
        self.assertEqual(res.getheader("Content-Type"), "text/event-stream")
        # first try with the stale token, then one refresh, then the replay with the new token
        self.assertEqual([s["auth"] for s in FakeUpstream.seen], ["Bearer access-1", "Bearer access-2"])
        self.assertEqual(len(self.refreshes), 1)
        self.assertEqual(self.refreshes[0]["client_id"], "oaiapp_test")
        self.assertEqual(self.refreshes[0]["resource"], "https://api.openai.com/v1")
        self.assertEqual(FakeUpstream.seen[1]["body"], b'{"model":"m","stream":true}')
        self.assertEqual(FakeUpstream.seen[1]["x-api-key"], "kept")
        # the sandbox's own Authorization header never reaches the upstream
        self.assertNotIn("Bearer from-sandbox", [s["auth"] for s in FakeUpstream.seen])
        saved = json.loads(Path(self.tmp, "credentials.json").read_text())
        self.assertEqual((saved["access_token"], saved["refresh_token"]), ("access-2", "refresh-2"))
        self.assertEqual(oct(Path(self.tmp, "credentials.json").stat().st_mode & 0o777), "0o600")

    def test_expiring_token_is_refreshed_before_the_request(self):
        cred = self.mod.read_credentials()
        cred["expires_at"] = int(time.time()) + 60
        self.mod.write_credentials(cred)
        res, _ = self.request("GET", "/v1/models")
        self.assertEqual(res.status, 200)
        self.assertEqual([s for s in FakeUpstream.seen], [])  # GET is not recorded; no 401 round trip needed
        self.assertEqual(len(self.refreshes), 1)

    def test_only_v1_paths_are_forwarded(self):
        res, data = self.request("GET", "/admin")
        self.assertEqual(res.status, 404)
        res, data = self.request("GET", "/healthz")
        self.assertEqual((res.status, json.loads(data)["status"]), (200, "ok"))
        self.assertEqual(FakeUpstream.seen, [])

    def test_clients_outside_the_allowed_network_are_refused(self):
        self.proxy.shutdown()
        self.proxy.server_close()
        self.proxy = serve(self.mod.make_handler(self.tokens, ipaddress.ip_network("10.120.0.0/24")))
        self.port = self.proxy.server_address[1]
        res, data = self.request("POST", "/v1/responses", body=b"{}")
        self.assertEqual(res.status, 403)
        self.assertEqual(FakeUpstream.seen, [])

    def test_unusable_refresh_token_signs_out_with_a_clear_error(self):
        cred = self.mod.read_credentials()
        cred["refresh_token"] = "stale"
        self.mod.write_credentials(cred)
        res, data = self.request("POST", "/v1/responses", body=b"{}")
        self.assertEqual(res.status, 401)
        self.assertEqual(json.loads(data)["error"]["code"], "proxy_signed_out")
        res, data = self.request("GET", "/healthz")
        self.assertEqual(res.status, 503)

    def test_new_login_on_disk_is_picked_up_without_restart(self):
        self.request("POST", "/v1/responses", body=b"{}")       # leaves the proxy on access-2
        FakeUpstream.seen = []
        time.sleep(0.01)
        self.mod.write_credentials({**self.mod.read_credentials(), "access_token": "access-2", "email": "new@example.com"})
        res, _ = self.request("POST", "/v1/responses", body=b"{}")
        self.assertEqual(res.status, 200)
        self.assertEqual(self.tokens.cred["email"], "new@example.com")


@unittest.skipUnless(shutil.which("openssl"), "needs the openssl CLI to make a signing key")
class IdTokenTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.mod = load_module(self.tmp)
        key = Path(self.tmp, "key.pem")
        subprocess.run(["openssl", "genrsa", "-out", str(key), "2048"], check=True, capture_output=True)
        modulus = subprocess.run(["openssl", "rsa", "-in", str(key), "-noout", "-modulus"], check=True,
                                 capture_output=True, text=True).stdout.strip().split("=")[1]
        self.key = key
        n = bytes.fromhex(modulus)
        b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
        self.b64 = b64
        jwks = {"keys": [{"kty": "RSA", "kid": "k1", "n": b64(n), "e": b64((65537).to_bytes(3, "big"))}]}
        self.mod.discovery = lambda: {"jwks_uri": "https://auth.example/jwks"}
        self.mod.http_json = lambda url, form=None: jwks

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def token(self, claims, kid="k1"):
        head = self.b64(json.dumps({"alg": "RS256", "kid": kid}).encode())
        body = self.b64(json.dumps(claims).encode())
        sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(self.key)], input=f"{head}.{body}".encode(),
                             check=True, capture_output=True).stdout
        return f"{head}.{body}.{self.b64(sig)}"

    def claims(self, **over):
        return {"iss": "https://auth.openai.com", "aud": "oaiapp_test", "sub": "user-1", "nonce": "n1",
                "exp": int(time.time()) + 600, **over}

    def test_valid_token_is_accepted(self):
        self.assertEqual(self.mod.verify_id_token(self.token(self.claims()), "oaiapp_test", "n1")["sub"], "user-1")

    def test_tampered_or_mismatched_tokens_are_rejected(self):
        good = self.token(self.claims())
        head, body, sig = good.split(".")
        forged = self.b64(json.dumps(self.claims(sub="attacker")).encode())
        cases = {
            "tampered payload": (f"{head}.{forged}.{sig}", "oaiapp_test", "n1"),
            "wrong audience": (good, "oaiapp_other", "n1"),
            "wrong nonce": (good, "oaiapp_test", "other"),
            "wrong issuer": (self.token(self.claims(iss="https://evil.example")), "oaiapp_test", "n1"),
            "expired": (self.token(self.claims(exp=int(time.time()) - 3600)), "oaiapp_test", "n1"),
            "unknown key": (self.token(self.claims(), kid="k2"), "oaiapp_test", "n1"),
        }
        for name, args in cases.items():
            with self.subTest(name), self.assertRaises(RuntimeError):
                self.mod.verify_id_token(*args)


if __name__ == "__main__":
    sys.exit(unittest.main())
