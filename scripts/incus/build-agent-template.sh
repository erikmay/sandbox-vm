#!/bin/bash
# Build a dated ubuntu-agent template from the clean `base`, verify it in a throwaway copy,
# then make it the current `ubuntu-agent` (the previous one is kept as `ubuntu-agent-prev`).
# Run on the Incus host as a member of incus-admin. Rebuild weekly; never patch a template in place.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
img="$here/../images/ubuntu-agent"
name="ubuntu-agent-$(date +%Y%m%d-%H%M)"

incus info base >/dev/null || { echo "need a stopped container 'base' (images:ubuntu/24.04)"; exit 1; }
echo "==> building $name"
incus copy base "$name" -p default -p agent
incus start "$name"
incus file push "$img/build.sh" "$name/root/build.sh"
incus exec "$name" -- bash /root/build.sh
incus exec "$name" -- rm -f /root/build.sh
incus stop "$name"

echo "==> verifying in a fresh copy"
incus delete -f "$name-verify" 2>/dev/null || true
incus copy "$name" "$name-verify"
incus start "$name-verify"
until incus exec "$name-verify" -- true 2>/dev/null; do sleep 0.5; done
incus file push "$img/verify.sh" "$name-verify/root/verify.sh"
if ! incus exec "$name-verify" -- bash /root/verify.sh; then
  echo "verification failed; $name kept for inspection, ubuntu-agent unchanged"
  exit 1
fi
incus delete -f "$name-verify"

echo "==> $name becomes ubuntu-agent"
if incus info ubuntu-agent >/dev/null 2>&1; then
  incus delete -f ubuntu-agent-prev 2>/dev/null || true
  incus move ubuntu-agent ubuntu-agent-prev
fi
incus copy "$name" ubuntu-agent
echo "done: ubuntu-agent (dated copy: $name)"
