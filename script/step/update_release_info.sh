#!/bin/bash
set -e

function update_release_info()
{
    #if [ "${ISCI}" -eq 0 ]; then
    #    return 0
    #fi
    
    temp_dir="code_merge_dir"
    pkg="openEuler-latest-release"
    obs_pro="${OBS_STANDARD_PROJECT}"

    [ -n "${temp_dir}" ] && rm -rf "${temp_dir}"
    mkdir "${temp_dir}"
    cd "${temp_dir}"

    #init_osc
    osc co "${obs_pro}" "${pkg}"
    osc up "${obs_pro}/${pkg}"
    set +u

    #update sdf file
    get_version
    release_dir=$(get_release_dir)
    TIME_DIR=${release_dir#/repo/openeuler/dailybuild/}

    TIME=${TIME_DIR##*/}
    TIME=${TIME#"${version}"-}
    version="openEuler"
    echo "${version}" > version
    rm -rf kernel*.rpm java-1.8.0-openjdk*.rpm gcc*.rpm
    #yumdownloader kernel
    wget -q -r -l1 -nd -A kernel-[0-9]*.${ARCH}.rpm ${OBS_STANDARD_REPO_URL}/${ARCH}/
    wget -q -r -l1 -nd -A java-1.8.0-openjdk-[0-9]*.${ARCH}.rpm ${OBS_STANDARD_REPO_URL}/${ARCH}/
    wget -q -r -l1 -nd -A gcc-[0-9]*.${ARCH}.rpm ${OBS_STANDARD_REPO_URL}/${ARCH}/
    mv kernel*.rpm kernel.rpm
    mv java-1.8.0-openjdk*.rpm java-1.8.0-openjdk.rpm
    mv gcc*.rpm gcc.rpm
    kver=$(rpm -qp --qf "%{Version}-%{Release}\n" kernel.rpm)
    dogshengopenjdk=$(rpm -qp --qf "%{Version}-%{Release}\n" java-1.8.0-openjdk.rpm)
    dogshenggcc=$(rpm -qp --qf "%{Version}-%{Release}\n" gcc.rpm)
    
    namer="${kver}"
    dailyversion="${OS_NAME}-${OS_VERSION}"
    
    set +e
    sdf_file="${obs_pro}/${pkg}/isopackage.sdf"
    echo "openeulerversion=${dailyversion}" > "${sdf_file}"
    echo "compiletime=${TIME}" >> "${sdf_file}"
    echo "gccversion=${dogshenggcc}" >> "${sdf_file}"
    echo "kernelversion=${namer}" >> "${sdf_file}"
    echo "openjdkversion=${dogshengopenjdk}" >> "${sdf_file}"
    sdf_file="${obs_pro}/${pkg}/isopackage_arm64.sdf"
    echo "openeulerversion=${dailyversion}" > "${sdf_file}"
    echo "compiletime=${TIME}" >> "${sdf_file}"
    echo "gccversion=${dogshenggcc}" >> "${sdf_file}"
    echo "kernelversion=${namer}" >> "${sdf_file}"
    echo "openjdkversion=${dogshengopenjdk}" >> "${sdf_file}"
    set -e
    #update end
    timestr=`date +%s --utc -d "$(grep "compiletime" ${sdf_file} | cut -d '=' -f2 | sed 's/-/ /3' | sed 's/-/:/3' | sed 's/-/:/3')"`
    root_url=$(echo ${OBS_STANDARD_REPO_URL%/*})
    arm_flag=0
    x86_flag=0
    wget -q -r -l1 -nd -A openEuler-latest-release-*.aarch64.rpm ${root_url}/standard_aarch64/aarch64/
    pkginfo=`ls | grep $pkg`
    if [[ "$pkginfo" =~ "$timestr" ]];then
        arm_flag=1
        rm -rf ${pkg}*
    fi
    wget -q -r -l1 -nd -A openEuler-latest-release-*.x86_64.rpm ${root_url}/standard_x86_64/x86_64/
    pkginfo=`ls | grep $pkg`
    if [[ "$pkginfo" =~ "$timestr" ]];then
        x86_flag=1
        rm -rf ${pkg}*
    fi
    if [[ ${arm_flag} -eq 1 ]] && [[ ${x86_flag} -eq 1 ]];then
        echo "nothing to do"
    else
        #code commit
        rm -rf ${pkg}*
        cd "${obs_pro}/${pkg}"
        osc up
        osc add isopackage.sdf 
        osc ci -m "update isopackage.sdf"
        osc up
        osc add isopackage_arm64.sdf 
        osc ci -m "update isopackage_arm64.sdf"
        waitime=6000
        while [ $waitime -gt 0 ]
        do
            set +e
            if [ ${arm_flag} -eq 0 ];then
                wget -q -r -l1 -nd -A openEuler-latest-release-*.aarch64.rpm ${root_url}/standard_aarch64/aarch64/
                pkginfo=`ls | grep $pkg`
                if [[ "$pkginfo" =~ "$timestr" ]];then
                    arm_flag=1
                fi
                rm -rf ${pkg}*
            fi
            if [ ${x86_flag} -eq 0 ];then
                wget -q -r -l1 -nd -A openEuler-latest-release-*.x86_64.rpm ${root_url}/standard_x86_64/x86_64/
                pkginfo=`ls | grep $pkg`
                if [[ "$pkginfo" =~ "$timestr" ]];then
                    x86_flag=1
                fi
                rm -rf ${pkg}*
            fi
            if [[ ${arm_flag} -eq 1 ]] && [[ ${x86_flag} -eq 1 ]];then
                break
            fi
            let waitime=$waitime-5
            sleep 5
            set -e
        done
        cd "${BUILD_SCRIPT_DIR}"
        [ -n "${temp_dir}" ] && rm -rf "${temp_dir}"
    fi
}
