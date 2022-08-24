#!/bin/bash
set -e

if echo "${BUILD_SCRIPT_DIR}" | grep 'gcov-'; then
    export CI_PROJECT="openeuler_${ARCH}_gcov"
else
    export CI_PROJECT="openeuler_${ARCH}"
fi

if [ "x${arm2x86}" = "xx86_64" ]; then
        export CI_PROJECT=$(echo "$CI_PROJECT" |sed 's/x86_64/aarch64/')
fi
export CI_PROJECT=$(echo "$CI_PROJECT" |sed 's/x86_64/X86/')
export CI_PROJECT=$(echo "$CI_PROJECT" |sed 's/aarch64/ARM64/')

export WORK_DIR="${OUTPUT_PATH}/work_dir/${CI_PROJECT}/"

#configure for release to remote
set +ue
export RELEASE_ROOT_PATH=${RELEASE_ROOT_PATH}
if [ "x${jenkins_build}" != "x" ]; then
    export USER=""
    export PASSWD=""
    export HTTP_DIR=${RELEASE_ROOT_PATH}
    export PRE_VERSION=${RELEASE_VERSION_DIR}
else
    export IP="127.0.0.1"
    export HTTP_DIR="${OUTPUT_PATH}/release"
    export PRE_VERSION="openeuler/${MYVERSION}"
fi
set -ue

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
