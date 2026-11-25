# Amp orbs (Sourcegraph Amp)

Checked: 2026-11-09 (image of Amp commit `db5a5936`). Source: the build
history (image config) of Amp's published orb image `amp-orb-debian13`
(amd64). Amp does not publish the Dockerfile or document the contents; this
list is read from the image metadata, so treat it as observed, not promised.

## Machine

| | |
| --- | --- |
| Base | Debian 13 (trixie), `buildpack-deps`-style layers (compilers, dev headers, git, mercurial, subversion) |
| Isolation | Container that expects systemd as PID 1 |
| Resources | Not documented |
| Arch | amd64 only |

## Preinstalled

| Area | Contents (version) |
| --- | --- |
| Node.js | Node 26.12.1, npm 10, pnpm 12.0.0, yarn 1.22, Bun 1.4.4 |
| Python | Debian `python3` with pip, venv, dev headers; uv 0.12.9 |
| Other languages | None (no Go, Rust, Java, Ruby, PHP toolchains) |
| Nix | Nix 2.35.3 |
| Containers | Docker CE, containerd (installed, services disabled by default) |
| Browser | agent-browser 0.38.1 |
| Desktop | A Wayland desktop for computer use: foot terminal, Xwayland, swaybg, wlr-randr, PulseAudio, fonts |
| Media | ffmpeg, ImageMagick 7.1.2 (AppImage) |
| Tools | git, gh 2.99.0, glab 1.127.0, ripgrep 14.1.0, websocat 1.14.1, jq, fzf, tmux, vim, lsof, zstd, dnsutils, openssh-server, sudo |

## Notes

- Lean compared to Codex and Claude Code: one JavaScript and one Python
  stack, plus Nix for everything else.
- A full desktop is part of the image, aimed at computer use.
- Docker is present but off; units are enabled per orb.

## Ground truth

Docs describe the image; the probe shows it. Run [`scripts/probe.sh`](../../scripts/probe.sh) inside a session as described in [`METHOD.md`](../METHOD.md) and commit the result to `research/probes/amp-orbs/`.
