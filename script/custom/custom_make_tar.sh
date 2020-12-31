#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

source "${BUILD_SCRIPT_DIR}"/custom/custom_make_repo.sh

######################
# get upgrade scripts from obs
# Globals:
# Arguments:
# Returns:
######################
function get_upgrade_scripts()
{
    local tmpdir=$(mktemp -d)
    local arch="$1"

    pushd "${tmpdir}" &>/dev/null
    wget -r -q -nd -np -A 'double-region-os-upgrade-[0-9]*.rpm' http://"${OBS_SERVER_IP}":82/EulerOS:/V3R1:/GENERAL:/Custom/"${arch}"/noarch/
    popd &>/dev/null

    mkdir -p "${KIWITOOL_DIR}/custom/cfg_ce/usr_install/all/update"
    pushd "${KIWITOOL_DIR}/custom/cfg_ce/usr_install/all/update" &>/dev/null
    rpm2cpio "${tmpdir}"/double-region-os-upgrade-*.rpm | cpio -dim
    popd &>/dev/null

    [ -n "${tmpdir}" ] && rm -rf "${tmpdir}"
}

######################
# make tar
# Globals:
# Arguments:
# Returns:
######################
function make_tar_native()
{
    TIME=""
    while getopts "t:v:c" arg
    do
        case "${arg}" in
            c)
                export YUM_CONF_FLAG=1
                ;;
            v)
                export TAR_VERSION="${OPTARG}"
                ;;
            t)
                TIME="${OPTARG}"
                ;;
        esac
    done

    if [ "${ARCH}" == "aarch64" ]; then
        export KIWIDIR="${BUILD_SCRIPT_DIR}/opt/sys-custom-config/sys-custom-tool_aarch64"
        make_repo aarch64
    elif [ "${ARCH}" == "x86_64" ];then
        export KIWIDIR="${BUILD_SCRIPT_DIR}/opt/sys-custom-config/sys-custom-tool_x86_64"
        make_repo x86_64
    fi

    if [ -z "${TIME}" ]; then
        TIME="$(date +%Y-%m-%d-%H-%M-%S)"
    fi

    [[ -d "${WORK_DIR}" ]] || mkdir -p "${WORK_DIR}"
    KIWITOOL_DIR="${WORK_DIR}${TAR_VERSION}"

    [ -n "${KIWITOOL_DIR}" ] && rm -rf "${KIWITOOL_DIR}"
    wget -r -q -nd -np -A 'security-tool-[0-9]*.rpm' http://"${OBS_SERVER_IP}":82/EulerOS:/V3R1:/GENERAL:/Custom/standard_"${ARCH}"/"${ARCH}"/
    rpm2cpio security-tool*.rpm | cpio -dim
    mkdir -pv "${KIWITOOL_DIR}"
    cp -r "${KIWIDIR}"/* "${KIWITOOL_DIR}"
    cp -r "${WORK_DIR}"repos/* "${KIWITOOL_DIR}/repos/"
    cp usr/sbin/security-tool.sh "${KIWITOOL_DIR}/security-tool/sysenhance.sh"
    cp etc/euleros_security/security.conf "${KIWITOOL_DIR}/security-tool/"
    cp -a etc/pam.d/* "${KIWITOOL_DIR}/security-tool/"

    if [ "${ARCH}" == "aarch64" ]; then
        get_upgrade_scripts "standard_aarch64"
    elif [ "${ARCH}" == "x86_64" ];then
        get_upgrade_scripts "standard_x86_64"
    fi

    cd "${WORK_DIR}"
    kernel_version=$(rpm -qp --qf '%{VERSION}' "${KIWITOOL_DIR}"/repos/euler_base/kernel-4*."${ARCH}".rpm)
    kernel_release_arch=$(rpm -qp --qf '-%{RELEASE}.%{ARCH}' "${KIWITOOL_DIR}"/repos/euler_base/kernel-4*."${ARCH}".rpm)

    #for storage
    kver_pangea=$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "${WORK_DIR}"repos/euler_base/kernel-4.*)    
    for product in $(find ./ -name isopackage.sdf)
    do
        sed -i  "s/^compiletime=.*/compiletime=${TIME}/g" "${product}"
        sed -i "s/^eulerversion=.*/eulerversion=${TAR_VERSION}/g" "${product}"
        if [ "$(echo ${product} | awk -F '/' '{print $4}')" = "cfg_pangea" ]; then
            sed -i "s/^kernelversion=.*/kernelversion=${kver_pangea}/g" "${product}"
        else
            sed -i "s/^kernelversion=.*/kernelversion=${kernel_version}/g" "${product}"
            sed -i "s/^localversion=.*/localversion=${kernel_release_arch}/g" "${product}"
            sed -i "s/^os_version=.*/os_version=${TAR_VERSION}/g" "${product}"
        fi
    done
    TGZ_NAME="${TAR_VERSION}.tar.gz"
    tar -cf - "${TAR_VERSION}" | pigz > "${TGZ_NAME}"
    if [ $? -ne 0 ]; then
        log_error "Tar ${KIWITOOL_DIR} into ${TAR_VERSION}.tar.gz failed"
    fi
    #create_checksum "${TGZ_NAME}"
    return 0
}

