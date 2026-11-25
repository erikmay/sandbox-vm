# GitHub Copilot coding agent ("cloud agent")

Checked: 2026-11-25. Sources:
[customize the agent environment](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-environment),
[agent firewall](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-firewall),
[cloud sandboxes](https://docs.github.com/en/copilot/concepts/security-governance-and-network-settings/about-cloud-sandboxes),
[GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[actions/runner-images](https://github.com/actions/runner-images).

Copilot uses two different backends:

1. **GitHub Actions runners** (the original backend), usually `ubuntu-latest` (Ubuntu x64 and Windows x64 only).
2. **Cloud sandboxes**, the newer default for sessions kicked off from github.com, mobile, Slack, Teams, or VS Code. Docs only call it "an isolated Linux environment" without listing OS version, resources, or installed tools. `copilot-setup-steps.yml` doesn't apply there; dotfiles get copied in instead.

## Runner image (`ubuntu-latest`)

| | |
| --- | --- |
| Base | Ubuntu 26.04.1 LTS, image version `20261116.202.1` |
| Isolation | Fresh VM per job, passwordless sudo |
| Resources | Public repos: 4 CPU / 16 GB / 14 GB SSD; private repos: 2 CPU / 8 GB / 14 GB |

| Area | Contents |
| --- | --- |
| Languages | Node 24.22.3 (22 cached), Python 3.14.4 (3.11–3.15 cached), Java 25 (11, 17, 21), Go 1.25–1.27, Rust 1.100.0, Ruby 3.3.8, PHP 8.5.4, .NET, Kotlin, Swift |
| Containers | Docker 29.4.2, Compose 5.1.3 |
| Browsers | Chrome and Chromium 157, Edge 157, Selenium |
| Databases | PostgreSQL 18.7, MySQL 8.4 |

This is by far the heaviest image of the bunch because it's a general-purpose CI runner image, not something built specifically for coding agents.

## Network and customization

A firewall is enabled by default with a recommended allowlist (OS repos, container/language registries, CAs, Playwright hosts). It restricts processes started by the agent, not the setup steps.

Customization for Actions runners lives in `.github/workflows/copilot-setup-steps.yml` with a single `copilot-setup-steps` job (`steps`, `permissions`, `runs-on`, `services`, `snapshot`, `timeout-minutes` up to 59). Runner VMs are ephemeral per job; stopped cloud-sandbox sessions keep a snapshot.
