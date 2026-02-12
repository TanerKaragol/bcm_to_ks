# bcm.ks -- Rocky 9.2 Stateful Installation for BCM Migration
# Generated for NVIDIA Bright Cluster Manager workaround

# /boot partition is ext4, and added to /etc/fstab
# slurm and munge services enabled

url --url="http://dl.rockylinux.org/vault/rocky/9.2/BaseOS/x86_64/os/"
text
# Enable reboot if you want it reboot after install
# reboot

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

# Bootloader location:
bootloader --location=mbr --boot-drive=/dev/vda

# disable kdump:
%addon com_redhat.kdump --disable
%end

%packages
@core
nfs-utils
rsync
%end

# Post-Install Script Section:
%post --nochroot
LOGFILE="/mnt/sysimage/root/ks-post.log"
echo "--- Post-Install Script Started: $(date) ---" >> "$LOGFILE" 2>&1

# Mount Bright Image via NFS
mkdir -p /mnt/sysimage/mnt/image >> "$LOGFILE" 2>&1
mount -t nfs -o nolock 192.168.122.254:/cm/images/default-image /mnt/sysimage/mnt/image >> "$LOGFILE" 2>&1

echo "---- Rsync Image to Target: $(date) ---" >> "$LOGFILE" 2>&1
rsync -aH --no-xattrs --no-acls --delete \
   --exclude=/etc/fstab \
   --exclude=/mnt/* \
   --exclude=/dev/* \
   --exclude=/proc/* \
   --exclude=/sys/* \
   --exclude=/tmp/* \
   --exclude=/run/* \
   --exclude=/media/* \
   /mnt/sysimage/mnt/image/ /mnt/sysimage/ >> "$LOGFILE" 2>&1

echo "---- Rsync Finished: $(date) ---" >> "$LOGFILE" 2>&1
umount /mnt/sysimage/mnt/image
rmdir /mnt/sysimage/mnt/image >> "$LOGFILE" 2>&1

# Fix DNS & FSTAB
echo "search cm.cluster eth.cluster" > /mnt/sysimage/etc/resolv.conf
echo "nameserver 192.168.122.254" >> /mnt/sysimage/etc/resolv.conf
mkdir -p /mnt/sysimage/cm/shared
echo "master:/cm/shared /cm/shared nfs rsize=32768,wsize=32768,hard,async 0 0" >> /mnt/sysimage/etc/fstab
echo "master:/home  /home  nfs  rsize=32768,wsize=32768,hard,async 0 0" >> /mnt/sysimage/etc/fstab

# repo modification:
rm -rf /mnt/sysimage/etc/yum.repos.d/cm*.repo >> "$LOGFILE" 2>&1

# UUID Update Logic
# In this kisckstart:  /dev/vda1=/boot, /dev/vda2=swap, /dev/vda3=/ (root)
NEW_ROOT_UUID=$(lsblk -no UUID /dev/vda3)
NEW_BOOT_UUID=$(lsblk -no UUID /dev/vda1)
NEW_SWAP_UUID=$(lsblk -no UUID /dev/vda2)

echo "Root UUID: $NEW_ROOT_UUID" >> "$LOGFILE" 2>&1
echo "Boot UUID: $NEW_BOOT_UUID" >> "$LOGFILE" 2>&1
echo "Swap UUID: $NEW_SWAP_UUID" >> "$LOGFILE" 2>&1


# GRUB and BLS PATH
GRUB_CFG_PATH="/mnt/sysimage/boot/grub2/grub.cfg"
BLS_ENTRIES_PATH="/mnt/sysimage/boot/loader/entries"

echo "GRUB is updating with new UUID..." >> "$LOGFILE" 2>&1

# 1. grub.cfg: 'search --fs-uuid --set=root' line:
sed -i "s|search --no-floppy --fs-uuid --set=root [0-9a-fA-F-]*|search --no-floppy --fs-uuid --set=root $NEW_ROOT_UUID|" "$GRUB_CFG_PATH" || echo "ERROR: SED: 1. Step" >> "$LOGFILE"

# 2. grub.cfg: 'search --fs-uuid --set=boot' line:
sed -i "s|search --no-floppy --fs-uuid --set=boot [0-9a-fA-F-]*|search --no-floppy --fs-uuid --set=boot $NEW_BOOT_UUID|" "$GRUB_CFG_PATH" || echo "ERROR: SED: 2. Step" >> "$LOGFILE"

# 3. kernelopts line: "root" and "resume (swap)" UUIDs:
sed -i "s|root=UUID=[0-9a-fA-F-]*|root=UUID=$NEW_ROOT_UUID|" "$GRUB_CFG_PATH" || echo "ERROR: SED: 3. Step: root" >> "$LOGFILE"
sed -i "s|resume=UUID=[0-9a-fA-F-]*|resume=UUID=$NEW_SWAP_UUID|" "$GRUB_CFG_PATH" || echo "ERROR: SED: 3. Step: resume" >> "$LOGFILE"

# 4. BLS (Boot Loader Specification) entires:
echo "update UUIDs in BLS entry files..." >> "$LOGFILE" 2>&1
for bls_file in "$BLS_ENTRIES_PATH"/*.conf; do
    if [ -f "$bls_file" ]; then
        echo "BLS files processing: $bls_file..." >> "$LOGFILE" 2>&1
        sed -i "s|root=UUID=[0-9a-fA-F-]*|root=UUID=$NEW_ROOT_UUID|" "$bls_file" || echo "ERROR: SED: 4. Step: root $bls_file" >> "$LOGFILE"
        sed -i "s|resume=UUID=[0-9a-fA-F-]*|resume=UUID=$NEW_SWAP_UUID|" "$bls_file" || echo "ERROR: SED: 4. Step: resume $bls_file" >> "$LOGFILE"
        sed -i "s|^linux /boot/|linux /|" "$bls_file" || echo "ERROR: SED: 4. Step: linux path $bls_file" >> "$LOGFILE"
        sed -i "s|^initrd /boot/|initrd /|" "$bls_file" || echo "ERROR: SED: 4. Step: initrd path $bls_file" >> "$LOGFILE"
    fi
done

# 5. Removing 'inst.repo' parameter in GRUB files.
# inst.repo releated to installation and may create problem in normal boot:
echo " removing 'inst.repo' parameters in grub.cfg and BLS entry files..." >> "$LOGFILE" 2>&1
sed -i "/inst.repo=/d" "$GRUB_CFG_PATH" || echo "ERROR: SED: 5. Step" >> "$LOGFILE"
for bls_file in "$BLS_ENTRIES_PATH"/*.conf; do
    if [ -f "$bls_file" ]; then
        sed -i "/inst.repo=/d" "$bls_file" || echo "ERROR: SED: 5. Step $bls_file" >> "$LOGFILE"
    fi
done

echo "installing GRUB2 bootloader and initramfs..." >> "$LOGFILE" 2>&1
for dir in proc sys dev run; do
    mkdir -p /mnt/sysimage/$dir >> "$LOGFILE" 2>&1
    mount --bind /$dir /mnt/sysimage/$dir >> "$LOGFILE" 2>&1
done

#Do jobs under chroot:
#Packages are reinstalled in case it is not included in BCM image or config files are wrong:
chroot /mnt/sysimage <<EOF_CHROOT >> "$LOGFILE" 2>&1
    dnf install -y grub2-pc grub2-efi-x64 dracut
    dnf reinstall -y grub2-pc grub2-efi-x64 dracut

    /usr/sbin/grub2-install /dev/vda
    /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
    CURRENT_KERNEL_VERSION=$(ls -1 /lib/modules | head -n 1)
    /bin/dracut --force --verbose /boot/initramfs-${CURRENT_KERNEL_VERSION}.img ${CURRENT_KERNEL_VERSION}

echo "----Fixing SLURM:----"
    mkdir -p /etc/systemd/system/slurmd.service.d/
    cat <<'EOF' > /etc/systemd/system/slurmd.service.d/override.conf
[Unit]
Requires=munge.service
After=munge.service
[Service]
# Reset Orijinal ExecStart
ExecStart=
# Define new ExecStart with slurm.conf path
# Make sure slurm.conf path is correct!
ExecStart=/cm/shared/apps/slurm/23.02.8/sbin/slurmd -D -s -f /cm/shared/apps/slurm/var/etc/slurm/slurm.conf \$SLURMD_OPTIONS
EOF

    # MUNGE override
    mkdir -p /etc/systemd/system/munge.service.d/
    cat <<'EOF' > /etc/systemd/system/munge.service.d/override.conf
[Unit]
RequiresMountsFor=/cm/shared
After=network-online.target remote-fs.target
EOF

    # Slurmd service ENABLE
    ln -s /usr/lib/systemd/system/slurmd.service /etc/systemd/system/multi-user.target.wants/slurmd.service
    # sync disks.
    sync
EOF_CHROOT

echo "End Chroot and umount special file systems..." >> "$LOGFILE" 2>&1
for dir in run dev sys proc; do
    umount /mnt/sysimage/$dir >> "$LOGFILE" 2>&1
done

echo "--- Post-Install Script Finished: $(date) ---" >> "$LOGFILE" 2>&1

sync
%end
