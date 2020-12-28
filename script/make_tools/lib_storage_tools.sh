#!/bin/bash
# Author: xudengfeng
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# make lib storage chroot outside 
# Globals:
# Arguments:
# Returns:
######################
function make_tools_lib_storage()
{
    chroot_run_bep "cd /home; bash make_version.sh lib_storage_inchroot"
}

######################
# make lib storage in chroot 
# Globals:
# Arguments:
# Returns:
######################
function lib_storage_inchroot()
{
    log_info "==========Start get_libstorage_rpm=========="
    #LIST="debug_tools.lst  DockerStack.lst  ServerLess.lst"
    LIST="LibStorage.lst"
    mkdir "${LIB_STORAGE_TOOLS}"; cd "${LIB_STORAGE_TOOLS}"
    yum clean all -c "${yum_conf}"
    yum list --installroot="${BUILD_SCRIPT_DIR}"/tmp available -c "${yum_conf}" | awk '{print $1}' > ava_lst
    for rpmlist in "${LIST}"
    do
        for rname in $(cat "${MAKE_TOOLS}"/"${rpmlist}")
        do
           if ! grep -w "^${rname}" ava_lst > /dev/null 2>&1; then
                log_error "can not find ${rname} failed"
            fi
        done
        rpm_dir=$(echo "${rpmlist}" | sed 's/.lst//g')
        mkdir "${rpm_dir}"
        yumdownloader -c "${yum_conf}" --disablerepo=obs-7 --destdir="${rpm_dir}" $(cat "${MAKE_TOOLS}"/"${rpmlist}" | tr '\n' ' ')
    done
    for dir in $(ls ./)
    do
        if [ -d "${dir}" ]; then
            cd "${dir}"
            for file in $(ls ./)
            do
                create_checksum "${file}"
            done
            cd ..
        fi
    done
    mkdir release debug tools
    mv "${LIB_STORAGE_TOOLS}"/*-dbg*.rpm ./debug
    mv "${LIB_STORAGE_TOOLS}"/*-mgr-tools*.rpm  ./release
    mv "${LIB_STORAGE_TOOLS}"/*-tools*.rpm ./tools
    mv "${LIB_STORAGE_TOOLS}"/*.rpm  ./release
    cd ..

    RELEASEDIR=$(get_release_dir)
    RELEASE_DIR="${RELEASEDIR}${LIB_STORAGE_TOOLS}"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"
    sshscp "${LIB_STORAGE_TOOLS}/release" "${RELEASE_DIR}"
    sshscp "${LIB_STORAGE_TOOLS}/debug" "${RELEASE_DIR}"
    sshscp "${LIB_STORAGE_TOOLS}/tools" "${RELEASE_DIR}"
    chmod_http
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi
}
