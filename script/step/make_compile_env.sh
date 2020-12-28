#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

source "${BUILD_SCRIPT_DIR}"/custom/custom_make_native_env.sh

######################
# 构建编译环境
# Globals:
# Arguments:
# Returns:
######################
function make_compile_env()
{
    chroot_run_bep "cd /home; bash make_version.sh make_compile_env_inchroot standard"
}

######################
# 构建编译环境
# Globals:
# Arguments:
# Returns:
######################
function make_compile_env_storage()
{
    chroot_run_bep "cd /home; bash make_version.sh make_compile_env_inchroot storage"
}

######################
# 使用chroot构建编译环境
# Globals:
# Arguments:
# Returns:
######################
function make_compile_env_inchroot()
{
    local product_env="${1}"

    get_version
    release_dir=$(get_release_dir)
    TIME_DIR="${release_dir#${HTTP_DIR}}"

    TIME=${TIME_DIR##*/}
    TIME=${TIME#"${version}"-}

    yum_conf="${BUILD_SCRIPT_DIR}/config/repo_conf/obs-repo.conf"
    yum clean all -c "${yum_conf}"
    rm -f sys-custom-config-*.noarch.rpm
    yumdownloader -y  -c "${yum_conf}" --destdir ./ sys-custom-config.noarch
    rpm2cpio sys-custom-config-*.noarch.rpm |cpio -dim
    cd opt/sys-custom-config
    if [ "${product_env}" = "standard" ];then
        make_compile_env_native -v "${version}" -t "${TIME}"
    else
        make_compile_env_pangea -v "${version}" -t "${TIME}"
    fi
    if [ $? -ne 0 ]; then
        result=1
        log_error "Failed on $0"
    else
        result=0
        log_info "Suessessful on $0"
    fi

    RELEASEDIR=$(get_release_dir)
    RELEASE_DIR="${RELEASEDIR}CompileTools/"

    create_checksum "${COMPILE_ENV}.tar.gz"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"

    sshscp "${COMPILE_ENV}.tar.gz ${COMPILE_ENV}.tar.gz${SHA256SUM}" "${RELEASE_DIR}"

    if [ "${product_env}" = "standard" ];then
        COMPILE_ENV_FOR_DOCKER="${COMPILE_ENV}_for_docker"
        sshscp "${COMPILE_ENV_FOR_DOCKER}.tar.gz ${COMPILE_ENV_FOR_DOCKER}.tar.gz${SHA256SUM}" "${RELEASE_DIR}"
    fi
    rm -f "${COMPILE_ENV}.tar.gz" "${COMPILE_ENV}.tar.gz${SHA256SUM}"
    chmod_http
    if [ $? -ne 0 ]; then
        result=1
        log_error "Failed in chmod_http"
    fi
    log_info "Release ${COMPILE_ENV} to ${RELEASE_SERVER_IP}:${RELEASE_DIR}"
    return "${result}"
}
