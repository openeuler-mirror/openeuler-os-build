#!/bin/bash
# --------------------------------------------------------------------------------------------------------------------
# Author: wangchong
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
# Decription: Create an UPDATE directory to add, delete, update, check and publish package binaries
# --------------------------------------------------------------------------------------------------------------------


# usage
function usage() {
    cat << EOF
Usage: bash multi_architecture_update.sh [operation] [project] [update_dir] [source_ip] [release_ip] [publish_key] [pkgname] [architecture]

optional arguments:
    operation    operation method, include: create, del_pkg_rpm, update, del_update_dir and release
    project      project name, such as: openEuler-24.03-LTS:everything
    update_dir   update directory name
    source_ip    dailybuild server
    release_ip   release server
    publish_key  server publish key
    pkgname      package name, such as: vim,gcc
    architecture architecture name
EOF
}

# ssh exec cmd
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

# prepare the environment
function prepare_env() {
	cmd="yum install -y createrepo &>/dev/null"
	ssh_cmd ${source_ip} "${cmd}"
}

# insert the update_xxx directory name into the json file
function insert_json_dir() {
	local category=$1
	if [[ "${category}" == "history" ]] || [[ "${category}" == "update" ]];then
		res=`grep "${update_dir}\"$" ${json_file_name}`
		if [ ! -n "${res}" ];then
			sed -i "/\"${category}\"/ a\		{\n			\"dir\": \"${update_dir}\"\n		}," ${json_file_name}
		fi
	fi
}

# delete the update_xxx directory name in the json file
function delete_json_dir() {
	result=`grep "${update_dir}\"$" ${json_file_name}`
	if [ -n "${result}" ];then
		sed -i -e "/${update_dir}\"$/{n;d}" -e "\$!N;/\n.*${update_dir}\"$/!P;D" ${json_file_name}
		sed -i "/${update_dir}\"$/d" ${json_file_name}
	fi
}

# init csv file
function init_csv_file() {
	cmd="if [ ! -f ${csv_file_path} ];then touch ${csv_file_path};fi"
	ssh_cmd ${source_ip} "${cmd}"
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
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${source_ip}:${json_file_path} ./
		if [[ ${operation} == "create" ]];then
			insert_json_dir "update"
		elif [[ ${operation} == "del_update_dir" ]];then
			delete_json_dir
		elif [[ ${operation} == "release" ]];then
			delete_json_dir
			insert_json_dir "history"
		fi
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ${json_file_name} root@${source_ip}:${json_file_path}
	fi
}

# update the contents of the pkglist file
function update_pkglist_file() {
	if [[ ${need_modify_pkglist[@]} =~ ${operation} ]];then
		cmd="if [ ! -s ${pkglist_file_path} ];then touch ${pkglist_file_path};fi"
		ssh_cmd ${source_ip} "${cmd}"
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null root@${source_ip}:${pkglist_file_path} ./
		for name in ${pkgname[@]}
		do
			if [[ ${operation} == "del_pkg_rpm" ]];then
				sed -i "/^${name%%:*}$/d" pkglist
			elif [[ ${operation} == "create" ]];then
				echo ${name%%:*} >> pkglist
			fi
		done
		sort -u pkglist -o pkglist
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null ./pkglist root@${source_ip}:${pkglist_file_path}
		rm -f pkglist
	fi
}

# update repodata
function update_repodata() {
	local machine_ip=$1
	local repo_path=$2
	cmd="cd ${repo_path} && rm -rf ${architecture}/repodata && createrepo -d ${architecture} --workers 32"
	ssh_cmd ${machine_ip} "${cmd}"
}

# update rpm info csv file
function update_csv_file() {
	init_csv_file
	scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${source_ip}:${csv_file_path} ./
	for pkg in ${pkgname[@]}
	do
		sed -i "/${pkg%%:*},/d" ${csv_file_name}
		if [[ ${operation} == "update" ]] || [[ ${operation} == "create" ]];then
			rpms=$(cat ${project}-${architecture}-${pkg}_rpmlist)
			line="${pkg%%:*},${rpms[@]}"
			echo ${line} >> ${csv_file_name}
		fi
	done
	scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ${csv_file_name} root@${source_ip}:${csv_file_path}
	rm -f ${csv_file_name}
}

