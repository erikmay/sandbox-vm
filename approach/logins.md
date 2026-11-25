# Logins: sign in once, every sandbox is signed in

New sandboxes should be able to use Codex and Claude Code right away, without a login per
sandbox and without credentials baked into the image. The host does this in two different ways,
because the two products handle shared logins differently.

| | How | Where the credential lives | Per new sandbox |
| --- | --- | --- | --- |
| Codex | A proxy on the host owns one ChatGPT plan login and adds the token to each request | Only on the host (backup in the secret store) | Nothing; `~/.codex/config.toml` points at the proxy |
| Claude Code | A long-lived token from `claude setup-token` | Secret store, copied into each sandbox | `sync-logins.sh` writes it at creation |

Scripts: [`../scripts/logins/`](../scripts/logins/) (host) and
[`../scripts/incus/sync-logins.sh`](../scripts/incus/sync-logins.sh) (injection).

## Codex: a login proxy on the host

A ChatGPT login can't simply be copied to several machines: its refresh token rotates, and the
first machine that refreshes logs the others out. OpenAI says so for Codex's `auth.json`
("Do not share the same file across concurrent jobs or multiple machines").

exe.dev solves this by keeping the ChatGPT login on its own servers and running a gateway that
VMs call without credentials. Their gateway isn't public, so this is the same design rebuilt on
OpenAI's documented flow, [ChatGPT plan usage for open-source and locally hosted
apps](https://developers.openai.com/siwc/token-sharing-open-source):

```
sandbox: codex ──http──▶ host: codex-plan-proxy (bridge gateway, one port)
                              adds "Authorization: Bearer <access token>"
                              only process that refreshes the rotating token
                         ──https──▶ api.openai.com/v1/responses
```

- [`codex_plan_proxy.py`](../scripts/logins/codex_plan_proxy.py) is one Python file without
  dependencies. `login` registers the host as the user's agent (PKCE, loopback callback,
  `client_id=dynamic_agent_client`, a stable host ID), validates the ID token against OpenAI's
  keys and stores the credential record with mode 0600. `serve` forwards `/v1/*` to
  `https://api.openai.com`, replaces any `Authorization` header with the current access token,
  and streams the response back.
- Refreshes are serialized behind one lock. The access token is renewed shortly before it
  expires, after a 401 from upstream (once, then the request is replayed), and once a day on an
  idle host so the 30-day refresh token doesn't lapse.
- After every refresh the record is backed up to the secret store, so a reinstalled host
  restores the login instead of asking for a new one.
- It runs as the unprivileged user `llmproxy` under systemd, listens only on the bridge gateway
  address, and refuses clients outside the sandbox network. The network ACL of the sandboxes
  opens exactly this port on the gateway and nothing else on the host.
- A sandbox gets this `~/.codex/config.toml` and never sees a token:

  ```toml
  model_provider = "chatgpt-plan"

  [model_providers.chatgpt-plan]
  name = "ChatGPT plan (host proxy)"
  base_url = "http://<gateway>:8455/v1"
  wire_api = "responses"
  requires_openai_auth = false
  supports_websockets = false
  ```

### Signing in

The callback goes to `127.0.0.1` on the machine that runs the browser, so forward that port to
the host for the one login:

```sh
ssh -L 1455:127.0.0.1:1455 <host> sudo codex-plan-proxy login
# open the printed address, approve in ChatGPT; the tab ends on "Sign-in received"
ssh <host> sudo codex-plan-proxy status
```

`login --paste` is the fallback: open the address anywhere and paste the `127.0.0.1` address the
browser was sent to.

### What I checked about device codes

exe.dev's onboarding shows a device code (`auth.openai.com/codex/device`). That flow belongs to
Codex's own OAuth client. For the plan-usage client the device endpoint answers
`invalid_client` ("This app is unavailable"), tested on 2026-11-25. A device login with Codex's
client ID yields a normal Codex login for ChatGPT's internal backend, which OpenAI says not to
use for plan usage from other tools. So this setup uses the documented browser flow.

