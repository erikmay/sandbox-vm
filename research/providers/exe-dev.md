# exe.dev

Checked: 2026-11-25 (tested on a trial account). Sources:
[docs](https://exe.dev/docs), [agent skill](https://exe.dev/docs/agent-skill.md),
[exeuntu Dockerfile](https://github.com/boldsoftware/exeuntu/blob/main/Dockerfile),
and `ssh exe.dev help <command>`.

exe.dev isn't a hosted coding agent itself (it's persistent SSH-accessible VMs), but it's commonly used to run self-managed agents, so it's a useful reference point.

## Machine

| | |
| --- | --- |
| Base | Ubuntu 24.04 (`exeuntu`, a container image booted as a VM with a block device) |
| Isolation | VM with persistent disk replicated within the region |
| Resources | Plan capacity shared across all VMs (trial: 2 vCPU, 8 GB RAM, 25 GB disk total) |
| User | `exedev`, passwordless sudo |
| Control plane | `ssh exe.dev <command>` (`new`, `cp`, `rm`, `pause`, `resume`, `ls --json`, …) or HTTPS API |

## Preinstalled (from the Dockerfile)

| Area | Contents |
| --- | --- |
| Agents | Claude Code, Codex, OpenCode, pi (updated via `exeuntu update <agent>`); Shelley (exe.dev's own agent) |
| Languages | Go (latest stable), Python 3 with pip/pipx, uv. No Node.js |
| Containers | docker.io, buildx, compose |
| Tools | git, gh 2.97, ripgrep, jq, sqlite3, curl, wget, vim, neovim, rsync, tree, socat, netcat, lsof, nginx, build-essential, ffmpeg, imagemagick, bubblewrap, mitmproxy, btop, DuckDB, Tailscale (service disabled) |
| Not included | dtach, mosh |

## Trial timings (2026-11-25)

| Operation | Time |
| --- | --- |
| Create and set up base VM | 33 s |
| Clone VM (`cp`) and start an agent | ~30 s |
| `pause` (RAM snapshot to disk) / `resume` | 4 s / 3 s (running processes survive) |

During testing, the SSH lobby occasionally hung on new connections during banner exchange, so any automation should retry failed connects.
