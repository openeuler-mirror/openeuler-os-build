#!/bin/bash
# Author:
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# 构建iso镜像
# Globals:
# Arguments:
# Returns:
######################
function make_devstation_netinst_iso()
{
    chroot_run "cd /home; bash make_version.sh make_devstation_netinst_iso_inchroot"
}

######################
# 在chroot中构建iso镜像
# Globals:
# Arguments:
# Returns:
######################
function make_devstation_netinst_iso_inchroot()
{
    get_version
    release_dir=$(get_release_dir)
    TIME_DIR="${release_dir#${HTTP_DIR}}"
    TIME=${TIME_DIR##*/}
    TIME=${TIME#"${version}"-}

    yum_conf="${BUILD_SCRIPT_DIR}/config/repo_conf/repofile.conf"
    yum clean all -c "${yum_conf}"
    yum remove -y oemaker lorax || true
    yum install -y oemaker lorax -c "${yum_conf}"
    
    # 配置 repo 源
    sed -i "/^%pre/i \
repo --name=\"epol\" --baseurl=${EPOL_PROJECT_REPO}" /opt/oemaker/config/$ARCH/livecd/devstation_livecd_$ARCH.ks

    if [[ -n "${THIRD_REPO}" ]];then
        sed -i "/^%pre/i \
repo --name=\"third_repo\" --baseurl=${THIRD_REPO}" /opt/oemaker/config/$ARCH/livecd/devstation_livecd_$ARCH.ks
    fi
    sed -i "s/%packages/%packages --nocore/g" /opt/oemaker/config/$ARCH/livecd/devstation_livecd_$ARCH.ks
    
    cd /opt/oemaker
    REPOS=`echo "${STANDARD_PROJECT_REPO}" | sed 's/[ \t]*$//g'`
    set +e
    num=0
    set +u
    while [ "${num}" -lt 3 ]
    do
        bash -x oemaker -t devstation_netinst -p ${PRODUCTS} -v "${OS_VERSION}" -r "" -u "${REPOS}"
        if [ $? -eq 0 ];then
            break
        elif [ $? -eq 133 ]; then
            sleep 60
            ((num=num+1))
            continue
        else
            log_error "make_iso fail"
            break
        fi
    done
    [ "${num}" -ge 3 ] && log_error "retry make_iso fail"
    
    cd /result
    devstation_netinst_iso_name=$(ls *.iso)
    if [ -z "${devstation_netinst_iso_name}" ]; then
        log_error "No ISO file found in /result"
        exit 1
    fi

    create_checksum "${devstation_netinst_iso_name}"
    RELEASE_DIR="${release_dir}/DevStation/$ARCH"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"
    sshscp "${devstation_netinst_iso_name} ${devstation_netinst_iso_name}.sha256sum" "${RELEASE_DIR}"
}
