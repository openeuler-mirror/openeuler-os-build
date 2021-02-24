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
    mv /etc/yum.repos.d /etc/yum.repos.d.bak
    mkdir -p /etc/yum.repos.d /tmp/EPOL/${ARCH}/Packages "/tmp/EPOL/source/Packages"
    yum-config-manager --add-repo "${OBS_EPOL_REPO_URL}" --add-repo "${OBS_BRINGINRELY_URL}"
    yum clean all
    RELEASE_DIR="${release_dir}/EPOL"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"

    yum list --installroot="/tmp/EPOL/aarch64/Packages" --available | awk '{print $1}' | grep -E "noarch|${ARCH}" | grep -v ".src" > ava_epol_lst

    yumdownloader --installroot="/tmp/EPOL/${ARCH}/Packages" --destdir="/tmp/EPOL/${ARCH}/Packages" $(cat ava_epol_lst | tr '\n' ' ')
    rm -rf /tmp/EPOL/${ARCH}/Packages/var
    createrepo -d /tmp/EPOL/${ARCH}
    sshscp "/tmp/EPOL/${ARCH}" "${RELEASE_DIR}"
    if [[ "$ARCH" == "aarch64" ]];then
        rm -rf /etc/yum.repos.d/*
        yum-config-manager --add-repo "${OBS_EPOL_REPO_URL}"
        yum clean all
        yum list --installroot="/tmp/EPOL/aarch64/Packages" --available | awk '{print $1}' | grep -E "noarch|${ARCH}" | grep -v ".src" > ava_epol_lst
        yumdownloader --installroot="/tmp/EPOL/source/Packages" --destdir="/tmp/EPOL/source/Packages" --source $(cat ava_epol_lst | tr '\n' ' ')
        rm -rf /tmp/EPOL/source/Packages/var
        createrepo -d /tmp/EPOL/source
        sshscp "/tmp/EPOL/source" "${RELEASE_DIR}"
    fi
    rm -rf /tmp/EPOL
    rm -rf /etc/yum.repos.d
    mv /etc/yum.repos.d.bak /etc/yum.repos.d
    set -e

    return 0
}
