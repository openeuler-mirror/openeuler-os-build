#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

##source "${BUILD_SCRIPT_DIR}"/custom/custom_common.sh
##source "${BUILD_SCRIPT_DIR}"/custom/custom_make_compile_env_common.sh

######################
# make cross compile env
# Globals:
# Arguments:
# Returns:
######################
function custom_make_compile_env_cross()
{
    while getopts "o:c:p:" arg
    do
        case "${arg}" in
            c)
                export YUM_CONF_FLAG=1
                ;;
            o)
                export OBS_KERNEL="${OPTARG}"
                ;;
            p)
                export NAME="${OPTARG}"
                ;;
        esac
    done

    COMPILE_ENV="Euler_compile_env_cross"
    COMPILE_ENV1="Euler_compile_env_x86_64"
    COMPILE_ENV2="Euler_compile_env_aarch64"

    KERNEL="kernel-[0-9]*.src.rpm"
    KERNEL_DEVEL="kernel-devel-[0-9]*.aarch64.rpm"
    KERNEL_DEBUG="kernel-debuginfo-[0-9]*.aarch64.rpm"

    cd "${BUILD_SCRIPT_DIR}";rm -rf "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}";

    mkdir -p "${COMPILE_ENV1}"/arm/{usr,arm_kernel,cross_compile}
    cp -a "${COMPILE_ENV2}"/usr/* "${COMPILE_ENV1}"/arm/usr/
    rm -f *.rpm;rm -rf {k_devel,k_debug,certdb};

    OBS_REPO="http://${OBS_SERVER_IP}:82/EulerOS:/V3R1:/${OBS_KERNEL}:/Kernel/standard_aarch64"
    wget -c -r -nd -np -k -L -p -A "${KERNEL}" "${OBS_REPO}"/src/
    wget -c -r -nd -np -k -L -p -A "${KERNEL_DEVEL}" "${OBS_REPO}"/aarch64/
    wget -c -r -nd -np -k -L -p -A "${KERNEL_DEBUG}" "${OBS_REPO}"/aarch64/
    KERNEL_DEVEL="$(ls|grep kernel-devel-[0-9]*.aarch64.rpm)"
    KERNEL_DEBUG="$(ls|grep kernel-debuginfo-[0-9]*.aarch64.rpm)"
    KERNEL="$(ls|grep kernel-[0-9]*.src.rpm)"
    mkdir k_devel; mv "${KERNEL_DEVEL}" k_devel/; cd k_devel; rpm2cpio "${KERNEL_DEVEL}" | cpio -di; cd ../;
    mkdir k_debug; mv "${KERNEL_DEBUG}" k_debug/; cd k_debug; rpm2cpio "${KERNEL_DEBUG}" | cpio -di; cd ../;
    CERTDB_PKG="euleros-certdb-[0-9]*.src.rpm"
    wget -c -r -nd -np -k -L -p -A "$CERTDB_PKG" "$OBS_REPO"/src/
    CERTDB_PKG="$(ls|grep euleros-certdb-[0-9]*.src.rpm)"
    mkdir certdb;mv "$CERTDB_PKG" certdb/;cd certdb; rpm2cpio "$CERTDB_PKG" | cpio -di; tar -xf euleros-certdb-*.tar.bz2; cd ../;

    KERNEL_VERSION=$(rpm -qp --queryformat  "%{version}-%{release}" "${KERNEL}")

    cp "${KERNEL}" "${COMPILE_ENV1}"/arm/arm_kernel/;cp -a opt/cross_compile/* "${COMPILE_ENV1}"/arm/cross_compile/;
    cd "${COMPILE_ENV1}"/arm/cross_compile/;tar xf hcc_arm64le_1620.tar.gz;rm -f hcc_arm64le_1620.tar.gz;mv hcc_arm64le_1620 install;cd - &> /dev/null;

    rm -rf "${COMPILE_ENV1}"/arm/cross_compile/install/sysroot/*
    pushd "${COMPILE_ENV2}" > /dev/null
    if [ -L "lib64/libaio.so" ]; then
        libaio_file="$(ls -lh lib64/libaio.so  | awk  '{print $NF}')"
        dir_name=$(dirname "${libaio_file}")
        base_name=$(basename "${libaio_file}")
        if [ "x${dir_name}" != "x\." ]; then
            pushd ."${dir_name}" > /dev/null;rm -rf libaio.so;ln -s  "${base_name}" libaio.so;popd >/dev/null;
        fi
    fi
    popd > /dev/null
    mv "${COMPILE_ENV2}"/* "${COMPILE_ENV1}"/arm/cross_compile/install/sysroot/

    cd "${COMPILE_ENV1}"/usr/src;mkdir -p arm;ln -s arm linux;
    cd "${BUILD_SCRIPT_DIR}";cd "${COMPILE_ENV1}"/arm/arm_kernel/;

    rpm2cpio "${KERNEL}" | cpio -id
    linux_tarname=$(rpm -qpl "${KERNEL}" | grep linux-.*\.tar)
    linux_dirname=${linux_tarname%*.tar.*}
    if tar tf "${linux_tarname}" | head | grep "${linux_dirname}" &>/dev/null; then tar xf "${linux_tarname}"
    else mkdir linux-"${KERNEL_VERSION}";tar xf "${linux_tarname}" --directory=linux-"${KERNEL_VERSION}"
    fi
    patch_pkgs="$(ls patches*.tar.bz2)"
    series_conf_name="$(ls series*.conf | grep -v develop.conf)"
    for i in ${patch_pkgs};do tar xf "${i}";done
    cd linux-4.19.13
    for conf_name in ${series_conf_name};do ../apply-patches ../"${conf_name}" ../;done
    if [ -f ../series-*develop.conf ]; then ../apply-patches ../series-*develop.conf ../;fi
    cd ..;mv linux-4.19.13 linux-"${KERNEL_VERSION}";cp x509.genkey linux-"${KERNEL_VERSION}";rm "${KERNEL}" "${linux_tarname}" patches*.tar.bz2;

    cd "${BUILD_SCRIPT_DIR}"
    echo -en "export PATH=/sbin:/usr/sbin:/usr/local/sbin:/root/bin:/usr/local/bin:/usr/bin:/bin:/usr/bin/X11:/usr/X11R6/bin:/usr/games:/usr/lib64/jvm/jre/bin:/usr/lib/mit/bin:/usr/lib/mit/sbin:/arm/cross_compile/install/bin\nexport PS1='[\u@\H \w]\$ '\n#export C_INCLUDE_PATH=/arm/cross_compile/install/sysroot/usr/include\nexport ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-\nmount -t proc proc /proc 2>/dev/null" >> "${COMPILE_ENV1}"/etc/profile

    cp k_devel/usr/src/kernels/"${KERNEL_VERSION}".aarch64/Makefile "${COMPILE_ENV1}"/arm/arm_kernel/linux-"${KERNEL_VERSION}"/
    cp k_devel/usr/src/kernels/"${KERNEL_VERSION}".aarch64/.config "${COMPILE_ENV1}"/arm/arm_kernel/linux-"${KERNEL_VERSION}"/
    cp k_devel/usr/src/kernels/"${KERNEL_VERSION}".aarch64/Module.symvers "${COMPILE_ENV1}"/arm/arm_kernel/linux-"${KERNEL_VERSION}"/
    rm -r k_devel;mkdir -p "${COMPILE_ENV1}"/opt/patch_workspace/;
    cp k_debug/usr/lib/debug/lib/modules/*/vmlinux "${COMPILE_ENV1}"/opt/patch_workspace/;rm -r k_debug;
    [ -d certdb ] && (cp certdb/euleros-certdb-1.0/ko-signing/4.3.3/signing_key.* "$COMPILE_ENV1"/arm/arm_kernel/linux-"${KERNEL_VERSION}"/; cp certdb/euleros-certdb-1.0/ko-signing/4.3.3/signing_key.*  "$COMPILE_ENV1"/opt/patch_workspace/signing/; rm -r certdb)

    chroot "${COMPILE_ENV1}" sh -c "export PATH=${PATH}:/arm/cross_compile/install/bin;cd /arm/arm_kernel/linux-${KERNEL_VERSION}/; make prepare ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-; make scripts ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-; make clean;"
    if [ $? -ne 0 ]; then log_error "make kernel failed in make_cross_compile_env";fi

    cd "${COMPILE_ENV1}"
    mkdir -p lib/modules/"${KERNEL_VERSION}".aarch64
    chroot ../"${COMPILE_ENV1}" sh -c "ln -s /arm/arm_kernel/linux-${KERNEL_VERSION} /lib/modules/${KERNEL_VERSION}.aarch64/build;cd /lib/modules/${KERNEL_VERSION}.aarch64/;ln -s build source; cd /arm/cross_compile/install/sysroot/; ln -s usr/lib64 lib64; cd usr/lib64;rm libsqlite3.so; ln -s libsqlite3.so.0.8.6 libsqlite3.so; rm libkeyutils.so; ln -s libkeyutils.so.1 libkeyutils.so;"

    rm -rf ../"${COMPILE_ENV1}"/arm/usr
    rm -rf ../"$COMPILE_ENV1"/arm/arm_kernel/linux-"${KERNEL_VERSION}"/signing_key.*
    rm -rf ../"$COMPILE_ENV1"/opt/patch_workspace/signing/signing_key.*

    cd "${BUILD_SCRIPT_DIR}";mv "${COMPILE_ENV1}" "${COMPILE_ENV}";
    if [ "x${NAME}" == "xstandard" ]; then tar -cf - "${COMPILE_ENV}" | pigz > "${COMPILE_ENV}".tar.gz;create_checksum "${COMPILE_ENV}".tar.gz
    else tar -cf - "${COMPILE_ENV}" | pigz > "${COMPILE_ENV}"_"${NAME}".tar.gz;create_checksum "${COMPILE_ENV}"_"${NAME}".tar.gz
    fi
    return 0
}
