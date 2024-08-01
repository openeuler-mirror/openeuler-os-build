#!/bin/bash
set -x
set -e

if [ ! -d "${OUTPUT_PATH}"  ]; then
    mkdir -p "${OUTPUT_PATH}" 
fi

set -e
export OPENEULER_CHROOT_PATH="/usr1/openeuler"
yum_conf="/home/config/repo_conf/repofile.conf"
hw_arch="$(uname -m)"
IMAGE_SIZE_MB=16384

ERROR()
{
    echo `date` - ERROR, $* | tee -a ${log_dir}/${builddate}.log
}

LOG()
{
    echo `date` - INFO, $* | tee -a ${log_dir}/${builddate}.log
}

UMOUNT_ALL()
{
    set +e
    echo "UMOUNT UMOUNT UMOUNT "
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

LOSETUP_D_IMG()
{
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

INSTALL_PACKAGES()
{
    for item in $(cat $1)
    do
        yum --installroot=${rootfs_dir}/ install -y $item -c "${yum_conf}"
        if [ $? == 0 ]; then
            LOG install $item.
        else
            ERROR can not install $item.
        fi
    done
}

prepare()
{
    if [ ! -d ${tmp_dir} ]; then
        mkdir -p ${tmp_dir}
    else
        rm -rf ${tmp_dir}/*
    fi
    
    img_file=${img_dir}/${RISCV64_QEMU_IMAGE_NAME}
    RAW_IMAGE_FILE=${img_file}.img

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

make_rootfs()
{
    LOG "make rootfs for ${yum_conf} begin..."
    if [[ -d ${rootfs_dir} ]]; then
        UMOUNT_ALL
        rm -rf ${rootfs_dir}
    fi
    # setup directory structure for chroot environment
    mkdir -p ${rootfs_dir}
    mkdir -p ${rootfs_dir}/var/lib/rpm
    rpm --root ${rootfs_dir} --initdb
    mkdir -p ${rootfs_dir}/etc/rpm
    chmod a+rX ${rootfs_dir}/etc/rpm
    echo "%_install_langs en_US" > ${rootfs_dir}/etc/rpm/macros.image-language-conf
    if [[ ! -d ${rootfs_dir}/etc/yum.repos.d ]]; then
        mkdir -p ${rootfs_dir}/etc/yum.repos.d
    fi
    yum --installroot=${OPENEULER_CHROOT_PATH}/ install parted -y -c "${yum_conf}"
    yum --installroot=${rootfs_dir}/ install ${os_release_name} -y -c "${yum_conf}"
    set +e
    INSTALL_PACKAGES $CONFIG_RPM_LIST
    cat ${rootfs_dir}/etc/systemd/timesyncd.conf | grep "^NTP=*"
    if [ $? -ne 0 ]; then
        sed -i -e '/^#NTP=/cNTP=0.cn.pool.ntp.org' ${rootfs_dir}/etc/systemd/timesyncd.conf
        sed -i 's/#FallbackNTP=/FallbackNTP=1.asia.pool.ntp.org 2.asia.pool.ntp.org /g' ${rootfs_dir}/etc/systemd/timesyncd.conf
    fi
    set -e
    # Run in chroot
    cp ${genimg_conf_dir}/chroot.sh ${rootfs_dir}/chroot.sh
    chmod +x ${rootfs_dir}/chroot.sh
    if [ ! -d ${rootfs_dir}/etc/rc.d/init.d ]; then
        mkdir -p ${rootfs_dir}/etc/rc.d/init.d
    fi
    cp ${genimg_conf_dir}/extend-root.sh ${rootfs_dir}/etc/rc.d/init.d/extend-root.sh
    # mount for in-chroot testing
    mount --bind /dev ${rootfs_dir}/dev
    mount -t proc /proc ${rootfs_dir}/proc
    mount -t sysfs /sys ${rootfs_dir}/sys
    set +e
    chroot ${rootfs_dir} /bin/bash -c "echo 'Y' | /chroot.sh"
    UMOUNT_ALL
    set -e
    rm ${rootfs_dir}/chroot.sh
    LOG "make rootfs for ${yum_conf} end."
}

make_img()
{
    LOG "make ${img_file} begin..."
    device=""
    LOSETUP_D_IMG
    losetup -D
    pwd
    yum install dosfstools parted rsync qemu-img -y -c "${yum_conf}"
    # Create empty image
    dd if=/dev/zero of=${RAW_IMAGE_FILE} bs=1MiB count=$IMAGE_SIZE_MB && sync
    
    # Partitioning
    parted ${RAW_IMAGE_FILE} mklabel gpt
    parted ${RAW_IMAGE_FILE} mkpart primary fat32 1M 513M
    parted ${RAW_IMAGE_FILE} -s set 1 boot
    parted ${RAW_IMAGE_FILE} -s set 1 esp on
    parted ${RAW_IMAGE_FILE} mkpart primary ext4 513M 100%
    device=`losetup -f --show -P ${RAW_IMAGE_FILE}`
    LOG "after losetup: ${device}"
    trap 'LOSETUP_D_IMG' EXIT
    LOG "image ${RAW_IMAGE_FILE} created and mounted as ${device}"
    # loopX=`kpartx -va ${device} | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
    # LOG "after kpartx: ${loopX}"
    kpartx -va ${device}
    loopX=${device##*\/}
    partprobe ${device}
    bootp=/dev/mapper/${loopX}p1
    rootp=/dev/mapper/${loopX}p2
    LOG "bootp: " ${bootp} "rootp: " ${rootp}

    # Creating filesystem and mounting
    mkfs.vfat -n boot ${bootp}
    mkfs.ext4 ${rootp}
    mkdir -p ${root_mnt} ${boot_mnt}
    mount -t vfat -o uid=root,gid=root,umask=0000 ${bootp} ${boot_mnt}
    mount -t ext4 ${rootp} ${root_mnt}

    # Generating fstab
    prefix_len=${#loopX}
    ### *hardcoded logic?* ###
    let prefix_len=prefix_len+13
    fstab_array=("" "" "" "")
    for line in `blkid | grep /dev/mapper/${loopX}p`
    do
        partuuid=${line#*PARTUUID=\"}
        fstab_array[${line:$prefix_len:1}]=${partuuid%%\"*}
    done
    echo "PARTUUID=${fstab_array[2]}  / ext4    defaults,noatime 0 0" > ${rootfs_dir}/etc/fstab
    echo "PARTUUID=${fstab_array[1]}  /boot vfat    defaults,noatime 0 0" >> ${rootfs_dir}/etc/fstab

    # locale
    cat ${rootfs_dir}/usr/share/zoneinfo/Asia/Shanghai > ${rootfs_dir}/etc/localtime
    # root password
    shadow_string=$(cat /home/config/riscv64_qemu_image/shadow.template)
    echo $shadow_string
    sed -i "s#root:.*#$shadow_string#g" ${rootfs_dir}/etc/fstab
    # hostname
    echo openeuler > ${rootfs_dir}/etc/hostname

    # Copying extlinux.conf, add a workaround for persistent kernel naming
    mkdir -p ${rootfs_dir}/boot/extlinux/
    cp ${genimg_conf_dir}/extlinux.conf ${rootfs_dir}/boot/extlinux/
    for item in $(ls ${rootfs_dir}/boot/vmlinuz*); do
        cp $item ${rootfs_dir}/boot/vmlinuz-openEuler;
    done
    cp -a ${rootfs_dir}/boot/* ${boot_mnt}/

    rm -rf ${rootfs_dir}/boot
    rsync -avHAXq ${rootfs_dir}/* ${root_mnt}
    sync
    sleep 10
    LOSETUP_D_IMG
    rm -rf ${rootfs_dir}
    losetup -D
    pushd ${img_dir}
    # Convert raw .img file to qcow2 file we actually want
    if [ -f ${RAW_IMAGE_FILE} ]; then
        qemu-img convert -f raw -O qcow2 ${RAW_IMAGE_FILE} ${img_file}
    else
        echo ":: NO img file here. make_img FAILED"
        return 1
    fi
    if [ -f ${img_file} ]; then
        sha256sum $(basename ${img_file}) > ${img_file}.sha256sum
        xz -T0 --memlimit=90% -z -c ${img_file} > ${img_file}.xz
        sha256sum $(basename ${img_file}.xz) > ${img_file}.xz.sha256sum
        LOG "made sum files for ${img_file}"
    else
        echo ":: NO converted qcow2 file here. make_img FAILED"
        return 1
    fi
    popd
    LOG "write ${img_file} done."
    LOG "make ${img_file} end."
    sshscp "${img_file} ${img_file}.sha256sum ${img_file}.xz ${img_file}.xz.sha256sum " "${RELEASE_DIR}"
}

function make_riscv64_qemu_image()
{
    chroot_run "cd /home; bash -x make_version.sh make_riscv64_qemu_image_inchroot"
}

function make_riscv64_qemu_image_inchroot()
{
    echo 'make riscv64 qemu image'
    if [ "$EUID" -ne 0 ]; then
        echo `date` - ERROR, Please run as root!
        exit
    fi

    OS_NAME=openEuler

    workdir=$(cd $(dirname $0);pwd)
    if [ "x${workdir}" == "x/" ]; then
        workdir=/rv64_qemu_output
    else
        workdir=${workdir}/rv64_qemu_output
    fi

    tmp_dir=${workdir}/tmp
    log_dir=${workdir}/log
    rootfs_dir=${workdir}/rootfs
    root_mnt=${workdir}/root
    boot_mnt=${workdir}/boot
    genimg_conf_dir=/home/config/riscv64_qemu_image
    CONFIG_RPM_LIST=${genimg_conf_dir}/rpmlist

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
    RELEASE_DIR="${release_dir}/riscv64_qemu_img/"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"

    trap 'UMOUNT_ALL' EXIT
    UMOUNT_ALL
    prepare
    IFS=$'\n'
    make_rootfs
    make_img
}
