#!/usr/bin/env python3
"""Minimal Infisical client for the sandbox host (stdlib only).

Reads its settings from the environment or from /etc/sandbox-logins/infisical.env:
  INFISICAL_API_URL, INFISICAL_PROJECT_ID, INFISICAL_ENVIRONMENT,
  INFISICAL_CLIENT_ID, INFISICAL_CLIENT_SECRET   (a Universal Auth machine identity)

CLI:
  infisical.py get NAME          print the value (no trailing newline)
  infisical.py set NAME          read the value from stdin
  infisical.py list              print the secret names
  infisical.py delete NAME       remove a secret
Values are never passed as arguments, so they do not show up in the process list.
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

ENV_FILE = os.environ.get("SANDBOX_LOGINS_ENV", "/etc/sandbox-logins/infisical.env")
KEYS = ("INFISICAL_API_URL", "INFISICAL_PROJECT_ID", "INFISICAL_ENVIRONMENT",
        "INFISICAL_CLIENT_ID", "INFISICAL_CLIENT_SECRET")


class InfisicalError(RuntimeError):
    pass


class NotFound(InfisicalError):
    pass


def load_settings():
    cfg = {k: os.environ[k] for k in KEYS if os.environ.get(k)}
    if len(cfg) < len(KEYS) and os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                key, sep, value = line.strip().partition("=")
                if sep and key in KEYS and key not in cfg:
                    cfg[key] = value.strip().strip('"').strip("'")
    missing = [k for k in KEYS if k not in cfg]
    if missing:
        raise InfisicalError(f"Infisical is not configured (missing {', '.join(missing)}; see {ENV_FILE})")
    cfg["INFISICAL_API_URL"] = cfg["INFISICAL_API_URL"].rstrip("/").removesuffix("/api")
    return cfg


class Client:
    def __init__(self, cfg=None):
        self.cfg = cfg or load_settings()
        self._token = None

    def _request(self, method, path, body=None, auth=True):
        headers = {"Accept": "application/json", "User-Agent": "sandbox-logins"}
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if auth:
            headers["Authorization"] = "Bearer " + self._access_token()
        req = urllib.request.Request(self.cfg["INFISICAL_API_URL"] + path, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as res:
                text = res.read().decode()
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:300]
            if e.code == 404:
                raise NotFound(f"{method} {path.split('?')[0]}: not found") from None
            raise InfisicalError(f"{method} {path.split('?')[0]}: HTTP {e.code} {detail}") from None
        except urllib.error.URLError as e:
            raise InfisicalError(f"{method} {path.split('?')[0]}: {e.reason}") from None
        return json.loads(text) if text else {}

    def _access_token(self):
        if self._token is None:
            r = self._request("POST", "/api/v1/auth/universal-auth/login",
                              {"clientId": self.cfg["INFISICAL_CLIENT_ID"],
                               "clientSecret": self.cfg["INFISICAL_CLIENT_SECRET"]}, auth=False)
            self._token = r["accessToken"]
        return self._token

    def _scope(self):
        return {"projectId": self.cfg["INFISICAL_PROJECT_ID"],
                "environment": self.cfg["INFISICAL_ENVIRONMENT"], "secretPath": "/"}

    def get(self, name):
        q = urllib.parse.urlencode({**self._scope(), "viewSecretValue": "true",
                                    "expandSecretReferences": "false", "includeImports": "false"})
        r = self._request("GET", f"/api/v4/secrets/{urllib.parse.quote(name)}?{q}")
        return r["secret"]["secretValue"]

    def set(self, name, value):
        body = {**self._scope(), "secretValue": value}
        path = f"/api/v4/secrets/{urllib.parse.quote(name)}"
        try:
            self._request("PATCH", path, body)
        except NotFound:
            self._request("POST", path, body)

    def delete(self, name):
        self._request("DELETE", f"/api/v4/secrets/{urllib.parse.quote(name)}", self._scope())

    def names(self):
        q = urllib.parse.urlencode({**self._scope(), "viewSecretValue": "false"})
        return sorted(s["secretKey"] for s in self._request("GET", f"/api/v4/secrets?{q}")["secrets"])


def main(argv):
    if len(argv) < 2 or argv[1] not in ("get", "set", "list", "delete") or (argv[1] != "list" and len(argv) != 3):
        sys.stderr.write(__doc__)
        return 2
    try:
        client = Client()
        if argv[1] == "get":
            sys.stdout.write(client.get(argv[2]))
        elif argv[1] == "set":
            client.set(argv[2], sys.stdin.read().rstrip("\n"))
        elif argv[1] == "delete":
            client.delete(argv[2])
        else:
            print("\n".join(client.names()))
    except NotFound as e:
        sys.stderr.write(f"{e}\n")
        return 3
    except InfisicalError as e:
        sys.stderr.write(f"{e}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
