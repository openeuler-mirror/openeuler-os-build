#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

BUILD_SCRIPT_DIR="${PWD}"
source "${BUILD_SCRIPT_DIR}"/custom/custom_common.sh

######################
# make compile env common
# Globals:
# Arguments:
# Returns:
######################
function make_compile_env_common()
{
    ARCH=$(uname -m)

    if [ "X${ARCH}" != "X" ];then
        COMPILE_ENV="Euler_compile_env_${ARCH}"
        YUM_CONF_ARCH="${BUILD_SCRIPT_DIR}/compile_env_cross_${ARCH}/${NAME}_yum.conf"
        YUM_CONF="${BUILD_SCRIPT_DIR}/compile_env_cross_${ARCH}/yum.conf"
        mv "${YUM_CONF_ARCH}" "${YUM_CONF}"
        REPO_DIR_ARCH="${BUILD_SCRIPT_DIR}/compile_env_cross_${ARCH}/${NAME}_yum.repos.d"
        REPO_DIR="${BUILD_SCRIPT_DIR}/compile_env_cross_${ARCH}/yum.repos.d"
        mv "${REPO_DIR_ARCH}" "${REPO_DIR}"
        rpmlist="${BUILD_SCRIPT_DIR}/compile_env_cross_${ARCH}/${NAME}_rpm.lst"
    fi

    if [ "${YUM_CONF_FLAG}" -eq 0 ]; then
        REPO_ROOT="/usr1/Euleros_yum"
        [[ -d "${REPO_ROOT}" ]] || mkdir -p "${REPO_ROOT}"
        [ -d "${REPO_ROOT}/yum.repos.d" ] && rm -rf "${REPO_ROOT}/yum.repos.d"
        cp -r "${REPO_DIR}" "${REPO_ROOT}"
    fi

    compile_env_rpm_lst=""

    #clean compile env folder first
    rm -rf "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}"
    while read line
    do
        if [ -z "${line}" ]; then
            continue
        fi

        compile_env_rpm_lst="${compile_env_rpm_lst} ${line}"
    done < "${rpmlist}"

    yum clean all -c "${YUM_CONF}"
    yum install -c "${YUM_CONF}" --installroot="${BUILD_SCRIPT_DIR}/${COMPILE_ENV}" -y $(echo "$compile_env_rpm_lst") -x glibc32
    #eulerversion=${RELEASEDIR##*/}
    if [ -z "${TIME}" ]; then
        TIME="$(date +%Y-%m-%d-%H-%M-%S)"
    fi
    eulerversion="${CROSS_ENV_VERSION}-${TIME}"
    echo "version=${eulerversion}" > "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/etc/EulerLinux.conf"
    echo "mount -t proc proc /proc 2>/dev/null" >> "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/etc/profile"
    echo "export PS1='[EulerOS_compile_env \w]\$ '" >> "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/etc/profile"

    echo "/usr/lib" >> "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/etc/ld.so.conf"
    echo "/usr/lib64" >> "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/etc/ld.so.conf"
    echo "ldconfig" >> "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/etc/profile"
    echo "unset PROMPT_COMMAND" >> "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/etc/profile"
    echo "update-ca-trust" >> "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/etc/profile"
    rm -rf "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}"/var/log/*;rm -rf "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}"/var/cache/yum/*;rm -rf "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}"/var/cache/ldconfig/aux-cache;rm -rf "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}"/etc/ld.so.cache;rm -rf "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}"/etc/pki/ca-trust/extracted/java/cacerts;rm -rf "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}"/var/lib/yum/*

    #change uname -r to show kernel version in compile enviroment
    mv "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/usr/bin/uname" "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/usr/bin/uname.bin"

    change_uname_cross

    chmod +x "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/usr/bin/uname"

    prepare_for_dev "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/dev/"

    if [ "X${ARCH}" == "Xaarch64" ];then
       tar -zcf "${COMPILE_ENV}".tar.gz "${COMPILE_ENV}" 
    fi
    return 0

}

CROSS_ENV_VERSION=""
YUM_CONF_FLAG=0
while getopts "t:v:c:p:" arg
do
case "${arg}" in
    c)
	export YUM_CONF_FLAG=1
	;;
    v)
	export CROSS_ENV_VERSION="${OPTARG}"
	;;
    t)
	TIME="${OPTARG}"
	;;
    p)
	export NAME="${OPTARG}"
	;;
esac
done
make_compile_env_common
