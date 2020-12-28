#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.

set -e

######################
# make make_compile_tools chroot outside
# Globals:
# Arguments:
# Returns:
######################
function make_compile_tools()
{
    [[ -d "${WORK_DIR}" ]] || mkdir -p "${WORK_DIR}"
    REPO="${WORK_DIR}compile_tools"

    [ -d "${REPO}" ] && rm -rf "${REPO}"
    python "${BUILD_SCRIPT_DIR}"/tools/repo_maker.py -f "${BUILD_SCRIPT_DIR}"/config/compile_tools.xml -d "${REPO}" -p "${OBS_SERVER_IP}:82"
    if [ $? -ne 0 ]; then
        log_error "Failed on repo_make compile_tools.xml"
    else
        log_info "Suessessful on repo_make compile_tools.xml"
    fi
    cd "${WORK_DIR}"
    TGZ_NAME=compile_tools
    tar czf "${TGZ_NAME}.tar.gz" "${TGZ_NAME}"
    create_checksum "${TGZ_NAME}".tar.gz
    release_dir="$(get_release_dir)"
    RELEASE_DIR="${release_dir}CompileTools/"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"
    sshscp "${TGZ_NAME}.tar.gz ${TGZ_NAME}.tar.gz${SHA256SUM}" "${RELEASE_DIR}"

}
