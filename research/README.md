# Provider research

Collected on 2026-11-25. Each provider has its own page in [`providers/`](providers/) with links to the docs, installed tools, network restrictions, and how customization works. Images change without much notice, so check the date on each page and treat the live docs (or a fresh probe) as authoritative.

## Machines

| Provider | Base | Isolation | vCPU / RAM / disk |
| --- | --- | --- | --- |
| [Claude Code on the web](providers/claude-code-web.md) | Ubuntu 24.04 | VM per session | 4 / 16 GB / 30 GB |
| [Codex cloud](providers/codex-cloud.md) | Ubuntu 24.04 (`codex-universal`) | VM per task (container in legacy docs) | 2–4 / 8–16 GiB / 8–32 GiB by plan |
| [Amp orbs](providers/amp-orbs.md) | Debian 13 | container with systemd | not documented |
| [Devin](providers/devin.md) | Linux (formerly Ubuntu 22.04); Windows/macOS opt-in | VM | not documented |
| [Cursor Cloud Agents](providers/cursor-cloud-agents.md) | Ubuntu (likely 24.04) | VM, container inside | not documented |
| [GitHub Copilot](providers/github-copilot.md) | Ubuntu 26.04 runner, or cloud sandbox | VM per job | 2–4 / 8–16 GB / 14 GB |
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

Cursor doesn't document what's in its default image.

## Network and customization

| | Default network | Setup mechanism | Saved state |
| --- | --- | --- | --- |
| Claude Code | allowlist (~200 domains) via proxy; GitHub credentials stay outside the VM | setup script, `SessionStart` hooks | filesystem snapshot, ~7 days |
| Codex | package-manager preset or full; proxy substitutes secrets | install script, start skill, `CODEX_ENV_*` versions | up to 7 days |
| Amp | open | per-repo orb kit | – |
| Devin | open | blueprints (`initialize`, `maintenance`, `knowledge`) | one snapshot per org, rebuilt daily |
| Cursor | open, allowlist optional | Dockerfile or `environment.json` | snapshot, deleted after 30 days unused |
| Copilot | firewall with allowlist | `copilot-setup-steps.yml` | none (runner) / snapshot (sandbox) |
| Jules | not documented | setup script, "Run and Snapshot" | snapshot per repo |
| exe.dev | open (egress policy optional) | image + setup script, `cp` to clone | persistent disk, `pause` keeps RAM |

## Common threads

Most providers ship a heavy polyglot image with version managers (pyenv, nvm, mise, rustup) preloaded. Amp and Devin keep theirs much smaller, while Copilot just reuses a GitHub Actions CI runner image that has way more stuff than a coding agent needs.

Customization looks almost the same everywhere: run a setup script, take a filesystem snapshot, and boot new sessions from a copy of that snapshot. The main difference is when snapshots get rebuilt (on config change, daily, or manually).

Claude Code, Codex, and Copilot all push outbound traffic through a proxy with domain allowlists, and inject credentials at the proxy layer so secrets never sit inside the VM.

Docker is available almost everywhere except Codex. Browsers (often paired with a full Linux desktop for computer use) are showing up in more of them now: Amp, Devin, and Cursor all include one.

Compute is modest across the board: 2–4 vCPU and 8–16 GB RAM. Most of the time the sandbox sits idle waiting on LLM responses anyway; builds and headless browsers are what actually spike usage.