# remove published rpms in update_xxx
function remove_published_rpm(){
	echo "[INFO]: Start delete published rpm from ${update_path}"
	scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${source_ip}:${pkglist_file_path} ./
	echo "${publish_path[@]}"

	unset rpmlist
	flag=0
	for path in ${publish_path[@]}
	do
		cmd="if [ -d ${path}/${architecture} ];then cd ${path}/${architecture}/Packages && ls *.rpm;fi"
		tmp_rpmlist=$(ssh_cmd ${source_ip} "${cmd}")
		rpmlist+=(${tmp_rpmlist[@]})
	done
	for pkg in ${pkgname[@]}
	do
		pkg_rpmlist=$(cat ${project}-${architecture}-${pkg}_rpmlist)
		if [ -n "${pkg_rpmlist}" ];then
			for pkg_rpm in ${pkg_rpmlist[@]}
			do
				if [[ "${rpmlist[@]}" =~ "${pkg_rpm}" ]];then
					echo "[WARNING]: ${pkg_rpm} has been published, will delete from dailybuild ${update_path}/${architecture}"
					cmd="rm -f ${update_path}/${architecture}/Packages/${pkg_rpm}"
					ssh_cmd ${source_ip} "${cmd}"
					sed -i "/^${pkg%%:*}$/d" pkglist
					flag=1
				fi
			done
		fi
	done
	if [ ${flag} -eq 1 ];then
		update_repodata ${source_ip} ${update_path}
	fi
	scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR pkglist root@${source_ip}:${pkglist_file_path}
	echo "[INFO]: Finish delete published rpm from ${update_path}"
}

# process the data
function parse_data(){
	base_file="update_${architecture}_rpm"
	if [ -s ${base_file} ];then
		for line in $(cat ${architecture}_rpm_list)
		do
			grep "^${line}$" ${base_file}
			if [[ $? -eq 0 ]];then
				if [[ ${operation} == "del_pkg_rpm" ]];then
					echo "${update_path}/${architecture}/Packages目录中多余二进制:${line}" >> check_result
				fi
			else
				if [[ ${operation} != "del_pkg_rpm" ]];then
					echo "${pkg_path}目录中缺少二进制:${line}" >> check_result
				fi
			fi
		done
	fi
}

# check packages binaries
function check_rpm_complete() {
	echo "Start checking update directory package rpm..."

	for pkg in ${pkgname[@]}
	do
		if [[ ${operation} == "del_pkg_rpm" ]];then
			grep "^${pkg%%:*}," ${csv_file_name} | awk -F',' '{print $NF}' | sed 's/ /\n/g' >> ${architecture}_rpm_list
		else
			cat ${project}-${architecture}-${pkg}_rpmlist >> ${architecture}_rpm_list
		fi
	done
	sed -i 's/^ *//g' ${architecture}_rpm_list
	cmd="cd ${update_path}/${architecture}/Packages && ls *.rpm > /tmp/update_${architecture}_rpm 2>/dev/null"
	ssh_cmd ${source_ip} "${cmd}"
	scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${source_ip}:/tmp/update_${architecture}_rpm ./ 2>/dev/null
	parse_data
	echo "======================检查结果汇总======================"
	if [ -s check_result ];then
		if [[ ${operation} == "del_pkg_rpm" ]];then
			echo "删除${update_path}目录中软件包(${pkgname})的二进制失败!"
			cat check_result
			rm -f update_${architecture}_rpm ${architecture}_rpm_list check_result
			exit 1
		fi
		cat check_result
		rm -f update_${architecture}_rpm ${architecture}_rpm_list check_result
		exit 1
	else
		if [[ ${operation} == "del_pkg_rpm" ]];then
			echo "删除${update_path}目录中软件包(${pkgname})的二进制成功!"
		fi
		echo "经过检查后，${update_path}目录中软件包(${pkgname})的二进制无缺失且无多余！"
		rm -f update_${architecture}_rpm ${architecture}_rpm_list check_result
	fi
}


