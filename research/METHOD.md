# Probing provider sandboxes

Most providers don't publish their VM images:

| Provider | Image public? |
| --- | --- |
| Codex cloud | Yes, [`openai/codex-universal`](https://github.com/openai/codex-universal), though OpenAI notes it's "not an identical environment" to production |
| GitHub Copilot (runner) | Yes, [`actions/runner-images`](https://github.com/actions/runner-images); the newer cloud sandbox is not |
| exe.dev | Yes, [`boldsoftware/exeuntu`](https://github.com/boldsoftware/exeuntu) |
| Claude Code on the web | No, only a table in the docs |
| Devin, Cursor, Jules | No (Jules lists versions, Devin and Cursor barely mention anything) |
| Amp orbs | No Dockerfile, though the image config can be read from the registry |

Because of that, the easiest way to see what's actually installed is to run [`../scripts/probe.sh`](../scripts/probe.sh) from inside a session and have the agent commit the output.

Committing the output as a file works much better than pasting it into chat. The report is a few hundred lines long, chat UIs often truncate or reformat tool output, and having files in git makes it easy to diff when a provider updates their image later. If an agent can't push a branch, pasting from chat into the file manually still works as a fallback.

## Prompt to use

Run this on a branch of this repo:

> Run `bash scripts/probe.sh > research/probes/<provider>/<YYYY-MM-DD>.md`
> without changing the script. Do not install anything before you run it.
> Commit only that file and open a pull request (or push the branch). Then
> reply with the first 40 lines of the file.

Tell it not to install anything first so we see the stock image before any setup script touches it. If you also want to capture your customized environment, run a second probe afterward and save it as `<date>-setup.md`.

## Where to run it per provider

| Provider | Where to start | How to get the file back |
| --- | --- | --- |
| Claude Code on the web | New session on this repo at claude.ai/code, no setup script, network set to "Full" for the network checks | Pushes a `claude/...` branch, open a PR |
| Codex cloud | Task on this repo at chatgpt.com/codex, no setup script; worth running once offline and once with internet on | Opens a PR |
| GitHub Copilot | Assign an issue with the prompt to Copilot (without `copilot-setup-steps.yml` it uses the default runner or cloud sandbox) | Opens a PR |
| Google Jules | Task on this repo with no setup script | Pushes a branch / PR |
| Cursor Cloud Agents | Cloud agent on this repo with the default image (no `environment.json`) | Pushes a branch |
| Devin | Session on this repo with an empty blueprint | Opens a PR |
| Amp orbs | Orb on this repo, or `docker run --rm` the published image with the script mounted | Pushes a branch |
| exe.dev | `ssh <vm>.exe.xyz 'bash -s' < scripts/probe.sh` on a fresh VM | Redirect straight to the local file |
| Local Incus | `incus exec <sandbox> -- bash -s < scripts/probe.sh` | Redirect straight to the local file |

## Before committing

`probe.sh` doesn't modify anything and only prints environment variable names, not values. Still check the file before committing, since hostnames, internal IPs, or usernames can show up in paths or the network section.

Note the date, the plan tier (since CPU/RAM vary by plan), and whether internet access was enabled, then update the corresponding page in [`providers/`](providers/) and bump its "Checked" date.
