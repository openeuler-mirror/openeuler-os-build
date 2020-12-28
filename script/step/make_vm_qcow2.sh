#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.

set -e

######################
# make vm qcow2 chroot outside
# Globals:
# Arguments:
# Returns:
######################
function make_vm_qcow2()
{
    chroot_run_bep "cd /home; bash make_version.sh make_vm_qcow2_inchroot"
}

######################
# make vm qcow2 in chroot 
# Globals:
# Arguments:
# Returns:
######################
function make_vm_qcow2_inchroot()
{
    remoteip=10.175.112.72
    remoteroot=root
    remotepwd=EulerLinux
    qcow2_image_dir=qcow2_image
    basedir=/home/V3R1/arm64_make_qcow2/arm64_standard
    remote_img_dir="${basedir}/qcow2_image"

    # remote build
    sh ./tools/sshcmd.sh -c "rm -rf ${basedir};mkdir -p ${basedir}" -m "${remoteip}" -u "${remoteroot}" -p "${remotepwd}"

    # mount iso for repo
    release_dir="$(get_release_dir)"
    set +e

    sh ./tools/sshscp.sh -d "${remoteip}":"${basedir}"/ -s $(pwd)  -p "${remotepwd}" -r
    sh ./tools/sshcmd.sh -c "cd ${basedir}/local_script; sed -i \"0,/STARTTIME/ s/STARTTIME/#STARTTIME/\" make_version.sh; \
                             sed -i \"0,/exec/ s/exec/#exec/\" make_version.sh;bash make_version.sh make_vm_qcow2_main" \
                              -m "${remoteip}" -u "${remoteroot}" -p "${remotepwd}"
    set -e

    # upload
    [ -n "${qcow2_image_dir}" ] && rm -rf "${qcow2_image_dir}"
    mkdir "${qcow2_image_dir}"
    RELEASE_DIR="${release_dir}/virtual_machine_img/$ARCH"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"

    sh "${TOOLS}"/safe_sshscp.sh -p "${remotepwd}" -s "${remoteip}:${remote_img_dir}/*.qcow2" -d "${qcow2_image_dir}" -r
    sh "${TOOLS}"/safe_sshscp.sh -p "${remotepwd}" -s "${remoteip}:${remote_img_dir}/*.qcow2${SHA256SUM}" -d "${qcow2_image_dir}" -r
    cd "${qcow2_image_dir}"
    qcow2_img="$(ls *.qcow2)"
    qcow2_sha256=$(ls *.qcow2"${SHA256SUM}")

    sshscp "${qcow2_img} ${qcow2_sha256}" "${RELEASE_DIR}"
    if [ $? -ne 0 ]; then log_error "Failed upload qcow2";fi;
    chmod_http
    if [ $? -ne 0 ]; then log_error "Failed in chmod_http";fi;

    log_info "Release ${qcow2_img} ${qcow2_sha256} to ${RELEASE_SERVER_IP}:${RELEASE_DIR}"
}

######################
# make vm qcow2 main function 
# Globals:
# Arguments:
# Returns:
######################
function make_vm_qcow2_main()
{
    get_version
    release_dir="$(get_release_dir)"
    version_time=${release_dir#/repo/openeuler/dailybuild/}
    version_time=${version_time##*/}

    IMG_DIR="../qcow2_image"

    set +e
    if [ ! -d "${IMG_DIR}" ]; then mkdir -p "${IMG_DIR}";fi;

    if [ -f config/ks/euleros-ks.cfg ]; then
        rm /var/www/html/ks/euleros-ks.cfg
        cp -f config/ks/euleros-ks.cfg /var/www/html/ks/euleros-ks.cfg
        chmod -R 755 /var/www/html/ks
    fi

    cp -f config/vm-install.xml "${IMG_DIR}"/
    cp -f config/grub.cfg /var/lib/tftpboot/
    pushd "${IMG_DIR}"

    rm -f vm*.log
    if [ ! -d euleros-iso ];then mkdir euleros-iso; else umount euleros-iso;fi

    if [ -f "${DVD_NAME}" ]; then rm "${DVD_NAME}";fi;

    MOUNT_DIR=$(echo "${release_dir}" | cut -d '/' -f 5-9)
    wget -q http://euleros_test:euleros_test@"${RELEASE_SERVER_IP}/${MOUNT_DIR}${DVD_NAME}"
    mount "${DVD_NAME}" euleros-iso

    if [ ! -f  /var/lib/tftpboot/grubaa64.efi ]; then cp euleros-iso/EFI/BOOT/grubaa64.efi /var/lib/tftpboot/;fi;
    cp -f euleros-iso/images/pxeboot/vmlinuz /var/lib/tftpboot/
    cp -f euleros-iso/images/pxeboot/initrd.img /var/lib/tftpboot/
    umount euleros-iso
    chmod -R 755 /var/lib/tftpboot/

    img_name="${OS_NAME}-${OS_VERSION}.${ARCH}.qcow2"
    if [ -f "${img_name}" ]; then rm "${img_name}";fi;

    UUID="$(cat /proc/sys/kernel/random/uuid)"
    VM=vm"${UUID}"
    sed -i "s/VM_NAME/${VM}/g" vm-install.xml
    sed -i "s:VM_PATH:${PWD}:g" vm-install.xml
    DATE=$(date +%Y-%m-%d)
    sed -i "s:LOG_PATH:${PWD}/${VM}_${DATE}_install.log:g" vm-install.xml
    virsh define vm-install.xml
    qemu-img create -f qcow2 "${img_name}" 100G
    DATE="$(date +%Y-%m-%d)"
    virsh start "${VM}"
    VM_STATUS="running"
    INSTALL_TIME=0
    while [ "${VM_STATUS}" = "running" ] && [ "${INSTALL_TIME}" -le 1800 ]; do
        sleep 30
        INSTALL_TIME="$(expr ${INSTALL_TIME} + 30)"
        VM_STATUS=$(virsh domstate "${VM}")
    done

    grep -nr "Power down" "${VM}"_"${DATE}"_install.log
    if [ $? -eq 0 ]; then
        virsh undefine "${VM}"
        log_info "vm install successful"
    else
        cat "${VM}_${DATE}_install.log"
        log_info "vm status is ${VM_STATUS} "
        virsh destroy "${VM}"
        virsh undefine "${VM}"
        rm "${img_name}"
        log_error "install vm failed"
    fi

    set -e
    sha256sum "${img_name}" > "${img_name}${SHA256SUM}"
    popd
}

