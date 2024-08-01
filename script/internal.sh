#!/bin/bash
set -e

if [[ ${ARCH} == "aarch64" ]];then
	arch_name="ARM64"
elif [[ ${ARCH} == "x86_64" ]];then
	arch_name="X86"
elif [[ ${ARCH} == "loongarch64" ]];then
	arch_name="LOONGARCH64"
elif [[ ${ARCH} == "riscv64" ]];then
	arch_name="RISCV64"
elif [[ ${ARCH} == "ppc64le" ]];then
	arch_name="PPC64LE"
fi

if echo "${BUILD_SCRIPT_DIR}" | grep 'gcov-'; then
    export CI_PROJECT="openeuler_${arch_name}_gcov"
else
    export CI_PROJECT="openeuler_${arch_name}"
fi

export WORK_DIR="${OUTPUT_PATH}/work_dir/${CI_PROJECT}/"

export USER=""
export PASSWD=""
export HTTP_DIR=${RELEASE_ROOT_PATH}
export PRE_VERSION=${RELEASE_VERSION_DIR}

export VERSION="${CI_PROJECT}"
export CMC_BASEDIR="/usr1"
export JENKINS_URL="http://114.116.250.98/jenkins/job"
export OPENEULER_CHROOT_PATH="/usr1/openeuler"

#configure for icp_ci
export ICP_CI_IP=""
export MOUNTDIR_MASTER=""
export MOUNTDIR_AGENT=""
export MASTER_USER=""
export MASTER_PASSWD=""

#for gerrit
export GERRIT_BRANCH="next"
export GERRIT_BASE_URL=""
