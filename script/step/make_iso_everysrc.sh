#!/bin/bash
set -e

######################
# make debug iso chroot outside
# Globals:
# Arguments:
# Returns:
######################
function make_iso_everysrc()
{
    chroot_run "cd /home; bash make_version.sh make_iso_everysrc_inchroot"
}

######################
# make debug iso in chroot
# Globals:
# Arguments:
# Returns:
######################
function make_iso_everysrc_inchroot()
{
    get_version
    release_dir=$(get_release_dir)
    TIME_DIR="${release_dir#${HTTP_DIR}}"
    TIME=${TIME_DIR##*/}
    TIME=${TIME#"${version}"-}

    yum_conf="${BUILD_SCRIPT_DIR}/config/repo_conf/obs-repo.conf"
    yum clean all -c "${yum_conf}"
    if rpm -q oemaker &> /dev/null; then
       yum remove oemaker -y
    fi
    if rpm -q lorax &> /dev/null; then
       yum remove lorax -y
    fi

    yum install oemaker lorax -y -c "${yum_conf}"
    cd /opt/oemaker
    rpmsnames=`cat ${UNABLE_INSTALL_LIST}`
    for rpmsname in $rpmsnames
    do
        sed -i '/<packagelist type="exclude">/a\        <packagereq>'$rpmsname'</packagereq>' config/rpmlist.xml
    done
    sed -i '/parse_rpmlist_xml \"conflict\"/d' rpm.sh
    OBS_STANDARD_REPO_URL=${OBS_STANDARD_REPO_URL%/*}
    set +e
    num=0
    while [ "${num}" -lt 3 ]
    do
        bash -x oemaker -t everything_src -p ${PRODUCTS} -v "${OS_VERSION}" -r "" -s "${OBS_STANDARD_REPO_URL}/standard_aarch64 ${OBS_STANDARD_REPO_URL}/standard_x86_64"
        if [ $? -eq 0 ];then
            break
        elif [ $? -eq 133 ]; then
            sleep 60
            ((num=num+1))
            continue
        else
            log_error "make_iso_debug fail"
            break
        fi
    done
    if [ "${num}" -ge 3 ]; then
        log_error "retry make_iso_debug fail"
    fi
    set -e

    cd /result
    TGZ_NAME=$(ls *-dvd.iso)
    if [ x"${TGZ_NAME}" == x'' ]; then
        log_error "can not find iso"
    fi
    create_checksum "${TGZ_NAME}"

    #TIME_DIR="${PRE_VERSION}/${VERSION}/${version}-${TIME}"
    #log_info "${HTTP_DIR}/${TIME_DIR}" > "${WORK_DIR}"releasedir_info
    CUSTOM_DIR="${TIME_DIR}"
    RELEASE_DIR="${release_dir}/ISO/source"
    MOUNT_DIR="${release_dir}/source"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"
    sshscp "${TGZ_NAME} ${TGZ_NAME}${SHA256SUM}" "${RELEASE_DIR}"
    set +e
    ret=$(get_repose ssh -i ~/.ssh/super_publish_rsa ${SSHPORT} root@${RELEASE_SERVER_IP} mount | grep ${RELEASE_VERSION_DIR} | grep source | grep -v test | awk '{print $3}')
    for mp in $ret
    do
        ret=$(get_repose ssh -i ~/.ssh/super_publish_rsa ${SSHPORT} root@${RELEASE_SERVER_IP} umount $mp)
    done
    SSH_CMD="mkdir -p ${MOUNT_DIR}"
    sshcmd "${SSH_CMD}"
    SSH_CMD="mount -t iso9660 -o loop ${RELEASE_DIR}/${TGZ_NAME} ${MOUNT_DIR}"
    sshcmd "${SSH_CMD}"
    set -e

    chmod_http
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi

    release_file="release_source"
    sub_dir=`echo ${RELEASE_DIR#*/dailybuild}`
    SSH_CMD="echo ${RELEASE_HTTP_URL}/${sub_dir}/${TGZ_NAME} > ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${release_file}; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${release_file}"
    sshcmd "${SSH_CMD}"
    sed +e
    DATE=`echo ${release_dir#*openeuler-}`
    html="release_iso_source.html"
    echo "<html><body>" >> "${html}"
    echo '<div style="border: 1px solid;background-color:PowderBlue;text-align:;height:200px;width:100%">' >> "${html}"
    echo "<h1>The newest ${VERSION} Release</h1>" >> "${html}"
    echo "The release is created on ${DATE}" >> "${html}"
    echo "<h3>Download on windows: <a href=\"${RELEASE_HTTP_URL}/${sub_dir}/${TGZ_NAME}\" target='_blank'>${TGZ_NAME}</a><br />" >> "${html}"
    echo "<p>Download on linux: run \"wget ${RELEASE_HTTP_URL}/${sub_dir}/${TGZ_NAME}\"</p>" >> "${html}"
    echo "<p>View the history version, please go to : <a href=\"${RELEASE_HTTP_URL}/${sub_dir}/${TGZ_NAME}\" target='_blank'>${RELEASE_HTTP_URL}/${RELEASE_VERSION_DIR}/</a></p></h3></div>" >> "${html}"
    echo "<br />" >> "${html}"
    echo "</div></body></html>" >> "${html}"
    set +e
    sshscp "${html}" "${HTTP_DIR}/${PRE_VERSION}/${VERSION}/"
    SSH_CMD="chmod 755 ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${html##*/}"
    sshcmd "${SSH_CMD}"
    chmod_http
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi
    set -e

    return 0
}

