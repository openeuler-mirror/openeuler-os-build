#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

source "${BUILD_SCRIPT_DIR}"/custom/custom_common.sh

######################
# make compile env native
# Globals:
# Arguments:
# Returns:
######################
function make_compile_env_native()
{
    local build_script_dir=$(pwd)
    TIME=""
    while getopts "t:v:c" arg
    do
        case "${arg}" in
            v)
                export NATIVE_ENV_VERSION="${OPTARG}"
                ;;
            t)
                TIME="${OPTARG}"
                ;;
        esac
    done

    cd "${build_script_dir}"
    COMPILE_ENV="Euler_compile_env"
    YUM_CONF="${build_script_dir}/compile_env_${ARCH}/yum.conf"
    REPO_DIR="${build_script_dir}/compile_env_${ARCH}/yum.repos.d"
    KERNEL_OBS="http://${OBS_SERVER_IP}:82/EulerOS:/V3R1:/GENERAL:/Kernel/standard_${ARCH}/src/"
    KERNEL_VERSION="4.19.*"
    KERNEL="kernel-${KERNEL_VERSION}-*.src.rpm"
    KERNEL_DEBUG_OBS="http://${OBS_SERVER_IP}:82/EulerOS:/V3R1:/GENERAL:/Kernel/standard_${ARCH}/${ARCH}/"
    KERNEL_DEBUG="kernel-debuginfo-${KERNEL_VERSION}-*.${ARCH}.rpm"
    rpmlist="${build_script_dir}/compile_env_${ARCH}/rpm.lst"

    [[ -d "${REPO_ROOT}" ]] || mkdir -p "${REPO_ROOT}"
    [ -d "${REPO_ROOT}/yum.repos.d" ] && rm -rf "${REPO_ROOT}/yum.repos.d"
    cp -r "${REPO_DIR}" "${REPO_ROOT}"

    #clean compile env folder first
    local compile_env_rpm_lst=""
    rm -rf "${build_script_dir}/${COMPILE_ENV}"
    while read line
    do
        if [ -z "${line}" ]; then continue;fi

        compile_env_rpm_lst="${compile_env_rpm_lst} ${line}"
    done < "${rpmlist}"

    yum clean all -c "${YUM_CONF}"
    yum install -c "${YUM_CONF}" --installroot="${build_script_dir}/${COMPILE_ENV}" -y $(echo "$compile_env_rpm_lst") -x glibc32
    #eulerversion=${RELEASEDIR##*/}
    if [ -z "${TIME}" ]; then TIME="$(date +%Y-%m-%d-%H-%M-%S)";fi
    eulerversion="${NATIVE_ENV_VERSION}-${TIME}"
    echo "version=${eulerversion}" > "${build_script_dir}/${COMPILE_ENV}/etc/EulerLinux.conf"
    echo "mount -t proc proc /proc 2>/dev/null" >> "${build_script_dir}/${COMPILE_ENV}/etc/profile"
    echo "export PS1='[EulerOS_compile_env \w]\$ '" >> "${build_script_dir}/${COMPILE_ENV}/etc/profile"
    #二进制差异消除
    echo "4e509de2-807a-4009-8c85-f935b160bcd6" > "${build_script_dir}/${COMPILE_ENV}/usr/share/fonts/.uuid"
    echo "64e10f9d-a8a5-4a53-90a1-2802c1cfb230" > "${build_script_dir}/${COMPILE_ENV}/usr/share/fonts/wqy-microhei/.uuid"
    echo "ba9afe57ebaaeba9521ee80847cb2889" > "${build_script_dir}/${COMPILE_ENV}/etc/brlapi.key"
    echo "7172c5f77a97430abeb6e6f2e0a75cd6" > "${build_script_dir}/${COMPILE_ENV}/etc/machine-id"
    echo "/usr/lib" >> "${build_script_dir}/${COMPILE_ENV}/etc/ld.so.conf";echo "/usr/lib64" >> "${build_script_dir}/${COMPILE_ENV}/etc/ld.so.conf";echo "ldconfig" >> "${build_script_dir}/${COMPILE_ENV}/etc/profile";echo "unset PROMPT_COMMAND" >> "${build_script_dir}/${COMPILE_ENV}/etc/profile";echo "update-ca-trust" >> "${build_script_dir}/${COMPILE_ENV}/etc/profile"
    rm -rf "${build_script_dir}/${COMPILE_ENV}"/var/log/*;rm -rf "${build_script_dir}/${COMPILE_ENV}"/var/cache/yum/*;rm -rf "${build_script_dir}/${COMPILE_ENV}"/var/cache/ldconfig/aux-cache;rm -rf "${build_script_dir}/${COMPILE_ENV}"/etc/ld.so.cache;rm -rf "${build_script_dir}/${COMPILE_ENV}"/etc/pki/ca-trust/extracted/java/cacerts;rm -rf "${build_script_dir}/${COMPILE_ENV}"/var/lib/yum/;rm -rf "${build_script_dir}/${COMPILE_ENV}"/var/lib/dnf/*;rm -rf "${build_script_dir}/${COMPILE_ENV}"/var/lib/systemd/catalog/database;rm -rf "${build_script_dir}/${COMPILE_ENV}"/usr/lib/fontconfig/cache/*.cache-7

    wget -q -c -r -nd -np -k -L -p -A "${KERNEL_DEBUG}" "${KERNEL_DEBUG_OBS}"
    KERNEL_DEBUG=$(ls $(echo kernel-debuginfo-"${KERNEL_VERSION}"-*."${ARCH}".rpm))
    rm -rf k_debug; mkdir k_debug; mv "${KERNEL_DEBUG}" k_debug/; cd k_debug; rpm2cpio "${KERNEL_DEBUG}" | cpio -di; cd ../;
    cp k_debug/usr/lib/debug/lib/modules/*/vmlinux "${build_script_dir}/${COMPILE_ENV}/opt/patch_workspace/";rm -r k_debug;

    pushd "${build_script_dir}/${COMPILE_ENV}/usr/src/kernels/";build_dir_name="$(ls -d 4.19*)";popd;

    wget -q -c -r -nd -np -k -L -p -A "${KERNEL}" "${KERNEL_OBS}"
    kernel_pkg=$(ls $(echo "${KERNEL}") | head -n 1)
    if [ -z "${kernel_pkg}" ]; then log_error "Cannot find kernel source rpm";fi

    mkdir -p "${build_script_dir}/${COMPILE_ENV}/usr/src/kernels/tmp"
    mv "${kernel_pkg}" "${build_script_dir}/${COMPILE_ENV}/usr/src/kernels/tmp"

    pushd "${build_script_dir}/${COMPILE_ENV}/usr/src/kernels/tmp"
    rpm2cpio "${kernel_pkg}" | cpio -di
    KERNEL_TAR_VER="linux-4.19.13"       # kernel_pkg=kernel-4.19.18-vhulk1811.2.0.h81.src.rpm
    mkdir "./${KERNEL_TAR_VER}";tar -xf "${KERNEL_TAR_VER}".tar.gz;tar -xf patches.tar.bz2;
    pushd "${KERNEL_TAR_VER}"
    ../apply-patches ../series.conf ../

    #copy kernel config
    if [ "${ARCH}" == "aarch64" ];then
        cp arch/arm64/configs/euleros_defconfig .config
    elif [ "${ARCH}" == "x86_64" ]; then
        cp arch/x86/configs/euleros_defconfig .config
    fi
    #copy for sign modules
    #cp ../signing_key.* .
    cp ../sign-modules .;cp ../x509.genkey .;

    #copy for kabi check
    #cp ../check-kabi .
    #cp ../Module.kabi_x86_64 .
    #cp ../kernel-abi-whitelists*.tar.bz2 .
    popd
    kernel_dir=$(rpm -qp --qf "linux-%{version}-%{release}\n" "${kernel_pkg}")
    mv "${KERNEL_TAR_VER}" "../${kernel_dir}"
    popd
    rm -rf "${build_script_dir}/${COMPILE_ENV}/usr/src/kernels/tmp"
    #change uname -r to show kernel version in compile enviroment
    mv "${build_script_dir}/${COMPILE_ENV}/usr/bin/uname" "${build_script_dir}/${COMPILE_ENV}/usr/bin/uname.bin"

    change_uname "${build_script_dir}/${COMPILE_ENV}/usr/bin/uname"
    chmod +x "${build_script_dir}/${COMPILE_ENV}/usr/bin/uname";

    prepare_for_dev "${build_script_dir}/${COMPILE_ENV}/dev/"

    cp "${build_script_dir}/chroot.sh" "${build_script_dir}/${COMPILE_ENV}"

    pushd "${build_script_dir}/${COMPILE_ENV}/"
    cp -r "usr/src/kernels/${kernel_dir}/net/" "usr/src/kernels/${build_dir_name}/";cp -r "usr/src/kernels/${kernel_dir}/drivers/" "usr/src/kernels/${build_dir_name}/";cp -r "usr/src/kernels/${kernel_dir}/fs/" "usr/src/kernels/${build_dir_name}/"
    rm -rf "usr/src/kernels/${kernel_dir}/Makefile"
    cp "usr/src/kernels/${build_dir_name}/Makefile" "usr/src/kernels/${kernel_dir}/"
    find usr/src/kernels/"${build_dir_name}"/net/ -type f -name *.c|xargs rm -rf

    find usr/src/kernels/"${build_dir_name}"/drivers/ -type f -name *.c|xargs rm -rf

    find usr/src/kernels/"${build_dir_name}"/fs/ -type f -name *.c|xargs rm -rf

    popd

    tar -cf - "${COMPILE_ENV}" | pigz > "${COMPILE_ENV}.tar.gz" &

    COMPILE_ENV_FOR_DOCKER="${COMPILE_ENV}_for_docker"
    pushd "${COMPILE_ENV}";tar -cf - * | pigz > ../"${COMPILE_ENV_FOR_DOCKER}".tar.gz;popd;
    wait;create_checksum "${COMPILE_ENV}".tar.gz;create_checksum "${COMPILE_ENV_FOR_DOCKER}".tar.gz;

    return 0

}
