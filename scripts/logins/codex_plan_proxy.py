#!/usr/bin/env python3
"""codex-plan-proxy: one ChatGPT plan login on the host, used by every sandbox (stdlib only).

The host signs in once with "Sign in with ChatGPT" (plan usage for open-source and locally
hosted apps, https://developers.openai.com/siwc/token-sharing-open-source), keeps the tokens,
and is the only process that refreshes them. Sandboxes send their Responses API requests to
this proxy without credentials; it adds the access token and forwards them to
https://api.openai.com/v1. A sandbox never sees a token.

  codex_plan_proxy.py login [--port 1455] [--paste]   sign in (browser, loopback callback)
  codex_plan_proxy.py serve                            run the proxy
  codex_plan_proxy.py status                           show the saved login, without secrets

Environment:
  CODEX_PROXY_STATE    state directory (default /var/lib/codex-plan-proxy)
  CODEX_PROXY_LISTEN   address:port to serve on (default 10.120.0.1:8455)
  CODEX_PROXY_ALLOW    client network allowed to use the proxy (default 10.120.0.0/24)
  CODEX_PROXY_BACKUP   secret name for the credential backup in Infisical
                       (default CODEX_PLAN_CREDENTIALS; empty disables the backup)
"""
import argparse
import base64
import hashlib
import hmac
import http.client
import http.server
import ipaddress
import json
import os
import secrets
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ISSUER = "https://auth.openai.com"
RESOURCE = "https://api.openai.com/v1"
UPSTREAM_HOST = "api.openai.com"
SCOPES = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
PLAN_SCOPE = "chatgpt.tokens.use.direct"
REGISTRATION_CLIENT = "dynamic_agent_client"
AGENT_NAME = "sandbox-vm"
CALLBACK_PATH = "/auth/callback"
USER_AGENT = "sandbox-vm-codex-plan-proxy"
TERMINAL_REFRESH_ERRORS = {"invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
                           "refresh_token_invalidated", "refresh_token_reused"}
HOP_BY_HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "proxy-connection",
              "te", "trailer", "transfer-encoding", "upgrade"}

STATE = os.environ.get("CODEX_PROXY_STATE", "/var/lib/codex-plan-proxy")
BACKUP_NAME = os.environ.get("CODEX_PROXY_BACKUP", "CODEX_PLAN_CREDENTIALS")


def log(msg):
    print(msg, file=sys.stderr, flush=True)


# ---------------------------------------------------------------- OAuth

class OAuthError(RuntimeError):
    def __init__(self, status, code, message=""):
        super().__init__(f"HTTP {status}: {code}{': ' + message if message else ''}")
        self.status, self.code = status, code


