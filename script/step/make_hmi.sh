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
    yum_conf="${BUILD_SCRIPT_DIR}/config/repo_conf/repofile.conf"
    [ -d "${RESULT_HMI}" ] && rm -rf "${RESULT_HMI}/*"
    mkdir -p "${RESULT_HMI}"
    
    HMI_REPOS="${STANDARD_PROJECT_REPO}"
    yum clean all -c ${yum_conf}
    yum install -y qemu-img bc sudo parted dosfstools e2fsprogs xz -c ${yum_conf}

    rm -rf CreateImage
    git clone https://gitee.com/openeuler/CreateImage.git
    if [ $? -ne 0 ];then
        echo "[ERROR] git clone CreateImage failed"
        exit 1
    fi
    sed -i '/#disbale other repos/i \cp /etc/resolv.conf ${TARGET_ROOT}/etc/' CreateImage/hooks/root.d/01-create-root
    sed -i '/most reliable/i \rm -f ${TARGET_ROOT}/etc/resolv.conf' CreateImage/hooks/root.d/01-create-root
    sed -i '47a \cat ${repo_config}' CreateImage/hooks/root.d/01-create-root
    
    yumdownloader kernel -c ${yum_conf} 
    kernel_version=$(rpm -qi kernel-* | grep Version | awk '{print $NF}')
    if [[ "${kernel_version}" > "6.1.0" ]] || [[ "${kernel_version}" == "6.1.0" ]];then
	    sed -i 's/nomodeset//g' CreateImage/hooks/finalise.d/50-bootloader
    fi
    rm -f kernel-*.rpm
    rm -rf /usr/share/CreateImage && mkdir -p /usr/share/CreateImage
    cp CreateImage/bin/* /usr/bin/
    cp -a CreateImage/lib CreateImage/hooks CreateImage/config /usr/share/CreateImage
    rm -rf CreateImage

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
