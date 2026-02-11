# bcm.ks -- Rocky 9.2 Stateful Installation for BCM Migration
# Generated for NVIDIA Bright Cluster Manager workaround

url --url="http://dl.rockylinux.org/vault/rocky/9.2/BaseOS/x86_64/os/"
text
reboot

# Disk Partitioning
clearpart --all --initlabel
part /boot --fstype="ext4" --size=1024
part swap --fstype="swap" --size=2048
part / --fstype="xfs" --grow --size=1

# System Locale & Network
lang en_US.UTF-8
keyboard --vckeymap=tr --xlayouts='tr'
network --bootproto=dhcp --onboot=on
firewall --disabled
selinux --disabled
timezone Europe/Istanbul --utc

# Root Password (Generate with: openssl passwd -6)
rootpw --iscrypted $6$XXXXXXXXXXXXXX
bootloader --location=mbr --boot-drive=/dev/vda

%packages
@core
nfs-utils
rsync
%end

%post --nochroot
LOGFILE="/mnt/sysimage/root/ks-post.log"
echo "--- Post-Install Started: $(date) ---" >> "$LOGFILE" 2>&1

# Mount Bright Image via NFS
mkdir -p /mnt/sysimage/mnt/image
mount -t nfs -o nolock 192.168.122.254:/cm/images/default-image /mnt/sysimage/mnt/image

# Rsync Image to Target
rsync -aH --no-xattrs --no-acls --delete \
   --exclude=/etc/fstab --exclude=/mnt/* --exclude=/dev/* \
   --exclude=/proc/* --exclude=/sys/* --exclude=/tmp/* \
   --exclude=/run/* --exclude=/media/* \
   /mnt/sysimage/mnt/image/ /mnt/sysimage/ >> "$LOGFILE" 2>&1

umount /mnt/sysimage/mnt/image

# Fix DNS & FSTAB
echo "nameserver 192.168.122.254" >> /mnt/sysimage/etc/resolv.conf
echo "master:/cm/shared /cm/shared nfs rsize=32768,wsize=32768,hard,async 0 0" >> /mnt/sysimage/etc/fstab

# UUID Update Logic
NEW_ROOT_UUID=$(lsblk -no UUID /dev/vda3)
NEW_BOOT_UUID=$(lsblk -no UUID /dev/vda1)
NEW_SWAP_UUID=$(lsblk -no UUID /dev/vda2)

# Update GRUB and BLS entries using sed
GRUB_CFG="/mnt/sysimage/boot/grub2/grub.cfg"
sed -i "s|root=UUID=[0-9a-fA-F-]*|root=UUID=$NEW_ROOT_UUID|" "$GRUB_CFG"
# ... (Other sed commands for UUID and /boot path fixing)

# Rebuild Initramfs in Chroot
for dir in proc sys dev run; do mount --bind /$dir /mnt/sysimage/$dir; done
chroot /mnt/sysimage <<EOF_CHROOT
    dnf reinstall -y grub2-pc dracut
    grub2-install /dev/vda
    grub2-mkconfig -o /boot/grub2/grub.cfg
    CURRENT_KERNEL=\$(ls -1 /lib/modules | head -n 1)
    dracut --force /boot/initramfs-\${CURRENT_KERNEL}.img \${CURRENT_KERNEL}
EOF_CHROOT

sync
%end
