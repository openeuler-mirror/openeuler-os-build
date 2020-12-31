#!/bin/bash
# Author: xudengfeng
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# get vmcoretool 
# Globals:
# Arguments:
# Returns:
######################
function get_vmcoretool()
{
    el_repo="$1"
    vmcorelst="$2"
    tooldir="$3"
    tooltar="$4"
    product="$5"

    if [ ! -f "${vmcorelst}" ];then
        log_error "not found ${vmcorelst}"
        return 1
    fi
    [ -n "${tooldir}" ] && rm -rf "${tooldir}"
    mkdir "${tooldir}"
    mkdir "${tooldir}"/tmp
    yum clean all -c "${yum_conf}"
    yum clean all -c "${yum_conf_storage}"
    if [ "x${product}" = "xstandard" ];then
        yumdownloader -c "${yum_conf}" --exclude="*.src" --destdir="${tooldir}"/tmp $(cat "${vmcorelst}" | tr '\n' ' ')
    elif [ "x${product}" = "xstorage" ];then
        yumdownloader -c "${yum_conf_storage}" --exclude="*.src" --destdir="${tooldir}"/tmp $(cat "${vmcorelst}" | tr '\n' ' ')
    fi

    if [ $? -ne 0 ]; then
        log_error "when get vmcore debug rpm failed"
        return 1
    fi
    cd "${tooldir}"
    cd tmp

    #vmcore_list=$(ls ./Euler/*.rpm)
    vmcore_list=$(ls ./*.rpm)
    if [ $? -ne 0 ];then
        echo "mktool.sh: function [get_vmcoretool] [${LINENO}]: rpm is not exist. please download it yourself." && return 1
    fi
    for rpm in ${vmcore_list[*]}
    do
        rpm2cpio "${rpm}" | cpio -id
        [ -n "${rpm}" ] && rm -rf "${rpm}"
    done

    if [ "x${product}" = "xstorage" ];then
        cp -p usr/lib64/libsnappy.so.1  ../
        cp -p usr/lib64/liblzo2.so.2  ../
        echo "#!/bin/bash" > ../install.sh
        echo "cp ./lib*  /usr/lib64/" >> ../install.sh
        chmod 700 ../install.sh
    fi

    cp -p usr/bin/crash ../
    cp -p usr/lib/debug/lib/modules/*/vmlinux ../
    cd -
    rm -rf tmp
    tar -zcf ../"${tooltar}" *
    cd ..
    [ -n "${tooldir}" ] && rm -rf "${tooldir}"
}
