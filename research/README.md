# Research: what remote agent providers put in their sandboxes

Snapshot of 2026-11-25. Each provider has a page in [`providers/`](providers/)
with sources, the full tool list, network policy and customization model.
Providers change their images often: every page has a "Checked" date, and the
live docs win over this file.

## Machines

| Provider | Base | Isolation | vCPU / RAM / disk |
| --- | --- | --- | --- |
| [Claude Code on the web](providers/claude-code-web.md) | Ubuntu 24.04 | VM per session | 4 / 16 GB / 30 GB |
| [Codex cloud](providers/codex-cloud.md) | Ubuntu 24.04 (`codex-universal`) | VM per task (container in the legacy docs) | 2–4 / 8–16 GiB / 8–32 GiB by plan |
| [Amp orbs](providers/amp-orbs.md) | Debian 13 | container with systemd | not documented |
| [Devin](providers/devin.md) | Linux (formerly Ubuntu 22.04); Windows and macOS opt-in | VM | not documented |
| [Cursor Cloud Agents](providers/cursor-cloud-agents.md) | Ubuntu (24.04 likely) | VM, container inside | not documented |
| [GitHub Copilot](providers/github-copilot.md) | Ubuntu 26.04 runner, or a cloud sandbox | VM per job | 2–4 / 8–16 GB / 14 GB |
| [Google Jules](providers/google-jules.md) | Ubuntu | short-lived VM | not documented |
| [exe.dev](providers/exe-dev.md) | Ubuntu 24.04 (`exeuntu`) | persistent VM | plan capacity, shared |

## Preinstalled

| | Claude Code | Codex | Amp | Devin | Copilot runner | Jules | exe.dev |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Python | 3.x, uv, poetry, ruff, mypy | 3.10–3.14, uv, poetry, ruff, pyright | 3, uv | ? | 3.11–3.15 | 3.12, uv, poetry, ruff | 3, uv |
| Node.js | 20–22, pnpm, yarn, bun | 18–24, pnpm, yarn, bun | 26, pnpm, yarn, bun | nvm | 22, 24 | 22 (18, 20), pnpm, bun | – |
| Go | ✓ | 1.22–1.25 | – | – | 1.25–1.27 | 1.24 | ✓ |
| Rust | ✓ | 1.83–1.95 | – | ✓ | 1.100 | 1.87 | – |
| Java | 21 | 11–25 | – | 17 | 11–25 | 21 | – |
| Ruby / PHP | 3.1–3.3 / 8.3 | 3.2–3.4 / 8.2–8.5 | – | – | ✓ / ✓ | – | – |
| Docker | ✓ | – | ✓ (off) | ✓ | ✓ | ✓ | ✓ |
| Browser | Chrome for Testing | – | agent-browser + desktop | Chrome + desktop | Chrome, Chromium, Edge | ChromeDriver only | – |
| Databases | PostgreSQL 16, Redis 7 (stopped) | sqlite3 CLI | – | – | PostgreSQL 18, MySQL 8.4 | – | sqlite3, DuckDB |
| `gh` CLI | ✓ (REST only) | – | ✓ (+ glab) | – | ✓ | – | ✓ |
| Agents preinstalled | Claude Code | Codex | Amp | Devin | Copilot | Jules | Claude Code, Codex, OpenCode, pi |

Cursor does not document its default image.

## Network and customization

| | Default network | Setup mechanism | Saved state |
| --- | --- | --- | --- |
| Claude Code | allowlist (~200 domains) through a proxy; GitHub credentials stay outside the VM | setup script, `SessionStart` hooks | filesystem snapshot, ~7 days |
| Codex | package-manager preset or full; secrets substituted by the proxy | install script, start skill, `CODEX_ENV_*` versions | up to 7 days |
| Amp | open | per-repo orb kit | – |
| Devin | open | blueprints (`initialize`, `maintenance`, `knowledge`) | one snapshot per org, rebuilt daily |
| Cursor | open, allowlist optional | Dockerfile or `environment.json` | snapshot, deleted after 30 days unused |
| Copilot | firewall with allowlist | `copilot-setup-steps.yml` | none (runner) / snapshot (sandbox) |
| Jules | not documented | setup script, "Run and Snapshot" | snapshot per repo |
| exe.dev | open (egress policy optional) | image + setup script, `cp` to clone | persistent disk, `pause` keeps RAM |

## Patterns

1. **Polyglot images with version managers** (pyenv, nvm, mise, rustup) are
   the norm. Amp and Devin are leaner; Copilot reuses a CI image that is far
   larger than an agent needs.
2. **Setup script, then snapshot, then a fresh copy per session.** Every
   provider customizes this way. Only the trigger differs (on change, daily,
   on demand).
3. **Egress control through a proxy** at the security-focused providers
   (Claude Code, Codex, Copilot), with credentials injected by the proxy
   instead of stored in the sandbox.
4. **Docker** is almost always available; Codex is the exception.
5. **A browser, often with a full desktop,** is becoming standard for
   testing and computer use (Amp, Devin, Cursor).
6. **Resources are small:** 2–4 vCPU and 8–16 GB per sandbox. Agents wait
   on the model most of the time; builds and browsers set the peak.
