#!/bin/bash
# Author: xiaqirong
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# make netinst iso chroot outside
# Globals:
# Arguments:
# Returns:
######################
function make_netinst_iso()
{
    chroot_run "cd /home; bash make_version.sh make_netinst_iso_inchroot"
}

######################
# make netinst iso in chroot
# Globals:
# Arguments:
# Returns:
######################
function make_netinst_iso_inchroot()
{
    get_version
    release_dir=$(get_release_dir)
    TIME_DIR="${release_dir#${HTTP_DIR}}"
    TIME=${TIME_DIR##*/}
    TIME=${TIME#"${version}"-}

    yum_conf="${BUILD_SCRIPT_DIR}/config/repo_conf/obs-repo.conf"
    yum clean all -c "${yum_conf}"
    if rpm -q mkeuleros &> /dev/null; then
       yum remove mkeuleros -y
    fi
    if rpm -q lorax &> /dev/null; then
       yum remove lorax -y
    fi

    yum install mkeuleros lorax -y -c "${yum_conf}"
    cd /opt/mkeuleros

    if [ "${ARCH}" = "x86_64" ]; then
        mkeuleros_conf="config/standard/standard.conf"
    elif [ "${ARCH}" = "aarch64" ]; then
        mkeuleros_conf="config/aarch64/standard.conf"
    fi

    set +e
    num=0
    while [ "${num}" -lt 3 ]
    do
        bash -x mkeuleros.sh -f "${mkeuleros_conf}" -n "${OS_NAME}" -N "TRUE" -v "${OS_VERSION}" -s "SP1" -a "${ARCH}" -r "${OBS_STANDARD_REPO_URL}"
        if [ $? -eq 0 ];then
            break
        elif [ $? -eq 133 ]; then
            sleep 60
            ((num=num+1))
            continue
        else
            log_error "make_netinst_iso fail"
            break
        fi
    done
    if [ "${num}" -ge 3 ]; then
        log_error "retry make_netinst_iso fail"
    fi
    set -e

    cd /result
    TGZ_NAME=$(ls *netinst-"${ARCH}"-dvd.iso)
    if [ x"${TGZ_NAME}" == x'' ]; then
        log_error "can not find iso"
    fi
    create_checksum "${TGZ_NAME}"

    CUSTOM_DIR="${TIME_DIR}"
    #RELEASE_DIR="${HTTP_DIR}/${CUSTOM_DIR}"
    RELEASE_DIR="${release_dir}/ISO/$ARCH"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"
    sshscp "${TGZ_NAME} ${TGZ_NAME}${SHA256SUM}" "${RELEASE_DIR}"

    chmod_http
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi

    release_file="release_netinst"
    sub_dir=`echo ${RELEASE_DIR#*/dailybuild}`
    SSH_CMD="echo ${RELEASE_HTTP_URL}/${sub_dir}/${TGZ_NAME} > ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${release_file}; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${release_file}"
    sshcmd "${SSH_CMD}"

    DATE=`echo ${release_dir#*openeuler-}`

    html="release_netinst_iso.html"
    echo "<html><body>" >> "${html}"
    echo '<div style="border: 1px solid;background-color:PowderBlue;text-align:;height:200px;width:100%">' >> "${html}"
    echo "<h1>The newest ${VERSION} Release</h1>" >> "${html}"
    echo "The release is created on ${DATE}" >> "${html}"
    echo "<h3>Download on windows: <a href=\"${RELEASE_HTTP_URL}/${sub_dir}/${TGZ_NAME}\" target='_blank'>${TGZ_NAME}</a><br />" >> "${html}"
    echo "<p>Download on linux: run \"wget ${RELEASE_HTTP_URL}/${sub_dir}/${TGZ_NAME}\"</p>" >> "${html}"
    echo "<p>View the history version, please go to : <a href=\"${RELEASE_HTTP_URL}/${RELEASE_VERSION_DIR}/\" target='_blank'>${RELEASE_HTTP_URL}/${RELEASE_VERSION_DIR}/</a></p></h3></div>" >> "${html}"
    echo "<br />" >> "${html}"
    echo "</div></body></html>" >> "${html}"
    set +e
    sshscp "${html}" "${HTTP_DIR}/${PRE_VERSION}/${VERSION}"
    SSH_CMD="chmod 755 ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${html##*/}"
    sshcmd "${SSH_CMD}"
    chmod_http
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi
    set -e

    return 0
}

