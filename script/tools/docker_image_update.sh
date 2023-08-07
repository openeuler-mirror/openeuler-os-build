#!/bin/bash
# --------------------------------------------------------------------------------------------------------------------
# Author: 
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
# Decription: Create an UPDATE directory to add, delete, update, check and publish package binaries
# --------------------------------------------------------------------------------------------------------------------


# usage
function usage() {
    cat << EOF
Usage: sh docker_image_update.sh [Operation] [Branch] [Openeuler_dir] [Update_dir] [Source_ip] [Release_ip] [Publish_key]

optional arguments:
    Operation     Operation method, include: create, update, delete_update_dir and release
    Branch        Branch name, such as: openEuler-22.03-LTS
    Openeuler_dir build directory start with openeuler- on the dailybuild server
    Update_dir    Update directory name
    Source_ip     Server of store hotpatch
    Release_ip    Server of release hotpatch
    Publish_key   Server of publish key
EOF
}

# ssh server exec cmd
function ssh_cmd() {
	local machine_ip=$1
	local exec_cmd=$2
	ssh -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${machine_ip} "${exec_cmd}"
	if [ $? -ne 0 ];then
		echo "Error: exec cmd fail. [cmd]:$cmd"
		exit 1
	fi
}

# insert the update directory name into the json file
function insert_dir() {
	local category=$1
	if [[ "${category}" == "history" ]] || [[ "${category}" == "update" ]];then
		res=`grep "${update_dir}\"$" ${json_file_name}`
		if [ ! -n "${res}" ];then
			sed -i "/\"${category}\"/ a\		{\n			\"dir\": \"${update_dir}\"\n		}," ${json_file_name}
		fi
	fi
}

# delete the update directory name in the json file
function delete_json_dir() {
	res=`grep "${update_dir}\"$" ${json_file_name}`
	if [ -n "${res}" ];then
		sed -i -e "/${update_dir}\"$/{n;d}" -e "\$!N;/\n.*${update_dir}\"$/!P;D" ${json_file_name}
		sed -i "/${update_dir}\"$/d" ${json_file_name}
	fi
}

# init json file
function init_json_file() {
	cmd="if [ ! -s ${json_file_path} ];then echo '{' > ${json_file_path} && sed -i '/{/a\ \t\"update\":[\n\t],\n\t\"history\":[\n\t]\n}' ${json_file_path};fi"
	ssh_cmd ${source_ip} "${cmd}"
}

# update the contents of the json file
function update_json_file() {
	if [[ ${need_modify_json[@]} =~ ${operation} ]];then
		init_json_file
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${source_ip}:${json_file_path} .
		if [[ ${operation} == "create" ]];then
			insert_dir "update"
		elif [[ ${operation} == "delete_update_dir" ]];then
			delete_json_dir
		elif [[ ${operation} == "release" ]];then
			delete_json_dir
			insert_dir "history"
		fi
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ${json_file_name} root@${source_ip}:${json_file_path}
	fi
}

# create update directory and add docker image
function create() {
	echo "add docker image into the ${update_dir} directory."
	for ar in ${arch_list[@]}
	do
		cmd="if [ ! -d ${update_path}/${ar} ];then mkdir -p ${update_path}/${ar};fi"
		ssh_cmd ${source_ip} "${cmd}"
		cmd="cp ${source_img_dir}/${ar}/openEuler-docker.${ar}.tar.xz ${update_path}/${ar}/"
		ssh_cmd ${source_ip} "${cmd}"
		cmd="cp ${source_img_dir}/${ar}/openEuler-docker.${ar}.tar.xz.sha256sum ${update_path}/${ar}/"
		ssh_cmd ${source_ip} "${cmd}"
	done
}

# delete update_xxx directory
function delete_update_dir() {
	echo "delete the ${update_path} directory."
	cmd="if [ -d ${update_path} ];then rm -rf ${update_path};fi"
	ssh_cmd ${source_ip} "${cmd}"
}

