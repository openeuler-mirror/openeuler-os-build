#!/bin/bash
# Author: xudengfeng
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# make docker tools chroot outside
# Globals:
# Arguments:
# Returns:
######################
function make_tools_dockertools()
{
    chroot_run_bep "cd /home; bash make_version.sh docker_tools_inchroot"
}

######################
# make docker tools in chroot
# Globals:
# Arguments:
# Returns:
######################

function docker_tools_inchroot()
{
    LIST="DockerStack.lst"
    mkdir "${DOCKER_TOOLS}"; cd "${DOCKER_TOOLS}"
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
        yumdownloader -c "${yum_conf}" --disablerepo=obs-7 --exclude="*.src" --destdir="${rpm_dir}" $(cat "${MAKE_TOOLS}"/"${rpmlist}" | tr '\n' ' ')
    done
    cd ./DockerStack
    ls . | while read line
    do
        create_checksum  "${line}"
    done
    cd ../..
    RELEASEDIR=$(get_release_dir)
    RELEASE_DIR="${RELEASEDIR}"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"
    sshscp "${DOCKER_TOOLS}/DockerStack" "${RELEASE_DIR}"
    chmod_http
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi
}
