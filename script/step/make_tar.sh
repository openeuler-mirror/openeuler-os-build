#!/bin/bash
# Author: zhengxuye
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e
source "${BUILD_SCRIPT_DIR}"/custom/custom_make_tar.sh

######################
# make tar chroot outside
# Globals:
# Arguments:
# Returns:
######################
function make_tar()
{
    chroot_run_bep "cd /home; bash make_version.sh make_tar_inchroot"
}

######################
# make tar in chroot
# Globals:
# Arguments:
# Returns:
######################
function make_tar_inchroot()
{
    set +u
    get_version
    release_dir=$(get_release_dir)
    TIME_DIR="${release_dir#${HTTP_DIR}/}"

    TIME=${TIME_DIR##*/}
    TIME=${TIME#"${version}"-}

    yum_conf="${BUILD_SCRIPT_DIR}/config/repo_conf/obs-repo.conf"
    yum clean all -c "${yum_conf}"
    rm -f sys-custom-config-*.noarch.rpm
    yumdownloader -y -c "${yum_conf}" --destdir ./ sys-custom-config.noarch
    rpm2cpio sys-custom-config-*.noarch.rpm |cpio -dim
    cd opt/sys-custom-config
    make_tar_native -v "${version}" -t "${TIME}"
    cd -
    TGZ_NAME=$(ls "${WORK_DIR}"/*.tar.gz)
    if [ $? -ne 0 ]; then
        log_error "Tar ${KIWITOOL_DIR} into ${version}.tar.gz failed"
    fi
    create_checksum "${TGZ_NAME}"
    CUSTOM_DIR="${TIME_DIR}"
    RELEASE_DIR="${HTTP_DIR}/${CUSTOM_DIR}"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"
    sshscp "${TGZ_NAME} ${TGZ_NAME}${SHA256SUM}" "${RELEASE_DIR}"

    chmod_http
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi
    log_info "Release iso to http://${RELEASE_SERVER_IP}/${CUSTOM_DIR}/"

    release_file="release"
    SSH_CMD="echo http://${RELEASE_SERVER_IP}/${CUSTOM_DIR}/${TGZ_NAME##*/} > ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${release_file}; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${release_file}"
    sshcmd "${SSH_CMD}"
    log_info "echo http://${RELEASE_SERVER_IP}/${CUSTOM_DIR}/${TGZ_NAME} > ${release_file}"

    if [ "${ISCI}" -eq "0" ]; then
        return 0
    fi
    mkdir -pv "${WORK_DIR}"output
    html="${WORK_DIR}"output/release_tar-"repo.html"
    cat /dev/null > "${html}"
    echo "<html><body>" >> "${html}"
    echo '<div style="border: 1px solid;background-color:PowderBlue;text-align:;height:200px;width:100%">' >> "${html}"
    echo "<h1>The newest ${VERSION} Release</h1>" >> "${html}"
    echo "The release is created on $(date)" >> "${html}"
    echo "<h3>Download on windows: <a href=\"http://${RELEASE_SERVER_IP}/${CUSTOM_DIR}/${TGZ_NAME##*/}\" target='_blank'>${TGZ_NAME##*/}</a><br />" >> "${html}"
    echo "<p>Download on linux: run \"wget http://${RELEASE_SERVER_IP}/${CUSTOM_DIR}/${TGZ_NAME##*/}\"</p>" >> "${html}"
    echo "<p>View the history version, please go to : <a href=\"http://${RELEASE_SERVER_IP}/${PRE_VERSION}/${VERSION}\" target='_blank'>http://${RELEASE_SERVER_IP}/${PRE_VERSION}/${VERSION}/</a></p></h3></div>" >> "${html}"
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
    set -ue

    return 0
}

