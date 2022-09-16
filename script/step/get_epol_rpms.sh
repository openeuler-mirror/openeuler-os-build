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
    wait_project_published
    chroot_run "cd /home; bash make_version.sh get_epol_rpms_inchroot"
}
######################
# get excluded packages binary rpms
# Globals:
# Arguments:
# Returns:
######################
function get_excluded_pkg_rpm()
{
    obs_project="${OBS_EPOL_PROJECT}"
    osc prjresults ${obs_project} --csv 2>/dev/null | grep "excluded" > excluded_lst
    > aarch64_epol_excluded_lst
    > x86_64_epol_excluded_lst
    excluded_msgs=`cat excluded_lst`
    for excluded_msg in ${excluded_msgs}
    do
	    pkg_name=$(echo $excluded_msg | awk -F";" '{print $1}')
	    a_status=$(echo $excluded_msg | awk -F";" '{print $2}')
	    x_status=$(echo $excluded_msg | awk -F";" '{print $3}')
	    if [[ ${a_status} == "excluded" ]];then
		    arch="x86_64"
	    elif [[ ${x_status} == "excluded" ]];then
		    arch="aarch64"
	    else
		    log_warning "${pkg_name} not excluded"
		    continue
	    fi
	    rpmlist=$(osc ls -b ${obs_project} ${pkg_name} standard_${arch} ${arch} 2>/dev/null | grep "\.src.rpm")
	    if [[ ${rpmlist} != "" ]];then
		    for rpm_name in ${rpmlist[@]}
		    do
			    tmp=${rpm_name%.*.rpm*}
			    echo $tmp >> ${arch}_epol_excluded_lst
		    done
	    fi
    done
    rm -rf excluded_lst
}
######################
# wait project build stable
# Globals:
# Arguments:
# Returns:
######################
function wait_project_published()
{
    set +e
    waitime=3600
    obs_project="${OBS_EPOL_PROJECT}"
    while [ $waitime -gt 0 ]
    do
        osc prjresults ${obs_project} --csv 2>/dev/null | grep "aarch64/published" | grep "x86_64/published"
        if [ $? -eq 0 ];then
		log_info "${obs_project} is published"
		break
        fi
        let waitime=$waitime-5
        sleep 5
    done
    if [ $waitime -eq 0 ];then
	    log_error "get_epol_rpms fail"
    fi
    get_excluded_pkg_rpm
    temp_dir="/tmp/compare_list_dir"
    rm -rf ${temp_dir} && mkdir -p ${temp_dir}
    mv /etc/yum.repos.d /etc/yum.repos.d.bak 
    archs="aarch64 x86_64"
    for arch in $archs
    do
	    rm -rf /etc/yum.repos.d/*
	    yum-config-manager --add-repo "${OBS_EPOL_REPO_URL%/*}/standard_${arch}"
	    yum clean all
	    yum list --installroot="${temp_dir}" --available | awk '{print $1,$2}' | grep "\.src" > ${arch}_epol_lst
	    sed -i -e 's/\.src /-/' ${arch}_epol_lst
	    sort -u ${arch}_epol_lst -o ${arch}_epol_lst
	    excluded_rpms=`cat ${arch}_epol_excluded_lst`
	    for excluded_rpm in ${excluded_rpms}
	    do
		    sed -i "/^${excluded_rpm}/d" ${arch}_epol_lst
	    done
	    rm -rf ${arch}_epol_excluded_lst "${temp_dir}/var"
    done
    rm -rf ${temp_dir}
    rm -rf /etc/yum.repos.d
    mv /etc/yum.repos.d.bak /etc/yum.repos.d
    diff -Nur aarch64_epol_lst x86_64_epol_lst
    if [ $? -eq 0 ];then
	    rm -rf aarch64_epol_lst x86_64_epol_lst
	    log_info "obs repo two architecture rpms version or release are same"
    else
	    rm -rf aarch64_epol_lst x86_64_epol_lst
	    log_error "obs repo two architecture rpms version or release are not same"
    fi
    set -e
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
    yum list --installroot="${tmp_dir}/Packages" --available | awk '{print $1}' | grep -E "noarch|${ARCH}" | grep -v "\.src" > ava_epol_lst
    unrpms=`cat ${UNABLE_INSTALL_LIST}`
    for unrpm in ${unrpms}
    do
	    sed -i "/${unrpm}\./d" ava_epol_lst
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
        yum list --installroot="${tmp_source}/Packages" --available | awk '{print $1}' | grep "\.src" > ava_epol_lst
        unrpms=`cat ${UNABLE_INSTALL_SOURCE_LIST}`
        for unrpm in ${unrpms}
        do
		sed -i "/${unrpm}\./d" ava_epol_lst
        done
        yumdownloader --installroot="${tmp_source}/Packages" --destdir="${tmp_source}/Packages" --source $(cat ava_epol_lst | tr '\n' ' ')
        rm -rf ${tmp_source}/Packages/var
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
            yum list --installroot="${tmp_dir}/Packages" --available | awk '{print $1}' | grep -E "noarch|${ARCH}" | grep -v "\.src" > ava_epol_lst
            yumdownloader --installroot="${tmp_dir}/Packages" --destdir="${tmp_dir}/Packages" $(cat ava_epol_lst | tr '\n' ' ')
            rm -rf ${tmp_dir}/Packages/var
            createrepo -d ${tmp_dir}
            SSH_CMD="mkdir -p ${RELEASE_DIR}/multi_version/${PKG}/${VER}"
            sshcmd "${SSH_CMD}"
            sshscp "${tmp_dir}" "${RELEASE_DIR}/multi_version/${PKG}/${VER}/"
            if [[ "${ARCH}" == "aarch64" ]];then
                tmp_source="/tmp/EPOL/multi_version/${PKG}/${VER}/source"
                mkdir -p ${tmp_source}/Packages
                yum-config-manager --add-repo "http://${OBS_SERVER_IP}:82/${SUB_EPOL_MULTI_REPO_URL}/standard_x86_64"
                yum list --installroot="${tmp_source}/Packages" --available | awk '{print $1}' | grep "\.src" > ava_epol_lst
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