def http_json(url, form=None):
    data = urllib.parse.urlencode(form).encode() if form is not None else None
    req = urllib.request.Request(url, data=data, headers={"Accept": "application/json", "User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            return json.loads(res.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        try:
            parsed = json.loads(body)
        except ValueError:
            parsed = {}
        err = parsed.get("error") if isinstance(parsed, dict) else None
        if isinstance(err, dict):       # {"error": {"code": ..., "message": ...}}
            code, message = err.get("code") or err.get("type") or "http_error", err.get("message", "")
        elif isinstance(err, str):      # {"error": "invalid_grant", "error_description": ...}
            code, message = err, parsed.get("error_description", "")
        else:
            code, message = "http_error", body[:200]
        raise OAuthError(e.code, code, message) from None


_discovery = None


def discovery():
    global _discovery
    if _discovery is None:
        d = http_json(ISSUER + "/.well-known/openid-configuration")
        if d.get("issuer") != ISSUER:
            raise RuntimeError("unexpected issuer in the OpenID configuration")
        _discovery = d
    return _discovery


def b64url_decode(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def verify_id_token(token, client_id, nonce):
    """Validate an RS256 ID token against OpenAI's JWKS: signature, issuer, audience, expiry, nonce."""
    try:
        h64, p64, s64 = token.split(".")
        header, claims, sig = json.loads(b64url_decode(h64)), json.loads(b64url_decode(p64)), b64url_decode(s64)
    except (ValueError, TypeError):
        raise RuntimeError("malformed ID token") from None
    if header.get("alg") != "RS256":
        raise RuntimeError(f"unexpected ID token algorithm {header.get('alg')}")
    keys = http_json(discovery()["jwks_uri"])["keys"]
    key = next((k for k in keys if k.get("kid") == header.get("kid") and k.get("kty") == "RSA"), None)
    if key is None:
        raise RuntimeError("ID token signed with an unknown key")
    n, e = int.from_bytes(b64url_decode(key["n"]), "big"), int.from_bytes(b64url_decode(key["e"]), "big")
    size = (n.bit_length() + 7) // 8
    digest_info = bytes.fromhex("3031300d060960864801650304020105000420") + hashlib.sha256(f"{h64}.{p64}".encode()).digest()
    expected = b"\x00\x01" + b"\xff" * (size - len(digest_info) - 3) + b"\x00" + digest_info
    if len(sig) != size or not hmac.compare_digest(pow(int.from_bytes(sig, "big"), e, n).to_bytes(size, "big"), expected):
        raise RuntimeError("ID token signature is invalid")
    aud = claims.get("aud")
    if claims.get("iss") != ISSUER or client_id not in (aud if isinstance(aud, list) else [aud]):
        raise RuntimeError("ID token issuer or audience does not match")
    if claims.get("exp", 0) < time.time() - 60:
        raise RuntimeError("ID token is expired")
    if nonce is not None and claims.get("nonce") != nonce:
        raise RuntimeError("ID token nonce does not match")
    return claims


# ---------------------------------------------------------------- credential store

def state_path(name):
    return os.path.join(STATE, name)


def read_credentials():
    try:
        with open(state_path("credentials.json")) as f:
            return json.load(f)
    except FileNotFoundError:
        return None


def write_credentials(cred):
    os.makedirs(STATE, mode=0o700, exist_ok=True)
    tmp = state_path(f".credentials.{os.getpid()}.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(cred, f, indent=1)
        f.flush()
        os.fsync(f.fileno())
    st = os.stat(STATE)
    if os.geteuid() == 0 and st.st_uid != 0:        # login ran as root: hand the file to the service user
        os.chown(tmp, st.st_uid, st.st_gid)
    os.replace(tmp, state_path("credentials.json"))


def host_id():
    """Stable opaque ext_agent_host_id of this host, created before the first sign-in."""
    path = state_path("host-id")
    try:
        with open(path) as f:
            return f.read().strip()
    except FileNotFoundError:
        os.makedirs(STATE, mode=0o700, exist_ok=True)
        value = f"urn:uuid:{uuid.uuid4()}"
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(value + "\n")
        st = os.stat(STATE)
        if os.geteuid() == 0 and st.st_uid != 0:
            os.chown(path, st.st_uid, st.st_gid)
        return value


def record(token_response, client_id, claims, previous=None):
    now = time.time()
    prev = previous or {}
    return {
        "email": claims.get("email") if claims else prev.get("email"),
        "issuer": ISSUER,
        "subject": claims.get("sub") if claims else prev.get("subject"),
        "client_id": client_id,
        "ext_agent_host_id": host_id(),
        "id_token": token_response.get("id_token") or prev.get("id_token"),
        "access_token": token_response["access_token"],
        "refresh_token": token_response.get("refresh_token") or prev.get("refresh_token"),
        "token_type": token_response.get("token_type", "Bearer"),
        "expires_in": token_response.get("expires_in", 3600),
        "scopes": sorted((token_response.get("scope") or " ".join(prev.get("scopes", []))).split()),
        "earliest_refresh_at": token_response.get("earliest_refresh_at"),
        "saved_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
        "saved_at_epoch": int(now),
        "expires_at": int(now + int(token_response.get("expires_in", 3600))),
    }


def backup(cred):
    """Best-effort copy of the credential record to Infisical, so a reinstalled host keeps the login."""
    if not BACKUP_NAME:
        return
    try:
        import infisical
        infisical.Client().set(BACKUP_NAME, json.dumps(cred))
    except Exception as e:  # the proxy must keep working without the backup
        log(f"backup to Infisical failed: {e}")


def restore_from_backup():
    if not BACKUP_NAME:
        return None
    try:
        import infisical
        cred = json.loads(infisical.Client().get(BACKUP_NAME))
    except Exception as e:
        log(f"no credential backup restored: {e}")
        return None
    write_credentials(cred)
    log("restored the login from the Infisical backup")
    return cred


# ---------------------------------------------------------------- login

def cmd_login(args):
    saved = read_credentials()
    returning = bool(saved and saved.get("client_id"))
    verifier, state, nonce = b64url(secrets.token_bytes(48)), b64url(secrets.token_bytes(24)), b64url(secrets.token_bytes(24))
    redirect_uri = f"http://127.0.0.1:{args.port}{CALLBACK_PATH}"
    query = {
        "client_id": saved["client_id"] if returning else REGISTRATION_CLIENT,
        "ext_agent_host_id": host_id(),
        "response_type": "code",
        "redirect_uri": redirect_uri,
        "scope": SCOPES,
        "resource": RESOURCE,
        "state": state,
        "nonce": nonce,
        "code_challenge_method": "S256",
        "code_challenge": b64url(hashlib.sha256(verifier.encode()).digest()),
    }
    if returning:
        if saved.get("id_token"):
            query["id_token_hint"] = saved["id_token"]
        if saved.get("email"):
            query["login_hint"] = saved["email"]
    else:
        query["agent_name_hint"] = AGENT_NAME
    url = discovery()["authorization_endpoint"] + "?" + urllib.parse.urlencode(query)

    result = {}
    done = threading.Event()

    class Callback(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urllib.parse.urlsplit(self.path)
            if parsed.path != CALLBACK_PATH:
                self.send_error(404)
                return
            result.update({k: v[0] for k, v in urllib.parse.parse_qs(parsed.query).items()})
            body = b"<!doctype html><meta charset=utf-8><title>sandbox-vm</title><p>Sign-in received. You can close this tab."
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            done.set()

        def log_message(self, *_):
            pass

    print("Open this address in a browser that can reach this host's 127.0.0.1"
          f" (for a remote host: ssh -L {args.port}:127.0.0.1:{args.port} <host>):\n", flush=True)
    print(f"AUTH_URL {url}\n", flush=True)
    if args.paste:
        print("Paste the full address the browser was sent to (http://127.0.0.1:.../auth/callback?...):", flush=True)
        pasted = urllib.parse.urlsplit(sys.stdin.readline().strip())
        result.update({k: v[0] for k, v in urllib.parse.parse_qs(pasted.query).items()})
    else:
        server = http.server.HTTPServer(("127.0.0.1", args.port), Callback)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        if not done.wait(args.timeout):
            sys.exit("no callback arrived in time")
        server.shutdown()

    if not hmac.compare_digest(result.get("state", ""), state):
        sys.exit("state mismatch; start again")
    if "error" in result:
        sys.exit(f"sign-in was not completed: {result['error']} {result.get('error_description', '')}")
    client_id = result.get("client_id") or (saved["client_id"] if returning else None)
    if not client_id or client_id == REGISTRATION_CLIENT:
        sys.exit("the callback has no issued client_id; registration is incomplete")
    if returning and client_id != saved["client_id"]:
        sys.exit("the callback names a different client than the saved login")

    tokens = http_json(discovery()["token_endpoint"], {
        "grant_type": "authorization_code", "client_id": client_id, "code": result.get("code", ""),
        "code_verifier": verifier, "redirect_uri": redirect_uri, "resource": RESOURCE})
    claims = verify_id_token(tokens["id_token"], client_id, nonce)
    if returning and saved.get("subject") and claims.get("sub") != saved["subject"]:
        sys.exit("this is a different ChatGPT account than the saved login; remove the state directory to switch")
    if PLAN_SCOPE not in (tokens.get("scope") or "").split():
        sys.exit("signed in, but ChatGPT plan usage was not granted (scope chatgpt.tokens.use.direct is missing)")
    cred = record(tokens, client_id, claims)
    write_credentials(cred)
    backup(cred)
    print(f"signed in as {cred['email']}; plan usage granted; credentials saved in {STATE}", flush=True)


def cmd_status(_args):
    cred = read_credentials()
    if not cred:
        print("not signed in")
        return 1
    left = int(cred.get("expires_at", 0) - time.time())
    print(json.dumps({"email": cred.get("email"), "client_id": cred.get("client_id"),
                      "host_id": cred.get("ext_agent_host_id"), "scopes": cred.get("scopes"),
                      "saved_at": cred.get("saved_at"), "access_token_expires_in_s": left,
                      "has_refresh_token": bool(cred.get("refresh_token"))}, indent=1))
    return 0


# ---------------------------------------------------------------- token manager

class SignedOut(RuntimeError):
    pass


class Tokens:
    """Owns the credential record. Every refresh goes through one lock, because refresh tokens rotate."""

    def __init__(self):
        self.lock = threading.Lock()
        self.cred = None
        self.mtime = None
        self.signed_out = None
        self._load()
        if not self.cred and restore_from_backup():
            self._load()
        if not self.cred:
            self.signed_out = "not signed in; run `codex-plan-proxy login` on the host"

    def _load(self):
        """Read the record when the file changed, so a new `login` takes effect without a restart."""
        try:
            mtime = os.stat(state_path("credentials.json")).st_mtime_ns
        except FileNotFoundError:
            return
        if mtime != self.mtime:
            self.cred, self.mtime, self.signed_out = read_credentials(), mtime, None

    def _save(self, cred):
        self.cred = cred
        write_credentials(cred)
        self.mtime = os.stat(state_path("credentials.json")).st_mtime_ns

    def problem(self):
        """Why the proxy cannot serve right now, or None."""
        with self.lock:
            self._load()
            return self.signed_out

    def access_token(self):
        with self.lock:
            self._load()
            if self.signed_out:
                raise SignedOut(self.signed_out)
            if self.cred["expires_at"] - time.time() < 300:
                self._refresh()
            return self.cred["access_token"]

    def refresh_after_rejection(self, rejected):
        with self.lock:
            self._load()
            if self.signed_out:
                raise SignedOut(self.signed_out)
            if self.cred["access_token"] == rejected:   # nobody refreshed in the meantime
                self._refresh()
            return self.cred["access_token"]

    def keepalive(self):
        """Refresh once a day on an idle host, so the 30-day refresh token never expires."""
        while True:
            time.sleep(1800)
            try:
                with self.lock:
                    self._load()
                    if not self.signed_out and time.time() - self.cred.get("saved_at_epoch", 0) > 20 * 3600:
                        self._refresh()
            except SignedOut:
                pass
            except Exception as e:
                log(f"keepalive: {e}")

    def _refresh(self):
        earliest = self.cred.get("earliest_refresh_at")
        if isinstance(earliest, (int, float)) and time.time() < earliest and self.cred["expires_at"] - time.time() > 30:
            return
        try:
            tokens = http_json(discovery()["token_endpoint"], {
                "grant_type": "refresh_token", "client_id": self.cred["client_id"],
                "refresh_token": self.cred["refresh_token"], "resource": RESOURCE})
        except OAuthError as e:
            if e.code in TERMINAL_REFRESH_ERRORS:
                self.signed_out = f"the ChatGPT login is no longer valid ({e.code}); run `codex-plan-proxy login` on the host"
                log(self.signed_out)
                raise SignedOut(self.signed_out) from None
            raise
        self._save(record(tokens, self.cred["client_id"], None, previous=self.cred))
        log("access token refreshed")
        threading.Thread(target=backup, args=(dict(self.cred),), daemon=True).start()


# ---------------------------------------------------------------- proxy

def make_handler(tokens, allow):
    class Proxy(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        server_version = "codex-plan-proxy"
        sys_version = ""

        def log_message(self, *_):
            pass

        def _json(self, status, code, message):
            body = json.dumps({"error": {"message": message, "type": "proxy_error", "code": code}}).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _body(self):
            if "chunked" in self.headers.get("Transfer-Encoding", "").lower():
                data = b""
                while True:
                    size = int(self.rfile.readline().split(b";")[0].strip() or b"0", 16)
                    if size == 0:
                        while self.rfile.readline().strip():
                            pass
                        return data
                    data += self.rfile.read(size)
                    self.rfile.readline()
            return self.rfile.read(int(self.headers.get("Content-Length") or 0))

        def _handle(self):
            started = time.time()
            status = 0
            try:
                if ipaddress.ip_address(self.client_address[0]) not in allow:
                    status = 403
                    return self._json(403, "forbidden", "this client may not use the proxy")
                path = self.path.split("?")[0]
                if path == "/healthz":
                    problem = tokens.problem()
                    status = 503 if problem else 200
                    body = json.dumps({"status": "signed_out" if problem else "ok", "detail": problem or ""}).encode()
                    self.send_response(status)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return
                if not path.startswith("/v1/") or self.headers.get("Upgrade"):
                    status = 404
                    return self._json(404, "not_found", "only HTTP requests under /v1/ are forwarded")
                body = self._body() if self.command in ("POST", "PUT", "PATCH") else None
                headers = {k: v for k, v in self.headers.items()
                           if k.lower() not in HOP_BY_HOP | {"host", "authorization", "content-length"}}
                try:
                    token = tokens.access_token()
                    res, conn = self._send(headers, body, token)
                    if res.status == 401:
                        res.read()
                        conn.close()
                        res, conn = self._send(headers, body, tokens.refresh_after_rejection(token))
                except SignedOut as e:
                    status = 401
                    return self._json(401, "proxy_signed_out", str(e))
                status = res.status
                try:
                    self._relay(res)
                finally:
                    conn.close()
            except (BrokenPipeError, ConnectionResetError):
                pass
            except Exception as e:
                log(f"error {self.command} {self.path.split('?')[0]}: {type(e).__name__}: {e}")
                if not status:
                    status = 502
                    try:
                        self._json(502, "upstream_error", "the proxy could not reach the upstream API")
                    except OSError:
                        pass
            finally:
                log(f"{self.client_address[0]} {self.command} {self.path.split('?')[0]} {status} {time.time() - started:.1f}s")

        def _send(self, headers, body, token):
            conn = http.client.HTTPSConnection(UPSTREAM_HOST, timeout=900)
            conn.request(self.command, self.path, body=body, headers={**headers, "Authorization": "Bearer " + token})
            return conn.getresponse(), conn

        def _relay(self, res):
            self.send_response(res.status)
            length = res.getheader("Content-Length")
            for k, v in res.getheaders():
                if k.lower() not in HOP_BY_HOP | {"content-length"}:
                    self.send_header(k, v)
            bodiless = self.command == "HEAD" or res.status in (204, 304)
            if length is not None:
                self.send_header("Content-Length", length)
            elif not bodiless:
                self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            if bodiless:
                return
            while True:
                chunk = res.read1(65536)
                if not chunk:
                    break
                self.wfile.write(chunk if length is not None else b"%x\r\n%s\r\n" % (len(chunk), chunk))
                self.wfile.flush()
            if length is None:
                self.wfile.write(b"0\r\n\r\n")
                self.wfile.flush()

        do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = _handle

    return Proxy


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 64

    def server_bind(self):
        # the bridge address may not exist yet when the host boots
        self.socket.setsockopt(socket.IPPROTO_IP, getattr(socket, "IP_FREEBIND", 15), 1)
        super().server_bind()


def cmd_serve(_args):
    host, _, port = os.environ.get("CODEX_PROXY_LISTEN", "10.120.0.1:8455").rpartition(":")
    allow = ipaddress.ip_network(os.environ.get("CODEX_PROXY_ALLOW", "10.120.0.0/24"))
    tokens = Tokens()
    threading.Thread(target=tokens.keepalive, daemon=True).start()
    server = Server((host, int(port)), make_handler(tokens, allow))
    log(f"listening on {host}:{port} for {allow}; " + (tokens.signed_out or f"signed in as {tokens.cred.get('email')}"))
    server.serve_forever()


def main():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    login = sub.add_parser("login")
    login.add_argument("--port", type=int, default=1455)
    login.add_argument("--timeout", type=int, default=600)
    login.add_argument("--paste", action="store_true", help="paste the callback address instead of listening")
    sub.add_parser("serve")
    sub.add_parser("status")
    args = ap.parse_args()
    return {"login": cmd_login, "serve": cmd_serve, "status": cmd_status}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main() or 0)
