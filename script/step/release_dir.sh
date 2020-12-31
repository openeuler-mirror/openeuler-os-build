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
    SSH_CMD="mkdir -p ${HTTP_DIR}/${PRE_VERSION}/${version}_ARM64; echo ${version} > ${HTTP_DIR}/${PRE_VERSION}/${version}_ARM64/version; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${version}_ARM64/version"
    sshcmd "${SSH_CMD}"
    SSH_CMD="mkdir -p ${HTTP_DIR}/${PRE_VERSION}/${version}_X86; echo ${version} > ${HTTP_DIR}/${PRE_VERSION}/${version}_X86/version; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${version}_X86/version"
    sshcmd "${SSH_CMD}"

    if [ -f "${WORK_DIR}DEBUG" ]
    then
        debug='debug'
    else
        debug='nodebug'
    fi
    
    SSH_CMD="echo ${debug} > ${HTTP_DIR}/${PRE_VERSION}/${version}_ARM64/log_level; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${version}_ARM64/log_level"
    sshcmd "${SSH_CMD}"
    SSH_CMD="echo ${debug} > ${HTTP_DIR}/${PRE_VERSION}/${version}_X86/log_level; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${version}_X86/log_level"
    sshcmd "${SSH_CMD}"

    release_tmp='release_tmp'
    TIME=$(date +%Y-%m-%d-%H-%M-%S)
    TIME_DIR="${PRE_VERSION}/${version}-${TIME}"
    SSH_CMD="echo ${HTTP_DIR}/${TIME_DIR} > ${HTTP_DIR}/${PRE_VERSION}/${version}_ARM64/${release_tmp}; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${version}_ARM64/${release_tmp}"
    sshcmd "${SSH_CMD}"
    SSH_CMD="echo ${HTTP_DIR}/${TIME_DIR} > ${HTTP_DIR}/${PRE_VERSION}/${version}_X86/${release_tmp}; chmod 644 ${HTTP_DIR}/${PRE_VERSION}/${version}_X86/${release_tmp}"
    sshcmd "${SSH_CMD}"
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
