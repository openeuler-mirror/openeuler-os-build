#!/bin/bash

set -e
yum_conf="${BUILD_SCRIPT_DIR}/config/repo_conf/obs-repo.conf"
dogsheng_arch="$(uname -m)"

ERROR(){
    echo `date` - ERROR, $* | tee -a ${log_dir}/${builddate}.log
}

LOG(){
    echo `date` - INFO, $* | tee -a ${log_dir}/${builddate}.log
}

UMOUNT_ALL(){
    set +e
    if grep -q "${rootfs_dir}/dev " /proc/mounts ; then
        umount -l ${rootfs_dir}/dev
    fi
    if grep -q "${rootfs_dir}/proc " /proc/mounts ; then
        umount -l ${rootfs_dir}/proc
    fi
    if grep -q "${rootfs_dir}/sys " /proc/mounts ; then
        umount -l ${rootfs_dir}/sys
    fi
    set -e
}

LOSETUP_D_IMG(){
    set +e
    if [ -d ${root_mnt} ]; then
        if grep -q "${root_mnt} " /proc/mounts ; then
            umount ${root_mnt}
        fi
    fi
    if [ -d ${boot_mnt} ]; then
        if grep -q "${boot_mnt} " /proc/mounts ; then
            umount ${boot_mnt}
        fi
    fi
    if [ "x$device" != "x" ]; then
        kpartx -d ${device}
        losetup -d ${device}
        device=""
    fi
    if [ -d ${root_mnt} ]; then
        rm -rf ${root_mnt}
    fi
    if [ -d ${boot_mnt} ]; then
        rm -rf ${boot_mnt}
    fi
    set -e
}

INSTALL_PACKAGES(){
    for item in $(cat $1)
    do
        # dnf --installroot=${rootfs_dir}/ install -y $item
        yum --installroot=${rootfs_dir}/ install -y $item -c "${yum_conf}"
        if [ $? == 0 ]; then
            LOG install $item.
        else
            ERROR can not install $item.
        fi
    done
}

