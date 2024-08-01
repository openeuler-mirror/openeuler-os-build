#!/bin/bash
# Author: dongjian

set -e

######################
# make everything iso chroot outside
# Globals:
# Arguments:
# Returns:
######################
function make_iso_everything()
{
    chroot_run "cd /home; bash make_version.sh make_iso_everything_inchroot"
}

######################
# make everything iso in chroot
# Globals:
# Arguments:
# Returns:
######################
function make_iso_everything_inchroot()
{
    get_version
    release_dir=$(get_release_dir)
    TIME_DIR="${release_dir#${HTTP_DIR}}"
    TIME=${TIME_DIR##*/}
    TIME=${TIME#"${version}"-}

    yum_conf="${BUILD_SCRIPT_DIR}/config/repo_conf/repofile.conf"
    yum clean all -c "${yum_conf}"

    yum install python3 -y -c "${yum_conf}"
    if [[ $checkdep == true ]];then
        python3 ${BUILD_SCRIPT_DIR}/tools/check_dep.py -d /tmp -l allist -f check_dep.log -e ${UNABLE_INSTALL_LIST} -c "${yum_conf}" -r obs-standard
    fi

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
        sed -i "/>${rpmname}<\/packagereq>/d" config/rpmlist.xml
        sed -i '/<packagelist type="exclude">/a\        <packagereq>'$rpmsname'</packagereq>' config/rpmlist.xml
    done
    REPOS=`echo "${STANDARD_PROJECT_REPO} ${THIRD_REPO}" | sed 's/[ \t]*$//g'`
    set +e
    num=0
    while [ "${num}" -lt 3 ]
    do
        bash -x oemaker -t everything -p ${PRODUCTS} -v "${OS_VERSION}" -r "" -s "${REPOS}"
        if [ $? -eq 0 ];then
            break
        elif [ $? -eq 133 ]; then
            sleep 60
            ((num=num+1))
            continue
        else
            log_error "make_iso_everything fail"
            break
        fi
    done
    if [ "${num}" -ge 3 ]; then
        log_error "retry make_iso_everything fail"
    fi
    set -e

    cd /result
    TGZ_NAME=$(ls *-dvd.iso)
    if [ x"${TGZ_NAME}" == x'' ]; then
        log_error "can not find iso"
    fi
    create_checksum "${TGZ_NAME}"

    RELEASE_DIR="${release_dir}/ISO/$ARCH"
    MOUNT_DIR="${release_dir}/everything/$ARCH"
    SSH_CMD="mkdir -p ${RELEASE_DIR} ${MOUNT_DIR}"
    sshcmd "${SSH_CMD}"
    sshscp "${TGZ_NAME} ${TGZ_NAME}${SHA256SUM}" "${RELEASE_DIR}"
    set +e
    ret=$(get_repose ssh -i ~/.ssh/super_publish_rsa ${SSHPORT} root@${RELEASE_SERVER_IP} mount | grep ${RELEASE_VERSION_DIR} | grep everything/${ARCH} | grep -v test | awk '{print $3}')
    for mp in $ret
    do
        ret=$(get_repose ssh -i ~/.ssh/super_publish_rsa ${SSHPORT} root@${RELEASE_SERVER_IP} umount $mp)
    done
    SSH_CMD="mount -t iso9660 -o loop ${RELEASE_DIR}/${TGZ_NAME} ${MOUNT_DIR}"
    sshcmd "${SSH_CMD}"
    set -e
    chmod_http
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi

    release_file="release_everything"
    sub_dir=`echo ${RELEASE_DIR#*/dailybuild}`
    SSH_CMD="echo ${RELEASE_HTTP_URL}/${sub_dir}/${TGZ_NAME} > ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${release_file}; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${release_file}"
    sshcmd "${SSH_CMD}"

    DATE=`echo ${release_dir#*openeuler-}`
    html="release_iso_everything.html"
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

