# Our approach: agent sandboxes on our own hardware

What we run instead of (or next to) hosted agent VMs: an old laptop in a
rack, reinstalled remotely with Debian 13, running [Incus](https://linuxcontainers.org/incus/)
system containers as sandboxes. Written down on 2026-11-25.

## Why

- **Cost and capacity:** a used 8-core laptop has more RAM and CPU than the
  small tiers of the hosted providers (2–4 vCPU, 8–16 GB per sandbox) and
  runs any number of sandboxes for the price of electricity.
- **Speed:** a new sandbox is ready in about 4 seconds, measured
  ([`../benchmarks/incus-lifecycle.md`](../benchmarks/incus-lifecycle.md)).
  The hosted VMs we tried took about 30 seconds.
- **Control:** our own base image, our own network rules, persistent state
  as long as we want it, SSH and every tool we like.
- **Trade-off:** we run the hardware, the updates and the backups ourselves,
  and the sandboxes share one host kernel (containers, not VMs).

## Architecture

```
 operator Mac ──SSH (VPN or LAN)──▶ host: Debian 13, LUKS + LVM
                                     │  dropbear :2222  (unlock after reboot)
                                     │  Incus 6.0 LTS
                                     │   ├─ storage: LVM thin pool (instant clones)
                                     │   ├─ network: incusbr0, NAT, 10.120.0.0/24
                                     │   ├─ base        clean Debian 13, stopped
                                     │   ├─ sandbox-1   copy of base, running
                                     │   └─ sandbox-2   copy of base, running
```

| Layer | Choice | Reason |
| --- | --- | --- |
| Host OS | Debian 13, no desktop | Stable, small, unattended security updates; Incus 6.0 LTS is in the main archive |
| Disk | LUKS2 + LVM; root 100 GB, swap 16 GB, the rest for sandboxes | Encrypted at rest; LVM thin snapshots make copies instant |
| Unlock | dropbear in the initramfs, key only, forced to `cryptroot-unlock` | Reboots need no keyboard at the rack (TPM2 auto-unlock is the next step) |
| Sandboxes | Incus system containers, unprivileged, `security.nesting=true` | Full systemd userland, ~50–100 MB overhead each, Docker inside works |
| Limits | 6 CPU, 6 GiB RAM, 40 GiB disk per sandbox (profile default) | A runaway build cannot take the host down |
| Base image | `images:debian/13`, nothing added | A clean start; tools are added in layers, not baked into everything |
| Network | NAT bridge; sandboxes reach the internet, not each other's files | Simple default; Incus network ACLs can restrict egress later |

## Layers (following the providers' pattern)

1. **`base`:** the clean distribution image. Never changed.
2. **`base-agent`** (optional): what every provider has in common: git, gh,
   ripgrep, jq, Python with uv, Node with pnpm, Docker, Claude Code, Codex.
3. **Per project:** a setup script, then `incus snapshot`; sessions are
   copies of that snapshot.

Reset a sandbox to a clean state with `incus snapshot restore` (about 4.5 s)
instead of rebuilding it.

## Setup

1. **Reinstall the host remotely**: [`remote-reinstall.md`](remote-reinstall.md).
   Unattended Debian install started from the running old OS, tested in a
   QEMU dry run first. Templates in [`../scripts/debian-preseed/`](../scripts/debian-preseed/).
2. **Install Incus**: [`../scripts/incus/`](../scripts/incus/): an LVM thin
   pool on the free space of the volume group, then `incus admin init --preseed`.
3. **Create sandboxes**:
   ```sh
   incus init images:debian/13 base
   incus copy base sandbox-1 && incus start sandbox-1
   incus shell sandbox-1
   ```

## Capacity (8-core Ryzen 7 5700U, 16 GB RAM)

- An empty sandbox uses about 50–100 MB RAM; 8 running empty sandboxes left
  14 GB free.
- RAM is the limit, not CPU or disk. A coding agent needs about 0.3–0.6 GB
  for the CLI, 1.5–2.5 GB while it builds, and 2.5–4 GB with a browser.
- Estimate: 4–5 agents working in parallel comfortably, 6–8 with light work,
  2–3 with browser tests or large builds. Lower `limits.memory` to 3–4 GiB
  when more than four run.
- A 15 W laptop chip throttles under long full load with the lid closed:
  parallel builds take longer, they do not fail.

## Lessons

- **Dry-run the preseed in a VM on the old system first.** It found two
  errors that would have stopped the real install: the user name `admin` is
  reserved in debian-installer, and LVM gave all free space to swap unless
  `partman-auto-lvm/guided_size` is set.
- **Pipe the LUKS passphrase without a trailing newline** to
  `cryptroot-unlock`, or it fails.
- **Keep the old SSH host keys and VPN keys** and restore them after the
  reinstall, so clients see the same host.
- **Unlock over the network needs a network in the initramfs:** add the NIC
  driver (`r8152` for Realtek USB LAN) to `/etc/initramfs-tools/modules` and
  set `IP=dhcp`. A VPN does not run there, so unlock works only from the LAN.
