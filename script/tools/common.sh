#!/bin/bash
# Author: xudengfeng
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# modify config for gcov 
# Globals:
# Arguments:
# Returns:
######################
function modify_for_gcov()
{
    root_path="$1"
    for prj in $(echo "${GCOV_OBS_STANDARD_REPO_URL}")
    do
        prj=$(echo "${prj}" | sed 's/EulerOS_T/EulerOS/g')
        old_prj=$(echo "${prj}" | sed 's/GCOV_EulerOS/EulerOS/g')
        old_repo=$(echo "${old_prj}" | sed 's/:/:\//g')
        repo=$(echo "${prj}" | sed 's/:/:\//g')
        files=$(find "${root_path}" -type f | grep  -v "gcov_.*repo" | xargs egrep "$old_prj" | awk -F':' '{print $1}' | sort | uniq)
        if [ -n "${files}" ]; then
            sed -i "s#${old_prj}#${prj}#g" $(echo "${files}")
        fi
        files=$(find "${root_path}" -type f | grep  -v "gcov_.*repo" | xargs egrep "${old_repo}" | awk -F':' '{print $1}' | sort | uniq)
        if [ -n "${files}" ]; then
            sed -i "s#${old_repo}#${repo}#g" $(echo "${files}")
        fi
    done
    grep "GCOV_GCOV_" "${root_path}" -lR | grep -v "tools/common.sh" | while read line
    do
        sed -i 's#GCOV_GCOV_#GCOV_#g' $(echo "${line}")
    done
}

######################
# set log level
# Globals:
# Arguments:
# Returns:
######################
function set_log_level()
{
    log_level='log_level'
    rm -f "./${log_level}"
    set +e
    sshscp_from "${HTTP_DIR}/${PRE_VERSION}/${VERSION/}${log_level}" "./" &> /dev/null
    if [ "$?" -ne "0" ]; then
        DEBUG=0
    else
        level=$(cat "${log_level}")
        if [ "${level}" == "debug" ]; then
            DEBUG=1
        fi
    fi
    set -e
}

######################
# chmod http 
# Globals:
# Arguments:
# Returns:
######################
function chmod_http()
{
    release_dir=$(get_release_dir)
    SSH_CMD="chmod -R 755 ${release_dir}/ISO"
    sshcmd "${SSH_CMD}"
}

######################
# trigger jenkins project 
# Globals:
# Arguments:
# Returns:
######################
function trigger_jenkins_project()
{
    jenkins_prj="$1"
    product="$2"
    set +u
    if [ "x${team_from_jenkins}" != "x" ]; then
        return 0
    fi
    if [ "x${product}" == "x" ]; then
        CMD="curl http://10.175.100.200:8080/jenkins/job//${jenkins_prj}/build?token=xdf"
    else
        CMD="curl http://10.175.100.200:8080/jenkins/job/${jenkins_prj}/buildWithParameters?token=xdf -d CONFIG_URL=http://${RELEASE_SERVER_IP}/${PRE_VERSION}/${VERSION}/config_${product}"
    fi
    eval "${CMD}"
}

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

function replace_release_server_ip()
{
    if [ -n ${RELEASE_SERVER_PORT} ];then
        SSHPORT="-p ${RELEASE_SERVER_PORT}"
    else
        SSHPORT=""
    fi
    setupfile=`find -iname "setup_env.sh"`
    for((i=0;i<5;i++));
    do
        ret=$(get_repose ssh -i ~/.ssh/super_publish_rsa ${SSHPORT} root@${RELEASE_SERVER_IP} ip addr | grep inet | awk '{print $2}' | grep -v '127' | awk -F '/' '{print $1}' | sed -n '1p')
        if [ -n "$ret" ];then
            sed -i "s/RELEASE_SERVER_IP=\"${RELEASE_SERVER_IP}\"/RELEASE_SERVER_IP=\"$ret\"/g" ${setupfile}
            if [ "$ret" != "${RELEASE_SERVER_IP}" ];then
                sed -i "s/RELEASE_SERVER_PORT=\"${RELEASE_SERVER_PORT}\"/RELEASE_SERVER_PORT=""/g" ${setupfile}
            fi
            break
        else
            if [ $i -eq 0 ];then
                sed -i "/${RELEASE_SERVER_IP}/d" ~/.ssh/known_hosts
            fi
        fi
    done
}
