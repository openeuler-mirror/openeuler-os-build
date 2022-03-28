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
    RELEASE_DIR="${release_dir}/EPOL"
    set +e
    mv /etc/yum.repos.d /etc/yum.repos.d.bak
    mkdir -p /etc/yum.repos.d /tmp/EPOL/${ARCH}/Packages "/tmp/EPOL/source/Packages"
    if [ -n "${OBS_BRINGINRELY_URL}" ];then
        bringinrely_repo="--add-repo ${OBS_BRINGINRELY_URL}"
    else
        bringinrely_repo=""
    fi
    # main standard
    yum-config-manager --add-repo "${OBS_EPOL_REPO_URL}" ${bringinrely_repo}
    yum clean all
    SSH_CMD="mkdir -p ${RELEASE_DIR}/main"
    sshcmd "${SSH_CMD}"
    tmp_dir="/tmp/EPOL/main/${ARCH}"
    mkdir -p ${tmp_dir}/Packages
    yum list --installroot="${tmp_dir}/Packages" --available | awk '{print $1}' | grep -E "noarch|${ARCH}" | grep -v ".src" > ava_epol_lst
    unrpms=`cat ${UNABLE_INSTALL_LIST}`
    for unrpm in ${unrpms}
    do
	    sed -i "/${unrpm}./d" ava_epol_lst
    done
    yumdownloader --installroot="${tmp_dir}/Packages" --destdir="${tmp_dir}/Packages" $(cat ava_epol_lst | tr '\n' ' ')
    rm -rf ${tmp_dir}/Packages/var
    createrepo -d ${tmp_dir}
    sshscp "${tmp_dir}" "${RELEASE_DIR}/main/"
    if [[ "$ARCH" == "aarch64" ]];then
        rm -rf /etc/yum.repos.d/*
        yum-config-manager --add-repo "${OBS_EPOL_REPO_URL%/*}/standard_aarch64" --add-repo "${OBS_EPOL_REPO_URL%/*}/standard_x86_64"
        yum clean all
        tmp_source="/tmp/EPOL/main/source"
        mkdir -p ${tmp_source}/Packages
        yum list --installroot="${tmp_source}/Packages" --available | awk '{print $1}' | grep -E "noarch|${ARCH}" | grep -v ".src" > ava_epol_lst
        yumdownloader --installroot="${tmp_source}/Packages" --destdir="${tmp_source}/Packages" --source $(cat ava_epol_lst | tr '\n' ' ')
        rm -rf ${tmp_source}/Packages/var
        for unrpm in ${unrpms}
        do
            rm -rf ${tmp_source}/Packages/${unrpm}
        done
        createrepo -d ${tmp_source}
        sshscp "${tmp_source}" "${RELEASE_DIR}/main/"
        SSH_CMD="mkdir -p ${RELEASE_DIR}/update/main/source/Packages && createrepo -d ${RELEASE_DIR}/update/main/source"
        sshcmd "${SSH_CMD}"
        SSH_CMD="mkdir -p ${release_dir}/update/source/Packages && createrepo -d ${release_dir}/update/source"
        sshcmd "${SSH_CMD}"
    fi
    # multi version
    if [[ ${OBS_EPOL_MULTI_VERSION_LIST} != "" ]];then
        for r in ${OBS_EPOL_MULTI_VERSION_LIST}
        do
            SUB_EPOL_MULTI_REPO_URL="$(echo ${r//:/:\/})"
            TMP=`echo ${r%:*}`
            PKG=`echo ${TMP##*:}`
            VER=`echo ${r##*:}`
            tmp_dir="/tmp/EPOL/multi_version/${PKG}/${VER}/${ARCH}"
            mkdir -p ${tmp_dir}/Packages
            repo_url="http://${OBS_SERVER_IP}:82/${SUB_EPOL_MULTI_REPO_URL}/standard_${ARCH}"
            rm -rf /etc/yum.repos.d/*
            yum-config-manager --add-repo ${repo_url}
            yum clean all
            yum list --installroot="${tmp_dir}/Packages" --available | awk '{print $1}' | grep -E "noarch|${ARCH}" | grep -v ".src" > ava_epol_lst
            yumdownloader --installroot="${tmp_dir}/Packages" --destdir="${tmp_dir}/Packages" $(cat ava_epol_lst | tr '\n' ' ')
            rm -rf ${tmp_dir}/Packages/var
            for unrpm in ${unrpms}
            do
                rm -rf ${tmp_dir}/Packages/${unrpm}
            done
            createrepo -d ${tmp_dir}
            SSH_CMD="mkdir -p ${RELEASE_DIR}/multi_version/${PKG}/${VER}"
            sshcmd "${SSH_CMD}"
            sshscp "${tmp_dir}" "${RELEASE_DIR}/multi_version/${PKG}/${VER}/"
            if [[ "${ARCH}" == "aarch64" ]];then
                tmp_source="/tmp/EPOL/multi_version/${PKG}/${VER}/source"
                mkdir -p ${tmp_source}/Packages
                yum-config-manager --add-repo "http://${OBS_SERVER_IP}:82/${SUB_EPOL_MULTI_REPO_URL}/standard_x86_64"
                yum list --installroot="${tmp_source}/Packages" --available | awk '{print $1}' | grep -E "noarch|${ARCH}" | grep -v ".src" > ava_epol_lst
                yumdownloader --installroot="${tmp_source}/Packages" --destdir="${tmp_source}/Packages" --source $(cat ava_epol_lst | tr '\n' ' ')
                rm -rf ${tmp_source}/Packages/var
                for unrpm in ${unrpms}
                do
                    rm -rf ${tmp_source}/Packages/${unrpm}
                done
                createrepo -d ${tmp_source}
                sshscp "${tmp_source}" "${RELEASE_DIR}/multi_version/${PKG}/${VER}/"
                SSH_CMD="mkdir -p ${RELEASE_DIR}/update/multi_version/${PKG}/${VER}/source/Packages && createrepo -d ${RELEASE_DIR}/update/multi_version/${PKG}/${VER}/source"
                sshcmd "${SSH_CMD}"
            fi
            SSH_CMD="mkdir -p ${RELEASE_DIR}/update/multi_version/${PKG}/${VER}/${ARCH}/Packages && createrepo -d ${RELEASE_DIR}/update/multi_version/${PKG}/${VER}/${ARCH}"
            sshcmd "${SSH_CMD}"
        done
    fi
    SSH_CMD="mkdir -p ${RELEASE_DIR}/update/main/${ARCH}/Packages ${RELEASE_DIR}/update/multi_version"
    sshcmd "${SSH_CMD}"
    SSH_CMD="createrepo -d ${RELEASE_DIR}/update/main/${ARCH}"
    sshcmd "${SSH_CMD}"
    SSH_CMD="mkdir -p ${release_dir}/update/${ARCH}/Packages && createrepo -d ${release_dir}/update/${ARCH}"
    sshcmd "${SSH_CMD}"

    rm -rf /tmp/EPOL
    rm -rf /etc/yum.repos.d
    mv /etc/yum.repos.d.bak /etc/yum.repos.d
    set -e

    return 0
}