### Limits

- OpenAI calls this a preview. The Responses API on this route rejects some fields and tools
  (hosted tools such as `tool_search`, image generation, file search). Codex's own shell tool
  works: in the test below it wrote a file and ran it. MCP tools and web search are untested.
- One person, own hardware. Letting other people use the sandboxes would be account sharing.
- On Plus the five-hour limit is shared by everything that uses the plan.
- Anything that can reach the proxy port can spend the plan. That is every container on the
  bridge and nothing else.

## Claude Code: a long-lived token

`claude setup-token` prints a token that is valid for about a year, doesn't rotate, and may be
used in several places at once. It is stored as `CLAUDE_CODE_OAUTH_TOKEN` in the secret store;
`sync-logins.sh` writes it to `/etc/agent-secrets.env` (root:agent, 0640) in each sandbox, and
the image loads that file into login shells and SSH sessions.

`sync-logins.sh` also sets `hasCompletedOnboarding` in `~/.claude.json`, otherwise the first
interactive `claude` stops at the theme picker even with a valid token. Claude Code's "do you
trust this folder?" question per new project stays.

The token only allows model requests: claude.ai connectors and Remote Control don't work with
it. Unlike the Codex setup, the token is inside the sandbox, so an agent that follows a
malicious prompt could read it. Rotate it by running `claude setup-token` again, storing the new
value, and `sync-logins.sh --all`.

## Tested (2026-11-25)

In a sandbox with no `codex login` and no OpenAI credential on disk:

```
$ codex exec --sandbox workspace-write "Create hello.py that prints the sum of 2 and 40, run it ..."
model: gpt-6.2-sol   provider: chatgpt-plan
exec /bin/bash -lc "printf 'print(2 + 40)\\n' > hello.py && python3 hello.py"  succeeded: 42
```

Two sandboxes created with `new-sandbox.sh` (about 5 s each) ran a Codex task and a `claude -p`
prompt at the same time over SSH, with no credential file in either home directory.
The proxy log shows `POST /v1/responses 200` for each turn. `claude -p` answers with the injected
token, and `/healthz` on the proxy reports the login state without revealing anything.

## Secret store

The scripts use a self-hosted [Infisical](https://infisical.com) through its API
([`infisical.py`](../scripts/logins/infisical.py), stdlib only). Only the host talks to it;
sandboxes have no access.

- [`infisical-setup.py`](../scripts/logins/infisical-setup.py) creates a project with one
  environment and a machine identity that can read and write only that project, and writes the
  identity's settings to an env file. It goes to `/etc/sandbox-logins/infisical.env` on the host
  (root:incus-admin, 0640).
- Secrets: `CLAUDE_CODE_OAUTH_TOKEN` (you set it once), `CODEX_PLAN_CREDENTIALS` (written by the
  proxy).
- If other identities get access to projects by a naming rule, name the project so the rule
  doesn't match. Mine gives a CI identity read access to every project that doesn't end in
  `-prod`, so the project is called `agent-logins-prod`.

```sh
# operator machine, once
scripts/logins/infisical-setup.py --url https://secrets.example.com --project agent-logins-prod \
    --identity sandbox-host --out infisical.env
# host
sudo scripts/logins/install.sh infisical.env && shred -u infisical.env
printf '%s' "$TOKEN" | sandbox-secrets set CLAUDE_CODE_OAUTH_TOKEN
```

## Tests

`python3 -m unittest discover -s tests` runs the proxy against a fake upstream: the sandbox's own
`Authorization` header never reaches the upstream, a rejected token is refreshed once and the
request replayed, an expiring token is refreshed first, clients outside the allowed network get
403, an unusable refresh token ends in a clear "signed out" error, a new login on disk is picked
up without a restart, and forged, expired or mismatched ID tokens are rejected.
