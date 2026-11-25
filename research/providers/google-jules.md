# Google Jules

Checked: 2026-11-25. Source: [environment](https://jules.google/docs/environment/).

## Machine

| | |
| --- | --- |
| Base | Ubuntu Linux (version not specified) |
| Isolation | "A secure, short-lived virtual machine" |
| Resources | Not documented |

## Preinstalled (per docs)

| Area | Contents |
| --- | --- |
| Python | 3.12.11 (3.10.18 via pyenv), pip, Poetry 2.1.3, uv 0.7.13, pytest, ruff, black, mypy |
| Node.js | 22.16.0 (18 and 20 via nvm), npm, yarn, pnpm, Bun |
| Java | OpenJDK 21.0.7, Maven 3.9.10, Gradle 8.8 |
| Go, Rust | Go 1.24.3, Rust 1.87.0 |
| C/C++ | clang 18.1.3, gcc 13.3.0, cmake 3.28.3 |
| Containers | Docker 28.2.2, Compose 2.36.2 |
| Browser | ChromeDriver 137 listed; no browser binary mentioned |
| Tools | git, jq, ripgrep, tmux, etc. |
| Databases | None listed |

## Customization and lifetime

Each repo can have an "Initial Setup" script. "Run and Snapshot" saves a snapshot reused for later tasks on that repo, while "Run to Validate" just tests the script without saving. VMs are short-lived and only the snapshot persists. Network rules and snapshot retention aren't documented.
