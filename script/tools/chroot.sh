#!/bin/bash
set -e

function chroot_addbep()
{
    # add bep-env in /usr1/openeuler
    wget -P "${OPENEULER_CHROOT_PATH}" -q -r -l1 -nd -A 'bep-env-*.rpm' "${OBS_EXTRAS_REPO_URL}/${ARCH}/" &> /dev/null
    chroot "${OPENEULER_CHROOT_PATH}" /bin/bash --login -c "rpm -ivh bep-env-*.rpm --nodeps --force &> /dev/null"
    chroot "${OPENEULER_CHROOT_PATH}" /bin/bash --login -c "sed -i '/BEP_GTDLIST/s/\"$/ createrepo lorax livemedia-creator\"/ ' /etc/profile"
    chroot "${OPENEULER_CHROOT_PATH}" /bin/bash --login -c "sed -i '/BEP_BLACKLIST/s/\"$/ createrepo lorax livemedia-creator\"/ ' /etc/profile"
    chroot "${OPENEULER_CHROOT_PATH}" /bin/bash --login -c "sed -i '/BEP_RANDOMLIST/s/\"$/ createrepo lorax livemedia-creator\"/ ' /etc/profile"
}

function chroot_init()
{
    chroot_clean
    rm -f openEuler_chroot-*.noarch.rpm
    wget -q -r -l1 -nd -A 'openEuler_chroot-*.noarch.rpm' "${OBS_EXTRAS_REPO_URL}/noarch/" &> /dev/null
    rpm -ivh openEuler_chroot-*.noarch.rpm
    rm -f openEuler_chroot-*.noarch.rpm
    cp -a "${BUILD_SCRIPT_DIR}"/* "${OPENEULER_CHROOT_PATH}/home"
    mkdir -p "${OPENEULER_CHROOT_PATH}/root/.ssh/"
    cp ~/.ssh/super_publish_rsa "${OPENEULER_CHROOT_PATH}/root/.ssh/"
    if echo "${BUILD_SCRIPT_DIR}" | grep 'gcov-'; then
        sed -i '/VERSION=/ iexport CI_PROJECT="openeuler_ARM64_gcov"' "${OPENEULER_CHROOT_PATH}"/home/internal.sh
    fi
    chroot "${OPENEULER_CHROOT_PATH}" /bin/bash -c "echo ${OBS_SERVER_IP} openeuler-obs-repo.huawei.com >> /etc/hosts"
}

function chroot_clean()
{
    pwd 
    ls /
    set +e
    rpm -e openEuler_chroot
    if [ -d "${OPENEULER_CHROOT_PATH}" ]; then
        lsof | grep openeuler
        for openeuler_pid in $(lsof | grep '/usr1/openeuler/' | awk '{print $2}')
        do
            kill -9 "${openeuler_pid}"
        done
        umount "${OPENEULER_CHROOT_PATH}/proc"
        umount "${OPENEULER_CHROOT_PATH}/sys"
        umount "${OPENEULER_CHROOT_PATH}/dev/pts"
        umount "${OPENEULER_CHROOT_PATH}/dev"
        rm -rf "${OPENEULER_CHROOT_PATH}"
    fi
    if [ -d "${OPENEULER_CHROOT_PATH}" ]; then
        log_error "delete ${OPENEULER_CHROOT_PATH} failed"
    fi
    set -e
}

######################
# 在chroot环境中运行
# Globals:
# Arguments:需要运行的shell命令
# Returns:
######################
function chroot_run()
{
    chroot_init
    chroot "${OPENEULER_CHROOT_PATH}" /bin/bash --login -c "$@"
    chroot_clean
}
######################
# 在bep chroot环境中运行
# Globals:
# Arguments:需要运行的shell命令
# Returns:
######################
function chroot_run_bep()
{
    chroot_init
    chroot_addbep
    chroot "${OPENEULER_CHROOT_PATH}" /bin/bash --login -c "$@"
    chroot_clean
}
