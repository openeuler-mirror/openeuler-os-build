#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# 修改远程配置
# Globals:
# Arguments:
# Returns:
######################
function modify_remote_config()
{
    ITEM="$1"
    ITEM="${ITEM%_in_docker}"
    STATUS="$2"
    for exclude_script in "${EXCLUDE_REGISTER_SCRIPT[@]}"
    do
        if [ "${ITEM}" == "BUILD_${exclude_script}" ]; then
            return 0
        fi
    done
    product_list=''
    for product in $(echo "${PRODUCTS}")
    do
        product_list="config_${product} ${product_list}"
    done
    #SSH_CMD="pushd ${HTTP_DIR}/${PRE_VERSION}/${VERSION}; sed -i  \"/${ITEM}=/d\" ${product_list}; sed -i \"/#BUILD_RESULT/a ${ITEM}=${STATUS}\" ${product_list}; chmod -R 755 ${product_list}; popd"
    #sshcmd "${SSH_CMD}"
}

######################
# clear and exit
# Globals:
# Arguments:
# Returns:
######################
function clean_and_exit()
{
    if [ "$1" -ne "0" ]; then
        modify_remote_config "BUILD_${SCRIPT}" 3
        echo "=========error start========="
        cat "${ERROR_LOG}"
        echo "=========error end========="
        exit "$1"
    fi
}

######################
# 执行对应的函数
# Globals:
# Arguments:函数名、函数所需要参数
# Returns:
######################
function run_srcipt()
{
    script="$1"
    shift
    args="$@"
    export SCRIPT="${script}"
    modify_remote_config "BUILD_${SCRIPT}" 1
    log_info "Start run ${script} ${args} at $(date)"
    eval "${script}" "${args}"
    if [ $? -ne 0 ]; then
        echo "[ERROR]: Run ${script} ${args} failed at $(date)"
        clean_and_exit 1
    fi
    log_info "Finished run ${script} ${args} at $(date)"
    modify_remote_config "BUILD_${SCRIPT}" 2
    clean_and_exit 0
}

######################
# 执行ALL_SCRIPT中所有的函数
# Globals:
# Arguments:
# Returns:
######################
function run_srcipt_all()
{
    scripts="$@"
    for script in "${ALL_SCRIPT[@]}"
    do
        run_srcipt "${script}"
    done

}

source "${BUILD_SCRIPT_DIR}"/step/get_version.sh
source "${BUILD_SCRIPT_DIR}"/step/release_dir.sh
source "${BUILD_SCRIPT_DIR}"/step/get_epol_rpms.sh
source "${BUILD_SCRIPT_DIR}"/step/make_hmi.sh
source "${BUILD_SCRIPT_DIR}"/step/make_docker_image.sh
if [[ ${STEP} == "make_raspi_image" ]];then
    source "${BUILD_SCRIPT_DIR}"/step/make_raspi_image.sh
elif [[ ${STEP} == "make_riscv64_qemu_image" ]];then
    source "${BUILD_SCRIPT_DIR}"/step/make_riscv64_qemu_image.sh
elif [[ ${STEP} == "make_microvm_image" ]];then
    source "${BUILD_SCRIPT_DIR}"/step/make_microvm_image.sh
fi
source "${BUILD_SCRIPT_DIR}"/step/make_iso.sh
source "${BUILD_SCRIPT_DIR}"/step/make_netinst_iso.sh
source "${BUILD_SCRIPT_DIR}"/step/make_edge_iso.sh
source "${BUILD_SCRIPT_DIR}"/step/make_desktop_iso.sh
source "${BUILD_SCRIPT_DIR}"/step/make_iso_everything.sh
source "${BUILD_SCRIPT_DIR}"/step/make_debug_everything.sh
source "${BUILD_SCRIPT_DIR}"/step/make_iso_everysrc.sh
source "${BUILD_SCRIPT_DIR}"/step/make_devstation_iso.sh
source "${BUILD_SCRIPT_DIR}"/step/make_devstation_netinst_iso.sh
