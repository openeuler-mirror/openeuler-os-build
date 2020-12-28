#!/bin/bash
# Author: liusirui
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

cd "$(dirname "$0")"
mkdir -p tmp_fs
mkdir -p old_fs  new_fs
mount LiveOS/squashfs.img old_fs
cp old_fs/*  new_fs/ -rf
mount new_fs/LiveOS/rootfs.img  tmp_fs
cp ./make_livecd_bep.sh ./tmp_fs/
cp ./bep_clean.conf ./tmp_fs/
cp ./bep_remove.conf ./tmp_fs/
chroot tmp_fs /make_livecd_bep.sh
rm -f ./tmp_fs/make_livecd_bep.sh
rm -f ./tmp_fs/bep_clean.conf
rm -f ./tmp_fs/bep_remove.conf
umount tmp_fs
mksquashfs new_fs/ squashfs.img -comp xz
umount old_fs
mv -f squashfs.img  LiveOS/squashfs.img
rm -rf old_fs new_fs tmp_fs
