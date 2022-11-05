#!/bin/bash

# Script is based off official guide: see "Debian Bullseye Root on ZFS"
# https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/Debian%20Bullseye%20Root%20on%20ZFS.html

# Settings
export DEBIAN_FRONTEND=noninteractive
DISK=$1
ZFSHOST=$2
[ -z "$ZFSHOST" ] && ZFSHOST="debianzfs"
CODENAME="bullseye"
ZFSROOT="/mnt"

# Display commands
set -x

# Is the DISK path a block device?
DISK_TYPE=$(file "${DISK}" | awk '{ print $2$3 }')
if [ "$DISK_TYPE" != "blockspecial" ]; then
	echo "ERROR: Disk '${DISK}' is not a block device"
	exit 1;
fi

###############################################
### Step 1: Prepare The Install Environment ###
###############################################

# 1. Boot the Debian GNU/Linux Live CD... done
# 2. Setup and update the repositories
SOURCES_LIST="/etc/apt/sources.list"
[ -f "$SOURCES_LIST" ] && mv "$SOURCES_LIST" "$SOURCES_LIST.$(date +%s).bak"
echo "deb http://deb.debian.org/debian/ ${CODENAME} main contrib" > "$SOURCES_LIST"
apt-get update

# 3. Optional: Install and start the OpenSSH server in the Live CD environment... done
# 4. Disable automounting... skipping, no GUI-based automounting present
# 5. Become root... done
# 6. Install ZFS in the Live CD environment (plus some tools)
apt-get install -y debootstrap gdisk pwgen zfsutils-linux

###############################
### Step 2: Disk Formatting ###
###############################

# 1. Set a variable with the disk name
# 2. If you are re-using a disk, clear it as necessary... skipping: do this yourself :)
# Ensure swap partitions are not in use
swapoff --all

# 3. Partition your disk(s)
# Run this for UEFI booting (for use now or in the future)
sgdisk -n2:1M:+512M -t2:EF00 "$DISK"

# Run this for the boot pool
sgdisk -n3:0:+1G    -t3:BF01 "$DISK"

# Unencrypted or ZFS native encryption
sgdisk -n4:0:0      -t4:BF00 "$DISK"

# 4. Create the boot pool
zpool create -f \
    -o ashift=12 \
    -o autotrim=on -d \
    -o cachefile=/etc/zfs/zpool.cache \
    -o feature@async_destroy=enabled \
    -o feature@bookmarks=enabled \
    -o feature@embedded_data=enabled \
    -o feature@empty_bpobj=enabled \
    -o feature@enabled_txg=enabled \
    -o feature@extensible_dataset=enabled \
    -o feature@filesystem_limits=enabled \
    -o feature@hole_birth=enabled \
    -o feature@large_blocks=enabled \
    -o feature@livelist=enabled \
    -o feature@lz4_compress=enabled \
    -o feature@spacemap_histogram=enabled \
    -o feature@zpool_checkpoint=enabled \
    -O devices=off \
    -O acltype=posixacl -O xattr=sa \
    -O compression=lz4 \
    -O normalization=formD \
    -O relatime=on \
    -O canmount=off -O mountpoint=/boot -R "$ZFSROOT" \
		bpool "${DISK}3"

# 5. Create the root pool
# ZFS native encryption (with a random password)
RPOOLPW="$(pwgen -s 16 1)"
echo "$RPOOLPW" | \
zpool create -f \
    -o ashift=12 \
    -o autotrim=on \
    -O encryption=on -O keylocation=prompt -O keyformat=passphrase \
    -O acltype=posixacl -O xattr=sa -O dnodesize=auto \
    -O compression=lz4 \
    -O normalization=formD \
    -O relatime=on \
    -O canmount=off -O mountpoint=/ -R "$ZFSROOT" \
		rpool "${DISK}4"
unset RPOOLPW

###################################
### Step 3: System Installation ###
###################################

# 1. Create filesystem datasets to act as containers
zfs create -o canmount=off -o mountpoint=none rpool/ROOT
zfs create -o canmount=off -o mountpoint=none bpool/BOOT

# 2. Create filesystem datasets for the root and boot filesystems
zfs create -o canmount=noauto -o mountpoint=/ rpool/ROOT/debian
zfs mount rpool/ROOT/debian
zfs create -o mountpoint=/boot bpool/BOOT/debian

