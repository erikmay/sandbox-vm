# Cursor Cloud Agents (formerly Background Agents)

Checked: 2026-11-25. Sources:
[setup](https://cursor.com/docs/cloud-agent/setup),
[builds](https://cursor.com/docs/cloud-agent/builds),
[security and network](https://cursor.com/docs/cloud-agent/security-network).

## Machine

| | |
| --- | --- |
| Base | "Isolated Ubuntu machines"; no version stated (the Docker install sample pins Ubuntu 24.04 packages) |
| Isolation | VMs on AWS; Docker "runs inside another container layer", so probably a container in a VM |
| Resources | "Default VM profile with limited memory and CPU", no numbers; Enterprise can ask for more |

## Preinstalled

Not documented. Agents start on "Cursor's default image" until your own build
succeeds. Agents have computer use with a desktop and a browser. Docker is
supported but you install it yourself (`fuse-overlayfs` and `iptables-legacy`
recommended).

## Network

Internet on by default. Admins choose "Default + allowlist" or "Allowlist
only" per user, team or environment. Tailscale and Cloudflare Tunnel reach
private networks. Egress IP ranges are published.

## Customization and lifetime

- Agent-led setup in the dashboard, a saved snapshot, or a Dockerfile.
- `.cursor/environment.json`: `snapshot`, `build.dockerfile` / `context`,
  `install` (idempotent, runs on each build, timeout 5–300 minutes, default
  90), `start` and `terminals` (tmux sessions at each agent start),
  `repositoryDependencies`.
- A build is a bootable disk snapshot including `/var/lib/docker`, without
  processes. Builds are refreshed on a schedule; a failed build keeps the
  last good one. Snapshots are deleted after 30 days without use.

## Ground truth

Docs describe the image; the probe shows it. Run [`scripts/probe.sh`](../../scripts/probe.sh) inside a session as described in [`METHOD.md`](../METHOD.md) and commit the result to `research/probes/cursor-cloud-agents/`.
