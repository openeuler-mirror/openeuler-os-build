#!/bin/bash
# --------------------------------------------------------------------------------------------------------------------
# Author: 
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
# Decription: Create an UPDATE directory to add, delete, update, check and publish package binaries
# --------------------------------------------------------------------------------------------------------------------


# Usage
function usage() {
    cat << EOF
Usage: sh hotpatch_update.sh [Operation] [Branch] [Update_dir] [Source_ip] [Release_ip] [Publish_key] [Rpmname]

optional arguments:
    Operation    Operation method, include: create, delete_hotpatch, update, delete_update_dir and release
    Branch       Branch name, such as: openEuler-22.03-LTS
    Update_dir   Update directory name
    Source_ip    Server of store hotpatch
    Release_ip   Server of release hotpatch
    Publish_key  Server of publish key
    Rpmname      Rpm name
EOF
}

# ssh server exec cmd
function ssh_cmd() {
	local machine_ip=$1
	local exec_cmd=$2
	local ignore_error=$3
	ssh -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${machine_ip} "${exec_cmd}"
	if [ $? -ne 0 ];then
		echo "Error: exec cmd fail. [cmd]:$cmd"
		if [[ "${ignore_error}" != "y" ]];then
			exit 1
		fi
	fi
}

# Prepare the environment
function prepare_env() {
	cmd="yum install -y createrepo &>/dev/null"
	ssh_cmd ${source_ip} "${cmd}"
}

# Insert the UPDATE directory name into the JSON file
function insert_dir() {
	local category=$1
	if [[ "${category}" == "history" ]] || [[ "${category}" == "update" ]];then
		res=`grep "${update_dir}\"$" ${json_file_name}`
		if [ ! -n "${res}" ];then
			sed -i "/\"${category}\"/ a\		{\n			\"dir\": \"${update_dir}\"\n		}," ${json_file_name}
		fi
	fi
}

# Delete the UPDATE directory name in the JSON file
function delete_json_dir() {
	res=`grep "${update_dir}\"$" ${json_file_name}`
	if [ -n "${res}" ];then
		sed -i -e "/${update_dir}\"$/{n;d}" -e "\$!N;/\n.*${update_dir}\"$/!P;D" ${json_file_name}
		sed -i "/${update_dir}\"$/d" ${json_file_name}
	fi
}

# Init json file
function init_json_file() {
	cmd="if [ ! -s ${json_file_path} ];then echo '{' > ${json_file_path} && sed -i '/{/a\ \t\"update\":[\n\t],\n\t\"history\":[\n\t]\n}' ${json_file_path};fi"
	ssh_cmd ${source_ip} "${cmd}"
}

# Update the contents of the JSON file
function update_json_file() {
	if [[ ${need_modify_json[@]} =~ ${operation} ]];then
		init_json_file
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o LogLevel=ERROR root@${source_ip}:${json_file_path} .
		if [[ ${operation} == "create" ]];then
			insert_dir "update"
		elif [[ ${operation} == "delete_update_dir" ]];then
			delete_json_dir
		elif [[ ${operation} == "release" ]];then
			delete_json_dir
			insert_dir "history"
		fi
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o LogLevel=ERROR ${json_file_name} root@${source_ip}:${branch_path}/
	fi
}

# Update the contents of the pkglist file
function update_pkglist_file() {
	if [[ ${need_modify_pkglist[@]} =~ ${operation} ]];then
		cmd="if [ ! -s ${pkglist_file_path} ];then touch ${pkglist_file_path};fi"
		ssh_cmd ${source_ip} "${cmd}"
		rm -f pkglist
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o LogLevel=ERROR root@${source_ip}:${pkglist_file_path} .
		for name in ${rpmname[@]}
		do
			if [[ ${operation} == "delete_hotpatch" ]];then
				sed -i "/^${name}$/d" pkglist
			fi
			if [[ ${operation} == "create" ]];then
				echo ${name} >> pkglist
			fi
		done
		sort -u pkglist -o pkglist
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o LogLevel=ERROR pkglist root@${source_ip}:${update_path}/
		rm -f pkglist
	fi
}

# update repodata
function update_repodata() {
	local machine_ip=$1
	local repo_path=$2
	local archs=$3
	if [ -z "${archs}" ];then
		archs=${arch_list[@]}
	fi
	for ar in ${archs[@]}
	do
		cmd="cd ${repo_path} && rm -rf ${ar}/repodata && createrepo -d ${ar} --workers 32"
		ssh_cmd ${machine_ip} "${cmd}"
	done
}

# Create UPDATE directory and add package binaries
function create() {
	echo "Added ${rpmname[@]} hot patches and xml files in the ${update_path} directory."
	cmd="if [ ! -d ${update_path} ];then mkdir -p ${update_path};fi"
	ssh_cmd ${source_ip} "${cmd}"
	for ar in ${arch_list[@]}
	do
		cmd="if [ ! -d ${update_path}/${ar} ];then mkdir -p ${update_path}/${ar}/Packages ${update_path}/${ar}/hotpatch_xml;fi"
		ssh_cmd ${source_ip} "${cmd}"
		for name in ${rpmname[@]}
		do
			if [[ "${ar}" != "source" ]];then
				name="patch-${name}"
			fi
			cmd="cp ${hotpatch_path}/${ar}/Packages/${name}*.rpm ${update_path}/${ar}/Packages/"
			ssh_cmd ${source_ip} "${cmd}" "y"
			cmd="cp ${hotpatch_path}/${ar}/hotpatch_xml/${name}*.xml ${update_path}/${ar}/hotpatch_xml/"
			ssh_cmd ${source_ip} "${cmd}" "y"
		done

	done
	update_repodata ${source_ip} ${update_path}
}

