#!/bin/bash
# set and get release_version directories
set -e
# setting up the daily build directory
# The default version is openeuler, can receive parameters passed by jenkins.
function set_release_dir()
{
    version="openeuler"
    [ -z "${version}" ] && log_error "You must set version in config file or from CI web page"
    log_info "------------the version is ${version}-----------"
    arch_list=(ARM64 X86)
    for arch in ${arch_list[@]}
    do
        SSH_CMD="mkdir -p ${HTTP_DIR}/${PRE_VERSION}/${version}_${arch}; echo ${version} > ${HTTP_DIR}/${PRE_VERSION}/${version}_${arch}/version; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${version}_${arch}/version"
        sshcmd "${SSH_CMD}"
    done

    if [ -f "${WORK_DIR}DEBUG" ]
    then
        debug='debug'
    else
        debug='nodebug'
    fi
    for arch in ${arch_list[@]}
    do
        SSH_CMD="echo ${debug} > ${HTTP_DIR}/${PRE_VERSION}/${version}_${arch}/log_level; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${version}_${arch}/log_level"
        sshcmd "${SSH_CMD}"
    done

    release_tmp='release_tmp'
    TIME=$(date +%Y-%m-%d-%H-%M-%S)
    TIME_DIR="${PRE_VERSION}/${version}-${TIME}"
    for arch in ${arch_list[@]}
    do
        SSH_CMD="echo ${HTTP_DIR}/${TIME_DIR} > ${HTTP_DIR}/${PRE_VERSION}/${version}_${arch}/${release_tmp}; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${version}_${arch}/${release_tmp}"
        sshcmd "${SSH_CMD}"
    done
}

# get release dir
# huo qu mei ri gou jian mu lu
function get_release_dir()
{
    release_tmp='release_tmp'
    rm -f ./"${release_tmp}"
    sshscp_from "${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${release_tmp}" "./" &> /dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed on sshscp_from ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/${release_tmp} ./"
    fi
    echo $(cat "${release_tmp}")
}
