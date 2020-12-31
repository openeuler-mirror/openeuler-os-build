#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# 触发obs编译并等待结果直至任务结束
# Globals:
# Arguments:
# Returns:
######################
function build_and_wait()
{
    get_version

    release_dir=$(get_release_dir)
    TIME_DIR=${release_dir#/repo/openeuler/dailybuild/}
    TIME=${TIME_DIR##*/}

    if echo "${CI_PROJECT}" | grep '_gcov'; then
        update_sys_custom_tool
    fi

    local service_list="${BUILD_SCRIPT_DIR}"/config/service_list_"${ARCH}".xml
    if [ "x${arm2x86}" = "xx86_64" ]; then
        service_list="${BUILD_SCRIPT_DIR}"/config/service_list_aarch64.xml
    fi

    init_osc
    set +e
    python "${BUILD_SCRIPT_DIR}"/tools/obs_build.py -s "${service_list}" -t 120
    result=$?

    if ! echo "${CI_PROJECT}" | grep '_gcov'; then
        PRJS=$(cat "${service_list}" | grep 'project name' | awk -F'"' '{print $2}' | sort | uniq)
        PRJS=$(echo "${PRJS}" | sed 's/ /@/g')
        curl  "${JENKINS_URL}"/job/obs_meta_tags/buildWithParameters?token=xdf -d GERRIT_BRANCH='next' \
              -d GERRIT_OBSLIST="${PRJS}" \
              -d GERRIT_DAILYVERSION="${TIME}"
    fi
    set -e

    if [ "${result}" -ne 0 ]; then
        log_error "Failed on obs_build"
    else
        log_info "Suessessful on obs_build"
    fi
}
