#!/bin/bash

set -e
arch="$(uname -m)"
kernel_config="kernel_config_5.10_${arch}"
yum_conf="${BUILD_SCRIPT_DIR}/config/repo_conf/obs-repo.conf"

ERROR(){
    echo `date` - ERROR, $* | tee -a ${log_dir}/${builddate}.log
}

LOG(){
    echo `date` - INFO, $* | tee -a ${log_dir}/${builddate}.log
}

CP_CHROOT_PACKAGES(){
    set +e
    mkdir -m 0755 -p ${rootfs_dir}${2}
    pushd ${2}
    cat ${1} | while read file
    do
        if [ "${file:0:1}" != "#" ]; then
            cp -rd --path $file ${rootfs_dir}${2}
        fi
    done
    popd
    set -e
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
    yum install iproute iputils -y -c "${yum_conf}"

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

    LOG "prepare vmlinux kernel begin..."
    yum clean all -c "${yum_conf}"
    yum makecache -c "${yum_conf}"

    yum install make gcc bison flex openssl-devel elfutils-devel bc iproute iputils -y -c "${yum_conf}"

    LOG "prepare vmlinux kernel end."
}

make_micro_rootfs(){
    LOG "make rootfs for micro_vm begin..."
    if [[ -d ${rootfs_dir} ]]; then
        UMOUNT_ALL
        rm -rf ${rootfs_dir}
    fi
    mkdir -p ${rootfs_dir}

    for dir in dev home mnt proc run srv sys boot etc media opt root tmp var usr
    do
        mkdir -m 0755 -p ${rootfs_dir}/${dir}
    done

    CP_CHROOT_PACKAGES ${package_dir}/bin.list /usr/bin
    CP_CHROOT_PACKAGES ${package_dir}/include.list /usr/include
    CP_CHROOT_PACKAGES ${package_dir}/lib.list /usr/lib
    CP_CHROOT_PACKAGES ${package_dir}/lib64.list /usr/lib64
    CP_CHROOT_PACKAGES ${package_dir}/sbin.list /usr/sbin
    CP_CHROOT_PACKAGES ${package_dir}/share.list /usr/share
    CP_CHROOT_PACKAGES ${package_dir}/systemd.list /usr/lib/systemd
    rm -rf ${rootfs_dir}/usr/lib64/python3.*/test
    cp -d /lib /lib64 /sbin /bin ${rootfs_dir}
    cp -r /etc/profile* /etc/bashrc /etc/ssh ${rootfs_dir}/etc
    cp -r ${microvm_dir}/passwd ${microvm_dir}/shadow ${microvm_dir}/pam.d ${rootfs_dir}/etc

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

make_micro_kernel(){
    LOG "make ${kernel_file} begin..."

    yum install kernel-source -y -c "${yum_conf}"
    kernel_src_name=$(rpm -qa | grep kernel-source)
    kernel_src_version=${kernel_src_name: 13}

    pushd /usr/src/linux${kernel_src_version}
    cp ${microvm_dir}/${kernel_config} .config
    if [ ${arch} == "x86_64" ]; then
        make ARCH=x86_64
    elif [ ${arch} == "aarch64" ]; then
        make ARCH=arm64
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
    package_dir=${microvm_dir}/source.list

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

    RELEASE_DIR="${release_dir}/microvm_img/${arch}"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"

    prepare_rootfs
    make_micro_rootfs
    make_micro_img

    prepare_kernel
    make_micro_kernel
}
