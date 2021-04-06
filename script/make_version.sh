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
#source "${BUILD_SCRIPT_DIR}"/tools/obs.sh || exit 1

function get_repose()
{
    expect -c "
    spawn $*
    expect {
        \"*yes/no*\" {send \"yes\n\"}
        eof
    }
    catch wait result;
    exit [lindex \$result 3]
    "
}
for((i=0;i<3;i++));
do
ret=$(get_repose ssh -i ~/.ssh/super_publish_rsa root@${RELEASE_SERVER_IP} ip addr | grep "172." | tr -cd "[0-9].[0-9]/ " | awk '{print $3}' | awk -F "/" '{print $1}')
if [ "$ret" != "${RELEASE_SERVER_IP}" ];then
    break
fi
done
#sed -i "s/RELEASE_SERVER_IP=\"${RELEASE_SERVER_IP}\"/RELEASE_SERVER_IP=\"$ret\"/g" "${BUILD_SCRIPT_DIR}"/setup_env.sh
#sh "${BUILD_SCRIPT_DIR}"/tools/safe_sshcmd.sh -c "ip add | grep 172 | awk -F '/' '{print \$1}'| awk '{print \$2}'" -m ${RELEASE_SERVER_IP} -u "root" -p "xxxx" -t 120 -n 3
#if echo "${CI_PROJECT}" | grep '_gcov'; then
#    modify_for_gcov "${BUILD_SCRIPT_DIR}"
#    source "${BUILD_SCRIPT_DIR}"/config.sh || exit 1
#fi
source "${BUILD_SCRIPT_DIR}"/common_function.sh || exit 1
export EXCLUDE_REGISTER_SCRIPT=('set_release_dir')

sed -i 's/container=.*>/container=\"'${CONTAINER_NAME}'\">/g'  "${BUILD_SCRIPT_DIR}"/config/docker_image/config.xml

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

export ALL_SCRIPT=('build_and_wait' 'update_release_info' 'make_tar' 'make_hmi' 'make_iso' 'make_iso_debug' 'make_iso_singleoss' 'make_livecd' 'make_compile_env' 'make_docker_image' 'make_raspi_image' 'make_microvm_image' 'make_euleros_certdb' 'make_tools_lib_storage' 'make_container_tools' 'make_tools_debug_tools' 'make_upgrade_patch' 'make_iso_everything' 'make_iso_everysrc' 'make_debug_everything' 'push_lts_dir' 'make_netinst_iso' 'get_epol_rpms')
[[ "${DEBUG}" -eq 1 ]] && set -x

#check_env

arg1="$1"
shift
arg2="$@"
if [ "${arg1}" == 'all' -o -z "${arg1}" ]; then
    run_srcipt_all
else
    run_srcipt "${arg1}" "${arg2}"
fi
