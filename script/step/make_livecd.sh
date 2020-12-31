#!/bin/bash
# Author: zhengxuye
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# make livecd chroot outside
# Globals:
# Arguments:
# Returns:
######################
function make_livecd()
{
    chroot_run "cd /home; bash make_version.sh make_livecd_inchroot"
}

######################
# make livecd in chroot
# Globals:
# Arguments:
# Returns:
######################
function make_livecd_inchroot()
{
    set -ex
    rm -rf /etc/yum.repos.d/* || true
    if [ ! -d /etc/yum.repos.d/ ]; then
         mkdir -p /etc/yum.repos.d
    fi
    cat config/repo_conf/obs-"${ARCH}".conf > /etc/yum.repos.d/EnCloudOS.repo

    yum clean all
    yum install -y lorax anaconda yum-langpacks libselinux-utils

    createrepo_euleros_all
    rm -rf /etc/yum.repos.d/EnCloudOS.repo || true

    set +e
    setenforce 0
    set -e

    sed -i "s/PRODUCT_NAME/${OS_NAME}-${OS_VERSION}/" "${BUILD_SCRIPT_DIR}/config/livecd/euleros-livecd_${ARCH}.ks"
    rm -rf /usr/share/lorax/templates.d/99-generic/live && cp -r config/livecd/live /usr/share/lorax/templates.d/99-generic/
    mkdir -p $(pwd)/tmp
    livemedia-creator --make-iso --ks=$(pwd)/config/livecd/euleros-livecd_"${ARCH}".ks --nomacboot --no-virt --project "${OS_NAME}" --releasever "${OS_VERSION}" --tmp $(pwd)/tmp --anaconda-arg="--nosave=all_ks" --dracut-arg="--xz" --dracut-arg="--add livenet dmsquash-live convertfs pollcdrom qemu qemu-net" --dracut-arg="--omit" --dracut-arg="plymouth" --dracut-arg="--no-hostonly" --dracut-arg="--debug" --dracut-arg="--no-early-microcode" --dracut-arg="--nostrip"
    #Release ISO to 158
    get_version
    release_dir=$(get_release_dir)
    TIME_DIR="${release_dir#${HTTP_DIR}}"

    cd tmp/*/images
    LIVECD_NAME="openEuler_minios_livecd.iso"
    LIVECD_TAR=$(ls *.iso)
    mv "${LIVECD_TAR}" "${LIVECD_NAME}"

    create_checksum "${LIVECD_NAME}"
    CUSTOM_DIR="${TIME_DIR}"
    RELEASE_DIR="${HTTP_DIR}/${CUSTOM_DIR}"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"
    sshscp "${LIVECD_NAME} ${LIVECD_NAME}${SHA256SUM}" "${RELEASE_DIR}"

    chmod_http
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi
    log_info "Release iso to http://${RELEASE_SERVER_IP}/${CUSTOM_DIR}/"

    cd -
    rm -rf *.log
    [ -n anaconda ] && rm -rf anaconda
    [ -n tmp ] && rm -rf tmp

    release_file="release_livecd"
    SSH_CMD="echo http://${RELEASE_SERVER_IP}/${CUSTOM_DIR}/${LIVECD_NAME} > ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${release_file}; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${release_file}"
    sshcmd "${SSH_CMD}"
    log_info "echo http://${RELEASE_SERVER_IP}/${CUSTOM_DIR}/${LIVECD_NAME} > ${release_file}"

    mkdir -pv "${WORK_DIR}"output
    html="${WORK_DIR}"output/release_livecd.html
    cat /dev/null > "${html}"
    echo "<html><body>" >> "${html}"
    echo '<div style="border: 1px solid;background-color:PowderBlue;text-align:;height:200px;width:100%">' >> "${html}"
    echo "<h1>The newest ${VERSION} Release</h1>" >> "${html}"
    echo "The release is created on $(date)" >> "${html}"
    echo "<h3>Download on windows: <a href=\"http://${RELEASE_SERVER_IP}/${CUSTOM_DIR}/${LIVECD_NAME}\" target='_blank'>${LIVECD_NAME}</a><br />" >> "${html}"
    echo "<p>Download on linux: run \"wget http://${RELEASE_SERVER_IP}/${CUSTOM_DIR}/${LIVECD_NAME}\"</p>" >> "${html}"
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
    set -e
    return 0
}

