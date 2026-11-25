# Codex cloud (OpenAI)

Checked: 2026-11-25. Sources:
[openai/codex-universal](https://github.com/openai/codex-universal) at commit
`47f4f0eb` (2026-05-02, Dockerfile, README, `setup_universal.sh`),
[legacy cloud environments](https://developers.openai.com/codex/cloud/environments),
[legacy internet access](https://developers.openai.com/codex/cloud/internet-access),
[current cloud environments](https://learn.chatgpt.com/docs/environments/cloud-environments).

OpenAI's docs currently cover two setups. The older docs describe containers based on the public `universal` image, while the newer docs say each task gets a VM and don't mention a specific image. The `codex-universal` README also warns it's "not an identical environment" to production.

## Machine

| | |
| --- | --- |
| Base | `ubuntu:24.04` (amd64 and arm64 built; production runs amd64) |
| Isolation | Container (legacy), VM per task (current) |
| Resources | Plus: 2 vCPU, 8 GiB RAM, 8 GiB disk. Pro / Business / Enterprise: 4 vCPU, 16 GiB, 32 GiB |
| State | Saved VM state kept up to 7 days (current); cached containers up to 12 hours (legacy) |

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

Runtime versions are switched via `CODEX_ENV_{PYTHON,NODE,RUBY,RUST,GO,SWIFT,PHP,JAVA}_VERSION`.

Not included: Docker, browsers/Playwright, database servers (just the `sqlite3` CLI and client headers), and `gh`. The current docs note Playwright has to be installed by the environment setup, and Browser Use / Computer Use aren't available in every cloud task.

## Network

In the legacy setup, setup scripts have internet access while the agent phase is offline by default, with allowlist presets (None, "Common dependencies" at ~70 domains, All), optional HTTP method restrictions (GET, HEAD, OPTIONS), and an HTTP proxy.

In the current setup, you get either full internet or a "Package managers" preset plus custom domains, Tailscale (TCP over proxy), OIDC for AWS/GCP/Azure, and published egress IPs.

## Customization

Legacy environments use a setup script plus a maintenance script that runs when a cached container resumes; secrets are only available during setup and stripped before the agent starts.

Current environments let Codex generate an install script and a "start skill", publishing a prepared filesystem for new tasks. "Network secrets" work as placeholders that the proxy swaps for real values on allowed HTTPS hosts.
