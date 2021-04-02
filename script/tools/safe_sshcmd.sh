#!/bin/bash
# Author: xudengfeng
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e
execcmd=""
machineip=""
machineport=""
loginuser=root
loginpassword=huawei
timeout=120
retry_cnt=3

######################
# display usage 
# Globals:
# Arguments:
# Returns:
######################
function usage()
{
    echo "Usage: sshcmd.sh -c "command" -m "machinetip" [-P machineport] [-u login_user] [-p login_password] [-t ping_timeout] [-n ssh_retry_time]"
}

while getopts "c:m:p:u:t:n:P:h" OPTIONS
do
        case "${OPTIONS}" in
                c) execcmd="${OPTARG}";;
                m) machineip="${OPTARG}";;
                u) loginuser="${OPTARG}";;
                p) loginpassword="${OPTARG}";;
                t) timeout="${OPTARG}";;
                n) retry_cnt="${OPTARG}";;
                P) machineport="${OPTARG}";;
                \?) echo "ERROR - Invalid parameter"; echo "ERROR - Invalid parameter" >&2;usage;exit 1;;
                *) echo "ERROR - Invalid parameter"; echo "ERROR - Invalid parameter" >&2; usage;exit 1;;
        esac
done


if [ "x${execcmd}" = "x" -o "x${machineip}" = "x"  ];then
        usage
        exit 1
fi

for((i=0;i<retry_cnt;i++))
do
    if [ -n "${machineport}" ];then
        sh "${TOOLS}"/sshcmd.sh -c "${execcmd}" -m "${machineip}" -u "${loginuser}" -p "${loginpassword}" -P "${machineport}"
    else
        sh "${TOOLS}"/sshcmd.sh -c "${execcmd}" -m "${machineip}" -u "${loginuser}" -p "${loginpassword}"
    fi
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
