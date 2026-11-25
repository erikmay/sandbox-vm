# Remote headless reinstall to Debian 13

How I converted a headless Linux box (Omarchy / Arch Linux with Limine) into an encrypted Debian 13 host over SSH, without physical access. The installer boots unattended from a preseed initrd added to the existing boot loader. The actual install took about 7 minutes.

Requirements: SSH + sudo on the current OS, a UEFI boot loader you can edit, wired Ethernet with DHCP, and another machine on the same LAN for the first LUKS unlock. Templates are in [`../scripts/debian-preseed/`](../scripts/debian-preseed/).

## Target setup

- **OS:** Debian 13 (trixie), no desktop, `en_US.UTF-8`, German keymap, `Europe/Berlin` (adjust in the template).
- **Disk:** Full wipe. GPT with 1 GB ESP, 1 GB `/boot`, LUKS2, and LVM `vg0` containing 100 GB `root` and 16 GB `swap`. The rest of `vg0` stays unallocated for Incus.
- **User:** `admin` with sudo and a password; `root` locked. Because `debian-installer` reserves the name `admin`, `late.sh` creates the account after install.
- **SSH:** Key-only auth, no root login.
- **Boot unlock:** dropbear in the initramfs on port 2222, key-only, forced to `cryptroot-unlock`.
- **Laptop tweaks:** Ignore lid close, mask sleep/suspend targets, cap battery charge at 60%.
- **Updates:** `unattended-upgrades` for security patches, no automatic reboots.

## 0. Prep work

Back up `/etc/ssh/ssh_host_*` and any VPN keys so clients still recognize the host after the wipe. Delete the backup once the new system is up.

Check `lsblk` for the exact target disk name. A plugged-in USB stick will show up as `/dev/sda`, and the preseed writes directly to the device you pass in.

Generate the admin password and LUKS passphrase and save them in your password manager before doing anything else. Read them back to be sure.

## 1. Download the installer and build the preseed initrd

```sh
B=https://deb.debian.org/debian/dists/trixie/main/installer-amd64/current/images
curl -fsSLO $B/SHA256SUMS
curl -fsSL -o linux     $B/netboot/debian-installer/amd64/linux
curl -fsSL -o initrd.gz $B/netboot/debian-installer/amd64/initrd.gz
# verify both against SHA256SUMS (./netboot/debian-installer/amd64/...)

openssl passwd -6 -stdin < admin.pw > admin.hash
scripts/debian-preseed/render.py <hostname> /dev/nvme0n1 admin.hash luks.pw ~/.ssh/id_ed25519.pub out/
(cd out && printf '%s\n' preseed.cfg late.sh | bsdcpio -o --format newc | gzip -9) > extra.gz
cat initrd.gz extra.gz > initrd-preseed.gz   # debian-installer picks up /preseed.cfg
```

You don't need the ~500 MB firmware bundle for common USB Ethernet adapters (`r8152`). The installed system pulls firmware from `non-free-firmware`.

## 2. Dry run in QEMU (don't skip this)

Run the rendered preseed inside QEMU with OVMF on the existing machine first, using dummy passwords and `/dev/vda`. Give `disk.raw` the same starting layout as the real disk (GPT, ESP, a LUKS partition):

```sh
qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 4 -m 3072 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=vars.fd -drive file=disk.raw,format=raw,if=virtio \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:22222-:2222,hostfwd=tcp:127.0.0.1:22223-:22 \
  -device virtio-net-pci,netdev=n0 -kernel linux -initrd initrd-test.gz \
  -append "auto=true priority=critical console=ttyS0,115200n8 DEBIAN_FRONTEND=text" \
  -display none -serial file:serial.log -no-reboot -daemonize
```

Watch `serial.log` for `!!` or `[Press enter to continue]`; any of those means the preseed missed a prompt. Once it finishes, boot `disk.raw` without `-kernel` and verify dropbear unlock (`ssh -J <old-host> -p 22222 root@127.0.0.1`), SSH login on port 22223, `sudo`, `passwd -S root` (`L`), and that `vgs` shows free space in `vg0`.

This dry run caught two blockers on my first try: `admin` being reserved in `debian-installer`, and swap eating the entire volume group without `partman-auto-lvm/guided_size`.

## 3. Boot into the installer

Shred the rendered files in `out/` once `initrd-preseed.gz` is built. Copy `linux` and `initrd-preseed.gz` onto the ESP and add a default boot entry. With Limine:

```text
/Debian 13 Installer (unattended)
    protocol: linux
    path: boot():/debian-installer/linux
    module_path: boot():/debian-installer/initrd.gz
    cmdline: auto=true priority=critical
```

Put it at the top and set `default_entry: 1`. Disable anything that regenerates the boot config (like `limine-snapper-sync`) and keep a backup of the old config until you actually reboot.

After rebooting, the installer loads into RAM and wipes the disk, including the ESP. From another box on the LAN, the machine responds to ping (no SSH) while installing, drops off during reboot, and comes back up with port 2222 open.

## 4. First boot

```sh
printf '%s' "$LUKS_PASSPHRASE" | ssh -p 2222 root@<lan-ip>   # no trailing newline
ssh admin@<lan-ip>
```

Restore the SSH host keys (owned by root, `600` / `644`, check with `sshd -t` and restart `ssh`) and VPN config. Clean up old UEFI boot entries with `efibootmgr`, sanity-check `lsblk`, `vgs`, and `systemctl --failed`, then run [`../scripts/incus/setup.sh`](../scripts/incus/setup.sh).

## Caveats

- Reboot unlocking requires a machine on the local LAN since no VPN runs in the initramfs. Enrolling TPM2 (`systemd-cryptenroll --tpm2-device=auto`) avoids this later.
- The preseed picks the first wired NIC with link; Wi-Fi is left unconfigured.
- If the installer stalls on an unanswered prompt after wiping the disk, you'll need physical access and a USB stick to recover. That's why the QEMU dry run matters.
