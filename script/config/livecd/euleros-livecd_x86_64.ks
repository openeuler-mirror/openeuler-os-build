# Minimal Disk Image
#
# Firewall configuration
firewall --enabled
# Use network installation
url --url="http://euleros-obs-repo.huawei.com:82/EulerOS_ALL_V3R1/PRODUCT_NAME/"
# Root password
rootpw --iscrypted $6$tmWZYrc3$Eyo4oYekTBYDrU0Okyw2vFWuJaqp4mY3cJro9qBdXl24kiarFENlIkcNYHmEtf/AO3cTqFjVitmRZcXajOpU00

# Network information
network  --bootproto=dhcp --onboot=on --activate
# System keyboard
keyboard --xlayouts=us --vckeymap=us
# System language
lang en_US.UTF-8
# SELinux configuration
selinux --enforcing
# Installation logging level
logging --level=info
# Shutdown after installation
shutdown
# System timezone
timezone Asia/Beijing 
# System bootloader configuration
bootloader --location=mbr
# Clear the Master Boot Record
zerombr
# Partition clearing information
clearpart --all
# Disk partitioning information
part / --fstype="ext4" --size=4000
part swap --size=1000

%post

touch /etc/sysconfig/network

cat << EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
TYPE=Ethernet
BOOTPROTO=dhcp
NAME=eth0
DEVICE=eth0
ONBOOT=yes
EOF

rm -rf /etc/systemd/system/multi-user.target.wants/kbox.service
rm -rf /etc/systemd/system/multi-user.target.wants/kdump.service
rm -rf /usr/lib/systemd/system/kbox.service
rm -rf /usr/lib/systemd/system/kdump.service

%end

%packages --excludedocs
@core --nodefaults
gtk2.x86_64
strace
vim-minimal
openssh-server
setup
passwd
findutils
sudo
util-linux
net-tools
iproute
rsyslog
rootfiles
openssh-clients
dhclient
yum-plugin-priorities.noarch
euleros-latest-release
kernel
memtest86+
grub2-efi-x64
grub2
shim-x64
syslinux
grub2-efi-x64-cdboot
euleros-logos
smartmontools
pciutils
pciutils-libs
libpciaccess
lsscsi
libnl
lftp
zip
unzip
dosfstools
btrfs-progs
genisoimage
nfs-utils
iscsi-initiator-utils
libiscsi
dhcp
dracut-live
-dracut-config-rescue
-grub2-efi-ia32-cdboot
-kbox-kmod
-kdump
-kexec-tools
-dump_mem_tool
-libnl
%end
