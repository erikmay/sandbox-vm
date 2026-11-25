# Incus sandbox lifecycle

Measured on 2026-11-25 with [`../scripts/incus/bench.sh`](../scripts/incus/bench.sh).

**Host:** ASUS ZenBook 14 (AMD Ryzen 7 5700U, 8 cores / 16 threads, 16 GB
RAM, WD SN530 NVMe), Debian 13, kernel 6.12, LUKS2 + LVM, Incus 6.0.4. LVM
thin pool, `incusbr0` NAT bridge. `base` is a stopped `images:debian/13`
container.

## One sandbox (5 rounds)

| Step | Time |
| --- | --- |
| `incus copy base <name>` | 2.3–2.6 s |
| `incus start` | 0.5–0.7 s |
| until `incus exec` works | +0.1 s |
| until DNS and network work | +0.6–0.8 s |
| **Total, usable with internet** | **3.7–4.0 s** |
| `incus stop` + `incus delete` | 1.4–1.7 s + 0.7–0.9 s = **2.2–2.5 s** |
| `incus delete --force` (running) | **1.9–2.1 s** |

Launching straight from the cached image (`incus launch images:debian/13`)
is slower: 4.3–4.5 s until `exec`, 5.0–5.5 s until network. Copying a
stopped base is the faster path.

## In parallel

| Sandboxes | Create, start, network | Delete all (`--force`) | Host RAM used |
| --- | --- | --- | --- |
| 4 | **3.8 s** | 2.6 s | 1.0 GB (14.3 GB available) |
| 8 | **6.3 s** | 2.7 s | 1.2 GB (14.2 GB available) |

An empty running sandbox costs about 50–60 MB of RAM.

## Reset to a clean state

| Step | Time |
| --- | --- |
| `incus snapshot create` (running sandbox) | **0.5 s** |
| `incus snapshot restore`, until `exec` works | **4.3–4.6 s** |

A 200 MB file written after the snapshot was gone after each restore.

## Compared with a hosted VM

| | Incus on the laptop | exe.dev (trial) |
| --- | --- | --- |
| New sandbox usable | ~4 s | ~30 s (clone + start + agent) |
| Delete | ~2 s | a few seconds |
| Pause / resume | not measured | 4 s / 3 s |

## Ideas

- **Warm pool:** keep 2–3 stopped copies of `base` ready. A new sandbox is
  then start + network, about 1.3 s instead of 4 s; refill in the background.
- The copy is the largest part. It is an LVM thin snapshot plus Incus
  bookkeeping; a ZFS or btrfs pool may be faster and is worth measuring.
