# Remote reinstall to Debian 13 (headless)

How to turn a machine that runs some Linux into an encrypted Debian 13 host
without anyone at the keyboard. The installer runs unattended (preseed) from
a boot entry added to the old system's boot loader. Done once on 2026-11-25:
Omarchy (Arch Linux, Limine) to Debian 13 on a laptop in a rack, in about
7 minutes of install time.

You need: SSH and sudo on the old system, a UEFI boot loader you can edit,
wired LAN with DHCP, and a client in the same LAN for the first unlock.
Templates: [`../scripts/debian-preseed/`](../scripts/debian-preseed/).

## What the host gets

| Area | Result |
| --- | --- |
| OS | Debian 13 (trixie), no desktop, `en_US.UTF-8`, German keymap, Europe/Berlin (edit the template) |
| Disk | Whole disk wiped. GPT: ESP 1 GB, `/boot` 1 GB, LUKS2, LVM `vg0` with `root` 100 GB and `swap` 16 GB; the rest of `vg0` stays free |
| User | `admin` with sudo and a password; `root` locked. `admin` is reserved in debian-installer, so `late.sh` creates it |
| SSH | Key only, no root login |
| Unlock | dropbear in the initramfs on port 2222, key only, forced to `cryptroot-unlock` |
| Laptop in a rack | Lid switch ignored, sleep targets masked, battery charge limit 60 % |
| Updates | `unattended-upgrades` for security, no automatic reboot |

## 0. Before you start

- Back up what you keep, at least the SSH host keys (`/etc/ssh/ssh_host_*`)
  and VPN keys, so clients see the same host afterwards. Delete the backup
  once the new system works; it holds private keys.
- Note the disk name (`lsblk`). A USB stick shows as `/dev/sda`; the preseed
  names the disk explicitly.
- Generate an admin password and a LUKS passphrase and store them in your
  password manager first. Read them back and compare.

## 1. Installer and preseed

```sh
B=https://deb.debian.org/debian/dists/trixie/main/installer-amd64/current/images
curl -fsSLO $B/SHA256SUMS
curl -fsSL -o linux     $B/netboot/debian-installer/amd64/linux
curl -fsSL -o initrd.gz $B/netboot/debian-installer/amd64/initrd.gz
# check both against SHA256SUMS (./netboot/debian-installer/amd64/...)

openssl passwd -6 -stdin < admin.pw > admin.hash
scripts/debian-preseed/render.py <hostname> /dev/nvme0n1 admin.hash luks.pw ~/.ssh/id_ed25519.pub out/
(cd out && printf '%s\n' preseed.cfg late.sh | bsdcpio -o --format newc | gzip -9) > extra.gz
cat initrd.gz extra.gz > initrd-preseed.gz   # the installer reads /preseed.cfg
```

The firmware archive (about 500 MB) is not needed for common USB LAN
adapters (`r8152`); the installed system gets firmware from
`non-free-firmware`.

## 2. Dry run in a VM (do not skip)

On the old system with QEMU and OVMF, with **test** passwords and `/dev/vda`
as the disk. Give the test disk the same shape as the real one (GPT, ESP, a
LUKS partition):

```sh
qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 4 -m 3072 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=vars.fd -drive file=disk.raw,format=raw,if=virtio \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:22222-:2222,hostfwd=tcp:127.0.0.1:22223-:22 \
  -device virtio-net-pci,netdev=n0 -kernel linux -initrd initrd-test.gz \
  -append "auto=true priority=critical console=ttyS0,115200n8 DEBIAN_FRONTEND=text" \
  -display none -serial file:serial.log -no-reboot -daemonize
```

Watch `serial.log` for `!!` or `[Press enter to continue]`: each is a
question the preseed does not answer. Then boot the disk without `-kernel`
and check the unlock (`ssh -J <old-host> -p 22222 root@127.0.0.1`), the
login on port 22223, `sudo`, `passwd -S root` (`L`), and free space in `vg0`
(`vgs`).

Our dry run found two errors that would have stopped the real install: the
reserved user name `admin`, and swap taking all free space (fixed with
`partman-auto-lvm/guided_size`).

## 3. Boot into the installer

Shred the rendered files once the initrd is built. Copy `linux` and
`initrd-preseed.gz` to the ESP and make a boot entry the default. With
Limine:

```text
/Debian 13 Installer (unattended)
    protocol: linux
    path: boot():/debian-installer/linux
    module_path: boot():/debian-installer/initrd.gz
    cmdline: auto=true priority=critical
```

Put it above the first entry and set `default_entry: 1`. Stop anything that
rewrites the boot config (for example `limine-snapper-sync`). Keep a copy of
the old config; until the reboot, everything can be undone.

The installer loads into RAM, then wipes the disk including the ESP. From a
client in the LAN: the machine answers ping without SSH while it installs,
disappears when it reboots, and comes back with port 2222 open.

## 4. First boot

```sh
printf '%s' "$LUKS_PASSPHRASE" | ssh -p 2222 root@<lan-ip>   # no trailing newline
ssh admin@<lan-ip>
```

Restore the SSH host keys (root, 600 / 644; `sshd -t`, restart `ssh`) and
the VPN config, delete stale UEFI entries with `efibootmgr`, and check
`lsblk`, `vgs`, `systemctl --failed`. Then install Incus:
[`../scripts/incus/setup.sh`](../scripts/incus/setup.sh).

## Limits

- Unlock after a reboot needs a client in the LAN: no VPN runs in the
  initramfs. TPM2 auto-unlock (`systemd-cryptenroll --tpm2-device=auto`) is
  the next step.
- The preseed picks the first wired interface with a link; Wi-Fi stays
  unconfigured.
- If the installer stops on a question, the machine has no OS until someone
  boots it from a USB stick. The dry run is what makes this unlikely.
