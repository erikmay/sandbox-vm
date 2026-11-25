# Self-hosted sandboxes with Incus

Instead of paying per-session for hosted agent VMs, I took an old laptop, put it in a rack, reinstalled it remotely with Debian 13, and set up [Incus](https://linuxcontainers.org/incus/) system containers as sandboxes. The host runs Debian 13, the sandboxes run Ubuntu 24.04.

A used 8-core laptop has more CPU and RAM than the entry-level hosted tiers (2–4 vCPU, 8–16 GB) and costs basically nothing to keep running. Starting a fresh container takes about 4 seconds ([`../benchmarks/incus-lifecycle.md`](../benchmarks/incus-lifecycle.md)), compared to ~30 seconds on the hosted VMs I tested. I also get full control over the base image, networking, and how long state sticks around.

The obvious downside is maintaining the hardware, updates, and backups myself. Also, because these are containers rather than VMs, sandboxes share the host kernel.

## Setup overview

```
 operator Mac ──SSH (VPN or LAN)──▶ host: Debian 13, LUKS + LVM
                                     │  dropbear :2222  (unlock after reboot)
                                     │  Incus 6.0 LTS
                                     │   ├─ storage: LVM thin pool (instant clones)
                                     │   ├─ network: incusbr0, NAT, 10.120.0.0/24
                                     │   ├─ base        clean Ubuntu 24.04, stopped
                                     │   ├─ sandbox-1   copy of base, running
                                     │   └─ sandbox-2   copy of base, running
```

- **Host OS:** Headless Debian 13. Small footprint, unattended security updates, and Incus 6.0 LTS is in the main apt repo.
- **Disk:** LUKS2 with LVM on top: 100 GB for root, 16 GB swap, and the rest left in an LVM thin pool so container copies are instant snapshots.
- **Remote unlock:** dropbear in the initramfs on port 2222, key-only, forced to `cryptroot-unlock` so reboots don't need physical access. TPM2 auto-unlock is on the todo list.
- **Sandboxes:** Unprivileged Incus system containers with `security.nesting=true`. Full systemd inside, ~50–100 MB RAM overhead each, and Docker works inside them.
- **Limits:** Default profile caps each container at 6 CPUs, 6 GiB RAM, and 40 GiB disk so a runaway build won't wedge the host.
- **Base image:** Plain `images:ubuntu/24.04` with nothing extra installed. Tools go in separate layers instead of baking everything into one giant image.
- **Network:** Standard NAT bridge (`incusbr0`). Sandboxes can reach the internet; egress restrictions via Incus network ACLs can be added later if needed.

## Why Ubuntu in the sandboxes

I started with `images:debian/13` and switched the sandboxes to Ubuntu 24.04, because that's what almost every hosted provider uses (Claude Code, Codex, Cursor; Copilot is on 26.04). Setup scripts, PPAs, vendor apt repos and `playwright install-deps` are mostly written and tested against Ubuntu LTS, and agents trip over fewer distro differences there.

The host stays on Debian. Containers don't have their own kernel, so every sandbox runs on the host's Debian 6.12 kernel and only the userland is Ubuntu. Re-running the benchmark after the switch gave the same numbers (see [`../benchmarks/incus-lifecycle.md`](../benchmarks/incus-lifecycle.md)). The stock Ubuntu container image has 255 packages including Python 3.12 and no snapd; the Debian one had 182 and no Python.

## Image layering

Following roughly what the hosted providers do:

1. `base`: stock `images:ubuntu/24.04`, never modified.
2. `base-agent` (optional): the common baseline (git, gh, ripgrep, jq, Python + uv, Node + pnpm, Docker, Claude Code, Codex).
3. Per-project containers: run the repo's setup script, take an `incus snapshot`, and clone from that for individual sessions.

Resetting a dirty sandbox takes ~4.5 seconds with `incus snapshot restore`, which beats rebuilding from scratch.

## Steps

1. Reinstall the host remotely using [`remote-reinstall.md`](remote-reinstall.md) and the preseed templates in [`../scripts/debian-preseed/`](../scripts/debian-preseed/). Test in QEMU first.
2. Set up the LVM thin pool and run `incus admin init --preseed` using [`../scripts/incus/`](../scripts/incus/).
3. Create the base image and spin up a sandbox:
   ```sh
   incus init images:ubuntu/24.04 base
   incus copy base sandbox-1 && incus start sandbox-1
   incus shell sandbox-1
   ```

## Capacity on an 8-core Ryzen 7 5700U (16 GB RAM)

An idle container uses around 50–100 MB of RAM. With 8 empty containers running, the host still had 14 GB free.

RAM is the real bottleneck, not CPU or disk. A coding agent CLI uses roughly 0.3–0.6 GB, a build pushes that to 1.5–2.5 GB, and running a headless browser brings it to 2.5–4 GB. In practice this box comfortably handles 4–5 active agents at once, 6–8 if they're doing light work, or 2–3 if they're running browser tests or heavy builds. If you run more than four, drop `limits.memory` to 3–4 GiB.

A 15 W laptop CPU with the lid closed will thermal-throttle under sustained all-core load, so parallel builds slow down a bit, though they still finish fine.

## Things I ran into

- Testing the preseed in a QEMU VM on the old OS first saved me from bricking the box remotely. It caught two issues immediately: `admin` is a reserved username in `debian-installer`, and LVM gave all remaining free space to swap unless `partman-auto-lvm/guided_size` was explicitly set.
- `cryptroot-unlock` fails if you send a trailing newline with the LUKS passphrase. Use `printf '%s'`.
- Back up the old SSH host keys and VPN keys before wiping and restore them afterward so clients don't complain about changed host keys.
- Remote LUKS unlock needs networking inside the initramfs: add the NIC driver (e.g. `r8152` for Realtek USB Ethernet) to `/etc/initramfs-tools/modules` and set `IP=dhcp`. Because no VPN runs in the initramfs, unlocking only works from the local LAN.
