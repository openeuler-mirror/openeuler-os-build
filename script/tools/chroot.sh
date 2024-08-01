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
    pkglist="pigz expect wget bash vim grep patch tar gzip bzip2 openssh-clients yum perl createrepo_c dnf-utils git kpartx xz"
    if [[ ${ARCH} == "ppc64le" ]];then
        pkglist="${pkglist} grub2-tools grub2-ppc64le-modules"
    fi
    yum install -c ${REPO_CONF} --installroot=${OPENEULER_CHROOT_PATH} -y ${pkglist} -x glibc32
    mkdir -m 755 -p ${OPENEULER_CHROOT_PATH}/dev/pts
    test -d ${OPENEULER_CHROOT_PATH}/dev/shm || rm -f ${OPENEULER_CHROOT_PATH}/dev/shm
    mkdir -m 755 -p ${OPENEULER_CHROOT_PATH}/dev/shm
    mount --bind /dev ${OPENEULER_CHROOT_PATH}/dev/
    while read com file mode arg
    do
	rm -f ${OPENEULER_CHROOT_PATH}/dev/$file
	if [[ $com = ln ]];then
            ln -s $arg ${OPENEULER_CHROOT_PATH}/dev/$file
            continue
	fi
	$com -m $mode ${OPENEULER_CHROOT_PATH}/dev/$file $arg
    done << DEVLIST
    mknod null    666 c 1 3
    mknod zero    666 c 1 5
    mknod full    622 c 1 7
    mknod random  666 c 1 8
    mknod urandom 644 c 1 9
    mknod tty     666 c 5 0
    mknod ptmx    666 c 5 2
    mknod loop-control 600 c 10 237
    mknod loop0   640 b 7 0
    mknod loop1   640 b 7 1
    mknod loop2   640 b 7 2
    mknod loop3   640 b 7 3
    ln    fd      777 /proc/self/fd
    ln    stdin   777 fd/0
    ln    stdout  777 fd/1
    ln    stderr  777 fd/2
DEVLIST
    mount -n -tdevpts -omode=0620,gid=5 none ${OPENEULER_CHROOT_PATH}/dev/pts
    mkdir -p ${OPENEULER_CHROOT_PATH}/proc ${OPENEULER_CHROOT_PATH}/sys
    mount --bind /sys ${OPENEULER_CHROOT_PATH}/sys
    mount --bind /proc ${OPENEULER_CHROOT_PATH}/proc

    rm -f "${OPENEULER_CHROOT_PATH}/etc/yum.repos.d"/*
    cp "${REPO_CONF}" "${OPENEULER_CHROOT_PATH}/etc/yum.repos.d/"
    cp -a "${BUILD_SCRIPT_DIR}"/* "${OPENEULER_CHROOT_PATH}/home"
    mkdir -p "${OPENEULER_CHROOT_PATH}/root/.ssh/"
    cp /root/.ssh/super_publish_rsa "${OPENEULER_CHROOT_PATH}/root/.ssh/"
    cp /etc/resolv.conf "${OPENEULER_CHROOT_PATH}/etc/"
    if echo "${BUILD_SCRIPT_DIR}" | grep 'gcov-'; then
        sed -i '/VERSION=/ iexport CI_PROJECT="openeuler_ARM64_gcov"' "${OPENEULER_CHROOT_PATH}"/home/internal.sh
    fi
    if [[ ${STEP} == "get_epol_rpms" ]];then
        git clone --depth=1 https://gitee.com/src-openeuler/openEuler-repos -b openEuler-23.03
        cp openEuler-repos/RPM-GPG-KEY-EBS "${OPENEULER_CHROOT_PATH}/home/"
        rm -rf openEuler-repos
    fi
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
