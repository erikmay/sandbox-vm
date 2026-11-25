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

Devin does not publish a full list of its base image. Most of the software
below comes from notes in the setup templates.

## Machine

| | |
| --- | --- |
| Base | "A Linux-based virtual machine". Older versions of the docs said Ubuntu 22.04, x86_64; the current pages no longer state a version |
| Other OS | Windows and macOS VMs, opt-in with `runs-on` |
| Isolation | VM |
| Resources | Not documented |
| User | `ubuntu` (inferred from paths like `/home/ubuntu/...`), repos in `~/repos/` |

## Preinstalled

| Area | Contents |
| --- | --- |
| Languages | OpenJDK 17, Rust (rustup, stable), nvm. Python and Node versions not listed |
| Tools | awscli, direnv (hooked into the shell), bash |
| Docker | Supported (templates configure `/etc/docker/daemon.json`) |
| Browser | Chrome with remote debugging (CDP) on port 29229 |
| Desktop | A full Linux desktop at 1024×768 for computer use |
| Access | SSH into a running session's VM |
| Databases | None documented |

## Customization and lifetime

- **Blueprints** (YAML, organization, repo and workspace level):
  `initialize` (system tools, runtimes), `maintenance` (dependencies, run
  during builds), `knowledge` (lint, test, build commands given to Devin).
- Setup is done by asking Devin to set up the repo; it proposes changes and
  builds the image.
- Secrets are encrypted, passed as environment variables, and removed from
  the saved image.
- One active snapshot per organization and platform; every session boots a
  fresh copy. Builds run on blueprint changes and about every 24 hours.
- The machine sleeps when idle and wakes for browser previews.
- Self-hosted machines are possible ("Outposts").

## Ground truth

Docs describe the image; the probe shows it. Run [`scripts/probe.sh`](../../scripts/probe.sh) inside a session as described in [`METHOD.md`](../METHOD.md) and commit the result to `research/probes/devin/`.
