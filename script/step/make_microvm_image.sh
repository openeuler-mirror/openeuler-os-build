#!/bin/bash

set -e
arch="$(uname -m)"
yum_conf="${BUILD_SCRIPT_DIR}/config/repo_conf/obs-repo.conf"

ERROR(){
    echo `date` - ERROR, $* | tee -a ${log_dir}/${builddate}.log
}

LOG(){
    echo `date` - INFO, $* | tee -a ${log_dir}/${builddate}.log
}

prepare_rootfs(){
    if [ ! -d ${tmp_dir} ]; then
        mkdir -p ${tmp_dir}
    else
        rm -rf ${tmp_dir}/*
    fi

    img_file=${img_dir}/${MICROVM_IMAGE_NAME}

    if [ ! -d ${log_dir} ]; then
        mkdir -p ${log_dir}
    fi
    LOG "prepare rootfs begin..."

    if [ -d ${rootfs_dir} ]; then
        rm -rf ${rootfs_dir}
    fi
    if [ ! -d ${img_dir} ]; then
        mkdir -p ${img_dir}
    fi

    yum clean all -c "${yum_conf}"
    yum makecache -c "${yum_conf}"

    set +e
    os_release_name=${OS_NAME}-release
    set -e
    LOG "prepare rootfs end."
}

prepare_kernel(){
    if [ ! -d ${tmp_dir} ]; then
        mkdir -p ${tmp_dir}
    else
        rm -rf ${tmp_dir}/*
    fi

    kernel_file=${img_dir}/${MICROVM_KERNEL_NAME}
    std_kernel_file=${img_dir}/${STDANDARD_VM_KERNEL_NAME}

    LOG "prepare vmlinux kernel begin..."
    yum clean all -c "${yum_conf}"
    yum makecache -c "${yum_conf}"

    yum install make gcc bison flex openssl-devel elfutils-devel bc -y -c "${yum_conf}"

    LOG "prepare vmlinux kernel end."
}

make_micro_rootfs(){
    LOG "make rootfs for micro_vm begin..."
    if [[ -d ${rootfs_dir} ]]; then
        UMOUNT_ALL
        rm -rf ${rootfs_dir}
    fi
    mkdir -p ${rootfs_dir}

    dnf -y --installroot=${rootfs_dir} --noplugins --config="${yum_conf}" install systemd yum iproute iputils

    pushd ${rootfs_dir}
    rm -rf ./var/cache/ ./var/lib ./var/log ./var/tmp
    touch etc/resolv.conf
    sed -i 's|root:\*|root:$6$o4rTi3d/.hh6JUYC$ClnCxd2mAQHlt0UloC4ystQg0CiuSVyhXz0sP1mDCNCgWV0rBwegwJ/bCWfjN4WxbahDa7F9U3c6/vFaNgsvX/|' etc/shadow
    popd

    LOG "make rootfs for micro_vm end."
}

make_micro_img(){
    LOG "make ${img_file} begin..."
    device=""
    size=`du -sh --block-size=1MiB ${rootfs_dir} | cut -f 1 | xargs`
    size=$(($size+500))
    pwd
    dd if=/dev/zero of=${img_file} bs=1MiB count=$size && sync
    mkfs.ext4 ${img_file}
    mkdir -p ${root_mnt}
    mount ${img_file} ${root_mnt}
    LOG "image ${img_file} created and mounted as ${root_mnt}"

    if [ -f ${tmp_dir}/rootfs.tar ]; then
        rm ${tmp_dir}/rootfs.tar
    fi

    pushd ${rootfs_dir}
    tar cpf ${tmp_dir}/rootfs.tar .
    popd
    pushd ${root_mnt}
    tar xpf ${tmp_dir}/rootfs.tar -C .
    popd
    sync
    sleep 10
    umount ${root_mnt}
    rm ${tmp_dir}/rootfs.tar
    rm -rf ${rootfs_dir}
    pushd ${img_dir}
    if [ -f ${img_file} ]; then
        xz -T 20 -z -c ${img_file} > ${img_file}.xz
        sha256sum $(basename ${img_file}.xz) > ${img_file}.xz.sha256sum
        rm -f ${img_file}
        LOG "made sum files for ${img_file}"
    fi
    popd
    LOG "write ${img_file} done."
    LOG "make ${img_file} end."
    sshscp "${img_file}.xz ${img_file}.xz.sha256sum " "${RELEASE_DIR}"
}

make_micro_kernel(){
    LOG "make ${kernel_file} begin..."

    yum install kernel-source -y -c "${yum_conf}"
    kernel_src_name=$(rpm -qa | grep kernel-source)
    kernel_src_version=${kernel_src_name: 13}
    kernel_version=$(rpm -q kernel-source --qf %{VERSION})
    kernel_main_version=${kernel_version%.*}

    pushd /usr/src/linux${kernel_src_version}
    kernel_config="kernel_config_${kernel_main_version}_${arch}"
    cp ${microvm_dir}/${kernel_config} .config
    if [ ${arch} == "x86_64" ]; then
        make ARCH=x86_64 -j8
    elif [ ${arch} == "aarch64" ]; then
        make ARCH=arm64 -j8
    else
        LOG "${arch} is not supported yet."
        return 0
    fi

    objcopy -O binary vmlinux ${kernel_file}
    popd

    pushd ${img_dir}
    if [ -f ${kernel_file} ]; then
        sha256sum $(basename ${kernel_file}) > ${kernel_file}.sha256sum
        LOG "made sum file for ${kernel_file}"
    fi
    popd

    LOG "make ${kernel_file} end."
    sshscp "${kernel_file} ${kernel_file}.sha256sum " "${RELEASE_DIR}"
}

make_standard_kernel(){
    LOG "make ${std_kernel_file} begin..."

    yum install kernel-source -y -c "${yum_conf}"
    kernel_src_name=$(rpm -qa | grep kernel-source)
    kernel_src_version=${kernel_src_name: 13}
    kernel_version=$(rpm -q kernel-source --qf %{VERSION})
    kernel_main_version=${kernel_version%.*}

    pushd /usr/src/linux${kernel_src_version}
    kernel_config="kernel_config_${kernel_main_version}_${arch}"
    cp ${standard_vm_dir}/${kernel_config} .config
    if [ ${arch} == "x86_64" ]; then
        std_kernel_file=${std_kernel_file}z
        make ARCH=x86_64 -j8
        make bzImage -j8
        mv arch/x86/boot/bzImage ${std_kernel_file}
    elif [ ${arch} == "aarch64" ]; then
        std_kernel_file=${std_kernel_file}.bin
        make ARCH=arm64 -j8
        objcopy -O binary vmlinux ${std_kernel_file}
    else
        LOG "${arch} is not supported yet."
        return 0
    fi

    popd

    pushd ${img_dir}
    if [ -f ${std_kernel_file} ]; then
        sha256sum $(basename ${std_kernel_file}) > ${std_kernel_file}.sha256sum
        LOG "made sum file for ${std_kernel_file}"
    fi
    popd

    LOG "make ${std_kernel_file} end."
    sshscp "${std_kernel_file} ${std_kernel_file}.sha256sum " "${RELEASE_DIR}"
}

function make_microvm_image()
{
    chroot_run "cd /home; bash -x make_version.sh make_microvm_image_inchroot"
}

function make_microvm_image_inchroot()
{
    echo 'make microvm image'
    if [ "$EUID" -ne 0 ]; then
        echo `date` - ERROR, Please run as root!
        exit
    fi

    OS_NAME=openEuler

    workdir=$(cd $(dirname $0);pwd)
    if [ "x${workdir}" == "x/" ]; then
        workdir=/microvm_output
    else
        workdir=${workdir}/microvm_output
    fi

    tmp_dir=${workdir}/tmp
    log_dir=${workdir}/log
    rootfs_dir=${workdir}/rootfs
    root_mnt=${workdir}/root
    microvm_dir=${BUILD_SCRIPT_DIR}/config/microvm_image
    standard_vm_dir=${BUILD_SCRIPT_DIR}/config/standard_vm_image

    builddate=$(date +%Y%m%d)
    get_version
    release_dir=$(get_release_dir)
    version_time="${release_dir#${HTTP_DIR}}"
    version_time=${version_time##*/}
    img_dir="${WORK_DIR}image"
    if [ -d "${img_dir}" ]; then
        rm -rf "${img_dir}"
    fi
    mkdir -p "${img_dir}"

    RELEASE_DIR="${release_dir}/stratovirt_img/${arch}"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"

    prepare_rootfs
    make_micro_rootfs
    make_micro_img

    prepare_kernel
    make_micro_kernel

    prepare_kernel
    make_standard_kernel
}