# 3. Create datasets
zfs create rpool/home
zfs create -o mountpoint=/root rpool/home/root
chmod 700 "$ZFSROOT/root"
zfs create -o canmount=off rpool/var
zfs create -o canmount=off rpool/var/lib
zfs create rpool/var/log
zfs create rpool/var/spool

# If you wish to separate these to exclude them from snapshots
zfs create -o com.sun:auto-snapshot=false rpool/var/cache
zfs create -o com.sun:auto-snapshot=false rpool/var/lib/nfs
zfs create -o com.sun:auto-snapshot=false rpool/var/tmp
chmod 1777 "$ZFSROOT/var/tmp"

# If you use /usr/local on this system
zfs create -o canmount=off rpool/usr
zfs create rpool/usr/local

# If this system will have a GUI
zfs create rpool/var/lib/AccountsService
zfs create rpool/var/lib/NetworkManager

# If this system will use Docker (which manages its own datasets & snapshots)
zfs create -o com.sun:auto-snapshot=false rpool/var/lib/docker

# 4. Mount a tmpfs at /run
mkdir "$ZFSROOT/run"
mount -t tmpfs tmpfs /mnt/run
mkdir "$ZFSROOT/run/lock"

# 5. Install the minimal system
debootstrap "$CODENAME" /mnt

# 6. Copy in zpool.cache
mkdir "$ZFSROOT/etc/zfs"
cp /etc/zfs/zpool.cache "$ZFSROOT/etc/zfs/"

####################################
### Step 4: System Configuration ###
####################################

# 1. Configure the hostname
hostname "$ZFSHOST"
hostname > "$ZFSROOT/etc/hostname"
sed "/^127.0.0.1.*localhost/a 127.0.1.1\\t$ZFSHOST" "$ZFSROOT/etc/hosts" | tee "$ZFSROOT/etc/hosts"

# 2. Configure the network interfaces
NETWORK_DEVICES=$(ip a | awk '$1 ~ /^[0-9][:]/ {print substr($2, 0, length($2)-1)}')
while read -r INTER; do
	if [ ! "$INTER" = "lo" ]; then
		cat <<-EOF > "$ZFSROOT/etc/network/interfaces.d/$INTER"
			auto ${INTER}
			iface ${INTER} inet dhcp
		EOF
	fi
done <<< "$NETWORK_DEVICES"

# 3. Configure the package sources
ZFS_SOURCES_LIST="$ZFSROOT/etc/apt/sources.list"
[ -f "$ZFS_SOURCES_LIST" ] && mv "$ZFS_SOURCES_LIST" "$ZFS_SOURCES_LIST.$(date +%s).bak"
cat <<-EOF > "$ZFS_SOURCES_LIST"
deb http://deb.debian.org/debian ${CODENAME} main contrib
deb-src http://deb.debian.org/debian ${CODENAME} main contrib

deb http://deb.debian.org/debian-security ${CODENAME}-security main contrib
deb-src http://deb.debian.org/debian-security ${CODENAME}-security main contrib

deb http://deb.debian.org/debian ${CODENAME}-updates main contrib
deb-src http://deb.debian.org/debian ${CODENAME}-updates main contrib
EOF

# 4. Bind the virtual filesystems from the LiveCD environment to the new system and chroot into it
# Copy DISK var under ZFSROOT
echo "DISK=${DISK}" > "$ZFSROOT/var/tmp/zfsenv"

# Bind
mount --make-private --rbind /dev /mnt/dev
mount --make-private --rbind /proc /mnt/proc
mount --make-private --rbind /sys /mnt/sys

# Chroot
cat << CHROOT | chroot /mnt bash --login
# Setup
export DEBIAN_FRONTEND=noninteractive
export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8
set -ex
. /var/tmp/zfsenv
unset CDPATH
cd

# 5. Configure a basic system environment
ln -s /proc/self/mounts /etc/mtab
apt-get update && apt-get upgrade -y
apt-get install -y console-setup locales

# Even if you prefer a non-English system language, always ensure that en_US.UTF-8 is available
dpkg-reconfigure locales tzdata keyboard-configuration console-setup

