#!/bin/bash
# Author: xudengfeng
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e
export DEBUG=1
export BUILD_SCRIPT_DIR=$(cd $(dirname "$0"); pwd)
export TOOLS="${BUILD_SCRIPT_DIR}/tools"
export HOME="/root"
export OUTPUT_PATH="${BUILD_SCRIPT_DIR}/output"
export PROJECT_PATH="${BUILD_SCRIPT_DIR}/../../../../.."
export ERROR_LOG="${OUTPUT_PATH}/error_log"
export UNABLE_INSTALL_LIST="${BUILD_SCRIPT_DIR}"/config/unable_install_list
export UNABLE_INSTALL_SOURCE_LIST="${BUILD_SCRIPT_DIR}"/config/unable_install_source_list

if [ ! -d "${OUTPUT_PATH}"  ]; then
    mkdir -p "${OUTPUT_PATH}" 
fi

if [ "${ISCI}" = "1" ]; then
    STARTTIME=$(perl -e 'print time()')
    exec 1> >(exec -a 'build logging' perl -e '$|=1;select(F);$|=1;while(<STDIN>){my $p=sprintf("[%5ds] ", time()-'"${STARTTIME}"');print STDOUT $p.$_;}') 2>&1
fi
# source const var and utils func
source "${BUILD_SCRIPT_DIR}"/setup_env.sh || exit 1
source "${BUILD_SCRIPT_DIR}"/internal.sh || exit 1
source "${BUILD_SCRIPT_DIR}"/tools/util.sh || exit 1
source "${BUILD_SCRIPT_DIR}"/tools/common.sh || exit 1
source "${BUILD_SCRIPT_DIR}"/tools/chroot.sh || exit 1
source "${BUILD_SCRIPT_DIR}"/common_function.sh || exit 1
export EXCLUDE_REGISTER_SCRIPT=('set_release_dir')

######################
# 使用说明
# Globals:
# Arguments:
# Returns:
######################
function usage()
{
    echo "$(basename $0) [script_name|all]"
}

export ALL_SCRIPT=('make_hmi' 'make_iso' 'make_docker_image' 'make_raspi_image' 'make_riscv64_qemu_image' 'make_microvm_image' 'make_iso_everything' 'make_iso_everysrc' 'make_debug_everything' 'make_netinst_iso' 'get_epol_rpms' 'make_edge_iso' 'make_desktop_iso' 'make_riscv64_image')
[[ "${DEBUG}" -eq 1 ]] && set -x

arg1="$1"
shift
arg2="$@"
if [ "${arg1}" == 'all' -o -z "${arg1}" ]; then
    run_srcipt_all
else
    run_srcipt "${arg1}" "${arg2}"
fi
