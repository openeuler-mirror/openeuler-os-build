#!/bin/bash
SCRIPTS_DIR=$(cd $(dirname $0);pwd)
set -xe

download_gcc()
{
    ls "${GCC_INSTALL_DIR}"/openeuler_gcc_arm32le "${GCC_INSTALL_DIR}"/openeuler_gcc_arm64le && return 0
    local url="https://gitee.com/openeuler/yocto-embedded-tools/attach_files/1003463/download/openeuler_gcc_arm32le.tar.xz"
    test -f "${TOOLS_DIR}/$(basename ${url})" || wget "${url}" -P "${TOOLS_DIR}"
    local url="https://gitee.com/openeuler/yocto-embedded-tools/attach_files/1003462/download/openeuler_gcc_arm64le.tar.xz"
    test -f "${TOOLS_DIR}/$(basename ${url})" || wget "${url}" -P "${TOOLS_DIR}"

    return 0

    local url="https://releases.linaro.org/components/toolchain/binaries/7.3-2018.05/aarch64-linux-gnu/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu.tar.xz"
    test -f "${TOOLS_DIR}/$(basename ${url})" || wget "${url}" -P "${TOOLS_DIR}"
    url="https://releases.linaro.org/components/toolchain/binaries/7.3-2018.05/aarch64-linux-gnu/sysroot-glibc-linaro-2.25-2018.05-aarch64-linux-gnu.tar.xz"
    test -f "${TOOLS_DIR}/$(basename ${url})" || wget "${url}" -P "${TOOLS_DIR}"
    url="https://releases.linaro.org/components/toolchain/binaries/7.3-2018.05/arm-linux-gnueabi/sysroot-glibc-linaro-2.25-2018.05-arm-linux-gnueabi.tar.xz"
    test -f "${TOOLS_DIR}/$(basename ${url})" || wget "${url}" -P "${TOOLS_DIR}"
    url="https://releases.linaro.org/components/toolchain/binaries/7.3-2018.05/arm-linux-gnueabi/gcc-linaro-7.3.1-2018.05-x86_64_arm-linux-gnueabi.tar.xz"
    test -f "${TOOLS_DIR}/$(basename ${url})" || wget "${url}" -P "${TOOLS_DIR}"
}

