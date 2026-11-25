# Incus sandbox lifecycle benchmarks

Measured on 2026-11-25 with [`../scripts/incus/bench.sh`](../scripts/incus/bench.sh).

Host hardware: ASUS ZenBook 14 (AMD Ryzen 7 5700U, 8C/16T, 16 GB RAM, WD SN530 NVMe) running Debian 13, kernel 6.12, LUKS2 + LVM, Incus 6.0.4. Storage is an LVM thin pool, networking is the default `incusbr0` NAT bridge, and `base` is a stopped `images:debian/13` container.

## Single sandbox (5 runs)

| Step | Time |
| --- | --- |
| `incus copy base <name>` | 2.3–2.6 s |
| `incus start` | 0.5–0.7 s |
| until `incus exec` works | +0.1 s |
| until DNS and network work | +0.6–0.8 s |
| **Total, usable with internet** | **3.7–4.0 s** |
| `incus stop` + `incus delete` | 1.4–1.7 s + 0.7–0.9 s = **2.2–2.5 s** |
| `incus delete --force` (running) | **1.9–2.1 s** |

Launching directly from the cached image (`incus launch images:debian/13`) took 4.3–4.5 s until `exec` and 5.0–5.5 s until network, so copying a stopped `base` container is noticeably quicker.

## Parallel launches

| Sandboxes | Create, start, network | Delete all (`--force`) | Host RAM used |
| --- | --- | --- | --- |
| 4 | **3.8 s** | 2.6 s | 1.0 GB (14.3 GB available) |
| 8 | **6.3 s** | 2.7 s | 1.2 GB (14.2 GB available) |

An idle running container takes roughly 50–60 MB of RAM.

## Snapshot reset

| Step | Time |
| --- | --- |
| `incus snapshot create` (running sandbox) | **0.5 s** |
| `incus snapshot restore`, until `exec` works | **4.3–4.6 s** |

Verified by writing a 200 MB file after taking the snapshot and checking it disappeared after restore.

## vs. hosted VM (exe.dev trial)

| | Incus on laptop | exe.dev (trial) |
| --- | --- | --- |
| New sandbox usable | ~4 s | ~30 s (clone + start + agent) |
| Delete | ~2 s | a few seconds |
| Pause / resume | not measured | 4 s / 3 s |

## Notes for later

Keeping 2–3 stopped copies of `base` around as a warm pool would cut startup down to start + network (~1.3 s) while refilling in the background.

Most of the 4 seconds is spent in `incus copy` (LVM thin snapshot plus Incus metadata). Might be worth benchmarking ZFS or btrfs on the same box to see if clones are faster there.
