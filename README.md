# sandbox-vm

Notes on what hosted coding agents run inside (Claude Code on the web, Codex, Amp, Devin, Cursor, GitHub Copilot, Jules, exe.dev), a small probe script to inspect those sandboxes from the inside, and my own setup for running agent sandboxes on an old laptop with [Incus](https://linuxcontainers.org/incus/) (Debian 13 host, Ubuntu 24.04 sandboxes).

Most hosted agent providers give each session a fresh Linux machine with a bunch of preinstalled runtimes, but only a few publish what's actually in the image. I wanted to see what they ship and compare it to just running containers on hardware I already own.

## What's in here

- [`research/`](research/): comparison across providers (OS, CPU/RAM, installed runtimes, Docker, browsers, databases, network rules, setup scripts) with a separate page per provider.
- [`research/METHOD.md`](research/METHOD.md): how to inspect a provider's actual image by having the agent run the probe script and commit the output.
- [`research/probes/`](research/probes/): raw probe outputs, grouped by provider and date.
- [`approach/`](approach/): the self-hosted Incus setup on a spare laptop, capacity notes, and things that went wrong during setup.
- [`approach/remote-reinstall.md`](approach/remote-reinstall.md): reinstalling a headless Linux box to encrypted Debian 13 over SSH via preseed, tested in QEMU first.
- [`benchmarks/`](benchmarks/): startup, teardown, parallel launch, and snapshot restore timings for Incus containers.
- [`scripts/`](scripts/): `probe.sh`, Debian preseed templates, and the Incus setup/benchmark scripts.

## Rough comparison

Hosted agent VMs typically give you Ubuntu 24.04 (Amp uses Debian 13), 2–4 vCPU, 8–16 GB RAM, and a big polyglot image with Python, Node, Go, Rust, Java, Docker, and sometimes a browser. Spinning up a fresh session usually takes tens of seconds.

On my laptop with Incus, I start from a plain Ubuntu 24.04 container image (same base as most providers) with nothing extra installed and layer tools on top as needed. A sandbox gets up to 6 CPUs and 6 GiB RAM by default, boots with networking in ~4 seconds (8 in parallel in ~6 seconds), and resets via snapshot restore in ~4.5 seconds.

## Running the probe

```sh
bash scripts/probe.sh > research/probes/<provider>/$(date +%F).md
```

The script is read-only and only prints environment variable names, never their values. Still worth skimming the output for internal hostnames or IPs before committing.

## License

[MIT](LICENSE)
