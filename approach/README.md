# Self-hosted sandboxes with Incus

Instead of paying per-session for hosted agent VMs, I took an old laptop, put it in a rack, reinstalled it remotely with Debian 13, and set up [Incus](https://linuxcontainers.org/incus/) system containers as sandboxes. The host runs Debian 13, the sandboxes run Ubuntu 24.04.

A used 8-core laptop has more CPU and RAM than the entry-level hosted tiers (2–4 vCPU, 8–16 GB) and costs basically nothing to keep running. Starting a fresh container takes about 4 seconds ([`../benchmarks/incus-lifecycle.md`](../benchmarks/incus-lifecycle.md)), compared to ~30 seconds on the hosted VMs I tested. I also get full control over the base image, networking, and how long state sticks around.

The obvious downside is maintaining the hardware, updates, and backups myself. Also, because these are containers rather than VMs, sandboxes share the host kernel.

## Setup overview

```
 operator Mac ──SSH (VPN or LAN)──▶ host: Debian 13, LUKS + LVM
                                     │  dropbear :2222        unlock after reboot
                                     │  codex-plan-proxy      one ChatGPT login for all sandboxes
                                     │  Incus 6.0 LTS
                                     │   ├─ storage: LVM thin pool (instant clones)
                                     │   ├─ network: incusbr0, NAT, 10.120.0.0/24, egress ACL
                                     │   ├─ base            clean Ubuntu 24.04, stopped
                                     │   ├─ ubuntu-agent    template with tools and agents, stopped
                                     │   ├─ sandbox-1       copy of ubuntu-agent, running
                                     │   └─ sandbox-2       copy of ubuntu-agent, running
```

- **Host OS:** Headless Debian 13. Small footprint, unattended security updates, and Incus 6.0 LTS is in the main apt repo.
- **Disk:** LUKS2 with LVM on top: 100 GB for root, 16 GB swap, and the rest left in an LVM thin pool so container copies are instant snapshots.
- **Remote unlock:** dropbear in the initramfs on port 2222, key-only, forced to `cryptroot-unlock` so reboots don't need physical access. TPM2 auto-unlock is on the todo list.
- **Sandboxes:** Unprivileged Incus system containers with `security.nesting=true`. Full systemd inside, ~100 MB RAM when idle, and Docker works inside them.
- **Limits:** The `agent` profile caps each sandbox at 6 CPUs, 4 GiB RAM, 8192 processes and 40 GiB disk so a runaway build won't wedge the host.
- **Images:** `base` is plain `images:ubuntu/24.04`. `ubuntu-agent` is built from it by a script and verified before it replaces the previous template ([`agent-image.md`](agent-image.md)).
- **Network:** NAT bridge (`incusbr0`). An ACL lets sandboxes reach the internet but not the LAN, the VPN, each other, or the host, apart from DNS, DHCP and the login proxy.
- **Logins:** Signed in once on the host. Codex goes through a proxy that holds the ChatGPT login; Claude Code gets a long-lived token from the secret store ([`logins.md`](logins.md)).

## Why Ubuntu in the sandboxes

I started with `images:debian/13` and switched the sandboxes to Ubuntu 24.04, because that's what almost every hosted provider uses (Claude Code, Codex, Cursor; Copilot is on 26.04). Setup scripts, PPAs, vendor apt repos and `playwright install-deps` are mostly written and tested against Ubuntu LTS, and agents trip over fewer distro differences there.

The host stays on Debian. Containers don't have their own kernel, so every sandbox runs on the host's Debian 6.12 kernel and only the userland is Ubuntu. Re-running the benchmark after the switch gave the same numbers (see [`../benchmarks/incus-lifecycle.md`](../benchmarks/incus-lifecycle.md)). The stock Ubuntu container image has 255 packages including Python 3.12 and no snapd; the Debian one had 182 and no Python.

## Image layering

Following roughly what the hosted providers do:

1. `base`: stock `images:ubuntu/24.04`, never modified.
2. `ubuntu-agent`: the common baseline of the hosted providers (Node, Python + uv, Go, Rust, Docker, Chromium, PostgreSQL/Redis, gh, Claude Code, Codex, OpenCode, pi), rebuilt weekly from `base`. Details in [`agent-image.md`](agent-image.md).
3. Per-project containers: run the repo's setup script, take an `incus snapshot`, and clone from that for individual sessions.

Resetting a dirty sandbox takes ~4.5 seconds with `incus snapshot restore`, which beats rebuilding from scratch.

## Steps

From a machine with some Linux on it to signed-in sandboxes. Each step has its own page or script; run the scripts on the host from a checkout of this repository.

1. **Host OS.** Reinstall remotely with [`remote-reinstall.md`](remote-reinstall.md) and the preseed templates in [`../scripts/debian-preseed/`](../scripts/debian-preseed/). Test in QEMU first.
2. **Incus.** `sudo scripts/incus/setup.sh` installs Incus, creates the LVM thin pool, applies [`incus-preseed.yaml`](../scripts/incus/incus-preseed.yaml) and creates the clean `base` container.
3. **Profile and network rules.** `scripts/incus/agent-profile.sh` creates the `agent` profile and the egress ACL.
4. **Secret store and login proxy.** On your own machine, `scripts/logins/infisical-setup.py` creates the project and the host's machine identity. On the host, `sudo scripts/logins/install.sh infisical.env` installs the proxy and the secret client. Then sign in once: `sudo codex-plan-proxy login` for Codex, `claude setup-token` plus `sandbox-secrets set CLAUDE_CODE_OAUTH_TOKEN` for Claude Code. Details in [`logins.md`](logins.md).
5. **Template.** `scripts/incus/build-agent-template.sh` builds `ubuntu-agent` from `base` (about 12 minutes) and verifies it in a fresh copy.
6. **Sandboxes.**
   ```sh
   scripts/incus/new-sandbox.sh sandbox-1 --pubkey ~/.ssh/id_ed25519.pub \
     --git-name "Your Name" --git-email you@example.com
   ssh -J <host> agent@<sandbox-ip>      # codex and claude are signed in
   ```

## Day to day

| Task | Command (on the host) |
| --- | --- |
| New sandbox | `scripts/incus/new-sandbox.sh <name> --pubkey FILE [--memory 6GiB]` |
| Shell without SSH | `incus exec <name> -- sudo -iu agent` |
| Reset a sandbox | `incus snapshot create <name> clean`, later `incus snapshot restore <name> clean` |
| Remove a sandbox | `incus delete --force <name>` |
| Update tools and agents | `scripts/incus/build-agent-template.sh` (weekly); existing sandboxes keep their versions, new ones get the new template. `ubuntu-agent-prev` is the rollback |
| Rotate the Claude token | `claude setup-token`, `sandbox-secrets set CLAUDE_CODE_OAUTH_TOKEN`, `scripts/incus/sync-logins.sh --all` |
| Check the Codex login | `curl http://<gateway>:8455/healthz`, `sudo codex-plan-proxy status`, `journalctl -u codex-plan-proxy` |
| Sign in to Codex again | `ssh -L 1455:127.0.0.1:1455 <host> sudo codex-plan-proxy login` |
| After a host reboot | Unlock the disk: `printf '%s' "$PASSPHRASE" \| ssh -p 2222 root@<host-lan-ip>`. Incus starts the sandboxes that were running and the proxy reads its login from disk (Incus's default behaviour; I haven't rebooted since setting this up) |
| See what an image contains | `incus exec <name> -- cat /etc/agent-image-manifest`, or run [`../scripts/probe.sh`](../scripts/probe.sh) in it |

## Capacity on an 8-core Ryzen 7 5700U (16 GB RAM)

An idle container uses around 50–100 MB of RAM. With 8 empty containers running, the host still had 14 GB free.

RAM is the real bottleneck, not CPU or disk. A coding agent CLI uses roughly 0.3–0.6 GB, a build pushes that to 1.5–2.5 GB, and running a headless browser brings it to 2.5–4 GB. In practice this box comfortably handles 4–5 active agents at once, 6–8 if they're doing light work, or 2–3 if they're running browser tests or heavy builds. If you run more than four, drop `limits.memory` to 3–4 GiB.

A 15 W laptop CPU with the lid closed will thermal-throttle under sustained all-core load, so parallel builds slow down a bit, though they still finish fine.

## Things I ran into

- Testing the preseed in a QEMU VM on the old OS first saved me from bricking the box remotely. It caught two issues immediately: `admin` is a reserved username in `debian-installer`, and LVM gave all remaining free space to swap unless `partman-auto-lvm/guided_size` was explicitly set.
- `cryptroot-unlock` fails if you send a trailing newline with the LUKS passphrase. Use `printf '%s'`.
- Back up the old SSH host keys and VPN keys before wiping and restore them afterward so clients don't complain about changed host keys.
- Remote LUKS unlock needs networking inside the initramfs: add the NIC driver (e.g. `r8152` for Realtek USB Ethernet) to `/etc/initramfs-tools/modules` and set `IP=dhcp`. Because no VPN runs in the initramfs, unlocking only works from the local LAN.
