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
function make_desktop_iso()
{
    chroot_run "cd /home; bash make_version.sh make_desktop_iso_inchroot"
}
######################
# 在chroot中构建iso镜像
# Globals:
# Arguments:
# Returns:
######################
function make_desktop_iso_inchroot()
{
    get_version
    release_dir=$(get_release_dir)
    TIME_DIR="${release_dir#${HTTP_DIR}}"
    TIME=${TIME_DIR##*/}
    TIME=${TIME#"${version}"-}
    yum_conf="${BUILD_SCRIPT_DIR}/config/repo_conf/repofile.conf"
    yum clean all -c "${yum_conf}"
    if rpm -q oemaker &> /dev/null; then
        yum remove oemaker -y
    fi
    if rpm -q lorax &> /dev/null; then
        yum remove lorax -y
    fi
    yum install oemaker lorax -y -c "${yum_conf}"
    cd /opt/oemaker
    REPOS=`echo "${STANDARD_PROJECT_REPO} ${EPOL_PROJECT_REPO} ${THIRD_REPO}" | sed 's/[ \t]*$//g'`
    set +e
    num=0
    set +u
    while [ "${num}" -lt 3 ]
    do
        bash -x oemaker -t desktop -p ${PRODUCTS} -v "${OS_VERSION}" -r "" -s "${REPOS}"
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
    if [ "${num}" -ge 3 ]; then
        log_error "retry make_iso fail"
    fi
    set -e
    cd "/result"

    TGZ_NAME=$(ls *"${ARCH}"-dvd.iso)
    if [ x"${TGZ_NAME}" == x'' ]; then  log_error "can not find iso";fi
    create_checksum "${TGZ_NAME}"
    iso_rpmlist="${OS_NAME}-Desktop-${OS_VERSION}-${ARCH}.rpmlist"
    mkdir temp && mount *"${ARCH}"-dvd.iso temp
    cd temp/Packages
    ls *.rpm > "../../${iso_rpmlist}"
    cd ../..
    umount temp
    [ -n temp ] && rm -rf temp
    RELEASE_DIR="${release_dir}/workstation/$ARCH"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"
    sshscp "${TGZ_NAME} ${TGZ_NAME}${SHA256SUM} ${iso_rpmlist}" "${RELEASE_DIR}"
    [ -n "${iso_rpmlist}" ] && rm -rf "${iso_rpmlist}"
    return 0
}
