#!/bin/bash
# Create a sandbox from the current ubuntu-agent template and inject per-sandbox settings.
#   new-sandbox.sh <name> [--memory 6GiB] [--pubkey FILE] [--git-name NAME --git-email EMAIL]
# Credentials are never in the template. sync-logins.sh puts the current ones in: Codex through
# the host's login proxy, Claude Code through its token from the secret store (scripts/logins).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
name=${1:?usage: new-sandbox.sh <name> [--memory SIZE] [--pubkey FILE] [--git-name N --git-email E]}; shift
memory=""; pubkey=""; git_name=""; git_email=""
while [ $# -gt 0 ]; do
  case $1 in
    --memory) memory=$2; shift 2 ;;
    --pubkey) pubkey=$2; shift 2 ;;
    --git-name) git_name=$2; shift 2 ;;
    --git-email) git_email=$2; shift 2 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done

incus copy ubuntu-agent "$name"
[ -n "$memory" ] && incus config set "$name" limits.memory="$memory"
incus start "$name"
until incus exec "$name" -- test -s /etc/machine-id 2>/dev/null; do sleep 0.2; done
for _ in $(seq 1 100); do incus exec "$name" -- systemctl is-active --quiet ssh.socket && break; sleep 0.2; done

if [ -n "$pubkey" ]; then
  incus file push "$pubkey" "$name/home/agent/.ssh/authorized_keys" --uid 1000 --gid 1000 --mode 0600
fi
if [ -n "$git_name" ] && [ -n "$git_email" ]; then
  incus exec "$name" -- sudo -u agent git config --global user.name "$git_name"
  incus exec "$name" -- sudo -u agent git config --global user.email "$git_email"
fi

"$here/sync-logins.sh" "$name"

ip=""
for _ in $(seq 1 50); do
  ip=$(incus list "$name" -c 4 --format csv | cut -d' ' -f1)
  [ -n "$ip" ] && break; sleep 0.2
done
echo "$name ready: incus exec $name -- sudo -iu agent   |   ssh -J <host> agent@$ip"
