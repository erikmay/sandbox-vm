# Devin (Cognition)

Checked: 2026-11-25. Sources:
[environment](https://docs.devin.ai/onboard-devin/environment),
[blueprint reference](https://docs.devin.ai/onboard-devin/environment/blueprint-reference),
[blueprints](https://docs.devin.ai/onboard-devin/environment/blueprints),
[templates](https://docs.devin.ai/onboard-devin/environment/templates),
[computer use](https://docs.devin.ai/work-with-devin/computer-use),
[SSH](https://docs.devin.ai/cli/ssh),
[secrets](https://docs.devin.ai/product-guides/secrets),
[browser previews](https://docs.devin.ai/work-with-devin/browser-previews).

Devin doesn't publish a base image manifest; most of the details below are pieced together from their setup templates.

## Machine

| | |
| --- | --- |
| Base | "A Linux-based virtual machine" (older docs said Ubuntu 22.04 x86_64; current docs drop the version) |
| Other OS | Windows and macOS VMs, opt-in via `runs-on` |
| Isolation | VM |
| Resources | Not documented |
| User | `ubuntu` (based on `/home/ubuntu/...` paths), repos cloned under `~/repos/` |

## Preinstalled

| Area | Contents |
| --- | --- |
| Languages | OpenJDK 17, Rust (rustup, stable), nvm. Python and Node versions aren't listed |
| Tools | awscli, direnv (hooked into the shell), bash |
| Docker | Supported (templates edit `/etc/docker/daemon.json`) |
| Browser | Chrome with remote debugging (CDP) on port 29229 |
| Desktop | Full Linux desktop at 1024×768 for computer use |
| Access | Direct SSH into a running session's VM |
| Databases | None documented |

## Customization and lifetime

Configured through YAML **Blueprints** (org, repo, or workspace level) split into `initialize` (system packages/runtimes), `maintenance` (dependencies run during builds), and `knowledge` (lint/test/build commands). Usually you just ask Devin to set up the repo and it proposes the blueprint and builds the image.

Secrets are encrypted, injected as env vars, and stripped from the saved snapshot. Each org and platform keeps one active snapshot, rebuilt on blueprint changes and roughly every 24 hours; sessions boot a fresh copy. Idle VMs sleep and wake back up for browser previews. Self-hosted runners ("Outposts") are also available.
