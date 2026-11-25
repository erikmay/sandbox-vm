# Vercel Sandbox

Checked: 2026-11-25 (docs only, no live probe yet). Sources:
[concepts](https://vercel.com/docs/sandbox/concepts),
[runtimes](https://vercel.com/docs/sandbox/concepts/runtimes),
[images](https://vercel.com/docs/sandbox/concepts/images),
[pricing and limits](https://vercel.com/docs/sandbox/pricing),
[firewall](https://vercel.com/docs/sandbox/concepts/firewall),
[snapshots](https://vercel.com/docs/sandbox/concepts/snapshots),
[persistent sandboxes](https://vercel.com/docs/sandbox/concepts/persistent-sandboxes),
[installing system packages](https://vercel.com/docs/sandbox/examples/install-system-packages),
and the [`universal` image Dockerfile](https://github.com/vercel/sandbox/tree/main/images/universal) (changelog 0.1.4, Ubuntu package snapshot of 2026-11-16).

Like exe.dev, this isn't a coding agent product but general-purpose sandboxes you drive from the CLI (`vercel sandbox create/exec`) or the `@vercel/sandbox` SDK. Plenty of people run agents in them, which is why it's here. The original [fxs](https://github.com/fazxes/fxs) tool that started this research ran its agents on Vercel Sandbox.

The product changed a lot this year: since SDK v3 the default is an Ubuntu 26.04 image. The older Amazon Linux 2023 "runtimes" still work but are deprecated.

## Machine

| | |
| --- | --- |
| Base | Ubuntu 26.04 (`vercel/sandbox/universal:latest`); legacy runtimes are Amazon Linux 2023 |
| Isolation | Firecracker microVM with its own kernel |
| Arch | x86_64 (custom images must be `linux/amd64`) |
| Resources | 1 or an even number of vCPUs from 2 to 32 (default 2), 2 GB RAM per vCPU. Caps: Hobby 4 / 8 GB, Pro 8 / 16 GB, Enterprise 32 / 64 GB |
| Disk | 64 GB ephemeral NVMe (32 GB on legacy runtimes) |
| Timeout | 5 min by default; max 45 min on Hobby, 24 h on Pro/Enterprise (`extendTimeout()`) |
| User | `ubuntu` (uid 1000), passwordless sudo, home and working directory `/vercel` |
| Regions | 19, default `iad1` |

## Images

Picked with `Sandbox.create({ image: 'vcr.vercel.com/vercel/sandbox/node:24' })`, pinnable by tag or digest, rebuilt nightly:

- `universal:latest` (default): Node, Python, coding agents and common tools (below)
- `node:22`, `node:24`, `node:26`: Node with pnpm
- `python:3.14`: pip, venv, uv
- `arch:latest`: Arch Linux with yay and base-devel
- `ubuntu:latest`: plain Ubuntu with sudo
- Legacy: `runtime: 'node22' | 'node24' | 'node26' | 'python3.13'`

Custom images are built from a Dockerfile and pushed to the Vercel Container Registry (`vercel vcr build docker . repo:tag --push`). `ENTRYPOINT` and `CMD` are ignored; `WORKDIR` sets the start directory.

## Preinstalled in `universal`

| Area | Contents |
| --- | --- |
| Node.js | Node 24 with npm, npx, corepack, pnpm 11; Bun |
| Python | Python 3.14 with pip, venv, uv (`python-is-python3`) |
| Agents | Claude Code 2.1.325, Codex 0.169.0, OpenCode, pi, fx |
| Tools | git, git-lfs, gh, curl, wget, jq, ripgrep, fzf, tmux, vim, nano, less, tree, rsync, zip, unzip, xz-utils, bzip2, sqlite3, lsof, procps, iproute2, dnsutils, iputils-ping, netcat, openssl, gnupg, file |
| Package manager | `apt-get` with sudo; run `apt-get update` first, a new sandbox has no package index |
| Docker | Not in the image; it can be installed and run with sudo |
| Browsers | None |
| Databases | Only the sqlite3 CLI |
| Other languages | None (no Go, Rust, Java, Ruby, PHP) |

The legacy Amazon Linux runtimes ship much less: bind-utils, bzip2, findutils, git, gzip, iputils, libicu, libjpeg, libpng, ncurses-libs, openssl, procps, tar, unzip, which, whois, zstd. User `vercel-sandbox`, working directory `/vercel/sandbox`, `dnf` with sudo.

## Network

Outbound is open by default (`allow-all`). A per-sandbox firewall can switch to `deny-all` or a custom policy that allows domains (matched by SNI, wildcards allowed) and allows or denies CIDR ranges. Rules can also inject credentials, proxy requests or return a fixed response; for those domains HTTPS is decrypted with a per-sandbox CA that is installed automatically.

Up to 15 ports can be exposed, each with its own public URL (`sandbox.domain(3000)`). Static IPs and VPC peering come with Secure Compute.

## Persistence and billing

Sandboxes are persistent by default: stopping one, or hitting the timeout, snapshots the filesystem and the next call resumes from it (`persistent: false` or `--non-persistent` to opt out). Snapshots expire 30 days after last use by default (`0` means never), and you can keep the last 1 to 10. Deleting a sandbox doesn't delete its snapshots.

Billing is by active CPU ($0.128 per hour) plus provisioned memory ($0.0212 per GB-hour, 1 minute minimum), creations, outbound data and snapshot storage ($0.08 per GB-month). A stopped sandbox costs nothing for CPU or memory.

## Probing it

```sh
vercel sandbox create --name probe
vercel sandbox copy scripts/probe.sh probe:/tmp/probe.sh
vercel sandbox exec probe -- bash /tmp/probe.sh > research/probes/vercel-sandbox/$(date +%F).md
vercel sandbox rm probe
```
