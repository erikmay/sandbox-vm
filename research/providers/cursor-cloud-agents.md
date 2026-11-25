# Cursor Cloud Agents (formerly Background Agents)

Checked: 2026-11-25. Sources:
[setup](https://cursor.com/docs/cloud-agent/setup),
[builds](https://cursor.com/docs/cloud-agent/builds),
[security and network](https://cursor.com/docs/cloud-agent/security-network).

## Machine

| | |
| --- | --- |
| Base | "Isolated Ubuntu machines", no version given (the Docker install example pins Ubuntu 24.04 packages) |
| Isolation | AWS VMs; docs note Docker "runs inside another container layer", so likely a container inside a VM |
| Resources | "Default VM profile with limited memory and CPU", no numbers published (Enterprise can request larger profiles) |

## Preinstalled

Cursor doesn't document what ships in its default image. Agents have computer use with a desktop and browser. Docker works, though you have to install it yourself (`fuse-overlayfs` and `iptables-legacy` are recommended).

## Network

Internet is open by default. Admins can switch to "Default + allowlist" or "Allowlist only" per user, team, or environment. Private networks are reachable via Tailscale or Cloudflare Tunnel, and egress IP ranges are published.

## Customization and lifetime

You can configure the environment interactively with an agent in the dashboard, save a snapshot, or point at a Dockerfile.

`.cursor/environment.json` supports `snapshot`, `build.dockerfile` / `context`, `install` (idempotent, runs on each build, 5–300 min timeout, default 90), `start` and `terminals` (tmux sessions started with each agent), and `repositoryDependencies`.

Builds produce a bootable disk snapshot (including `/var/lib/docker`, minus running processes) and refresh on a schedule. If a rebuild fails, the last working snapshot stays active. Unused snapshots get deleted after 30 days.
