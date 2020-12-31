#!/bin/bash
# Author: xudengfeng
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# init env 
# Globals:
# Arguments:
# Returns:
######################
function init(){
    DOCKER_TOOLS="docker_tools"
    LIB_STORAGE_TOOLS="LibStorage"
    KERNEL_RPM="KERNEL_RPM"
    DEBUG_TOOLS="DebugTools"
    DEBUG_STD="DebugTools/standard"
    DEBUG_STG="DebugTools/storage"
    MAKE_TOOLS="${BUILD_SCRIPT_DIR}/make_tools"
    yum_conf="${BUILD_SCRIPT_DIR}/config/repo_conf/obs-repo.conf"
    yum_conf_storage="${BUILD_SCRIPT_DIR}/config/repo_conf/obs-pangea-repo.conf"
}

######################
# make tool main 
# Globals:
# Arguments:
# Returns:
######################
function make_tool()
{
    el_repo="$1"
    rpmlst="$2"
    tooldir="$3"
    tooltar="$4"

    if [ ! -f "${rpmlst}" ];then
        log_error "not found ${rpmlst}"
            return 1
    fi

    [ -n "${tooldir}" ] && rm -rf "${tooldir}"
    mkdir "${tooldir}"
    yum clean all -c "${yum_conf}"
    yumdownloader -c "${yum_conf}" --exclude="*.src" --destdir="${tooldir}" $(cat "${rpmlst}" | tr '\n' ' ')

    if [ $? -ne 0 ]; then
        log_error "when download rpm failed"
            return 1
    fi
    cd "${tooldir}"

    #rpm_list=$(ls ./Euler/*.rpm)
    rpm_list=$(ls ./*.rpm)
    if [ $? -ne 0 ];then
        echo "mktool.sh: function [make_tool] [${LINENO}]: rpm is not exist. please download it yourself." && return 1
    fi
    for rpm in ${rpm_list[*]}
    do
            rpm2cpio "${rpm}" | cpio -id
        [ -n "${rpm}" ] && rm -rf "${rpm}"
    done

    rm -rf Euler

    rm -rf usr/share/doc usr/share/man
    if [ -d bin ];then
        if [ ! -d usr/bin ];then
                mkdir -p usr/bin
        fi
        cp -ap bin/* usr/bin/
        rm -rf bin
    fi
    if [ -d sbin ];then
        if [ ! -d usr/sbin ];then
                mkdir -p usr/sbin
        fi
        cp -ap sbin/* usr/sbin/
        rm -rf sbin
    fi
    if [ -d lib ];then
        if [ ! -d usr/lib ];then
                mkdir -p usr/lib
        fi
        cp -ap lib/* usr/lib/
        rm -rf lib
    fi
    if [ -d lib64 ];then
        if [ ! -d usr/lib64 ];then
                mkdir -p usr/lib64
        fi
        cp -ap lib64/* usr/lib64/
        rm -rf lib64
    fi

    tar -zcf ../"${tooltar}" *
    cd ..
    [ -n "${tooldir}" ] && rm -rf "${tooldir}"
}

init
