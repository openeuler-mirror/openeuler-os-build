#!/bin/bash
systemctl enable sshd
systemctl enable NetworkManager
systemctl enable systemd-timesyncd
echo openeuler-riscv64 > /etc/hostname
echo "openEuler12#$" | passwd --stdin root
useradd -m -G wheel -s /bin/bash openeuler
echo "openeuler:openEuler12#$" | chpasswd
if [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
    if [ -f /etc/localtime ]; then
        rm -f /etc/localtime
    fi
    ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
fi
if [ -f /etc/rc.d/rc.local ]; then
    chmod +x /etc/rc.d/rc.local
fi
cd /etc/rc.d/init.d
chmod +x extend-root.sh
chkconfig --add extend-root.sh
chkconfig extend-root.sh on
cd -
if [ -f /etc/locale.conf ]; then
    sed -i -e "s/^LANG/#LANG/" /etc/locale.conf
fi
localectl set-locale LANG=en_US.UTF-8
