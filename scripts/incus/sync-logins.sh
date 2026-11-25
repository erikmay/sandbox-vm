#!/bin/bash
# Put the current logins into running sandboxes. new-sandbox.sh calls this for each new sandbox;
# run it by hand after rotating a secret:
#   sync-logins.sh <name>... | --all   [--force-codex-config]
#
# Codex        ~/.codex/config.toml points at the host's login proxy (scripts/logins). The sandbox
#              holds no OpenAI credential at all. Written only if the file is missing, so your
#              own Codex settings survive; --force-codex-config replaces it.
# Claude Code  CLAUDE_CODE_OAUTH_TOKEN (from `claude setup-token`, stored in Infisical) goes to
#              /etc/agent-secrets.env (root:agent, 0640), which the image loads into every session.
set -euo pipefail
NET=${NET:-incusbr0}
PROXY_PORT=${PROXY_PORT:-8455}
force_codex=no
targets=()
for arg in "$@"; do
  case $arg in
    --all) mapfile -t targets < <(incus list type=container status=running profile=agent -c n --format csv) ;;
    --force-codex-config) force_codex=yes ;;
    -*) echo "unknown option $arg" >&2; exit 2 ;;
    *) targets+=("$arg") ;;
  esac
done
[ ${#targets[@]} -gt 0 ] || { echo "usage: sync-logins.sh <name>... | --all [--force-codex-config]" >&2; exit 2; }

gw=$(incus network get "$NET" ipv4.address | cut -d/ -f1)

claude_token=""
if command -v sandbox-secrets >/dev/null; then
  claude_token=$(sandbox-secrets get CLAUDE_CODE_OAUTH_TOKEN 2>/dev/null) || claude_token=""
fi
[ -n "$claude_token" ] || echo "note: no CLAUDE_CODE_OAUTH_TOKEN in the secret store; Claude Code stays logged out" >&2

for name in "${targets[@]}"; do
  incus exec "$name" -- sudo -H -u agent env FORCE="$force_codex" sh -c '
    umask 077; mkdir -p ~/.codex
    [ "$FORCE" = yes ] || [ ! -e ~/.codex/config.toml ] || exit 0
    cat > ~/.codex/config.toml' <<EOF
# Written by sync-logins.sh. Requests go to the login proxy on the sandbox host, which adds the
# ChatGPT plan token; there is no credential in this sandbox and \`codex login\` is not needed.
model_provider = "chatgpt-plan"

[model_providers.chatgpt-plan]
name = "ChatGPT plan (host proxy)"
base_url = "http://$gw:$PROXY_PORT/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
EOF

  if [ -n "$claude_token" ]; then
    printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$claude_token" |
      incus exec "$name" -- sh -c 'umask 027; cat > /etc/agent-secrets.env; chown root:agent /etc/agent-secrets.env'
    # With the token set, the first interactive `claude` would still stop at the theme picker.
    incus exec "$name" -- sudo -H -u agent python3 - <<'PY'
import json, os
path = os.path.expanduser("~/.claude.json")
try:
    with open(path) as f:
        cfg = json.load(f)
except (FileNotFoundError, ValueError):
    cfg = {}
if not cfg.get("hasCompletedOnboarding"):
    cfg["hasCompletedOnboarding"] = True
    cfg.setdefault("theme", "dark")
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
    os.chmod(path, 0o600)
PY
  fi
  echo "$name: logins synced (codex: proxy http://$gw:$PROXY_PORT, claude: $([ -n "$claude_token" ] && echo token || echo none))"
done