# 6. Install ZFS in the chroot environment for the new system
apt-get install -y dpkg-dev linux-headers-generic linux-image-generic zfs-initramfs
echo REMAKE_INITRD=yes > /etc/dkms/zfs.conf

# 7. For LUKS installs only, setup /etc/crypttab... skipping
# 8. Install GRUB
# Install GRUB for UEFI booting
apt-get install -y dosfstools

mkdosfs -F 32 -s 1 -n EFI "\${DISK}2"
mkdir /boot/efi
BLKID_BOOT="/dev/disk/by-uuid/\$(blkid -s UUID -o value \${DISK}2)"
echo "\${BLKID_BOOT} /boot/efi vfat defaults 0 0" >> /etc/fstab
mount /boot/efi
apt-get install -y grub-efi-amd64 shim-signed

# 9. Optional: Remove os-prober
apt-get purge -y os-prober

# 10. Set a root password
ROOTPW=$(pwgen 8 1)
echo "root:\$ROOTPW" | chpasswd
unset ROOTPW

# 11. Enable importing bpool
cat <<- BPOOL > /etc/systemd/system/zfs-import-bpool.service
[Unit]
DefaultDependencies=no
Before=zfs-import-scan.service
Before=zfs-import-cache.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/zpool import -N -o cachefile=none bpool
# Work-around to preserve zpool cache:
ExecStartPre=-/bin/mv /etc/zfs/zpool.cache /etc/zfs/preboot_zpool.cache
ExecStartPost=-/bin/mv /etc/zfs/preboot_zpool.cache /etc/zfs/zpool.cache

[Install]
WantedBy=zfs-import.target
BPOOL

systemctl enable zfs-import-bpool.service

# 12 Optional (but recommended): Mount a tmpfs to /tmp
cp /usr/share/systemd/tmp.mount /etc/systemd/system/
systemctl enable tmp.mount

# 13. Optional: Install SSH... skipping
# 14. Optional: For ZFS native encryption or LUKS, configure Dropbear for remote unlocking... skipping
# 15. Optional (but kindly requested): Install popcon... skipping

#################################
### Step 5: GRUB Installation ###
#################################

# 1. Verify that the ZFS boot filesystem is recognized
grub-probe /boot

# 2. Refresh the initrd files
update-initramfs -c -k all

# 3. Workaround GRUB's missing zpool-features support
sed -i "s/^\(GRUB_CMDLINE_LINUX=\).*/\1\"root=ZFS=rpool\/ROOT\/debian\"/" /etc/default/grub

# 4. Optional (but highly recommended): Make debugging GRUB easier
sed -i "s/^\(GRUB_CMDLINE_LINUX_DEFAULT=\).*/\1\"\"/" /etc/default/grub
sed -i '/GRUB_TERMINAL/s/^#//g' /etc/default/grub
cat /etc/default/grub

# 5. Update the boot configuration
update-grub

# 6. Install the boot loader
# For UEFI booting, install GRUB to the ESP
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
						 --bootloader-id=debian --recheck --no-floppy

# 7. Fix filesystem mount ordering
mkdir /etc/zfs/zfs-list.cache
touch /etc/zfs/zfs-list.cache/bpool
touch /etc/zfs/zfs-list.cache/rpool
timeout 10 zed -F || \

# Verify that zed updated the cache by making sure these are not empty
test -s /etc/zfs/zfs-list.cache/bpool &&
test -s /etc/zfs/zfs-list.cache/rpool

# Fix the paths to eliminate /mnt
sed -Ei "s|/mnt/?|/|" /etc/zfs/zfs-list.cache/*

##########################
### Step 6: First Boot ###
##########################

# 1. Optional: Snapshot the initial installation
zfs snapshot bpool/BOOT/debian@install
zfs snapshot rpool/ROOT/debian@install

# 2. Exit from the chroot environment back to the LiveCD environment
exit
CHROOT

# 3. Run these commands in the LiveCD environment to unmount all filesystems
mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | \
    xargs -I{} umount -lf {}

# 4. If this fails for rpool, mounting it on boot will fail and you will need to
#    zpool import -f rpool, then exit in the initamfs prompt
zpool export -a || exit 0
exit 0