# Delete hotpatch rpm and xml
function delete_hotpatch() {
	echo "Delete ${rpmname[@]} hot patches and xml files from the ${update_path} directory."
	for name in ${rpmname[@]}
	do
		for ar in ${arch_list[@]}
		do
			if [[ "${ar}" == "source" ]];then
				tmp_name=${name}
			else
				tmp_name="patch-${name}"
			fi
			cmd="rm -f ${update_path}/${ar}/Packages/${tmp_name}*"
			ssh_cmd ${source_ip} "${cmd}"
			cmd="rm -f ${update_path}/${ar}/hotpatch_xml/${tmp_name}*"
			ssh_cmd ${source_ip} "${cmd}"
		done
	done
	if [ ${operation} != "update" ];then
		update_repodata ${source_ip} ${update_path}
	fi
}

# Delete hotpatch-update_xxx directory
function delete_update_dir() {
	echo "Delete the ${update_path} directory."
	cmd="if [ -d ${update_path} ];then rm -rf ${update_path};fi"
	ssh_cmd ${source_ip} "${cmd}"
}

# Update hotpatch rpm and xml
function update() {
	cmd="if [ ! -d ${update_path} ];then echo \"Error: ${update_path} is not exist.\" && exit 1;fi"
	ssh_cmd ${source_ip} "${cmd}"
	echo "Update hot patches and xml files in the ${update_path} directory."
	delete_hotpatch
	create
}

# Publish hot patch and xml file
function release() {
	cmd="if [ ! -d ${update_path} ];then echo \"${update_path} is not exist.\" && exit 1;fi"
	ssh_cmd ${source_ip} "${cmd}"
	echo "Publish hot patches and xml files in the ${update_path} directory to the official website."
	for ar in ${arch_list[@]}
	do
		cmd="if [ ! -d ${backup_path}/${ar} ];then mkdir -p ${backup_path}/${ar}/Packages ${backup_path}/${ar}/hotpatch_xml;fi"
		ssh_cmd ${source_ip} "${cmd}"
		cmd="if [ ! -d ${release_path}/${ar} ];then mkdir -p ${release_path}/${ar}/Packages ${release_path}/${ar}/hotpatch_xml;fi"
		ssh_cmd ${release_ip} "${cmd}"

		# backup hotpatch_update_xxx dir hotpatch and xml into hotpatch_update dir
		cmd="cp ${update_path}/${ar}/Packages/*.rpm ${backup_path}/${ar}/Packages/"
		ssh_cmd ${source_ip} "${cmd}" "y"
		cmd="cp ${update_path}/${ar}/hotpatch_xml/*.xml ${backup_path}/${ar}/hotpatch_xml/"
		ssh_cmd ${source_ip} "${cmd}" "y"
		update_repodata ${source_ip} ${backup_path} "${ar}"

		# release hotpatch and xml to website
		rm -rf ${ar}
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -r root@${source_ip}:${update_path}/${ar} ./
		result=$(find ./${ar}/Packages/ -name "*.rpm" -type f)
		if [ -z "${result}" ];then
			echo "[Warning]: Directory ${update_path}/${ar} does not contain hot patches or xml files."
		else
			scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ./${ar}/Packages/*.rpm root@${release_ip}:${release_path}/${ar}/Packages/
			scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ./${ar}/hotpatch_xml/*.xml root@${release_ip}:${release_path}/${ar}/hotpatch_xml/
			update_repodata ${release_ip} ${release_path} "${ar}"
			rm -rf ${ar}
		fi
	done
}

# Main function
function main() {
	if [ $# -lt 6 ] || [ $# -gt 7 ];then
		echo "Error: please check the params."
		usage
		exit 1
	fi
	operation=$1
	branch=$2
	update_dir=$3
	source_ip=$4
	release_ip=$5
	publish_key=$6
	rpmname=$7
	
	need_rpmname=(create delete_hotpatch update)
	if [ -z "${operation}" ] || [ -z "${branch}" ] || [ -z "${update_dir}" ] || [ -z "${source_ip}" ] || [ -z "${release_ip}" ] || [ -z "${publish_key}" ];then
		echo "Error: please check the params."
		usage
		exit 1
	fi
	if [[ ${need_rpmname[@]} =~ ${operation} ]];then
		if [ -z "${rpmname}" ];then
			echo "Error: rpmname is empty."
			usage
			exit 1
		fi
	fi
	if [[ "${update_dir}" != "hotpatch_update"* ]];then
		update_dir="hotpatch_update_${update_dir}"
	fi
	arch_list=(aarch64 source x86_64)
	need_modify_json=(create delete_update_dir release)
	need_modify_pkglist=(create delete_hotpatch update)
	rpmname=${rpmname//,/ }
	branch_path="/repo/openeuler/repo.openeuler.org/${branch}"
	backup_path="${branch_path}/hotpatch_update"
	update_path="${branch_path}/${update_dir}"
	hotpatch_path="/repo/openeuler/hotpatch/${branch}"
	release_path="/repo/openeuler/${branch}/hotpatch_update"
	json_file_name="${branch}-hotpatch-update.json"
	json_file_path="${branch_path}/${json_file_name}"
	pkglist_file_path="${update_path}/pkglist"
	prepare_env
	if [ ${operation} == "create" ];then
		create
		update_pkglist_file
		update_json_file
	elif [ ${operation} == "delete_update_dir" ];then
		delete_update_dir
		update_json_file
	elif [ ${operation} == "delete_hotpatch" ];then
		delete_hotpatch
		update_pkglist_file
	elif [ ${operation} == "update" ];then
		update
		update_pkglist_file
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
