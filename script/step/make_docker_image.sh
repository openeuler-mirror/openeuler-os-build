#!/bin/bash
set -e
yum_conf="${BUILD_SCRIPT_DIR}/config/repo_conf/obs-repo.conf"
dogsheng_arch="$(uname -m)"
function kiwi_init()
{
    if [ ! -f /usr/share/perl5/vendor_perl/Env.pm ]; then
        cp "${BUILD_SCRIPT_DIR}/config/docker_image/Env.pm" /usr/share/perl5/vendor_perl/
    fi

    if which kiwi &> /dev/null; then
        echo "kiwi has been ok"
    else
	if [ "$dogsheng_arch" == "x86_64" ]
	then
            wget http://172.16.1.95:88/mainline/standard_aarch64/rpmlist/xorriso.x86_64.rpm
	    wget http://172.16.1.95:88/mainline/standard_aarch64/rpmlist/umoci.x86_64.rpm
	    wget http://172.16.1.95:88/mainline/standard_aarch64/rpmlist/containers-common.x86_64.rpm
	    wget http://172.16.1.95:88/mainline/standard_aarch64/rpmlist/libisoburn.x86_64.rpm
            wget http://172.16.1.95:88/mainline/standard_aarch64/rpmlist/libburn.x86_64.rpm
	    yum clean all -c "${yum_conf}"
	    yum install -y python3-setuptools python3-docopt -c "${yum_conf}"
	    yum install -y python3-future -c "${yum_conf}"
	    yum install -y libisofs -c "${yum_conf}"
	    # yum install -y libisoburn -c "${yum_conf}"
	    yum install -y libburn.x86_64.rpm
	    yum install -y libisoburn.x86_64.rpm
	    #yum install -y libburn -c. "${yum_conf}"
	    yum install -y kde-filesystem -c "${yum_conf}"
	    yum install -y ostree-libs -c "${yum_conf}"
            yum install -y xorriso.x86_64.rpm
	    yum install -y kiwi -c "${yum_conf}"
	    yum install -y umoci.x86_64.rpm
	    yum install -y containers-common.x86_64.rpm
	    yum install -y skopeo -c "${yum_conf}"
	else
            wget http://172.16.1.95:88/mainline/standard_aarch64/rpmlist/xorriso.aarch64.rpm
            wget http://172.16.1.95:88/mainline/standard_aarch64/rpmlist/libisoburn.aarch64.rpm
            wget http://172.16.1.95:88/mainline/standard_aarch64/rpmlist/umoci.aarch64.rpm
            wget http://172.16.1.95:88/mainline/standard_aarch64/rpmlist/containers-common.aarch64.rpm
            yum clean all -c "${yum_conf}"
            yum install -y python3-setuptools python3-docopt -c "${yum_conf}"
            yum install -y python3-future -c "${yum_conf}"
            yum install -y libisofs -c "${yum_conf}"
            # yum install -y libisoburn -c "${yum_conf}"
            yum install -y libburn -c "${yum_conf}"
            yum install -y libisoburn.aarch64.rpm
            yum install -y kde-filesystem -c "${yum_conf}"
            yum install -y ostree-libs -c "${yum_conf}"
      
            yum install -y xorriso.aarch64.rpm
            yum install -y kiwi -c "${yum_conf}"
            yum install -y umoci.aarch64.rpm
            yum install -y containers-common.aarch64.rpm
            # yum install -y ostree-libs.aarch64.rpm
            # yum install -y skopeo.aarch64.rpm
            yum install -y skopeo -c "${yum_conf}"
        fi
    fi
    umask_value=$(umask)
    if [ "x${umask_value}" != "x0022" ]; then
        umask 0022
    fi
    if [ ! -d /var/run/screen/S-root ]; then
        mkdir -p /var/run/screen/S-root
    fi
}

######################
# make docker image chroot outside 
# Globals:
# Arguments:
# Returns:
######################
function make_docker_image()
{
    chroot_run "cd /home; bash make_version.sh make_docker_image_inchroot"
}

######################
# make docker image in chroot
# Globals:
# Arguments:
# Returns:
######################
function make_docker_image_inchroot()
{
    #docker_init
    kiwi_init
    get_version
    release_dir=$(get_release_dir)

    version_time="${release_dir#${HTTP_DIR}}"
    version_time=${version_time##*/}

    repo_dir="${WORK_DIR}repository"
    img_dir="${WORK_DIR}image"
    cfg_dir="${WORK_DIR}config"

    if [ -d "${img_dir}" ]; then
        rm -rf "${img_dir}"
    fi

    mkdir -p "${img_dir}"

    if [ -d "${repo_dir}" ]; then
        rm -rf "${repo_dir}"
    fi

    mkdir -p "${repo_dir}"

    if [ -d "${cfg_dir}" ]; then
        rm -rf "${cfg_dir}"
    fi

    mkdir -p "${cfg_dir}"


    RELEASE_DIR="${release_dir}/docker_img/$ARCH"

    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"

    # To workaround one kiwi problem, otherwise, kiwi will copy passwd and group file
    # from host to baseimage's rootfs.
    # Copy passwd(from setup package) file to /var/adm/fillup-templates/passwd.aaa_base
    # Copy group(from setup package) file to /var/adm/fillup-templates/group.aaa_base
    mkdir -p /var/adm/fillup-templates/
    cp config/docker_image/passwd /var/adm/fillup-templates/passwd.aaa_base
    cp config/docker_image/group /var/adm/fillup-templates/group.aaa_base

    # build
    sed -i "s#IMAGE_NAME#${version_time}#" "${BUILD_SCRIPT_DIR}"/config/docker_image/config.xml

    MOUNT_DIR=$(echo "${release_dir}" | cut -d '/' -f 5-9)
    mkdir -p /mnt/EulerOS
    TMPDIR=$(mktemp '/mnt/EulerOS/docker-XXXX')-$(date +%F-%T)
    mkdir -p "${TMPDIR}"

    for repo_url in $(echo "${OBS_STANDARD_REPO_URL}" | xargs)
    do
        sed -i "/obs_repo_here/a <repository type=\"rpm-md\"><source path=\"${repo_url}\" \/></repository>" "${BUILD_SCRIPT_DIR}"/config/docker_image/config.xml
    done
    cp -a "${BUILD_SCRIPT_DIR}"/config/docker_image/config.xml "${cfg_dir}"/config.xml
    cp "${BUILD_SCRIPT_DIR}"/config/docker_image/images.sh "${cfg_dir}"

    chmod 700 /var/run/screen/S-root
    #Removing yum repos in kiwi build
    if [ -d /var/cache/kiwi/yum ];then
        rm -rf /var/cache/kiwi/yum
    fi
    kiwi compat --build "${cfg_dir}" -d "${img_dir}"
    if [ $? -ne 0 ];then
        log_error "Failed on kiwi build docker image" &> /dev/null
    fi

    # upload image
    docker_img_path_tmp=$(ls "${img_dir}"/*.tar.xz)
    docker_img_path="${img_dir}/openEuler-docker.${ARCH}.tar.xz"
    mv "${docker_img_path_tmp}" "${docker_img_path}"

    cd "${img_dir}"
    sha256sum "${docker_img_path##*/}" > "${docker_img_path##*/}""${SHA256SUM}"
    cd - > /dev/null
    sshscp "${docker_img_path} ${docker_img_path}${SHA256SUM}" "${RELEASE_DIR}"
    if [ $? -ne 0 ]; then
        log_error "Failed upload docker image"
    fi

    log_info "Release ${docker_img_path} to ${RELEASE_SERVER_IP}:${RELEASE_DIR}"
}
