# Claude Code on the web (Anthropic)

Checked: 2026-11-25. Sources:
[cloud environments](https://code.claude.com/docs/en/cloud-environments),
[Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web),
[GitHub Actions](https://code.claude.com/docs/en/github-actions).

## Machine

| | |
| --- | --- |
| Base | Ubuntu 24.04, x86_64 |
| Isolation | A fresh VM per session (the docs also call it "the container") |
| Resources | about 4 vCPU, 16 GB RAM, 30 GB disk ("approximate ceilings that may change") |
| User | Setup scripts run as root, so `apt install` works |

## Preinstalled (documented table)

| Area | Contents |
| --- | --- |
| Python | Python 3.x with pip, poetry, uv, black, mypy, pytest, ruff |
| Node.js | 20, 21 and 22 (`/opt/node20` to `/opt/node22`, 22 on `PATH`), npm, yarn, pnpm, bun, eslint, prettier, chromedriver |
| Ruby | 3.1, 3.2, 3.3 with gem, bundler, rbenv |
| PHP | 8.3 with Composer |
| Java | OpenJDK 21 with Maven and Gradle |
| Go, Rust | Go with modules; rustc and cargo (no versions given) |
| C/C++ | GCC, Clang, cmake, ninja, conan |
| Containers | docker, dockerd, docker compose |
| Databases | PostgreSQL 16, Redis 7.0, installed but not running (`service postgresql start`) |
| Browser | Chrome for Testing at `/usr/bin/google-chrome`, `CHROME_PATH` set |
| Tools | git, gh, jq, yq, ripgrep, tmux, vim, nano |

`check-tools` inside a session prints the exact versions. The .NET SDK is
named as not installed. Deno and Playwright are not listed.

## Network

- Three levels: None, Limited, Full. The default is **Limited** with "Allow
  package managers": an allowlist of about 200 domains in 17 categories
  (package and container registries, cloud platforms, distro mirrors, MCP
  hosts), extendable with `*.` wildcards.
- All traffic goes through Anthropic's security proxy.
- GitHub goes through a dedicated proxy that keeps the credentials out of the
  VM. It rejects GraphQL, so `gh pr` and `gh issue` fail; `gh api` against
  REST works.

## Customization and lifetime

- Per environment: variables (`.env` format), network secrets, allowed
  domains, and a setup script (Bash, up to 64 KB).
- A setup script that finishes in about 5 minutes is snapshotted and cached
  for about 7 days (files and pulled Docker images, no processes).
- `SessionStart` hooks in `.claude/settings.json` run on every start
  (`CLAUDE_CODE_REMOTE=true` marks the cloud).
- The base image cannot be replaced yet. Organizations can route sessions to
  self-hosted runners with their own image.
- The VM pauses after a few minutes without activity and can be reclaimed
  later; a reclaimed session gets a fresh VM with the conversation restored.
- Command timeout 2 minutes by default, up to 10.

Claude Code GitHub Actions is a different environment: it runs on
GitHub-hosted runners (see [github-copilot.md](github-copilot.md) for that
image).

## Ground truth

Docs describe the image; the probe shows it. Run [`scripts/probe.sh`](../../scripts/probe.sh) inside a session as described in [`METHOD.md`](../METHOD.md) and commit the result to `research/probes/claude-code-web/`.