# delete docker image
function delete_docker_image() {
	echo "delete docker image from the ${update_path} directory."
	cmd="if [ ! -d ${update_path} ];then echo \"Error: ${update_path} is not exist.\" && exit 1;fi"
	ssh_cmd ${source_ip} "${cmd}"
	for ar in ${arch_list[@]}
	do
		cmd="rm -f ${update_path}/${ar}/openEuler-docker.${ar}.tar.xz"
		ssh_cmd ${source_ip} "${cmd}"
		cmd="rm -f ${update_path}/${ar}/openEuler-docker.${ar}.tar.xz.sha256sum"
		ssh_cmd ${source_ip} "${cmd}"
	done
}

# update docker image
function update() {
	echo "update docker image in the ${update_path} directory."
	delete_docker_image
	create
}

# publish docker image file
function release() {
	cmd="if [ ! -d ${update_path} ];then echo \"Error: ${update_path} is not exist.\" && exit 1;fi"
	ssh_cmd ${source_ip} "${cmd}"
	echo "publish docker image file in the ${update_path} directory to the official website."
	for ar in ${arch_list[@]}
	do
		# backup update_xxx dir docker image into docker_img/update dir
		cmd="if [ ! -d ${backup_path}/${ar} ];then mkdir -p ${backup_path}/${ar};fi"
		ssh_cmd ${source_ip} "${cmd}"
		cmd="cp ${update_path}/${ar}/openEuler-docker.${ar}.tar.xz ${backup_path}/${ar}/"
		ssh_cmd ${source_ip} "${cmd}"
		cmd="cp ${update_path}/${ar}/openEuler-docker.${ar}.tar.xz.sha256sum ${backup_path}/${ar}/"
		ssh_cmd ${source_ip} "${cmd}"

		# release docker image to website
		cmd="if [ ! -d ${release_path} ];then mkdir -p ${release_path};fi"
		ssh_cmd ${release_ip} "${cmd}"
		rm -rf ${ar}
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -r root@${source_ip}:${update_path}/${ar} ./
		result=$(find ./${ar} -name "openEuler-docker.${ar}.tar.xz*" -type f)
		if [ -z "${result}" ];then
			echo "Error: there is no docker image file in directory ${update_path}/${ar}."
			exit 1
		else
			scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -r ./${ar} root@${release_ip}:${release_path}/
			rm -rf ${ar}
		fi
	done
}


# main function
function main() {
	if [ $# -lt 6 ] || [ $# -gt 7 ];then
		echo "Error: please check the params."
		usage
		exit 1
	fi

	operation=$1
	branch_name=$2
	openeuler_dir=$3
	update_dir=$4
	source_ip=$5
	release_ip=$6
	publish_key=$7

	if [ -z "${operation}" ] || [ -z "${branch_name}" ] || [ -z "${update_dir}" ] || [ -z "${source_ip}" ] || [ -z "${release_ip}" ] || [ -z "${publish_key}" ];then
		echo "Error: please check the params."
		usage
		exit 1
	fi

	need_openeuler_dir=(create update)
	if [[ ${need_openeuler_dir[@]} =~ ${operation} ]];then
		if [ -z "${openeuler_dir}" ];then
			echo "Error: openeuler_dir is empty."
			usage
			exit 1
		fi
	fi

	if [ "x${update_dir}" == "x" ];then
		update_dir="update_"`date +%Y%m%d`
	fi

	arch_list=(aarch64 x86_64)
	need_modify_json=(create delete_update_dir release)
	source_img_dir="/repo/openeuler/dailybuild/${branch_name}/${openeuler_dir}/docker_img"

	if [[ ${branch_name} =~ "EBS-" ]];then
	    branch_name=${branch_name#*-}
	fi
	json_file_name="${branch_name}-update.json"
	branch_path="/repo/openeuler/repo.openeuler.org/${branch_name}"
	update_path="${branch_path}/docker_img/${update_dir}"
	json_file_path="${branch_path}/docker_img/${json_file_name}"
	date_str="$(date +%Y-%m-%d)"
	backup_path="${branch_path}/docker_img/update/${date_str}"
	release_path="/repo/openeuler/${branch_name}/docker_img/update/${date_str}"

	if [ ${operation} == "create" ];then
		create
		update_json_file
	elif [ ${operation} == "delete_update_dir" ];then
		delete_update_dir
		update_json_file
	elif [ ${operation} == "update" ];then
		update
	elif [ ${operation} == "release" ];then
		release
		update_json_file
	else
		echo "Error: not support function:${operation}."
		usage
		exit 1
	fi
}


main "$@"
