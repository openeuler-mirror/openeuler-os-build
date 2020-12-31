#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# make gcov data publish 
# Globals:
# Arguments:
# Returns:
######################
function make_gcov_data_publish()
{
    release_dir=$(get_release_dir)
    publish_dir="$release_dir/gcov"
    gcov_repo_path='/repo/openeuler/dailybuild/gcov'

    cd "${BUILD_SCRIPT_DIR}"
    rm -rf gcov_data
    mkdir gcov_data
    for line in $(echo "EulerOS:V3R1:BuildToolsBep EulerOS:V3R1:COMMOM EulerOS:V3R1:CompileTools EulerOS:V3R1:GENERAL EulerOS:V3R1:GENERAL:Custom EulerOS:V3R1:GENERAL:Kernel EulerOS:V3R1:KIWI EulerOS:V3R1:PANGEA EulerOS:V3R1:PANGEA:Custom EulerOS:V3R1:PANGEA:Kernel EulerOS:V3R1:PANGEA:Storage EulerOS:V3R1:STANDARD EulerOS:V3R1:STANDARD:Docker EulerOS:V3R1:STANDARD:LibStorage")
    do
        sh "${TOOLS}"/safe_sshscp.sh -p "huawei" -s "${RELEASE_SERVER_IP}:${gcov_repo_path}/${line}" -d "${BUILD_SCRIPT_DIR}/gcov_data" -r
    done

    tar -czvf gcov_data.tar.gz gcov_data
    create_checksum gcov_data.tar.gz
    SSH_CMD="mkdir -p ${publish_dir}"
    sshcmd "${SSH_CMD}"
    sshscp "gcov_data.tar.gz gcov_data.tar.gz${SHA256SUM}" "${publish_dir}"
    rm -rf gcov_data*
}

######################
# update sys-custom-tool 
# Globals:
# Arguments:
# Returns:
######################
function update_sys_custom_tool()
{
    rm -rf sys-custom-tool
    gerrit_url="${gerrit_base_url}/euleros/self_src/userspace/sys-custom-tool"
expect <<-END1
    set timeout -1
    spawn git clone "${gerrit_url}"
    expect {
        "*Are you sure you want to continue connecting*" { send "yes\r"; exp_continue }
        eof { catch wait result; exit [lindex \${result} 3] }
    }
    expect {
        eof { catch wait result; exit [lindex \${result} 3] }
    }
END1
    if [ $? -ne 0 ]; then
        log_error "git clone ${gerrit_url} failed"
    fi
    pushd sys-custom-tool
    git checkout next
    flag_pri=5
    middle_dir="./sys-custom-tool-1.0.0/local_script/make_tar_arm/yum.repos.d"
    ls "${middle_dir}" | while read line
    do
        cp -a "${middle_dir}"/"${line}" "${middle_dir}"/gcov_"${line}"
        name=$(echo "${middle_dir}"/"${line}" | awk -F '/' '{print $NF}'  | awk -F '.' '{print $1}')
        sed -i "s#$name#gcov_${name}#g" "${middle_dir}"/gcov_"${line}"
        sed -i "s#priority=.*#priority=${flag_pri}#" "${middle_dir}"/gcov_"${line}"
        let "flag_pri = $flag_pri +1"
    done
    modify_for_gcov './'
    source_module=$(ls | grep -v *.spec)
    tar -czf "${source_module}.tar.gz" "${source_module}" --remove-files
    popd

    rm -rf EulerOS:V3R1:GENERAL:Custom
expect -c "
    set timeout 300
    spawn osc co EulerOS:V3R1:GENERAL:Custom sys-custom-tool
    expect {
        \"Enter choice*:\" {send \"2\r\"; exp_continue}
         eof { catch wait result; exit [lindex \$result 3] }
    }
    expect {
        eof { catch wait result; exit [lindex \$result 3] }
    }
"
    if [ $? -ne 0 ]; then
        log_error "osc co EulerOS:V3R1:GENERAL:Custom sys-custom-tool failed"
    fi
    pushd EulerOS:V3R1:GENERAL:Custom/sys-custom-tool
    osc rm *
    cp ../../sys-custom-tool/* .
    osc add "${source_module}".tar.gz *.spec
    newfiles=$(osc status | grep ? | awk '{print $2}')
    if [ -n "${newfiles}" ]; then
        osc add "${newfiles}"
    fi
    osc ci -m"update for v2r8_arm"
    if [ $? -ne 0 ]; then
        log_error "osc ci in EulerOS:V3R1:GENERAL:Custom/sys-custom-tool failed"
    fi
}
