#!/bin/bash
set -e

function make_hmi()
{
    chroot_run "cd /home; bash make_version.sh make_hmi_inchroot"
}

function make_hmi_inchroot()
{
    local counter=0
    version="openeuler"
    RESULT_HMI="/usr1/mkeuleros/result_hmi"
    [ -d "${RESULT_HMI}" ] && rm -rf "${RESULT_HMI}/*"
    mkdir -p "${RESULT_HMI}"

    HMI_REPOS=$(echo "${OBS_STANDARD_REPO_URL}")
    #HMI_REPOS=$(echo "${OBS_STANDARD_REPO_URL}" | sed 's/ / -r /g')
    yum -c "${BUILD_SCRIPT_DIR}"/config/repo_conf/obs-repo.conf clean all
    if [ "${ARCH}" = "aarch64" ];then
        yum install -y CreateImage sudo parted dosfstools e2fsprogs -c "${BUILD_SCRIPT_DIR}"/config/repo_conf/obs-repo.conf
    else
        yum install -y CreateImage sudo parted -c "${BUILD_SCRIPT_DIR}"/config/repo_conf/obs-repo.conf
    fi
    pushd "${RESULT_HMI}"
    set +e
    chmod 755 /usr/bin/create-image
    create-image -r "${HMI_REPOS}" 
    mv system.img "${version}"-hmi.raw
    qemu-img convert "${version}"-hmi.raw -O qcow2 "${VM_IMAGE_NAME}"
    local ret_value=$?
    while [ "${ret_value}" != 0 ]
    do
        qemu-img convert -f raw -O qcow2 "${version}-hmi.raw" "${VM_IMAGE_NAME}"
        ret_value=$?
        counter="$(expr $counter + 1)"
        if [ "${counter}" -gt 3 ]; then
            log_error "qemu-img convert failed"
        fi
    done
    log_info "qemu-img convert success!"

    xz -T 0 -9 --lzma2=dict=8MiB "${VM_IMAGE_NAME}"
    wait 120
    popd
    cd "${RESULT_HMI}"

    TGZ_QCOW2="$(ls *.qcow2.xz)"
    create_checksum "${TGZ_QCOW2}"

    release_dir="$(get_release_dir)"
    RELEASE_DIR="${release_dir}/virtual_machine_img/$ARCH"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"
    sshscp "${TGZ_QCOW2} ${TGZ_QCOW2}${SHA256SUM}" "${RELEASE_DIR}"
    set +e
    chmod_http
    set -ue
    return 0
}
