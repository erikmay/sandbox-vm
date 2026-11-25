# Amp orbs (Sourcegraph Amp)

Checked: 2026-11-09 (image from Amp commit `db5a5936`). Read from the image config / build history of `amp-orb-debian13` (amd64). Amp doesn't publish the Dockerfile or document the package list, so this is just what was observed in the image metadata.

## Machine

| | |
| --- | --- |
| Base | Debian 13 (trixie) with `buildpack-deps`-style layers (compilers, dev headers, git, mercurial, subversion) |
| Isolation | Container expecting systemd as PID 1 |
| Resources | Not documented |
| Arch | amd64 only |

## Preinstalled

| Area | Contents (version) |
| --- | --- |
| Node.js | Node 26.12.1, npm 10, pnpm 12.0.0, yarn 1.22, Bun 1.4.4 |
| Python | Debian `python3` with pip, venv, dev headers; uv 0.12.9 |
| Other languages | None (no Go, Rust, Java, Ruby, PHP) |
| Nix | Nix 2.35.3 |
| Containers | Docker CE, containerd (installed, services disabled by default) |
| Browser | agent-browser 0.38.1 |
| Desktop | Wayland desktop for computer use: foot terminal, Xwayland, swaybg, wlr-randr, PulseAudio, fonts |
| Media | ffmpeg, ImageMagick 7.1.2 (AppImage) |
| Tools | git, gh 2.99.0, glab 1.127.0, ripgrep 14.1.0, websocat 1.14.1, jq, fzf, tmux, vim, lsof, zstd, dnsutils, openssh-server, sudo |

Much leaner than Codex or Claude Code: basically one JS stack, one Python stack, and Nix for anything else, plus a Wayland desktop for computer use. Docker is installed but disabled by default and turned on per orb.
