# Claude Code on the web (Anthropic)

Checked: 2026-11-25. Sources:
[cloud environments](https://code.claude.com/docs/en/cloud-environments),
[Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web),
[GitHub Actions](https://code.claude.com/docs/en/github-actions).

## Machine

| | |
| --- | --- |
| Base | Ubuntu 24.04, x86_64 |
| Isolation | Fresh VM per session (the docs also refer to it as "the container") |
| Resources | ~4 vCPU, 16 GB RAM, 30 GB disk ("approximate ceilings that may change") |
| User | Setup scripts run as root, so `apt install` works |

## Preinstalled (per docs)

| Area | Contents |
| --- | --- |
| Python | Python 3.x with pip, poetry, uv, black, mypy, pytest, ruff |
| Node.js | 20, 21, 22 (`/opt/node20` to `/opt/node22`, 22 on `PATH`), npm, yarn, pnpm, bun, eslint, prettier, chromedriver |
| Ruby | 3.1, 3.2, 3.3 with gem, bundler, rbenv |
| PHP | 8.3 with Composer |
| Java | OpenJDK 21 with Maven and Gradle |
| Go, Rust | Go with modules; rustc and cargo (versions not specified) |
| C/C++ | GCC, Clang, cmake, ninja, conan |
| Containers | docker, dockerd, docker compose |
| Databases | PostgreSQL 16, Redis 7.0, installed but stopped by default (`service postgresql start`) |
| Browser | Chrome for Testing at `/usr/bin/google-chrome` (`CHROME_PATH` set) |
| Tools | git, gh, jq, yq, ripgrep, tmux, vim, nano |

Running `check-tools` inside a session prints exact versions. The docs note that .NET SDK is not installed; Deno and Playwright aren't listed either.

## Network

Three modes: None, Limited, and Full. Default is **Limited** with "Allow package managers", which allows ~200 domains across 17 categories (package/container registries, cloud platforms, distro mirrors, MCP hosts) and supports custom `*.` wildcards.

All outbound traffic goes through Anthropic's proxy. GitHub traffic goes through a separate proxy so credentials stay outside the VM. It blocks GraphQL, meaning `gh pr` and `gh issue` fail while `gh api` against REST endpoints works.

## Customization and lifetime

Each environment can define `.env` variables, network secrets, allowed domains, and a Bash setup script (up to 64 KB). If the setup script finishes within ~5 minutes, the filesystem (including pulled Docker images, excluding running processes) is snapshotted and cached for about 7 days.

`SessionStart` hooks in `.claude/settings.json` run on every start (`CLAUDE_CODE_REMOTE=true` is set in cloud sessions). You can't swap the base image directly, though orgs can route sessions to self-hosted runners with custom images.

VMs pause after a few minutes of inactivity and may be reclaimed later; resuming a reclaimed session boots a fresh VM and restores the conversation. Default command timeout is 2 minutes (max 10).

Note that Claude Code GitHub Actions is separate and runs on standard GitHub-hosted runners (see [github-copilot.md](github-copilot.md)).
