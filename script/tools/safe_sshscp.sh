#!/bin/bash
# Author: xielaili
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e
src=""
des=""
loginuser="root"
loginpassword="kong"
r_option=0
timeout=120
retry_cnt=3

######################
# 使用说明
# Globals:
# Arguments:
# Returns:
######################
function usage()
{
        echo "Usage: sshscp.sh -s src -d destination [-p login_password] [-t ping_timeout] [-n ssh_retry_time] -r"
        echo "       r: scp directory"
}


while getopts "p:s:d:t:n:hr" OPTIONS
do
        case "${OPTIONS}" in
                p) loginpassword="${OPTARG}";;
                s) src="${OPTARG}";;
                d) des="${OPTARG}";;
                t) timeout="${OPTARG}";;
                n) retry_cnt="${OPTARG}";;
                r) r_option=1;;
                h) usage; exit 1
                ;;
                \?) echo "ERROR - Invalid parameter"; echo "ERROR - Invalid parameter" >&2;usage;exit 1;;
                *) echo "ERROR - Invalid parameter"; echo "ERROR - Invalid parameter" >&2; usage;exit 1;;
        esac
done


if [ "x${src}" = "x" -o "x${des}" = "x" ];then
        usage
        exit 1
fi

if echo "${src}" | grep ':'; then
    machineip=$(echo "${src}" | awk -F':' '{print $1}')
elif echo "${des}" | grep ':'; then
     machineip=$(echo "${des}" | awk -F':' '{print $1}')
else
    usage
    exit 1
fi

for((i=0;i<retry_cnt;i++))
do
    sh "${TOOLS}"/sshscp.sh -p "${loginpassword}" -s "${src}" -d "${des}" -r
    if [ $? -ne 0 ];then
        while true
        do
            ping -c4 "${machineip}" &> /dev/null
            if [ $? -ne 0 ]; then
                if [ "${sleeptime}" -ge "${timeout}" ]; then
                    echo "ERROR: ping ${RELEASE_SERVER_IP} Failed"
                    exit 1
                else
                    sleep 15
                    ((sleeptime = "${sleeptime}" + 15))
                fi
            else
                break
            fi
        done
    else
        break
    fi
done
