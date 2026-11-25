# GitHub Copilot coding agent ("cloud agent")

Checked: 2026-11-25. Sources:
[customize the agent environment](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-environment),
[agent firewall](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-firewall),
[cloud sandboxes](https://docs.github.com/en/copilot/concepts/security-governance-and-network-settings/about-cloud-sandboxes),
[GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[actions/runner-images](https://github.com/actions/runner-images).

Copilot has two environments:

1. **A GitHub Actions runner** (the original model), usually `ubuntu-latest`;
   Ubuntu x64 and Windows x64 only.
2. **A cloud sandbox**, the newer default for sessions started from
   github.com, mobile, Slack, Teams and VS Code: "an isolated Linux
   environment" with no documented OS version, resources or tools.
   `copilot-setup-steps.yml` does not apply there; dotfiles are copied in.

## Runner image `ubuntu-latest`

| | |
| --- | --- |
| Base | Ubuntu 26.04.1 LTS, image version 20261116.202.1 |
| Isolation | Fresh VM per job, passwordless sudo |
| Resources | Public repos 4 CPU / 16 GB / 14 GB SSD; private repos 2 CPU / 8 GB / 14 GB |

| Area | Contents |
| --- | --- |
| Languages | Node 24.22.3 (22 cached), Python 3.14.4 (3.11–3.15 cached), Java 25 (11, 17, 21), Go 1.25–1.27, Rust 1.100.0, Ruby 3.3.8, PHP 8.5.4, .NET, Kotlin, Swift |
| Containers | Docker 29.4.2, Compose 5.1.3 |
| Browsers | Chrome and Chromium 157, Edge 157, Selenium |
| Databases | PostgreSQL 18.7, MySQL 8.4 |

The runner image is the largest of all providers here: it is built for CI of
any project, not for agents.

## Network and customization

- Firewall on by default with a recommended allowlist (OS repos, container
  and language registries, certificate authorities, Playwright hosts). It
  covers processes the agent starts, not the setup steps.
- `.github/workflows/copilot-setup-steps.yml` with one job
  `copilot-setup-steps`: `steps`, `permissions`, `runs-on`, `services`,
  `snapshot`, `timeout-minutes` (max 59).
- Runners are one job each; stopped cloud-sandbox sessions keep a snapshot.

## Ground truth

Docs describe the image; the probe shows it. Run [`scripts/probe.sh`](../../scripts/probe.sh) inside a session as described in [`METHOD.md`](../METHOD.md) and commit the result to `research/probes/github-copilot/`.