prepare(){
    if [ ! -f /usr/share/perl5/vendor_perl/Env.pm  ]; then
        cp "${BUILD_SCRIPT_DIR}/config/docker_image/Env.pm" /usr/share/perl5/vendor_perl/
    fi

    if [ ! -d ${tmp_dir} ]; then
        mkdir -p ${tmp_dir}
    else
        rm -rf ${tmp_dir}/*
    fi
    
    img_file=${img_dir}/${RASPI_IMAGE_NAME}

    if [ ! -d ${log_dir} ]; then
        mkdir -p ${log_dir}
    fi
    LOG "prepare begin..."
    yum clean all -c "${yum_conf}"
    yum makecache -c "${yum_conf}"

    if [ -d ${rootfs_dir} ]; then
        rm -rf ${rootfs_dir}
    fi
    if [ ! -d ${img_dir} ]; then
        mkdir -p ${img_dir}
    fi

    set +e
    os_release_name=${OS_NAME}-release 
    set -e
    LOG "prepare end."
}

make_rootfs(){
    LOG "make rootfs for ${yum_conf} begin..."
    if [[ -d ${rootfs_dir} ]]; then
        UMOUNT_ALL
        rm -rf ${rootfs_dir}
    fi
    mkdir -p ${rootfs_dir}
    mkdir -p ${rootfs_dir}/var/lib/rpm
    rpm --root ${rootfs_dir} --initdb
    #rpm -ivh --nodeps --root ${rootfs_dir}/ ${os_release_name}
    mkdir -p ${rootfs_dir}/etc/rpm
    chmod a+rX ${rootfs_dir}/etc/rpm
    echo "%_install_langs en_US" > ${rootfs_dir}/etc/rpm/macros.image-language-conf
    if [[ ! -d ${rootfs_dir}/etc/yum.repos.d ]]; then
        mkdir -p ${rootfs_dir}/etc/yum.repos.d
    fi
    # cp ${yum_conf} ${rootfs_dir}/etc/yum.repos.d/tmp.repo
    # dnf --installroot=${rootfs_dir}/ install dnf --nogpgcheck -y # --repofrompath=tmp,${rootfs_dir}/etc/yum.repos.d/tmp.repo --disablerepo="*"
    #dnf --installroot=${rootfs_dir}/ makecache
    #yum --installroot=${rootfs_dir}/ install makecache -y -c "${yum_conf}"
    yum --installroot=${OPENEULER_CHROOT_PATH}/ install parted -y -c "${yum_conf}"
    yum --installroot=${rootfs_dir}/ install ${os_release_name} -y -c "${yum_conf}"
    # dnf --installroot=${rootfs_dir}/ install -y alsa-utils wpa_supplicant vim net-tools iproute iputils NetworkManager openssh-server passwd hostname ntp bluez pulseaudio-module-bluetooth
    # dnf --installroot=${rootfs_dir}/ install -y raspberrypi-kernel raspberrypi-firmware openEuler-repos
    set +e
    INSTALL_PACKAGES $CONFIG_RPM_LIST
    cat ${rootfs_dir}/etc/systemd/timesyncd.conf | grep "^NTP*"
    if [ $? -ne 0 ]; then
        sed -i 's/#NTP=/NTP=0.cn.pool.ntp.org/g' ${rootfs_dir}/etc/systemd/timesyncd.conf
        sed -i 's/#FallbackNTP=/FallbackNTP=1.asia.pool.ntp.org 2.asia.pool.ntp.org/g' ${rootfs_dir}/etc/systemd/timesyncd.conf
    fi
    set -e
    #cp ${euler_dir}/hosts ${rootfs_dir}/etc/hosts
    #if [ ! -d $rootfs_dir/etc/sysconfig/network-scripts ]; then
    #    mkdir -p $rootfs_dir/etc/sysconfig/network-scripts
    #fi
    cp ${euler_dir}/ifcfg-eth0 $rootfs_dir/etc/sysconfig/network-scripts/ifcfg-eth0
    mkdir -p ${rootfs_dir}/lib/udev/rules.d
    if [ ! -d ${rootfs_dir}/usr/share/licenses/raspi ]; then
        mkdir -p ${rootfs_dir}/usr/share/licenses/raspi
    fi
    cp ${euler_dir}/*.rules ${rootfs_dir}/lib/udev/rules.d/
    cp ${euler_dir}/LICENCE.* ${rootfs_dir}/usr/share/licenses/raspi/
    cp ${euler_dir}/chroot.sh ${rootfs_dir}/chroot.sh
    chmod +x ${rootfs_dir}/chroot.sh
    if [ ! -d ${rootfs_dir}/etc/rc.d/init.d ]; then
        mkdir -p ${rootfs_dir}/etc/rc.d/init.d
    fi
    cp ${euler_dir}/extend-root.sh ${rootfs_dir}/etc/rc.d/init.d/extend-root.sh
    mount --bind /dev ${rootfs_dir}/dev
    mount -t proc /proc ${rootfs_dir}/proc
    mount -t sysfs /sys ${rootfs_dir}/sys
    chroot ${rootfs_dir} /bin/bash -c "echo 'Y' | /chroot.sh"
    UMOUNT_ALL
    # rm ${rootfs_dir}/etc/yum.repos.d/tmp.repo
    rm ${rootfs_dir}/chroot.sh
    LOG "make rootfs for ${yum_conf} end."
}

make_img(){
    LOG "make ${img_file} begin..."
    device=""
    LOSETUP_D_IMG
    size=`du -sh --block-size=1MiB ${rootfs_dir} | cut -f 1 | xargs`
    size=$(($size+1100))
    losetup -D
    pwd
    yum install dosfstools parted rsync -y -c "${yum_conf}"
    dd if=/dev/zero of=${img_file} bs=1MiB count=$size && sync
    parted ${img_file} mklabel msdos mkpart primary fat32 8192s 593919s
    parted ${img_file} -s set 1 boot
    parted ${img_file} mkpart primary linux-swap 593920s 1593343s 
    parted ${img_file} mkpart primary ext4 1593344s 100%
    device=`losetup -f --show -P ${img_file}`
    LOG "after losetup: ${device}"
    trap 'LOSETUP_D_IMG' EXIT
    LOG "image ${img_file} created and mounted as ${device}"
    # loopX=`kpartx -va ${device} | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
    # LOG "after kpartx: ${loopX}"
    kpartx -va ${device}
    loopX=${device##*\/}
    partprobe ${device}
    bootp=/dev/mapper/${loopX}p1
    swapp=/dev/mapper/${loopX}p2
    rootp=/dev/mapper/${loopX}p3
    LOG "bootp: " ${bootp} "rootp: " ${rootp}
    mkfs.vfat -n boot ${bootp}
    mkswap ${swapp} --pagesize 4096
    mkfs.ext4 ${rootp}
    mkdir -p ${root_mnt} ${boot_mnt}
    mount -t vfat -o uid=root,gid=root,umask=0000 ${bootp} ${boot_mnt}
    mount -t ext4 ${rootp} ${root_mnt}
    fstab_array=("" "" "" "")
    for line in `blkid | grep /dev/mapper/${loopX}p`
    do
        partuuid=${line#*PARTUUID=\"}
        fstab_array[${line:18:1}]=${partuuid%%\"*}
    done
    echo "PARTUUID=${fstab_array[3]}  / ext4    defaults,noatime 0 0" > ${rootfs_dir}/etc/fstab
    echo "PARTUUID=${fstab_array[1]}  /boot vfat    defaults,noatime 0 0" >> ${rootfs_dir}/etc/fstab
    echo "PARTUUID=${fstab_array[2]}  swap swap    defaults,noatime 0 0" >> ${rootfs_dir}/etc/fstab

    cp -a ${rootfs_dir}/boot/* ${boot_mnt}/
    cp ${euler_dir}/config.txt ${boot_mnt}/
    echo "console=serial0,115200 console=tty1 root=PARTUUID=${fstab_array[3]} rootfstype=ext4 elevator=deadline rootwait" > ${boot_mnt}/cmdline.txt

    rm -rf ${rootfs_dir}/boot
    rsync -avHAXq ${rootfs_dir}/* ${root_mnt}
    sync
    sleep 10
    LOSETUP_D_IMG
    rm -rf ${rootfs_dir}
    losetup -D
    pushd ${img_dir}
    if [ -f ${img_file} ]; then
        sha256sum $(basename ${img_file}) > ${img_file}.sha256sum
        xz -T 20 -z -c ${img_file} > ${img_file}.xz
        sha256sum $(basename ${img_file}.xz) > ${img_file}.xz.sha256sum
        LOG "made sum files for ${img_file}"
    fi
    popd
    LOG "write ${img_file} done."
    LOG "make ${img_file} end."
    sshscp "${img_file} ${img_file}.sha256sum ${img_file}.xz ${img_file}.xz.sha256sum " "${RELEASE_DIR}"
}

function make_raspi_image()
{
    chroot_run "cd /home; bash -x make_version.sh make_raspi_image_inchroot"
    #make_raspi_image_inchroot    #make_raspi_image_inchroot
}

function make_raspi_image_inchroot()
{
    echo 'make raspi image'
    if [ "$EUID" -ne 0 ]; then
        echo `date` - ERROR, Please run as root!
        exit
    fi

    OS_NAME=openEuler

    workdir=$(cd $(dirname $0);pwd)
    if [ "x${workdir}" == "x/" ]; then
        workdir=/raspi_output
    else
        workdir=${workdir}/raspi_output
    fi

    tmp_dir=${workdir}/tmp
    log_dir=${workdir}/log
    rootfs_dir=${workdir}/rootfs
    root_mnt=${workdir}/root
    boot_mnt=${workdir}/boot
    euler_dir=${BUILD_SCRIPT_DIR}/config/raspi_image
    CONFIG_RPM_LIST=${euler_dir}/rpmlist

    builddate=$(date +%Y%m%d)
    get_version
    release_dir=$(get_release_dir)
    version_time="${release_dir#${HTTP_DIR}}"
    version_time=${version_time##*/}
    repo_dir="${WORK_DIR}repository"
    img_dir="${WORK_DIR}image"
    cfg_dir="${WORK_DIR}config"
    if [ -d "${img_dir}"  ]; then
        rm -rf "${img_dir}"
    fi
    mkdir -p "${img_dir}"
    if [ -d "${repo_dir}"  ]; then
        rm -rf "${repo_dir}"
    fi
    mkdir -p "${repo_dir}"
    if [ -d "${cfg_dir}"  ]; then
        rm -rf "${cfg_dir}"
    fi
    mkdir -p "${cfg_dir}"
    RELEASE_DIR="${release_dir}/raspi_img/"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"

    trap 'UMOUNT_ALL' EXIT
    UMOUNT_ALL
    prepare
    IFS=$'\n'
    make_rootfs
    make_img
}
