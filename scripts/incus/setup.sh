#!/bin/bash
# Install Incus on a Debian 13 host with an LVM volume group "vg0" that has free space,
# then create the clean base container. Run as root. Idempotent.
# Next: agent-profile.sh, ../logins/install.sh, build-agent-template.sh, new-sandbox.sh.
set -euo pipefail
POOL_SIZE=${POOL_SIZE:-340G}
here=$(cd "$(dirname "$0")" && pwd)
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq incus incus-client thin-provisioning-tools >/dev/null
[ -n "${SUDO_USER:-}" ] && usermod -aG incus-admin "$SUDO_USER"

lvs vg0/incus-thin >/dev/null 2>&1 || lvcreate -q --type thin-pool -L "$POOL_SIZE" -n incus-thin vg0
incus storage show default >/dev/null 2>&1 || incus admin init --preseed < "$here/incus-preseed.yaml"

incus info base >/dev/null 2>&1 || incus init images:ubuntu/24.04 base
incus list
