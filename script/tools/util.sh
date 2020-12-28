#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# 输出info等级的日志
# Globals:
# Arguments:需要打印的信息
# Returns:
######################
function log_info()
{
    echo "[INFO] $@"
}

######################
# 输出warning等级的日志
# Globals:
# Arguments:需要打印的信息
# Returns:
######################
function log_warn()
{
    echo "[WARNING] $@"
}

######################
# 输出error等级的日志，并结束任务执行
# Globals:
# Arguments:需要打印的信息
# Returns:
######################
function log_error()
{
    echo "[ERROR] $@"
    exit 1
}

######################
# 输出debug等级的日志
# Globals:
# Arguments:需要打印的信息
# Returns:
######################
function log_debug()
{
    echo "[DEBUG] $@"
}

######################
# 在指定机器上执行shell命令
# Globals:
# Arguments:cmd:执行命令，ip:远程机器id，user:远程机器用户，passwd:该用户密码
# Returns:
######################
function sshcmd()
{
    sh "${BUILD_SCRIPT_DIR}/tools/safe_sshcmd.sh" -c "$1" -m "${RELEASE_SERVER_IP}" -u "${USER}" -p "${PASSWD}" -t 120 -n 3
}

######################
# 拷贝本地东西到远程机器
# Globals:
# Arguments:
# Returns:
######################
function sshscp()
{
    sh "${BUILD_SCRIPT_DIR}/tools/safe_sshscp.sh" -p "${PASSWD}" -s "$1" -d "${RELEASE_SERVER_IP}:$2" -r -t 120 -n 3
}

######################
# 从远程机器拷贝东西到本地
# Globals:
# Arguments:
# Returns:
######################
function sshscp_from()
{
    sh "${BUILD_SCRIPT_DIR}/tools/safe_sshscp.sh" -p "${PASSWD}" -s "${RELEASE_SERVER_IP}:$1" -d "$2" -r -t 120 -n 3
}

######################
# 在指定arm机器上执行shell命令,用于制作交叉编译环境
# Globals:
# Arguments:cmd:执行命令，ip:远程机器id，user:远程机器用户，passwd:该用户密码
# Returns:
######################
function sshcmd_arm()
{
    sh "${BUILD_SCRIPT_DIR}/tools/safe_sshcmd.sh" -c "$1" -m "${RELEASE_ROOT_PATH}" -u "${USER}" -p "${PASSWD}" -t 120 -n 3
}

######################
# 拷贝本地东西到远程arm机器, 用于制作交叉编译环境
# Globals:
# Arguments:
# Returns:
######################
function sshscp_arm()
{
    sh "${BUILD_SCRIPT_DIR}/tools/safe_sshscp.sh" -p "${PASSWD}" -s "$1" -d "${RELEASE_SERVER_IP}:$2" -r -t 120 -n 3
}

######################
# 从远程arm机器拷贝东西到本地, 用于制作交叉编译环境
# Globals:
# Arguments:
# Returns:
######################
function sshscp_from_arm()
{
    sh "${BUILD_SCRIPT_DIR}/tools/safe_sshscp.sh" -p "${PASSWD}" -s "${RELEASE_ROOT_PATH}:$1" -d "$2" -r -t 120 -n 3
}
######################
# 安全运行相关命令
# Globals:
# Arguments:
# Returns:
######################
function safe_run()
{
  if ! "$@"; then
    log_error "$* failed; aborting!"
  fi
}

######################
# 生成文件的sha256值，并存放在相应的文件中
# Globals:
# Arguments:
# Returns:
######################
function create_checksum()
{
    file="$1"
    sha256sum "${file}" > "$file${SHA256SUM}"
}


