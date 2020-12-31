#!/bin/bash
# Author: xudengfeng
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# make debug tool chroot outside
# Globals
# Arguments:
# Returns:
######################
function make_tools_debug_tools()
{
    chroot_run_bep "cd /home; bash make_version.sh debug_tools_inchroot"
}

######################
# make debug tool in chroot
# Globals:
# Arguments:
# Returns:
######################
function debug_tools_inchroot()
{
    rm -rf "${BUILD_SCRIPT_DIR}"/"${DEBUG_TOOLS}"
    mkdir -p "${BUILD_SCRIPT_DIR}"/"${DEBUG_STD}"
    mkdir -p "${BUILD_SCRIPT_DIR}"/"${DEBUG_STG}"

    log_info "==========Start debug_tools vmcore_debug_tool====standard======"
    vmcore_tool_dir="vmcore_debug_tool"
    vmcore_tool_tar="vmcore_debug_tool.tar.gz"
    get_vmcoretool "${WORK_DIR}"repos/Euler "${MAKE_TOOLS}"/vmcore_debug_tool.rpmlist "${vmcore_tool_dir}" "${vmcore_tool_tar}" "standard"
    if [ -f "./${vmcore_tool_tar}" ]; then
        create_checksum "${vmcore_tool_tar}"
        cp -ap "${vmcore_tool_tar}" "${vmcore_tool_tar}${SHA256SUM}" ./"${DEBUG_STD}"
        rm -f "${vmcore_tool_tar}" "${vmcore_tool_tar}${SHA256SUM}"
    else
        log_error "no ${vmcore_tool_tar}"
        exit 1
    fi
    log_info "==========Start DebugTools vmcore_debug_tool====storage======"
    vmcore_tool_dir="vmcore_debug_tool"
    vmcore_tool_tar="vmcore_debug_tool.tar.gz"
    get_vmcoretool "${WORK_DIR}"repos/Euler "${MAKE_TOOLS}"/vmcore_debug_tool_storage.rpmlist "${vmcore_tool_dir}" "${vmcore_tool_tar}" "storage"
    if [ -f "./${vmcore_tool_tar}" ]; then
        create_checksum "${vmcore_tool_tar}"
        cp -ap "${vmcore_tool_tar}" "${vmcore_tool_tar}${SHA256SUM}" ./"${DEBUG_STG}"/
        rm -f "${vmcore_tool_tar}" "${vmcore_tool_tar}${SHA256SUM}"
    else
        log_error "no ${vmcore_tool_tar}"
        exit 1
    fi


    log_info "==========start debug_tools debug_tool=========="
    debug_tool_dir="debug_tool"
    debug_tool_tar="debug_tool.tar.gz"
    if [ x"${ARCH}" == x"x86_64" ]; then
        sed -i 's/aarch64/x86_64/g' "${MAKE_TOOLS}"/debug_tool.rpmlist
    fi
    make_tool "${WORK_DIR}"repos/Euler "${MAKE_TOOLS}"/debug_tool.rpmlist "${debug_tool_dir}" "${debug_tool_tar}"
    if [ -f "./${debug_tool_tar}" ]; then
        create_checksum "${debug_tool_tar}"
        cp -ap "${debug_tool_tar}" "${debug_tool_tar}${SHA256SUM}" ./"${DEBUG_STD}"/
        rm -f "${debug_tool_tar}" "${debug_tool_tar}${SHA256SUM}"
    else
        log_error "no ${debug_tool_tar}"
        exit 1
    fi
    log_info "==========Start debug_tools perf_oprofile_tool=========="
    perf_tool_dir="perf_oprofile_tool"
    perf_tool_tar="perf_oprofile_tool.tar.gz"
    make_tool "${WORK_DIR}"repos/Euler "${MAKE_TOOLS}"/perf_oprofile_tool.rpmlist "${perf_tool_dir}" "${perf_tool_tar}"
    if [ -f "./${perf_tool_tar}" ]; then
        create_checksum "${perf_tool_tar}"
        cp -ap "${perf_tool_tar}" "${perf_tool_tar}${SHA256SUM}" ./"${DEBUG_STD}"/
        rm -f "${perf_tool_tar}" "${perf_tool_tar}${SHA256SUM}"
    else
        log_error "no ${perf_tool_tar}"
        exit 1
    fi

    RELEASEDIR=$(get_release_dir)
    RELEASE_DIR="${RELEASEDIR}"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"
    sshscp "${DEBUG_TOOLS}" "${RELEASE_DIR}"
    chmod_http
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi
}
