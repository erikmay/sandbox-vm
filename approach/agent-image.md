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
[`verify.sh`](../scripts/images/ubuntu-agent/verify.sh) (53 checks) in a fresh copy. The
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
| Agents | Claude Code (native installer), Codex (full release package in `/opt/codex`), OpenCode, pi | Latest at build time, self-update off |
| Logins | None in the image. `/etc/agent-secrets.env` is loaded into every session if it exists | Written per sandbox by `sync-logins.sh`, see [`logins.md`](logins.md) |
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
  and none to the host except DNS, DHCP and the login proxy on the bridge gateway. Internet
  is open.
- No credentials in the template. `new-sandbox.sh` signs each sandbox in to Codex and Claude
  Code ([`logins.md`](logins.md)): Codex through a proxy on the host, so no OpenAI credential
  ever enters a sandbox, and Claude Code with a token from the secret store. The proxy port is
  the one host service the ACL lets sandboxes reach. For GitHub, prefer a fine-grained,
  repo-scoped token or a per-sandbox SSH key, and don't forward your SSH agent.

## Measured (2026-11-25, Ryzen 7 5700U host)

- Template build: about 12 minutes. Verification: 53 of 53 checks pass in a fresh copy on its first boot.
- Idle memory of a fresh sandbox: about 90–100 MB.
- `new-sandbox.sh` (copy, start, key, git identity, logins): about 5 s; SSH login works right after, and Codex and Claude Code answer without any setup in the sandbox. The first `docker run` starts dockerd on demand.

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
- **Codex needs its whole release package.** The single `codex` binary starts fine, but current
  models run in "code mode" and fail every tool call without `codex-code-mode-host` next to it
  ("failed to spawn code-mode host"). The image installs `codex-package-*.tar.gz` and
  `bubblewrap`, which Codex uses for its own sandbox; that works inside the unprivileged
  container.

## Deliberately left out

Java, Ruby, PHP, .NET (install on demand with mise or apt), a desktop or VNC, MySQL,
a shared package cache across sandboxes (hardlinks and reflinks don't cross mounts, plus uid
and lock trouble), a domain-allowlist proxy, and preinstalled credentials.
