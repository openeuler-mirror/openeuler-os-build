#!/bin/bash
# Author: zhengxuye
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

function check_rpm_sign()
{
    > /tmp/not_sign_rpm
    for pkg in `ls $1/Packages/*.rpm`
    do
	    rpm -Kv ${pkg} | grep "key ID [a-z0-9]*: OK" > /dev/null
	    if [[ $? -ne 0 ]];then
		echo "${pkg}" >>  /tmp/not_sign_rpm
	    fi
    done
    if [[ -s "/tmp/not_sign_rpm" ]];then
	    echo "[Error]: some rpm is not sign"
	    cat /tmp/not_sign_rpm
	    exit 1
    fi
    rm -f /tmp/not_sign_rpm
}

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
    rpm --import /home/RPM-GPG-KEY-EBS

    yum-config-manager --add-repo ${EPOL_PROJECT_REPO}
    yum clean all
    SSH_CMD="rm -rf ${RELEASE_DIR}/main/${ARCH};mkdir -p ${RELEASE_DIR}/main/${ARCH}"
    sshcmd "${SSH_CMD}"
    tmp_dir="/tmp/EPOL/main/${ARCH}"
    mkdir -p ${tmp_dir}/Packages
    yum list --installroot="${tmp_dir}/Packages" --available | awk '{print $1}' | grep -E "noarch|${ARCH}" | grep -v "\.src" > ava_epol_lst
    unrpms=`cat ${UNABLE_INSTALL_LIST}`
    for unrpm in ${unrpms}
    do
        sed -i "/^${unrpm}\./d" ava_epol_lst
    done
    if [ ! -s ava_epol_lst ];then
        echo "There don't have some rpms in the repo"
        exit 1
    fi
    yumdownloader --installroot="${tmp_dir}/Packages" --destdir="${tmp_dir}/Packages" $(cat ava_epol_lst | tr '\n' ' ')
    rm -rf ${tmp_dir}/Packages/var

    # download everything project kernel rpm
    rm -rf /etc/yum.repos.d/*
    yum-config-manager --add-repo ${STANDARD_PROJECT_REPO}
    yum clean all
    rpmlist=$(cat ${BUILD_SCRIPT_DIR}/config/epol/kernel_rpm_list_${ARCH})
    for rpms in ${rpmlist[@]}
    do
        yumdownloader --installroot="${tmp_dir}/Packages" --destdir="${tmp_dir}/Packages" ${rpms}
    done
    rm -rf ${tmp_dir}/Packages/var

    check_rpm_sign ${tmp_dir}
    createrepo -d ${tmp_dir}
    sshscp "${tmp_dir}" "${RELEASE_DIR}/main/"
    if [[ "$ARCH" == "aarch64" ]];then
        rm -rf /etc/yum.repos.d/*
        yum-config-manager --add-repo "${EPOL_PROJECT_REPO%/*}/aarch64" --add-repo "${EPOL_PROJECT_REPO%/*}/x86_64"
        yum clean all
        SSH_CMD="rm -rf ${RELEASE_DIR}/main/source;mkdir -p ${RELEASE_DIR}/main/source"
        sshcmd "${SSH_CMD}"
        tmp_source="/tmp/EPOL/main/source"
        mkdir -p ${tmp_source}/Packages
        yum list --installroot="${tmp_source}/Packages" --available | awk '{print $1}' | grep "\.src" > ava_epol_lst
        unrpms=`cat ${UNABLE_INSTALL_SOURCE_LIST}`
        for unrpm in ${unrpms}
        do
            sed -i "/^${unrpm}\./d" ava_epol_lst
        done
        if [ ! -s ava_epol_lst ];then
            echo "There don't have some rpms in the repo"
            exit 1
        fi
        yumdownloader --installroot="${tmp_source}/Packages" --destdir="${tmp_source}/Packages" --source $(cat ava_epol_lst | tr '\n' ' ')
        rm -rf ${tmp_source}/Packages/var

        # download everything project kernel source rpm
        rm -rf /etc/yum.repos.d/*
        yum-config-manager --add-repo "${STANDARD_PROJECT_REPO%/*}/aarch64" --add-repo "${STANDARD_PROJECT_REPO%/*}/x86_64"
        yum clean all
        rpmlist=$(cat ${BUILD_SCRIPT_DIR}/config/epol/kernel_src_list)
        for rpms in ${rpmlist[@]}
        do
            yumdownloader --installroot="${tmp_source}/Packages" --destdir="${tmp_source}/Packages" --source ${rpms}
        done
        rm -rf ${tmp_source}/Packages/var

        check_rpm_sign ${tmp_source}
        createrepo -d ${tmp_source}
        sshscp "${tmp_source}" "${RELEASE_DIR}/main/"
        SSH_CMD="mkdir -p ${RELEASE_DIR}/update/main/source/Packages && createrepo -d ${RELEASE_DIR}/update/main/source"
        sshcmd "${SSH_CMD}"
        SSH_CMD="mkdir -p ${release_dir}/update/source/Packages && createrepo -d ${release_dir}/update/source"
        sshcmd "${SSH_CMD}"
    fi
    # multi version
    SSH_CMD="mkdir -p ${RELEASE_DIR}/multi_version"
    sshcmd "${SSH_CMD}"
    if [[ ${EPOL_MULTI_VERSION_LIST} != "" ]];then
        for r in ${EPOL_MULTI_VERSION_LIST}
        do
            TMP=`echo ${r%:*}`
            PKG=`echo ${TMP##*:}`
            VER=`echo ${r##*:}`
            tmp_dir="/tmp/EPOL/multi_version/${PKG}/${VER}/${ARCH}"
            mkdir -p ${tmp_dir}/Packages
            if [[ "${VER}" == "Train" ]];then
                repo_name="${Train_repo}"
            fi
            if [[ "${VER}" == "Wallaby" ]];then
                repo_name="${Wallaby_repo}"
            fi
            if [[ "${VER}" == "Antelope" ]];then
                repo_name="${Antelope_repo}"
            fi
            if [[ "${VER}" == "humble" ]];then
                repo_name="${humble_repo}"
            fi
            if [[ "${VER}" == "noetic" ]];then
                repo_name="${noetic_repo}"
            fi
            if [[ "${VER}" == "For-Virt" ]];then
                repo_name="${nestos_for_virt_repo}"
            fi
            if [[ "${VER}" == "For-Container" ]];then
                repo_name="${nestos_for_container_repo}"
            fi
            if [[ "${PKG}" == "kubernetes" ]];then
                repo_name="${kubernetes_repo}"
            fi
            if [[ "${PKG}" == "lustre" ]];then
                repo_name="${lustre_repo}"
            fi
            repo_url="${repo_name}/${ARCH}"
            rm -rf /etc/yum.repos.d/*
            yum-config-manager --add-repo ${repo_url}
            yum clean all
            yum list --installroot="${tmp_dir}/Packages" --available | awk '{print $1}' | grep -E "noarch|${ARCH}" | grep -v "\.src" > ava_epol_lst
            if [[ "${PKG}" == "kubernetes" ]] || [[ "${PKG}" == "lustre" ]];then
                unrpms=`cat ${UNABLE_INSTALL_LIST}_${PKG}`
            else
                unrpms=`cat ${UNABLE_INSTALL_LIST}_${VER}`
            fi
            for unrpm in ${unrpms}
            do
                sed -i "/^${unrpm}\./d" ava_epol_lst
            done
            if [ ! -s ava_epol_lst ];then
                echo "[Warning]: ${repo_url} don't have rpm."
                continue
            fi
            yumdownloader --installroot="${tmp_dir}/Packages" --destdir="${tmp_dir}/Packages" $(cat ava_epol_lst | tr '\n' ' ')
            rm -rf ${tmp_dir}/Packages/var
            createrepo -d ${tmp_dir}
            SSH_CMD="rm -rf ${RELEASE_DIR}/multi_version/${PKG}/${VER}/${ARCH};mkdir -p ${RELEASE_DIR}/multi_version/${PKG}/${VER}/${ARCH}"
            sshcmd "${SSH_CMD}"
            sshscp "${tmp_dir}" "${RELEASE_DIR}/multi_version/${PKG}/${VER}/"
            if [[ "${ARCH}" == "aarch64" ]];then
                SSH_CMD="rm -rf ${RELEASE_DIR}/multi_version/${PKG}/${VER}/source;mkdir -p ${RELEASE_DIR}/multi_version/${PKG}/${VER}/source"
                sshcmd "${SSH_CMD}"
                tmp_source="/tmp/EPOL/multi_version/${PKG}/${VER}/source"
                mkdir -p ${tmp_source}/Packages
                yum-config-manager --add-repo "${repo_name}/x86_64"
                yum list --installroot="${tmp_source}/Packages" --available | awk '{print $1}' | grep -E "noarch|${ARCH}" | grep -v "\.src" > ava_epol_lst

                if [[ "${PKG}" == "kubernetes" ]] || [[ "${PKG}" == "lustre" ]];then
                    unrpms=`cat ${UNABLE_INSTALL_SOURCE_LIST}_${PKG}`
                else
                    unrpms=`cat ${UNABLE_INSTALL_SOURCE_LIST}_${VER}`
                fi
                for unrpm in ${unrpms}
                do
                    sed -i "/^${unrpm}\./d" ava_epol_lst
                done
                yumdownloader --installroot="${tmp_source}/Packages" --destdir="${tmp_source}/Packages" --source $(cat ava_epol_lst | tr '\n' ' ')
                rm -rf ${tmp_source}/Packages/var
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
