function get_repose()
{
    expect -c "
    spawn $*
    expect {
        \"*yes/no*\" {send \"yes\n\"}
        eof
    }
    catch wait result;
    exit [lindex \$result 3]
    "
}

function get_latest()
{
    # release iso path
    release_path=$1
    key_file=$2
    ip=$3
    port=$4
    version=${release_path#*dailybuild/}
    daily_dir=""
    while [[ ! ${daily_dir} ]]
    do
        daily_dir=$(get_repose ssh -i ${key_file} -p ${port} root@${ip} ls -lr ${release_path} | grep openeuler- | grep -v ${version} | grep -v test | grep -v total | grep -v established | awk '{print $9}' | grep ^openeuler- | head -n 1 | tr -d '\r')
    done
    echo ${daily_dir}
}

function umount_iso()
{
    latest_path=$1
    key_file=$2
    ip=$3
    port=$4
    release_path=${latest_path%/*}
    latest_dir=${latest_path##*/}
    res=$(get_repose ssh -i ${key_file} -p ${port} root@${ip} mount | grep "${release_path}" | grep -v "${latest_dir}" | grep -v test | awk '{print $1}')
    if [[ $res ]];then
        for iso_path in $res
        do
            if [[ ${iso_path} =~ ${latest_path} ]];then
                continue
            fi
            if [[ ${iso_path} =~ ${release_path} ]];then
                get_repose ssh -i ${key_file} -p ${port} root@${ip} umount ${iso_path}
            fi
        done
    fi
}

function check_iso_mount()
{
    iso_list=$1
    key_file=$2
    ip=$3
    port=$4
    for iso_path in ${iso_list}
    do
        release_path=${iso_path%ISO*}
        tmp=${iso_path#*ISO/}
        arch=${tmp%/*}
        res=$(get_repose ssh -i ${key_file} -p ${port} root@${ip} mount | grep ${iso_path})
        if [[ ${res} =~ ${iso_path} ]];then
            echo "mount success"
        elif [[ ${iso_path} =~ "source" ]];then
            get_repose ssh -i ${key_file} -p ${port} root@${ip} mount -o loop ${iso_path} ${release_path}/source
        elif [[ ${iso_path} =~ "debug" ]];then
            get_repose ssh -i ${key_file} -p ${port} root@${ip} mount -o loop ${iso_path} ${release_path}/debuginfo/${arch}
        elif [[ ${iso_path} =~ "everything" ]];then
            get_repose ssh -i ${key_file} -p ${port} root@${ip} mount -o loop ${iso_path} ${release_path}/everything/${arch}
        else
            get_repose ssh -i ${key_file} -p ${port} root@${ip} mount -o loop ${iso_path} ${release_path}/OS/${arch}
        fi
    done
}

function get_iso_list()
{
    latest_path=$1
    key_file=$2
    ip=$3
    port=$4
    iso_list=
    res=$(get_repose ssh -i ${key_file} -p ${port} root@${ip} ls -R ${latest_path}/ISO | grep iso | grep -v sha256sum | grep -v netinst)
    for iso_path in $res
    do
        if [[ ${iso_path} =~ ".iso" ]];then
            iso_name=`echo ${iso_path} | tr -d '\r'`
            if [[ ${iso_name} =~ "source" ]];then
                iso_name=${latest_path}/ISO/source/${iso_name}
            elif [[ ${iso_name} =~ "aarch64" ]];then
                iso_name=${latest_path}/ISO/aarch64/${iso_name}
            else
                iso_name=${latest_path}/ISO/x86_64/${iso_name}
            fi
            iso_list="${iso_list} ${iso_name}" 
        fi
    done
    echo ${iso_list}
}


release_path=$1
key_file=$2
dailybuild_ip=$3
dailybuild_port=$4
latest_path=${release_path}/$(get_latest ${release_path} ${key_file} ${dailybuild_ip} ${dailybuild_port})
iso_list=$(get_iso_list ${latest_path} ${key_file} ${dailybuild_ip} ${dailybuild_port})
umount_iso ${latest_path} ${key_file} ${dailybuild_ip} ${dailybuild_port}
check_iso_mount "${iso_list}" ${key_file} ${dailybuild_ip} ${dailybuild_port}



