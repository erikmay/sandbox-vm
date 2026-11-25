# Codex cloud (OpenAI)

Checked: 2026-11-25. Sources:
[openai/codex-universal](https://github.com/openai/codex-universal) at commit
`47f4f0eb` (2026-05-02, Dockerfile, README, `setup_universal.sh`),
[legacy cloud environments](https://developers.openai.com/codex/cloud/environments),
[legacy internet access](https://developers.openai.com/codex/cloud/internet-access),
[current cloud environments](https://learn.chatgpt.com/docs/environments/cloud-environments).

The docs now describe two generations. The legacy docs say tasks run in a
container from the public `universal` image. The current docs say each task
runs in a VM and do not name an image. The README of `codex-universal` says
it is "not an identical environment" to production.

## Machine

| | |
| --- | --- |
| Base | `ubuntu:24.04` (images for amd64 and arm64; only amd64 runs in production) |
| Isolation | Container (legacy), VM per task (current) |
| Resources | Plus: 2 vCPU, 8 GiB RAM, 8 GiB disk. Pro, Business, Enterprise: 4 vCPU, 16 GiB, 32 GiB |
| State | Saved VM state recoverable for up to 7 days (current); containers cached up to 12 hours (legacy) |

## Preinstalled (from the Dockerfile)

| Area | Versions (default first) | Manager |
| --- | --- | --- |
| Python | 3.14, 3.13, 3.12, 3.11, 3.10; ruff, black, mypy, pyright, isort, pytest per version; Poetry 2.1, uv 0.7 | pyenv, pipx |
| Node.js | 22 (default), 18, 20, 24; npm, pnpm 10.12, corepack, yarn, prettier, eslint, typescript | nvm 0.40.2 |
| Rust | 1.95.0 down to 1.83.0, rustfmt, clippy | rustup |
| Go | 1.25.1, 1.24.3, 1.23.8, 1.22.12; golangci-lint 2.1.6 | mise |
| Java | 25 (default), 24, 23, 22, 21, 17, 11; Gradle 8.14, Maven 3.9.10 | mise |
| Swift | 6.2, 6.1, 5.10 | swiftly |
| Ruby | 3.4.4, 3.3.8, 3.2.3 | mise |
| PHP | 8.5, 8.4, 8.3, 8.2; Composer | phpenv |
| Others | Bun 1.2.14, Erlang 27.1.2, Elixir 1.18.3 | |
| C/C++ | build-essential, LLVM/clang, cmake, ninja, ccache, clang-tidy and clang-format 20.1, Bazel via bazelisk 1.26 | |
| Tools | git, git-lfs, curl, wget, jq 1.7, ripgrep 14.1, fd, rsync, sqlite3, protobuf-compiler, universal-ctags, openssh-client, netcat, dnsutils | apt |

Versions are selected with `CODEX_ENV_{PYTHON,NODE,RUBY,RUST,GO,SWIFT,PHP,JAVA}_VERSION`.

**Not in the image:** Docker, browsers and Playwright, database servers (only
the sqlite3 CLI and client headers), `gh`. The current docs say Playwright
must be installed by the environment; Browser Use and Computer Use "aren't
available in every cloud task".

## Network

- Legacy: setup scripts have internet; the agent phase is offline by
  default. Allowlist presets: None, "Common dependencies" (about 70 domains),
  All. HTTP methods can be limited to GET, HEAD, OPTIONS. Everything goes
  through an HTTP proxy.
- Current: full internet, or a "Package managers" preset plus extra domains.
  Tailscale (TCP through a proxy) and OIDC for AWS, GCP, Azure. Egress IPs
  are published.

## Customization

- Legacy: setup script plus maintenance script (runs when a cached container
  resumes). Secrets exist only in the setup phase and are removed before the
  agent starts.
- Current: Codex writes an install script and a "start skill"; a prepared
  filesystem is published for new tasks. "Network secrets" are placeholders
  that the proxy replaces with the real value for allowed HTTPS hosts.

## Ground truth

Docs describe the image; the probe shows it. Run [`scripts/probe.sh`](../../scripts/probe.sh) inside a session as described in [`METHOD.md`](../METHOD.md) and commit the result to `research/probes/codex-cloud/`.
