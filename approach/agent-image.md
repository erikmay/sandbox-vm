# The ubuntu-agent image

A template container for coding-agent sandboxes, built from the clean `base`
(`images:ubuntu/24.04`) by [`../scripts/images/ubuntu-agent/build.sh`](../scripts/images/ubuntu-agent/build.sh).
The contents follow what the hosted providers ship (see [`../research/`](../research/)), sized
for a 16 GB host running several sandboxes at once. A Fable model reviewed the first draft;
its main corrections are noted below.

## Build, verify, use

```sh
scripts/incus/agent-profile.sh            # once: profile `agent` and network ACL
scripts/incus/build-agent-template.sh     # build ubuntu-agent-<date>, verify a fresh copy, promote
scripts/incus/new-sandbox.sh sbx1 --pubkey ~/.ssh/id_ed25519.pub \
  --git-name "Your Name" --git-email you@example.com [--memory 6GiB]
```

`build-agent-template.sh` never touches the current template until the new one passes
[`verify.sh`](../scripts/images/ubuntu-agent/verify.sh) (51 checks) in a fresh copy. The
previous template stays as `ubuntu-agent-prev` for rollback. Rebuild weekly instead of
updating tools inside the template or the sandboxes.

## What's in it

| Area | Contents | Notes |
| --- | --- | --- |
| User | `agent` (uid 1000), passwordless sudo, locked password, home `/home/agent`, work dir `~/work` | The stock `ubuntu` user is renamed |
| Shell env | `/etc/environment` and `/etc/profile.d/00-agent-env.sh` | Agents run `bash -c` without a login shell, so PATH can't live in `.bashrc` |
| System | build-essential, cmake, common `-dev` headers, git, git-lfs, curl, jq, ripgrep, fd, fzf, tmux, dtach, vim, htop, strace, sqlite3, shellcheck, fonts, `ncurses-term` | Timezone UTC, locale `en_US.UTF-8` |
| Node | 24 (default) and 26 via [mise](https://mise.jdx.dev) in `/opt/mise`; pnpm and bun via mise | No corepack: it's gone from Node 25+ |
| Python | System 3.12 with venv and headers; [uv](https://docs.astral.sh/uv/) for anything else | No poetry/ruff/mypy preinstalled, `uvx` covers them |
| Go, Rust | Go via mise; Rust via rustup (minimal profile, clippy, rustfmt) | Cheap on a thin pool |
| Docker | Docker CE, compose, buildx from Docker's repo; `agent` in the `docker` group | Socket-activated: dockerd only starts on first use |
| Databases | PostgreSQL 16 and Redis installed, disabled | No RAM until `sudo systemctl start postgresql` |
| Browser | Chrome for Testing via Playwright in `/opt/ms-playwright`, OS deps installed, `chromium` on PATH; [agent-browser](https://github.com/vercel-labs/agent-browser) points at the same binary | One browser, not two |
| GitHub | `gh` from GitHub's apt repo | |
| Agents | Claude Code (native installer), Codex (release binary in `/usr/local/bin`), OpenCode, pi | Latest at build time, self-update off |
| SSH | Key-only, no root login; host keys generated on the first boot of each copy | |

`/etc/agent-image-manifest` records the versions of each build.

## Defaults that keep agents from hanging or drifting

- `GIT_EDITOR=true`, `PAGER=cat`, `GIT_PAGER=cat`, `GH_PAGER=cat`, `GH_PROMPT_DISABLED=1`: no
  editor or pager waits for input that never comes.
- `DISABLE_AUTOUPDATER=1` for Claude Code, `"autoupdate": false` for OpenCode, Codex as a
  static binary: five sandboxes don't update themselves into five different versions.
  Updates come only from a template rebuild.
- `CI` is deliberately **not** set: it switches pnpm to frozen lockfiles and changes test
  runners, which confuses agents in a dev sandbox.
- Git: `init.defaultBranch=main`, `pull.ff=only`, `push.autoSetupRemote`, `fetch.prune`. No
  identity in the template; `new-sandbox.sh` sets it per sandbox, otherwise agents invent one.
- Apt timers and unattended-upgrades are off: no apt lock fights or background CPU in every
  sandbox.
- Telemetry and update notices off (`DO_NOT_TRACK`, npm and pip notifiers).

## Isolation (profile `agent`)

- 4 GiB RAM, 6 CPUs, 8192 processes per sandbox; raise memory for browser or heavy-build
  sandboxes (`--memory 6GiB`).
- Unprivileged, with an isolated uid range per container (`security.idmap.isolated`).
- Nesting plus `mknod`/`setxattr` interception for Docker inside.
- `security.port_isolation`: sandboxes can't talk to each other.
- ACL `agent-egress`: no traffic to private ranges (LAN, VPN, `100.64.0.0/10`, link-local)
  and none to the host except DNS and DHCP on the bridge gateway. Internet is open.
- No credentials in the template. Log in to Claude, Codex and gh inside each sandbox, or push
  credential files with `incus file push` after creating it. Prefer a fine-grained,
  repo-scoped GitHub token, and don't forward your SSH agent.

## Measured (2026-11-25, Ryzen 7 5700U host)

- Template build: about 12 minutes. Verification: 51 of 51 checks pass in a fresh copy on its first boot.
- Idle memory of a fresh sandbox: about 90–100 MB.
- `new-sandbox.sh` (copy, start, key and git identity): about 4.3 s; SSH login works right after. The first `docker run` starts dockerd on demand.

## Things that went wrong while building it

- **Incus ACLs put reject before allow.** An "allow DNS to the gateway" exception next to a
  "reject 10.0.0.0/8" rule never matches. The ACL leaves the gateway out of the private ranges
  (as IP ranges around it) and rejects only its non-DNS/DHCP ports.
- **Editing an ACL that is in use fails** on Incus 6.0.4 (`nft ... flush chain ... acl.incusbr0`).
  `agent-profile.sh` detaches, recreates and reattaches it.
- **Ordering the host-key unit before `ssh.socket` delays SSH on the first boot.** Sockets start
  before `basic.target`, a default service starts after it, so the socket waits in a loop that
  systemd resolves late. The unit is ordered before `ssh.service` only; the socket listens
  immediately and sshd starts on the first connection, after the keys exist.
- Docker in an unprivileged container worked out of the box on this stack (Docker 29.10,
  runc 1.5.3, kernel 6.12, Incus 6.0.4): overlayfs via the containerd snapshotter, cgroup v2.
  The Fable review warned about a runc/AppArmor regression in nested LXC; it did not show up
  here, but test `docker run hello-world` first on other hosts.
- Version probes need per-tool flags (`tmux -V`, `go version`), and `pi --version` prints
  to stderr.

## Deliberately left out

Java, Ruby, PHP, .NET (install on demand with mise or apt), a desktop or VNC, MySQL,
a shared package cache across sandboxes (hardlinks and reflinks don't cross mounts, plus uid
and lock trouble), a domain-allowlist proxy, and preinstalled credentials.
