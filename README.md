# sandbox-vm

What the big remote coding agents run in, and how to run the same kind of
sandbox on your own hardware.

Claude Code, Codex, Amp, Devin, Cursor, Copilot and Jules all give their
agent a fresh Linux machine with a preinstalled toolchain. Most of them do not
publish what is in it. This repository collects it, gives you a probe to read
it from inside any sandbox, and documents a self-hosted alternative: an old
laptop with Debian 13 and [Incus](https://linuxcontainers.org/incus/), where a
new sandbox is ready in about 4 seconds.

## Contents

| Folder | What |
| --- | --- |
| [`research/`](research/) | Comparison of the providers' sandboxes (OS, resources, runtimes, Docker, browsers, network, customization), one page per provider |
| [`research/METHOD.md`](research/METHOD.md) | How to read a provider's real image: let its own agent run the probe and commit the result |
| [`research/probes/`](research/probes/) | Probe results, one folder per provider and date |
| [`approach/`](approach/) | Our self-hosted setup: architecture, layers, capacity, lessons |
| [`approach/remote-reinstall.md`](approach/remote-reinstall.md) | Reinstall a headless machine to encrypted Debian 13 over SSH, with a QEMU dry run first |
| [`benchmarks/`](benchmarks/) | Measured create, delete, parallel and reset times for Incus sandboxes |
| [`scripts/`](scripts/) | `probe.sh`, the Debian preseed templates, Incus setup and benchmark |

## The short version

| | Hosted agents (typical) | Own laptop with Incus |
| --- | --- | --- |
| Base | Ubuntu 24.04 (Amp: Debian 13) | Debian 13, clean |
| Per sandbox | 2–4 vCPU, 8–16 GB | up to 6 CPU, 6 GiB (configurable) |
| Preinstalled | polyglot: Python, Node, Go, Rust, Java, Docker, often a browser | nothing; add layers you need |
| New sandbox | tens of seconds | ~4 s, 8 in parallel in ~6 s |
| Reset | new session | snapshot restore in ~4.5 s |

## Probe a sandbox

```sh
bash scripts/probe.sh > research/probes/<provider>/$(date +%F).md
```

Read-only; prints environment variable names, never values. Check the output
for internal hostnames or IPs before you commit it.

## License

[MIT](LICENSE)
