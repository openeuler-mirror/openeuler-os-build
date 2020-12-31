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
rm -rf /boot/initramfs*

%end

%packages --excludedocs
@core --nodefaults
dracut-live
dracut-network
grub2
grub2-efi-aa64-cdboot
shim
euleros-logos
kernel
%end
