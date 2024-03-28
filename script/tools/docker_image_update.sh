#!/bin/bash
# --------------------------------------------------------------------------------------------------------------------
# Author: 
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
# --------------------------------------------------------------------------------------------------------------------
. chroot_libs.sh

# usage
function usage() {
    cat << EOF
Usage: bash docker_image_update.sh [Operation] [Branch] [Update_dir] [Source_ip] [Release_ip] [Publish_key]

optional arguments:
    Operation     Operation method, include: create, delete_update_dir and release
    Branch        Branch name, such as: openEuler-22.03-LTS
    Update_dir    Update directory name
    Source_ip     Server of source
    Release_ip    Server of release
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

function config_repo()
{
	rm -rf /etc/yum.repos.d.bak
	mv /etc/yum.repos.d /etc/yum.repos.d.bak
	mkdir -p /etc/yum.repos.d
	export yum_conf="/etc/yum.repos.d/my.repo"
	touch ${yum_conf}
	i=1
	for repo in ${repo_url[@]}
	do
		cat >> ${yum_conf} <<-EOF
		[repo_$i]
		name=repo_$i
		baseurl=${repo}
		enabled=1
		gpgcheck=0

		EOF
		let i=i+1
	done
	cat /etc/yum.repos.d/my.repo
}

# create update directory and docker image
function create() {
	echo "add docker image into the ${update_dir} directory."
	cmd="if [ ! -d ${update_path}/${ARCH} ];then mkdir -p ${update_path}/${ARCH};fi"
	ssh_cmd ${source_ip} "${cmd}"
	config_repo
	chroot_init
	export branch=$(echo ${branch_name} | tr A-Z a-z)
	chroot "${root_path}" /bin/bash --login -c "cd /home/; bash make_docker.sh"
	if [ -f "${root_path}/result/docker_image/image/openEuler-docker.${ARCH}.tar.xz" ];then
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -r ${root_path}/result/docker_image/image/openEuler-docker.${ARCH}.tar.xz root@${source_ip}:${update_path}/${ARCH}/
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -r ${root_path}/result/docker_image/image/openEuler-docker.${ARCH}.tar.xz.sha256sum root@${source_ip}:${update_path}/${ARCH}/
	else
		echo "make docker image failed."
		chroot_clean
		exit 1
	fi
	chroot_clean
}

# delete update_xxx directory
function delete_update_dir() {
	echo "delete the ${update_path} directory."
	cmd="if [ -d ${update_path} ];then rm -rf ${update_path};fi"
	ssh_cmd ${source_ip} "${cmd}"
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

# link latest date dir
function link_latest_dir() {
	cmd="cd ${docker_update_path} && rm -rf current && ln -s ${date_str} current"
	ssh_cmd ${release_ip} "${cmd}"
}

# main function
function main() {
	if [ $# -lt 5 ] || [ $# -gt 6 ];then
		echo "Error: please check the params."
		usage
		exit 1
	fi

	operation=$1
	branch_name=$2
	update_dir=$3
	source_ip=$4
	release_ip=$5
	publish_key=$6

	if [ -z "${operation}" ] || [ -z "${branch_name}" ] || [ -z "${update_dir}" ] || [ -z "${source_ip}" ] || [ -z "${release_ip}" ] || [ -z "${publish_key}" ];then
		echo "Error: please check the params."
		usage
		exit 1
	fi

	if [ "x${update_dir}" == "x" ];then
		update_dir="update_"`date +%Y%m%d`
	fi

	arch_list=(aarch64 x86_64)
	need_modify_json=(create delete_update_dir release)

	if [[ ${branch_name} =~ "EBS-" ]];then
	    branch_name=${branch_name#*-}
	fi
	json_file_name="${branch_name}-update.json"
	branch_path="/repo/openeuler/repo.openeuler.org/${branch_name}"
	update_path="${branch_path}/docker_img/${update_dir}"
	json_file_path="${branch_path}/docker_img/${json_file_name}"
	date_str="$(date +%Y-%m-%d)"
	backup_path="${branch_path}/docker_img/update/${date_str}"
	docker_update_path="/repo/openeuler/${branch_name}/docker_img/update"
	release_path="${docker_update_path}/${date_str}"
	ARCH=$(arch)
	export repo_url="https://repo.openeuler.openatom.cn/${branch_name}/everything/${ARCH} https://repo.openeuler.openatom.cn/${branch_name}/update/${ARCH}"

	if [ ${operation} == "create" ];then
		create
		update_json_file
	elif [ ${operation} == "delete_update_dir" ];then
		delete_update_dir
		update_json_file
	elif [ ${operation} == "release" ];then
		release
		link_latest_dir
		update_json_file
	else
		echo "Error: not support function:${operation}."
		usage
		exit 1
	fi
}


main "$@"
