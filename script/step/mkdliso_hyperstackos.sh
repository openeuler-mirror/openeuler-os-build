#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.

set -e

######################
# make HyperStackOS chroot outside
# Globals:
# Arguments:
# Returns:
######################
function mkdliso_hyperstackos()
{
    chroot_run_bep "cd /home; bash make_version.sh mkdliso_hyperstackos_inchroot"
}

######################
# make HyperStackOS in chroot
# Globals:
# Arguments:
# Returns:
######################
function mkdliso_hyperstackos_inchroot()
{
    MKISO_PATH=/home/mkiso_ARM64
    basedir=/usr1/EulerOS__ARM64
    PRODUCT="$1"
    CFG="custom/cfg_"$(echo "${PRODUCT}" | tr '[A-Z]' '[a-z]')""
    ISO="${DVD_NAME}"
    ISOILP32=EulerOS-V3.0SP1-aarch64-ilp32-dvd.iso

    rm -f ./release_tmp ./release *.tar.gz
    cd "${basedir}"
    sshscp_from "/repo/openeuler/dailybuild/${PRE_VERSION}/${VERSION}/release" .
    TAR_NAME="$(cat release |awk -F / '{print $NF}')"
    TAR=${TAR_NAME%.tar.gz}

    thread_list="$(ps -ef | grep mkdliso | grep -v grep | awk '{print $2}')"
    for id in $(cat thread_list)
    do
        log_info "There has been several threads about mkdliso ,already. Killing..."
        kill 9 "${id}"
    done

    [ -n "${TAR}" ] && rm -rf "${TAR}"
    [ -n "${TAR_NAME}" ] && rm -rf "${TAR_NAME}"
    wget -q $(cat release) &> /dev/null
    if [ $? -ne 0 ];then
        log_error "wget ${TAR_NAME} failed!"
    fi
    log_info "wget ${TAR_NAME} success!"

    tar xzf "${TAR_NAME}"
    if [ $? -ne 0 ]
    then
        log_error "${TAR_NAME} unzip failed!"
    fi
    log_info "${TAR_NAME} unzip success!"
    rm -rf "${TAR_NAME}"

    cd "${basedir}/${TAR}"
    mv repos/kernel repos/Update/
    mv repos/glibc-pkgs repos/Update/
    find repos/ -name *.rpm > repos/iso_package.list

    ./mkdliso -p "${PRODUCT}" -c "${CFG}"
    if [ $? -ne 0 ];then
        log_error "kiwi_iso failed!"
    fi
    log_info "kiwi iso success!"

    sshscp_from "/repo/openeuler/dailybuild/${PRE_VERSION}/${VERSION}/release_tmp" .
    if [ $? -ne 0 ];then
        log_error "wget release_tmp failed!"
    fi
    log_info "wget release_tmp success!"

    RELEASEDIR="$(cat release_tmp)"
    RELEASE_DIR="${RELEASEDIR}/ISO"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"

    cd result/20*
    create_checksum "${ISO}"
    sshscp "${ISO} ${ISO}${SHA256SUM}" "${RELEASE_DIR}"

    chmod_http 'openeuler_${ARCH}'
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi
    log_info "Release ${ISO} to ${RELEASE_SERVER_IP}:${RELEASE_DIR}"

    return 0
}
