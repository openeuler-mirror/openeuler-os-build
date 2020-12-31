#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# make dev file for compile env
# Globals:
# Arguments:
# Returns:
######################
function prepare_for_dev()
{
    #pushd "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/dev/"
    pushd "${1}"
    rm -rf *
    mkdir shm pts
    mknod tty c 5 0
    mknod ptmx c 5 2
    mknod null c 1 3
    mknod zero c 1 5
    mknod full c 1 7
    mknod random c 1 8
    mknod urandom c 1 9
    mknod loop0 b 7 0
    mknod loop1 b 7 1
    mknod loop2 b 7 2
    mknod loop3 b 7 3
    ln -sf /proc/self/fd fd
    ln -sf fd/0 stdin
    ln -sf fd/1 stdout
    ln -sf fd/2 stderr
    popd
}

######################
# change uname file for compile env
# Globals:
# Arguments:
# Returns:
######################
function change_uname()
{
    cat << EOF > "${1}"
#!/bin/sh

OUTPUT=\`uname.bin \$*\`
NOT_INSTALLED="is not installed"

if [[ \$* == "-r" ]];then
    dir=\`rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel | head -n 1\`
    if [ -z "\$(echo "\${dir}" | grep "\${NOT_INSTALLED}")" ]; then
        [ -n "\${dir}" ] && echo \${dir} && exit 0
    fi
    dir=\`rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-devel | head -n 1\`
    if [ -z "\$(echo "\${dir}" | grep "\${NOT_INSTALLED}")" ]; then
        [ -n "\${dir}" ] && echo \${dir} && exit 0
    fi
    dir=\`rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-headers | head -n 1\`
    if [ -z "\$(echo "\${dir}" | grep "\${NOT_INSTALLED}")" ]; then
        [ -n "\${dir}" ] && echo \${dir} && exit 0
    fi
    echo "error: you must installed kernel or kernel-headers" && exit 1
else
    echo \${OUTPUT}
fi
EOF

}

######################
# change uname file for cross compile env
# Globals:
# Arguments:
# Returns:
######################
function change_uname_cross()
{
    cat << EOF > "${BUILD_SCRIPT_DIR}/${COMPILE_ENV}/usr/bin/uname"
#!/bin/sh

OUTPUT=\`uname.bin \$*\`
if [  \$# -ne 1 ]||[[ \$1 != "-r" && \$1 != "-a" ]]; then
    echo \${OUTPUT}
else
    if test -f /.kernelversion ; then
        MREL=\`cat /.kernelversion\`
    fi

    if test -z "\${MREL}" -a -L /usr/src/linux -a -d /usr/src/linux ; then
        MREL=\$( shopt -s nullglob; set -- /lib/modules/*-default /lib/modules/* ; basename \$1 )
    fi

    if test -z "\${MREL}" -a -f /usr/src/linux/Makefile ; then
        MREL=\`grep "^VERSION = " /usr/src/linux/Makefile 2> /dev/null | sed -e "s/VERSION = //"\`
        MREL="\${MREL}".\`grep "^PATCHLEVEL = " /usr/src/linux/Makefile 2> /dev/null | sed -e "s/PATCHLEVEL = //"\`
        MREL="\${MREL}".\`grep "^SUBLEVEL = " /usr/src/linux/Makefile 2> /dev/null | sed -e "s/SUBLEVEL = //"\`
    fi

    if test -z "\${MREL}" ; then
        MREL=\`grep UTS /usr/include/linux/version.h 2> /dev/null | sed -ne "s/.*\"\(.*\)\".*/\1/p;q"\`
    fi

    if test -n "\${MREL}" ; then
        if [[ "\$1" == "-r" ]] ; then
            echo \${MREL}
        else
            echo \${OUTPUT} | awk -v mrel=\${MREL} '{\$3=mrel;print}'
        fi
    else
        echo \${OUTPUT}
    fi
fi
EOF
}
