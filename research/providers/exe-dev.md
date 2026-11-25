# exe.dev

Checked: 2026-11-25, with a live trial account. Sources:
[docs](https://exe.dev/docs), [agent skill](https://exe.dev/docs/agent-skill.md),
[exeuntu Dockerfile](https://github.com/boldsoftware/exeuntu/blob/main/Dockerfile),
and the CLI help (`ssh exe.dev help <command>`).

exe.dev is not an agent product but general persistent VMs reached over SSH;
it is included because it is a common host for self-managed agents.

## Machine

| | |
| --- | --- |
| Base | Ubuntu 24.04 (`exeuntu` image, a container image booted as a VM with a block device) |
| Isolation | VM, persistent disk replicated in the region |
| Resources | Plan capacity shared by all your VMs (trial: 2 vCPU, 8 GB RAM, 25 GB disk in total) |
| User | `exedev`, passwordless sudo |
| Control plane | `ssh exe.dev <command>` (`new`, `cp`, `rm`, `pause`, `resume`, `ls --json`, …) or an HTTPS API |

## Preinstalled (Dockerfile)

| Area | Contents |
| --- | --- |
| Agents | Claude Code, Codex, OpenCode, pi; updated with `exeuntu update <agent>`; Shelley (exe.dev's own agent) |
| Languages | Go (latest stable), Python 3 with pip and pipx, uv. No Node.js |
| Containers | docker.io, buildx, compose |
| Tools | git, gh 2.97, ripgrep, jq, sqlite3, curl, wget, vim, neovim, rsync, tree, socat, netcat, lsof, nginx, build-essential, ffmpeg, imagemagick, bubblewrap, mitmproxy, btop, DuckDB, Tailscale (service disabled) |
| Not included | dtach, mosh |

## Measured (trial, 2026-11-25)

| Operation | Time |
| --- | --- |
| Create a VM and set it up (base VM) | 33 s |
| Clone a VM (`cp`) and start an agent | about 30 s |
| `pause` (RAM snapshot to disk) / `resume` | 4 s / 3 s; running processes survive |

The SSH lobby sometimes stalled new connections during the banner exchange;
clients should retry connection failures.

## Ground truth

Docs describe the image; the probe shows it. Run [`scripts/probe.sh`](../../scripts/probe.sh) inside a session as described in [`METHOD.md`](../METHOD.md) and commit the result to `research/probes/exe-dev/`.
