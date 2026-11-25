# How to analyze a provider's sandbox

Most providers do not publish their images:

| Provider | Image public? |
| --- | --- |
| Codex cloud | Yes, [`openai/codex-universal`](https://github.com/openai/codex-universal), but OpenAI says it is "not an identical environment" to production |
| GitHub Copilot (runner) | Yes, [`actions/runner-images`](https://github.com/actions/runner-images); the newer cloud sandbox is not |
| exe.dev | Yes, [`boldsoftware/exeuntu`](https://github.com/boldsoftware/exeuntu) |
| Claude Code on the web | No, only a documented table |
| Devin, Cursor, Jules | No (Jules documents versions, Devin and Cursor barely) |
| Amp orbs | No Dockerfile; the image config is readable from the registry |

So docs are a starting point, and the ground truth comes from **inside** the
sandbox: we let the provider's own agent run
[`../scripts/probe.sh`](../scripts/probe.sh) and commit the output.

## Why a file in the repo, not the chat

- The output is long (hundreds of lines); chat UIs truncate or summarize it.
- A committed file can be diffed against the next probe, so changes in the
  provider's image show up as a diff.
- Some providers redact or reformat tool output in chat.

Asking in chat still works as a fallback (see the prompt below); paste the
answer into the probe file by hand.

## Standard prompt

Give every agent the same prompt, on a branch of this repository:

> Run `bash scripts/probe.sh > research/probes/<provider>/<YYYY-MM-DD>.md`
> without changing the script. Do not install anything before you run it.
> Commit only that file and open a pull request (or push the branch). Then
> reply with the first 40 lines of the file.

"Do not install anything" matters: we want the image as the provider ships
it, before the agent's own setup. Run it once without a setup script, and
optionally a second time after your usual setup script (`<date>-setup.md`).

## Per provider

| Provider | Where to run it | How the result comes back |
| --- | --- | --- |
| Claude Code on the web | New session on this repo at claude.ai/code, environment without a setup script, network "Full" for the network section | Session pushes a branch (`claude/...`), open a PR |
| Codex cloud | Task on this repo in chatgpt.com/codex, environment without setup script; run once with internet off and once on | Codex creates a PR |
| GitHub Copilot | Assign an issue with the prompt to Copilot. Without `copilot-setup-steps.yml` it runs on the default runner or cloud sandbox | Copilot opens a PR |
| Google Jules | Task on this repo, no setup script configured | Jules publishes a branch / PR |
| Cursor Cloud Agents | Cloud agent on this repo with the default image (no `environment.json`) | Agent pushes a branch |
| Devin | Session on this repo with an empty blueprint | Devin opens a PR |
| Amp orbs | Orb on this repo; or `docker run --rm` the published image with the script mounted | Amp pushes a branch |
| exe.dev | `ssh <vm>.exe.xyz 'bash -s' < scripts/probe.sh` on a fresh VM | Redirect to the file locally |
| Own Incus sandboxes | `incus exec <sandbox> -- bash -s < scripts/probe.sh` | Redirect to the file locally |

## Rules

- The probe is read-only and prints environment variable **names** only.
  Still read the output before you commit it: hostnames, internal IPs or
  account names can appear in paths or the network section. Redact them.
- Record the date, the plan tier (resources differ by plan) and whether
  internet was on.
- Update the provider page in [`providers/`](providers/) from the probe and
  set its "Checked" date.
