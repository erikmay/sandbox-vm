#!/usr/bin/env python3
"""One-time Infisical setup for a sandbox host, run on the operator machine (stdlib only).

Creates (or reuses) a project with a single environment and a Universal Auth machine identity
that can read and write only that project, then writes the identity's settings to an env file
for the host. Acts with your own `infisical login` session; prints no secret.

  infisical-setup.py --url https://secrets.example.com --profile work \
      --project agent-logins-prod --env prod --identity sandbox-host --out infisical.env

Copy the env file to the host as /etc/sandbox-logins/infisical.env (root, mode 0640) and
delete the local copy. Running it again creates a new client secret for the same identity.
"""
import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", required=True, help="Infisical base URL, without /api")
    ap.add_argument("--profile", help="infisical CLI profile holding your login")
    ap.add_argument("--project", required=True)
    ap.add_argument("--env", default="prod")
    ap.add_argument("--identity", required=True)
    ap.add_argument("--role", default="member", help="project role of the identity (member = read and write)")
    ap.add_argument("--out", required=True, help="env file to write (mode 0600)")
    a = ap.parse_args()
    base = a.url.rstrip("/")

    cmd = ["infisical", "user", "get", "token", "--plain"] + (["--profile", a.profile] if a.profile else [])
    token = subprocess.run(cmd, capture_output=True, text=True).stdout.strip().split("\n")[-1]
    if len(token) < 20:
        sys.exit("no infisical CLI session; run `infisical login` first")

    def req(method, path, body=None):
        r = urllib.request.Request(base + path, method=method,
                                   data=json.dumps(body).encode() if body is not None else None,
                                   headers={"Authorization": "Bearer " + token, "Content-Type": "application/json",
                                            "User-Agent": "sandbox-logins-setup"})  # Cloudflare blocks Python-urllib
        try:
            with urllib.request.urlopen(r, timeout=30) as res:
                text = res.read().decode()
        except urllib.error.HTTPError as e:
            sys.exit(f"{method} {path}: HTTP {e.code} {e.read().decode(errors='replace')[:300]}")
        return json.loads(text) if text else {}

    org = req("GET", "/api/v1/organization")["organizations"][0]

    projects = {p["name"]: p for p in req("GET", "/api/v1/projects?type=secret-manager")["projects"]}
    if a.project in projects:
        pid = projects[a.project]["id"]
        print(f"project {a.project}: exists")
    else:
        pid = req("POST", "/api/v1/projects", {"projectName": a.project, "slug": a.project,
                                               "type": "secret-manager", "shouldCreateDefaultEnvs": True})["project"]["id"]
        print(f"project {a.project}: created")
        # keep only the requested environment in a project this script created
        envs = req("GET", f"/api/v1/projects/{pid}")
        envs = envs.get("project", envs).get("environments", [])
        if not any(e["slug"] == a.env for e in envs):
            req("POST", f"/api/v1/projects/{pid}/environments", {"name": a.env, "slug": a.env})
        for e in envs:
            if e["slug"] != a.env:
                req("DELETE", f"/api/v1/projects/{pid}/environments/{e['id']}")
    envs = req("GET", f"/api/v1/projects/{pid}")
    envs = [e["slug"] for e in envs.get("project", envs).get("environments", [])]
    if a.env not in envs:
        sys.exit(f"project {a.project} has no environment {a.env} (has: {', '.join(envs)})")

    members = req("GET", f"/api/v2/organizations/{org['id']}/identity-memberships?limit=100")["identityMemberships"]
    identity = next((m["identity"]["id"] for m in members if m["identity"]["name"] == a.identity), None)
    if identity:
        print(f"identity {a.identity}: exists")
    else:
        identity = req("POST", "/api/v1/identities", {"name": a.identity, "organizationId": org["id"],
                                                      "role": "no-access"})["identity"]["id"]
        req("POST", f"/api/v1/auth/universal-auth/identities/{identity}", {
            "accessTokenTTL": 3600, "accessTokenMaxTTL": 86400,
            "clientSecretTrustedIps": [{"ipAddress": "0.0.0.0/0"}, {"ipAddress": "::/0"}],
            "accessTokenTrustedIps": [{"ipAddress": "0.0.0.0/0"}, {"ipAddress": "::/0"}]})
        print(f"identity {a.identity}: created (organization role no-access)")

    in_project = req("GET", f"/api/v1/projects/{pid}/identity-memberships?limit=100")["identityMemberships"]
    if not any(m["identity"]["id"] == identity for m in in_project):
        req("POST", f"/api/v1/projects/{pid}/identity-memberships/{identity}",
            {"roles": [{"role": a.role, "isTemporary": False}]})
        print(f"identity {a.identity}: {a.role} in {a.project}")

    client_id = req("GET", f"/api/v1/auth/universal-auth/identities/{identity}")["identityUniversalAuth"]["clientId"]
    secret = req("POST", f"/api/v1/auth/universal-auth/identities/{identity}/client-secrets",
                 {"description": f"{a.identity} host", "ttl": 0, "numUsesLimit": 0})["clientSecret"]

    fd = os.open(a.out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(f"INFISICAL_API_URL={base}\nINFISICAL_PROJECT_ID={pid}\nINFISICAL_ENVIRONMENT={a.env}\n"
                f"INFISICAL_CLIENT_ID={client_id}\nINFISICAL_CLIENT_SECRET={secret}\n")
    print(f"wrote {a.out} (mode 0600); the client secret has no expiry and is shown nowhere else")


if __name__ == "__main__":
    main()
