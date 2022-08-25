#!/bin/bash
# Author: xudengfeng
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

echo "Configure image: [${kiwi_iname}]..."

euler_version=${kiwi_iname%%-*}
compile_time=${kiwi_iname#*-}
echo "eulerversion=${euler_version}" > /etc/EulerLinux.conf
echo "compiletime=${compile_time}"  >> /etc/EulerLinux.conf

set +e
# Security enforce
export EULEROS_SECURITY=0
# TODO remove
/usr/sbin/security-tool.sh -d / -c /etc/openEuler_security/security.conf -u /etc/openEuler_security/usr-security.conf -l /var/log/openEuler-security.log -s

[ -n /boot ] && rm -rf /boot

#a few systemd things
[ -n /etc/machine-id ] && rm -rf /etc/machine-id
[ -n /usr/lib/systemd/system/multi-user.target.wants/getty.target ] && rm -rf /usr/lib/systemd/system/multi-user.target.wants/getty.target
[ -n /usr/lib/systemd/system/multi-user.target.wants/systemd-logind.service ] && rm -rf /usr/lib/systemd/system/multi-user.target.wants/systemd-logind.service

#locales
#strip most of the languages from the archive.
localedef --delete-from-archive $(localedef --list-archive | grep -v -i ^en_US | xargs )
#prep the archive template
mv /usr/lib/locale/locale-archive  /usr/lib/locale/locale-archive.tmpl
#rebuild archive
/usr/sbin/build-locale-archive
#empty the template
:>/usr/lib/locale/locale-archive.tmpl

cd /usr/share/i18n/charmaps;rm -rf $(ls | grep -v ^UTF-8.gz$ | xargs )
cd /usr/share/i18n/locales;rm -rf $(ls | grep -v ^en_US$ | xargs )
rm -rf /usr/share/locale/*

#Generate installtime file record
#/bin/date +%Y%m%d_%H%M > /etc/BUILDTIME

#man pages and documentation
#find /usr/share/{man,doc,info} -type f | xargs /bin/rm
rm -rf /usr/share/{man,doc,info,mime}

#sln
rm -f /sbin/sln

#ldconfig
[ -n /etc/ld.so.cache ] && rm -rf /etc/ld.so.cache
[ -d /var/cache/ldconfig ] && rm -rf /var/cache/ldconfig/*
[ -d /var/cache/yum ] && rm -rf /var/cache/yum/*

[ -n /var/lib/yum ] && rm -rf /var/lib/yum
[ -n /var/lib/systemd/catalog/database ] && rm -rf /var/lib/systemd/catalog/database
[ -d /var/log ] && rm -rf /var/log/*.log
[ -d /var/lib/dnf ] && rm -rf /var/lib/dnf/*
[ -d /var/lib/systemd ] && rm -rf /var/lib/systemd/random-seed
set -e
[ -d /var/lib/rpm ] && rm -rf /var/lib/rpm/__db.*
rm -f /etc/default/useradd.rpmsave /etc/login.defs.rpmsave
# openEuler_chroot will change /etc/hosts in host, we should change it back with hosts.rpmnew
# mv /etc/hosts.rpmnew /etc/hosts

exit
