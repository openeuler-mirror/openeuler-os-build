#!/bin/bash
# Author: xudengfeng
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# get_kernel_rpm
# Globals:
# Arguments:
# Returns:
######################
function make_other_tools()
{
    log_info "==========Start get_kernel_rpm=========="
    get_kernel_rpm
    cd "$KERNEL_RPM"
    for dir in $(ls ./)
    do
        if [ -d "$dir" ]; then
            cd "$dir"
            for file in $(ls ./)
            do
                create_checksum "$file"
            done
            cd ..
        fi
    done
    cd ..

    RELEASEDIR=$(get_release_dir)
    RELEASE_DIR="${RELEASEDIR}/"
    SSH_CMD="mkdir -p $RELEASE_DIR"
    sshcmd "$SSH_CMD"
    sshscp "$KERNEL_RPM" "$RELEASE_DIR"
    chmod_http
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi
}


function get_kernel_rpm()
{
    local repo="KERNEL_RPM"
    [ -d "${repo}" ] && rm -rf "$repo"
    python "${BUILD_SCRIPT_DIR}"/tools/repo_maker.py -f "${BUILD_SCRIPT_DIR}"/make_tools/kernel_rpm_list.xml -d "${repo}" -p "${OBS_SERVER_IP}:82"
    if [ $? -ne 0 ]; then
        log_error "Error: when get kernelrpm"
    fi
}

