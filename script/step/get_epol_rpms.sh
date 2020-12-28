#!/bin/bash
# Author: zhengxuye
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# 构建iso镜像
# Globals:
# Arguments:
# Returns:
######################
function get_epol_rpms()
{
    chroot_run "cd /home; bash make_version.sh get_epol_rpms_inchroot"
}
######################
# 在chroot中构建iso镜像
# Globals:
# Arguments:
# Returns:
######################
function get_epol_rpms_inchroot()
{
    get_version
    release_dir=$(get_release_dir)
    TIME_DIR="${release_dir#${HTTP_DIR}}"
    TIME=${TIME_DIR##*/}
    TIME=${TIME#"${version}"-}
    CUSTOM_DIR="${TIME_DIR}"
    set +e
    RELEASE_DIR="${release_dir}/EPOL/$ARCH/Packages"
    RELEASE_SOURCE_DIR="${release_dir}/EPOL/source/Packages"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    SSH_CMD="mkdir -p ${RELEASE_SOURCE_DIR}"
    sshcmd "${SSH_CMD}"
    SSH_CMD="cd ${RELEASE_DIR} && wget -c -r -np -nd ${OBS_EPOL_REPO_URL}/${ARCH}/ && rm -rf ${ARCH} && rm -rf index.html*"
    sshcmd "${SSH_CMD}"
    SSH_CMD="cd ${RELEASE_DIR} && wget -c -r -np -nd ${OBS_EPOL_REPO_URL}/noarch/ && rm -rf noarch && rm -rf index.html*"
    sshcmd "${SSH_CMD}"
    SSH_CMD="cd ${RELEASE_SOURCE_DIR} && wget -c -r -np -nd ${OBS_EPOL_REPO_URL}/src/ && rm -rf src && rm -rf index.html*"
    sshcmd "${SSH_CMD}"
    SSH_CMD="cd ${RELEASE_DIR} && wget -c -r -np -nd ${OBS_BRINGINRELY_URL}/${ARCH}/ && rm -rf ${ARCH} && rm -rf index.html*"
    sshcmd "${SSH_CMD}"
    set -e
    SSH_CMD="cd ${release_dir} && createrepo -d ${release_dir}/EPOL/$ARCH; createrepo -d ${release_dir}/EPOL/source"
    sshcmd "${SSH_CMD}"
    return 0
}
