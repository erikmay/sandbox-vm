#!/bin/bash
# Incus profile `agent` and network ACL `agent-egress` for agent sandboxes. Idempotent.
# Sandboxes get: 4 GiB / 6 CPUs / 8192 processes, Docker-capable nesting, an isolated uid range,
# no traffic to sibling sandboxes, and no traffic to private networks (LAN, VPN, the host itself)
# except DNS and DHCP on the bridge gateway. Raise memory per sandbox with `incus config set <name> limits.memory=6GiB`.
set -euo pipefail
NET=${NET:-incusbr0}

# Editing an ACL that is in use fails on Incus 6.0.4 (nft "flush chain ... acl.<bridge>"), so
# detach it, recreate it with all rules, and attach it again below.
if incus profile show agent >/dev/null 2>&1; then
  incus profile device remove agent eth0 >/dev/null 2>&1 || true
fi
incus network acl delete agent-egress >/dev/null 2>&1 || true
gw=$(incus network get "$NET" ipv4.address | cut -d/ -f1)
# Incus orders reject before allow, so an "allow DNS" exception never wins. Instead the gateway is
# left out of the private ranges, and only its DNS (53) and DHCP (67) ports stay open.
IFS=. read -r a b c d <<<"$gw"
before="10.0.0.0-$a.$b.$c.$((d-1))"; after="$a.$b.$c.$((d+1))-10.255.255.255"
[ "$a" = 10 ] || { echo "expects the bridge in 10.0.0.0/8, got $gw"; exit 1; }
incus network acl create agent-egress <<YAML
description: Agent sandboxes reach the internet, not private networks or the host
egress:
- action: reject
  description: private and link-local ranges, except the bridge gateway
  destination: $before,$after,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10,169.254.0.0/16
  state: enabled
- action: reject
  description: host services on the gateway, except DNS
  destination: $gw/32
  protocol: tcp
  destination_port: 1-52,54-65535
  state: enabled
- action: reject
  description: host services on the gateway, except DNS and DHCP
  destination: $gw/32
  protocol: udp
  destination_port: 1-52,54-66,68-65535
  state: enabled
ingress: []
YAML

incus profile show agent >/dev/null 2>&1 || incus profile create agent
incus profile edit agent <<YAML
description: Agent sandbox limits and isolation
config:
  limits.cpu: "6"
  limits.memory: 4GiB
  limits.processes: "8192"
  security.nesting: "true"
  security.syscalls.intercept.mknod: "true"
  security.syscalls.intercept.setxattr: "true"
  security.idmap.isolated: "true"
devices:
  eth0:
    name: eth0
    network: $NET
    type: nic
    security.port_isolation: "true"
    security.acls: agent-egress
    security.acls.default.egress.action: allow
    security.acls.default.ingress.action: allow
YAML
incus profile show agent
