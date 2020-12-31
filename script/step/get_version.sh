#!/bin/bash
# Author: renhongxun
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# 获取构建版本
# Globals:
# Arguments:
# Returns:
######################
function get_version()
{
    #if [ "${ISCI}" -eq 0 ]; then
    #    version="${MYVERSION}"
    #    log_info "version is ${version}"
    #    return 0
    #fi
    version_on_web='version'
    rm -f ./"${version_on_web}"
    sshscp_from "${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${version_on_web}" "./"
    if [ $? -ne 0 ]; then
        log_error "Failed on sshscp_from ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${version_on_web} ./" &> /dev/null
    fi
    version=$(cat "${version_on_web}")
    [ -z "${version}" ] && log_error "You must set version in config file or from CI web page"
    log_info "version is ${version}"
}
