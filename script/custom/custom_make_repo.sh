#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e
#REPO_ROOT=/usr1/Euleros_yum

######################
# make repo for tar
# Globals:
# Arguments:
# Returns:
######################
function make_repo()
{
    local build_script_dir=$(pwd)
    if [ "x$1" == "xaarch64" ]; then
        REPO_DIR="${build_script_dir}/make_tar_aarch64/yum.repos.d"
        RPMLIST_DIR="${build_script_dir}/make_tar_aarch64"
        YUM_CONF="${build_script_dir}/make_tar_aarch64/yum.conf"
        BASE_REPO=euler_base
        REPORULE_FILE="${build_script_dir}/make_tar_aarch64/RepositoryRule.conf"
    elif [ "x$1" == "xx86_64" ]; then
        REPO_DIR="${build_script_dir}/make_tar_x86_64/yum.repos.d"
        RPMLIST_DIR="${build_script_dir}/make_tar_x86_64"
        YUM_CONF="${build_script_dir}/make_tar_x86_64/yum.conf"
        BASE_REPO=euler_base
        REPORULE_FILE="${build_script_dir}/make_tar_x86_64/RepositoryRule.conf"
        rm -rf "${REPO_DIR}"/Compile_*
    fi

    [ -n "${WORK_DIR}" ] && rm -rf "${WORK_DIR}"
    mkdir -p "${WORK_DIR}"
    REPO="${WORK_DIR}repos"
    other_rpm_dir=""
    ret=0
    lost_list=""

    [[ -d "${WORK_DIR}" ]] || mkdir -p "${WORK_DIR}"
    [ -d "${REPO}" ] && rm -rf "${REPO}"

    if [ "${YUM_CONF_FLAG}" -eq 0 ]; then
        [[ -d "${REPO_ROOT}" ]] || mkdir -p "${REPO_ROOT}"
        [ -d "${REPO_ROOT}/yum.repos.d" ] && rm -rf "${REPO_ROOT}/yum.repos.d"
        cp -r "${REPO_DIR}" "${REPO_ROOT}"
        sed -i "s/enabled=1/enabled=0/g" "${REPO_ROOT}"/yum.repos.d/*.repo > /dev/null 2>&1
    fi

    yum clean all -c "${YUM_CONF}"
    set +e
    for rpmlst in $(ls "${RPMLIST_DIR}" | grep "lst")
    do
        rpm_dir=$(echo "${rpmlst}" | sed 's/.lst//g')
        awk -v awk_repo="${rpm_dir}" '$1==awk_repo {print $0}' "${REPORULE_FILE}" > "${WORK_DIR}/rule_file"
        while read line
        do
            if [ -z "${line}" ]; then continue;fi;

            repo_name=$(echo "${line}" | awk '{print $3}')
            repo_num=$(echo "${line}" | awk '{print $2}')
            sed -i "s/priority=[1-9]/priority=${repo_num}/g" "${REPO_ROOT}"/yum.repos.d/"${repo_name}".repo > /dev/null 2>&1
            sed -i "s/enabled=0/enabled=1/g" "${REPO_ROOT}"/yum.repos.d/"${repo_name}".repo > /dev/null 2>&1
        done < "${WORK_DIR}/rule_file"
        rm -rf "${build_script_dir}/tmp"
        yum clean all -c "${YUM_CONF}"
        yum list --installroot="${build_script_dir}/tmp" --showduplicates -c "${YUM_CONF}" | awk '{print $1" "$2}' > "${build_script_dir}/ava_lst"
        for rname in $(cat "${RPMLIST_DIR}/${rpmls}")
        do
            if [ "${rpm_dir}" = "UVP" ]; then break;fi;

            grep -w "^${rname}" "${build_script_dir}/ava_lst" > /dev/null 2>&1
            if [ $? != 0 ]; then
                rname_new=$(echo "${rname}" | sed 's/-[0-9\.]*-[0-9\.h]*\././g')
                grep -w "^${rname_new}" "${build_script_dir}/ava_lst" > /dev/null 2>&1
                if [ $? != 0 ]; then
                    log_error "can not find ${rname},make_tar failed"
                    lost_list="${lost_list}, ${rname}"
                    ret=1
                else
                    yversion=$(grep -w "^${rname_new}" "${build_script_dir}/ava_lst"|awk '{print $2}')
                    rversion=$(echo "${rname}" | egrep -o '[0-9.]+-[0-9.h]+'| sed 's/.$//')
                    echo "${yversion}" | grep "${rversion}$" > /dev/null 2>&1
                    if [ $? != 0 ]; then
                        log_error "can not find ${rname},make_tar failed"
                        lost_list="${lost_list}, ${rname}"
                        ret=1
                    fi
                fi
            fi
        done
        mkdir -p "${REPO}/${rpm_dir}"
        rpms=$(cat "${RPMLIST_DIR}/${rpmlst}" | tr '\n' ' ')
        yumdownloader -c "${YUM_CONF}" --resolve --installroot="$(pwd)"/tmp --destdir="${REPO}/${rpm_dir}" $(echo "$rpms")
        sed -i "s/enabled=1/enabled=0/g" "${REPO_ROOT}"/yum.repos.d/*.repo > /dev/null 2>&1
        if [ "${rpm_dir}" != "${BASE_REPO}" ]; then other_rpm_dir="${other_rpm_dir} ${rpm_dir}";fi;

    done
    set -e
    ls "${REPO}/${BASE_REPO}" | grep rpm > "${REPO}"/"${BASE_REPO}".lst
    for rpm_dir in $(echo "${other_rpm_dir}")
    do
        ls "${REPO}/${rpm_dir}" | grep rpm > "${REPO}"/"${rpm_dir}".lst
        for two_pac in $(cat "${REPO}"/"${rpm_dir}".lst "${REPO}"/"${BASE_REPO}".lst | sort -n | uniq -d)
        do
            sha1=$(sha256sum "${REPO}/${rpm_dir}/${two_pac}" | awk '{print $1}')
            sha2=$(sha256sum "${REPO}/${BASE_REPO}/${two_pac}" | awk '{print $1}')
            if [ "${sha1}" == "${sha2}" ]; then rm -rf "${REPO}/${rpm_dir}/${two_pac}";fi;
        done
        rm -rf "${REPO}/${rpm_dir}".lst
    done
    rm -rf "${REPO}/${BASE_REPO}".lst
    if [ "x${lost_list}" != "x" ];then
        echo "*********************************"
        echo "These rpm is lost:${lost_list}"
    fi

    set -e
    return "${ret}"
}