# create update_xxx directory and add package rpm
function create() {
	cmd="if [ ! -d ${update_path} ];then mkdir -p ${update_path}/${architecture}/Packages && touch ${pkglist_file_path};fi"
	ssh_cmd ${source_ip} "${cmd}"

	for pkg in ${pkgname[@]}
	do
		rpm_dir="${project}-${architecture}-${pkg}"
		ccb download os_project=${project} packages=${pkg} architecture=${architecture} -b all -d 2>/dev/null
		if [ $? -ne 0 ];then
			echo "ccb download error."
			exit 1
		fi
		ls ${rpm_dir}/*.rpm | awk -F'/' '{print $NF}' > ${rpm_dir}_rpmlist
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ./${rpm_dir}/*.rpm root@${source_ip}:${update_path}/${architecture}/Packages/ 2>/dev/null
		rm -rf ${rpm_dir} 2>/dev/null
	done
}

# delete packages rpm
function del_pkg_rpm() {
	scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${source_ip}:${csv_file_path} ./
	for pkg in ${pkgname[@]}
	do
		rpms=$(grep "^${pkg%%:*}," ${csv_file_name} | awk -F',' '{print $NF}')
		cmd="cd ${update_path}/${architecture}/Packages && rm -f ${rpms}"
		ssh_cmd ${source_ip} "${cmd}"
	done
}

# delete update_xxx directory
function del_update_dir() {
	echo "Delete the ${update_path} directory."
	cmd="if [ -d ${update_path} ];then rm -rf ${update_path};fi"
	ssh_cmd ${source_ip} "${cmd}"
}

# update rpm
function update() {
	cmd="if [ ! -d ${update_path} ];then echo \"Error: ${update_path} is not exist.\" && exit 1;fi"
	ssh_cmd ${source_ip} "${cmd}"
	echo "Update ${pkgname} rpm in the ${update_path} directory."
	del_pkg_rpm
	create
}

# publish packages rpm
function release() {
	cmd="if [ ! -d ${update_path} ];then echo \"${update_path} is not exist.\" && exit 1;fi"
	ssh_cmd ${source_ip} "${cmd}"
	cmd="if [ ! -d ${backup_path}/${architecture}/Packages ];then mkdir -p ${backup_path}/${architecture}/Packages;fi"
	ssh_cmd ${source_ip} "${cmd}"
	cmd="if [ ! -d ${release_path}${architecture}/Packages ];then mkdir -p ${release_path}/${architecture}/Packages;fi"
	ssh_cmd ${release_ip} "${cmd}"
	if [[ "x${pkgname}" == "x" ]];then
		echo "开始发布${update_path}目录中所有rpm包"
		rm -rf ${architecture} && mkdir ${architecture}
		# backup rpm
		cmd="cp -rf ${update_path}/${architecture}/Packages/*.rpm ${backup_path}/${architecture}/Packages/"
		ssh_cmd ${source_ip} "${cmd}"
		update_repodata ${source_ip} ${backup_path}
		# release rpm
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${source_ip}:${update_path}/${architecture}/Packages/*.rpm ./${architecture}/
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ./${architecture}/*.rpm root@${release_ip}:${release_path}/${architecture}/Packages/
		update_repodata ${release_ip} ${release_path}
		rm -rf ${architecture}
	else
		rm -rf ${architecture} && mkdir ${architecture}
		rm -f NOT_FOUND && touch NOT_FOUND
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${source_ip}:${csv_file_path} ./
		for pkg in ${pkgname[@]}
		do
			rpms=$(grep "^${pkg%%:*}," ${csv_file_name} | awk -F',' '{print $NF}')
			for rpm in ${rpms[@]}
			do
				scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${source_ip}:${update_path}/${architecture}/Packages/${rpm} ./${architecture}/
				result=$(ls ./${architecture}/${rpm})
				if [[ "x${result}" == "x" ]];then
					echo "${rpm}" >> NOT_FOUND
				fi
			done
		done

		if [ -s NOT_FOUND ];then
			echo "==========Warning: Not Found some rpm in ${update_path} directory=========="
			cat NOT_FOUND
			echo "==========================================================================="
		fi
		echo "开始发布${update_path}目录中指定软件包${pkgname}的rpm包"
		ls ${architecture}
		# backup rpm
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ./${architecture}/*.rpm root@${source_ip}:${backup_path}/${architecture}/Packages/
		update_repodata ${source_ip} ${backup_path}
		# release rpm
		scp -i ${publish_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ./${architecture}/*.rpm root@${release_ip}:${release_path}/${architecture}/Packages/
		update_repodata ${release_ip} ${release_path}
		rm -rf ${architecture}
	fi
	update_json_file
}

# Main function
function main() {
	if [ $# -lt 7 ] || [ $# -gt 8 ];then
		echo "Error: please check the params."
		usage
		exit 1
	fi
	operation=$1
	project=$2
	update_dir=$3
	source_ip=$4
	release_ip=$5
	publish_key=$6
	pkgname=$7
	architecture=$8

	if [ -z "${operation}" ] || [ -z "${project}" ] || [ -z "${update_dir}" ] || [ -z "${source_ip}" ] || [ -z "${release_ip}" ] || [ -z "${publish_key}" ] || [ -z "${architecture}" ] ;then
		echo "Error: please check the params."
		usage
		exit 1
	fi

	need_pkgname=(create delete_pkg_rpm update)
	if [[ ${need_pkgname[@]} =~ ${operation} ]];then
		if [ -z "${pkgname}" ];then
			echo "Error: pkgname is empty."
			usage
			exit 1
		fi
	fi

	update_dir="${update_dir}_${architecture}"
	need_modify_json=(create del_update_dir release)
	need_modify_pkglist=(create del_pkg_rpm update)
	pkgname=${pkgname//,/ }
	if [[ ${project} =~ "everything" ]];then
		tmp_str=${project%%:everything*}
		branch=${tmp_str%%-everything*}
		branch_path="/repo/openeuler/repo.openeuler.org/${branch}"
		update_path="${branch_path}/${update_dir}"
		backup_path="${branch_path}/update"
		release_path="/repo/openeuler/${branch}/update"
		publish_path=(/repo/openeuler/${branch}/update /repo/openeuler/${branch}/everything /repo/openeuler/${branch}/debuginfo)
	elif [[ ${project} =~ "epol" ]];then
		tmp_str=${project%%:epol*}
		branch=${tmp_str%%-epol*}
		branch_path="/repo/openeuler/repo.openeuler.org/${branch}/EPOL"
		update_path="${branch_path}/${update_dir}/main"
		backup_path="${branch_path}/update/main"
		release_path="/repo/openeuler/${branch}/EPOL/update/main"
		publish_path=(/repo/openeuler/${branch}/EPOL/update/main /repo/openeuler/${branch}/EPOL/main)
	elif [[ ${project} =~ "Multi-Version" ]];then
		tmp_str=${project%%_Epol_*}
		branch=${tmp_str//_/-}
		tmp_str=${project##*Multi-Version_}
		pkg=${tmp_str%_*}
		ver=${tmp_str#*_}
		branch_path="/repo/openeuler/repo.openeuler.org/${branch}/EPOL"
		update_path="${branch_path}/${update_dir}/multi_version/${pkg}/${ver}"
		backup_path="${branch_path}/update/multi_version/${pkg}/${ver}"
		release_path="/repo/openeuler/${branch}/EPOL/update/multi_version/${pkg}/${ver}"
		publish_path=(/repo/openeuler/${branch}/EPOL/multi_version/${pkg}/${ver} /repo/openeuler/${branch}/EPOL/update/multi_version/${pkg}/${ver})
	fi

	json_file_name="${branch}-${architecture}-update.json"
	json_file_path="${branch_path}/${json_file_name}"
	csv_file_name="${branch}-${architecture}.csv"
	csv_file_path="${update_path}/${csv_file_name}"
	pkglist_file_path="${update_path}/pkglist"
	prepare_env
	if [ ${operation} == "create" ];then
		create
		update_pkglist_file
		update_json_file
		update_csv_file
		check_rpm_complete
		remove_published_rpm
		update_repodata ${source_ip} ${update_path}
	elif [ ${operation} == "del_update_dir" ];then
		del_update_dir
		update_json_file
	elif [ ${operation} == "del_pkg_rpm" ];then
		del_pkg_rpm
		update_pkglist_file
		check_rpm_complete
		update_csv_file
		update_repodata ${source_ip} ${update_path}
	elif [ ${operation} == "update" ];then
		update
		update_csv_file
		check_rpm_complete
		remove_published_rpm
		update_repodata ${source_ip} ${update_path}
	elif [ ${operation} == "release" ];then
		release
	else
		echo "Error: not support function:${operation}."
		usage
		exit 1
	fi
}

main "$@"