install_gcc_tar()
{
    local install_dir="$1"
    [[ -z "${install_dir}" ]] && install_dir="/usr1/openeuler/gcc"
    test -d "${install_dir}" || mkdir -p "${install_dir}"
    pushd "${install_dir}"
    for i in $(ls "${TOOLS_DIR}"/*.tar.*)
    do
        local unpackdir="$(tar -tf "$i"  | awk -F/ '{print $1}' | uniq)"
        test -d ./"${unpackdir}" || tar -xf "$i"
        find ./"${unpackdir}" -type d | xargs chmod go+x
        chmod go+r ./"${unpackdir}" -R
    done
    popd
}

update_code_repo()
{
    local repo="$1"
    local branch="-b $2"
    local realdir="$3"
    local pkg="$(basename ${repo})"
    local branchname="$2"
    [[ -z "${realdir}" ]] || pkg="$(basename ${realdir})"
    [[ "${pkg}" == "kernel-5.10" ]] && local git_param="--depth 1"
    pushd "${SRC_DIR}"
    test -d ./"${pkg}"/.git || { rm -rf ./"${pkg}";git clone "${URL_PREFIX}/${repo}" ${branch} ${git_param} -v "${pkg}"; }
    pushd ./"${pkg}"
    git checkout origin/${branchname} -b ${branchname} || echo ""
    git checkout -f ${branchname}
    git branch | grep "^*" | grep " ${branchname}$" || exit 1
    git config pull.ff only
    while true
    do
        git reset --hard HEAD^ || echo ""
        git reset --hard HEAD
        git clean -dfx
        git pull
        git status | grep "is up to date with" && break
    done
    local newest_commitid="$(git log --pretty=oneline  -n1 | awk '{print $1}')"
    echo "${repo} ${newest_commitid}" >> "${SRC_DIR}"/code.list
    popd
    popd
}

download_code()
{
    mkdir -p "${SRC_DIR}"/
    rm -f "${SRC_DIR}"/code.list
    update_code_repo openeuler/yocto-meta-openeuler openEuler-22.03-LTS
}

install_python()
{
wget https://www.python.org/ftp/python/3.9.2/Python-3.9.2.tgz
tar -xf Python-3.9.2.tgz
install_dir="/opt/buildtools/python-3.9.2/"
rm -rf "${install_dir}"
rm /usr/local/bin/python3 /usr/local/bin/python
cd Python-3.9.2
./configure --prefix=/opt/buildtools/python-3.9.2 --enable-loadable-sqlite-extensions
make -j 8 && make install
ln -s /opt/buildtools/python-3.9.2/bin/python3 /usr/local/bin/python3
ln -s /opt/buildtools/python-3.9.2/bin/python3 /usr/local/bin/python
#ModuleNotFoundError: No module named '_socket'
#export PYTHON_HOME="/opt/buildtools/python-3.9.2/"
export PYTHONPATH=/opt/buildtools/python-3.9.2/lib64/python3.9/lib-dynload/
export PYTHONPATH="/opt/buildtools/python-3.9.2/lib/python3.9/site-packages/:/opt/buildtools/python-3.9.2/:/opt/buildtools/python-3.9.2/lib64/python3.9/lib-dynload/"
}

install_ninja()
{
"${TOOLS_INSTALL_DIR}"/ninja-1.10.1/bin/ninja  --version && return 0
wget https://distfiles.macports.org/ninja/ninja-1.10.1.tar.gz
tar -xf ninja-1.10.1.tar.gz
cd ninja-1.10.1
ls -l
sed -ie '1c#!/usr/bin/env python3' *.py
./configure.py --bootstrap
mkdir -p "${TOOLS_INSTALL_DIR}"/ninja-1.10.1/bin || echo ""
install -m 0755 ./ninja "${TOOLS_INSTALL_DIR}"/ninja-1.10.1/bin
cd -
}

install_sphinx()
{
yum -y install sphinx

#Installing:
# sphinx                   x86_64                2.2.11-1.oe1                everything                4.4 M
#Installing dependencies:
# apr                      x86_64                1.7.0-4.oe1                 OS                        109 k
# apr-util                 x86_64                1.6.1-14.oe1                OS                        110 k
# gpdb                     x86_64                6.17.0-3.oe1                update                     11 M
# net-tools                x86_64                2.0-0.54.oe1                OS                        198 k
# rsync                    x86_64                3.1.3-6.oe1                 OS                        323 k
# xerces-c                 x86_64                3.2.2-3.oe1                 everything                916 k

}

#zypper install autoconf automake chrpath patch
TOOLS_DIR="/usr1/openeuler/src/tools"
SRC_DIR="/usr1/openeuler/src/"
GCC_INSTALL_DIR="/usr1/openeuler/gcc"
TOOLS_INSTALL_DIR="/opt/buildtools"
URL_PREFIX="https://gitee.com/"

is_install_tools=$1
if [[ "$is_install_tools" == "yes" ]];then
download_gcc
#install_ninja
install_gcc_tar "${GCC_INSTALL_DIR}"
#zypper --non-interactive install rpmbuild libtool patchelf autoconf automake chrpath patch
###depends by python
#zypper --non-interactive install libffi-devel sqlite-devel xz-devel
#for openeuler
yum -y install tar cmake gperf sqlite-devel
yum -y install chrpath gcc-c++ patch rpm-build flex autoconf automake m4 bison bc libtool gettext-devel createrepo_c rpcgen texinfo hostname python meson dosfstools mtools parted ninja-build autoconf-archive libmpc-devel gmp-devel numactl-devel make
#dsoftbus need python3 to build
which python
python --version | grep " 3" || ln -sf /usr/bin/python3 /usr/local/bin/python
fi

download_code
#download kernel by tag, cannot change tag automatically
rm -rf "${SRC_DIR}"/kernel-5.10
sh "${SRC_DIR}"/yocto-meta-openeuler/scripts/download_code.sh
exit $?
