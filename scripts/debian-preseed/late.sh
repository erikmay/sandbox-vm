#!/bin/sh
# Runs inside the installed system (chroot) at the end of the Debian install.
set -eux
PUBKEY='__PUBKEY__'
ADMIN_HASH='__ADMIN_HASH__'

# admin user (name is reserved in d-i, so it is created here) with sudo; root gets locked
id admin >/dev/null 2>&1 || useradd -m -u 1000 -s /bin/bash -c Admin admin
usermod -p "$ADMIN_HASH" -aG sudo,adm admin
passwd -l root

install -d -m 700 -o 1000 -g 1000 /home/admin/.ssh
echo "$PUBKEY" > /home/admin/.ssh/authorized_keys
chown 1000:1000 /home/admin/.ssh/authorized_keys; chmod 600 /home/admin/.ssh/authorized_keys

# SSH: keys only
cat > /etc/ssh/sshd_config.d/10-rack.conf <<'C'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
C

# Remote LUKS unlock: dropbear in the initramfs on port 2222, key-only, forced to cryptroot-unlock
install -d /etc/dropbear/initramfs
echo "no-port-forwarding,no-agent-forwarding,no-X11-forwarding,command=\"/usr/bin/cryptroot-unlock\" $PUBKEY" > /etc/dropbear/initramfs/authorized_keys
chmod 600 /etc/dropbear/initramfs/authorized_keys
echo 'DROPBEAR_OPTIONS="-I 600 -j -k -s -p 2222"' > /etc/dropbear/initramfs/dropbear.conf
# initramfs networking via DHCP on any interface; make sure the USB LAN adapter driver is inside
grep -q '^IP=' /etc/initramfs-tools/initramfs.conf && sed -i 's/^IP=.*/IP=dhcp/' /etc/initramfs-tools/initramfs.conf || echo 'IP=dhcp' >> /etc/initramfs-tools/initramfs.conf
for m in usbnet mii r8152 cdc_ether cdc_ncm; do grep -qx "$m" /etc/initramfs-tools/modules || echo "$m" >> /etc/initramfs-tools/modules; done

# Headless laptop: ignore the lid, never suspend
install -d /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/10-rack.conf <<'C'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
C
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Battery: stop charging at 60% (rack use, 24/7 on AC)
cat > /etc/systemd/system/battery-charge-limit.service <<'C'
[Unit]
Description=Limit battery charge to 60% for 24/7 rack use
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for f in /sys/class/power_supply/BAT*/charge_control_end_threshold; do [ -w "$f" ] && echo 60 > "$f"; done; true'

[Install]
WantedBy=multi-user.target
C
systemctl enable battery-charge-limit.service

# Security updates automatically
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'C'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
C

update-initramfs -u -k all
