# Debian 13 (trixie) unattended install. Rendered by render.py; placeholders: __HOSTNAME__ __DISK__ __ADMIN_HASH__ __LUKS__
d-i debian-installer/locale string en_US.UTF-8
d-i debian-installer/language string en
d-i debian-installer/country string DE
d-i localechooser/supported-locales multiselect en_US.UTF-8, de_DE.UTF-8
d-i keyboard-configuration/xkb-keymap select de
d-i keyboard-configuration/layoutcode string de
d-i hw-detect/load_firmware boolean false

d-i netcfg/enable boolean true
d-i netcfg/choose_interface select auto
d-i netcfg/link_wait_timeout string 30
d-i netcfg/dhcp_timeout string 90
d-i netcfg/get_hostname string __HOSTNAME__
d-i netcfg/get_domain string
d-i netcfg/hostname string __HOSTNAME__
d-i netcfg/wireless_wep string

d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

# "admin" is a reserved name in debian-installer: install with root only, create admin in late_command, then lock root
d-i passwd/root-login boolean true
d-i passwd/make-user boolean false
d-i passwd/root-password-crypted password __ADMIN_HASH__

d-i clock-setup/utc boolean true
d-i time/zone string Europe/Berlin
d-i clock-setup/ntp boolean true

d-i partman-auto/disk string __DISK__
d-i partman-auto/method string crypto
d-i partman-auto/purge_lvm_from_device boolean true
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-md/device_remove_md boolean true
d-i partman-lvm/confirm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true
d-i partman-crypto/passphrase password __LUKS__
d-i partman-crypto/passphrase-again password __LUKS__
d-i partman-crypto/weak_passphrase boolean true
d-i partman-auto-crypto/erase_disks boolean false
d-i partman-auto-lvm/new_vg_name string vg0
d-i partman-auto-lvm/guided_size string 120GB
d-i partman-partitioning/choose_label select gpt
d-i partman-partitioning/default_label string gpt
d-i partman-efi/non_efi_system boolean true
d-i partman-auto/choose_recipe select rackroot
d-i partman-auto/expert_recipe string rackroot :: \
  1024 1024 1024 free $iflabel{ gpt } $reusemethod{ } method{ efi } format{ } . \
  1024 1024 1024 ext4 $defaultignore{ } method{ format } format{ } use_filesystem{ } filesystem{ ext4 } mountpoint{ /boot } . \
  102400 102400 102400 ext4 $lvmok{ } lv_name{ root } method{ format } format{ } use_filesystem{ } filesystem{ ext4 } mountpoint{ / } . \
  16384 16384 16384 linux-swap $lvmok{ } lv_name{ swap } method{ swap } format{ } .
d-i partman-basicfilesystems/no_swap boolean false
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

d-i apt-setup/non-free-firmware boolean true
d-i apt-setup/non-free boolean false
d-i apt-setup/contrib boolean false
d-i apt-setup/cdrom/set-first boolean false
d-i apt-setup/services-select multiselect security, updates
tasksel tasksel/first multiselect standard, ssh-server
d-i pkgsel/include string sudo curl ca-certificates dropbear-initramfs cryptsetup-initramfs wireguard-tools efibootmgr lvm2 thin-provisioning-tools unattended-upgrades apt-listchanges rsync htop tmux
d-i pkgsel/upgrade select full-upgrade
popularity-contest popularity-contest/participate boolean false

d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean false
d-i grub-installer/force-efi-extra-removable boolean true
d-i grub-installer/bootdev string __DISK__

d-i preseed/late_command string cp /late.sh /target/root/late.sh; in-target sh /root/late.sh
d-i finish-install/reboot_in_progress note
