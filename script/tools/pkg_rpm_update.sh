#!/bin/bash
# --------------------------------------------------------------------------------------------------------------------
# Author: wangchong
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
# Decription: Create an UPDATE directory to add, delete, update, check and publish package binaries
# Function introduction and use method:
# 1. copy_rpm: create update directory and add binary rpm of package
#    Usage: bash pkg_rpm_update.sh "create" <project> <update_dir> <source_ip> <release_ip> <ssh_key> <pkglist>
# 2. del_pkg_rpm: delete binary rpm of package in the update directory
#    Usage: bash pkg_rpm_update.sh "del_pkg_rpm" <project> <update_dir> <source_ip> <release_ip> <ssh_key> <pkglist>
# 3. update_rpm: update binary rpm of package in the update directory
#    Usage: bash pkg_rpm_update.sh "update" <project> <update_dir> <source_ip> <release_ip> <ssh_key> <pkglist>
# 4. del_update_dir: delete update directory
#    Usage: bash pkg_rpm_update.sh "del_update_dir" <project> <update_dir> <source_ip> <release_ip> <ssh_key> <pkglist>
# 5. release_rpm: release binary rpm of package in the update directory
#    Usage: bash pkg_rpm_update.sh "release" <project> <update_dir> <source_ip> <release_ip> <ssh_key> <pkglist>
# --------------------------------------------------------------------------------------------------------------------

# usage
function usage() {
    cat << EOF
Usage: bash pkg_rpm_update.sh [action] [project] [update_dir] [source_ip] [release_ip] [ssh_key] [pkglist]

optional arguments:
    action       action method, include: create, del_pkg_rpm, update, del_update_dir and release
    project      project name, such as: openEuler-24.03-LTS:everything
    update_dir   update directory name
    source_ip    dailybuild server ip
    release_ip   release server ip
    ssh_key      ssh server key
    pkglist      package name list, such as: vim,gcc
EOF
}

# ssh exec cmd
function ssh_cmd() {
	local ip=$1
	local cmd=$2
	local ignore_error=$3
	ssh -i ${ssh_key} ${ssh_str} root@${ip} "${cmd}"
	if [ $? -ne 0 ];then
		echo "Error: exec cmd fail. [cmd]:${cmd}"
		if [[ "${ignore_error}" != "y" ]];then
			exit 1
		fi
	fi
}

# update repo data
function update_repodata() {
	local ip=$1
	local repo_path=$2
	for arch in ${arch_list[@]}
	do
		cmd="cd ${repo_path} && rm -rf ${arch}/repodata ${arch}/.repodata && createrepo -d ${arch} --workers 32"
		ssh_cmd ${ip} "${cmd}"
	done
}

# install jq
function install_jq() {
	sudo yum install -y jq &>/dev/null
}

# install createrepo
function install_createrepo() {
	cmd="yum install -y createrepo &>/dev/null"
	ssh_cmd ${source_ip} "${cmd}"
}

# Init json file
function init_json() {
	cmd="if [ ! -s ${json_file_path} ];then echo '{' > ${json_file_path} && sed -i '/{/a\ \t\"update\":[\n\t],\n\t\"history\":[\n\t]\n}' ${json_file_path};fi"
	ssh_cmd ${source_ip} "${cmd}"
}

# Insert the UPDATE directory name into the JSON file
function insert_dir() {
	local operation=$1
	line=$(grep "${update_dir}\"$" ${json_file_name})
	if [ ! -n "${line}" ];then
		sed -i "/\"${operation}\"/ a\		{\n			\"dir\": \"${update_dir}\"\n		}," ${json_file_name}
	fi
}

# Delete the UPDATE directory name in the JSON file
function delete_dir() {
	line=$(grep "${update_dir}\"$" ${json_file_name})
	if [ -n "${line}" ];then
		sed -i -e "/${update_dir}\"$/{n;d}" -e "\$!N;/\n.*${update_dir}\"$/!P;D" ${json_file_name}
		sed -i "/${update_dir}\"$/d" ${json_file_name}
	fi
}

# Update the contents of the JSON file
function update_json_file() {
	if [[ ${need_modify_json[@]} =~ ${action} ]];then
		init_json
		rm -rf ${json_file_name}
		scp -i ${ssh_key} ${ssh_str} root@${source_ip}:${json_file_path} ${work_path}
		if [[ ${action} == "create" ]];then
			insert_dir "update"
		elif [[ ${action} == "del_update_dir" ]];then
			delete_dir
		elif [[ ${action} == "release" ]];then
			delete_dir
			insert_dir "history"
		fi
		scp -i ${ssh_key} ${ssh_str} ${json_file_name} root@${source_ip}:${json_file_path}
		rm -rf ${json_file_name}
	fi
}

# get project snapshot_id
function get_snapshot_id() {
	for i in {1..5}
	do
		snapshot_id_list=$(ccb select builds os_project=${project} build_type=full,incremental,specified status=201,202 published_status=4 --sort create_time:desc --size 10 -f snapshot_id | jq -r '.[]._source.snapshot_id' | awk '!a[$0]++')
		if [ "x${snapshot_id_list}" == "x" ];then
			if [ ${i} -eq 5 ];then
				echo "error: ccb select snapshot_id failed."
				exit 1
			else
				echo "error: ccb select snapshot_id failed, will try again."
			fi
		else
			break
		fi
	done
}

# search package commits
function save_pkg_commits(){
	cmd="if [ ! -f "${commit_file_path}" ];then touch ${commit_file_path};fi"
	ssh_cmd ${source_ip} "${cmd}"
	rm -f ${commit_file_name}
	scp -i ${ssh_key} ${ssh_str} root@${source_ip}:${commit_file_path} ${work_path}

	if [[ ${action} == "del_pkg_rpm" ]];then
		for pkg in ${pkglist[@]}
		do
			sed -i "/^${pkg%%:*}:/d" ${commit_file_name}
		done
	elif [[ ${action} == "create" ]] || [[ ${action} == "update" ]];then
		unset snapshot_id_list
		get_snapshot_id
		rm -f pkglist
		scp -i ${ssh_key} ${ssh_str} root@${source_ip}:${pkglist_file_path} ${work_path}
		latest_pkg=$(cat pkglist)
		for pkg in ${pkglist[@]}
		do
			if [[ ${pkg} =~ ":" ]];then
				local pkg=${pkg%%:*}
			fi
			if [[ ${latest_pkg[@]} =~ ${pkg} ]];then
				for snapshot_id in ${snapshot_id_list[@]}
				do
					commit_id=$(ccb select snapshots _id=${snapshot_id} -f spec_commits | jq -r ".[0]._source.spec_commits[\"${pkg}\"].commit_id")
					if [[ ${commit_id} != "null" ]];then
						break
					fi
				done
				sed -i "/^${pkg}:/d" ${commit_file_name}
				if [[ ${commit_id} == "null" ]];then
					echo "${pkg}:" >> ${commit_file_name}
				else
					echo "${pkg}:${commit_id}" >> ${commit_file_name}
				fi
			fi
		done
		rm -f pkglist
	fi
	scp -i ${ssh_key} ${ssh_str} ${commit_file_name} root@${source_ip}:${commit_file_path}
	rm -f ${commit_file_name}
}

# save pkg rpm info file
function save_csv_file() {
	cmd="if [ ! -f ${csv_file_path} ];then touch ${csv_file_path};fi"
	ssh_cmd ${source_ip} "${cmd}"
	rm -f ${csv_file_name}
	scp -i ${ssh_key} ${ssh_str} root@${source_ip}:${csv_file_path} ${work_path}

	for pkg in ${pkglist[@]}
	do
		sed -i "/${pkg%%:*},/d" ${csv_file_name}
		if [[ ${action} == "update" ]] || [[ ${action} == "create" ]];then
			rpms=$(cat ${project}-aarch64-${pkg}_rpmlist ${project}-x86_64-${pkg}_rpmlist | sort | uniq)
			line="${pkg%%:*},${rpms[@]}"
			echo ${line} >> ${csv_file_name}
		fi
	done
	scp -i ${ssh_key} ${ssh_str} ${csv_file_name} root@${source_ip}:${csv_file_path}
	rm -f ${csv_file_name}
}

# Remove published rpms in update_xxx
function remove_published_rpm(){
	echo "[INFO]: Start delete published rpm from ${update_path}"
	echo "${publish_src_path[@]}"
	unset source_rpmlist bin_rpmlist
	for path in ${publish_src_path[@]}
	do
		cmd="cd ${path} && ls *.src.rpm"
		tmp_source_rpmlist=$(ssh_cmd ${release_ip} "${cmd}")
		source_rpmlist+=(${tmp_source_rpmlist[@]})
	done

	echo "${publish_bin_path[@]}"
	arch=(aarch64 x86_64)
	for ar in ${arch[@]}
	do
		for path in ${publish_bin_path[@]}
		do
			cmd="cd ${path}/${ar}/Packages && ls *.rpm"
			tmp_rpmlist=$(ssh_cmd ${release_ip} "${cmd}")
			bin_rpmlist+=(${tmp_rpmlist[@]})
		done
	done

	rm -f pkglist
	scp -i ${ssh_key} ${ssh_str} root@${source_ip}:${pkglist_file_path} ${work_path}

	for ar in ${arch[@]}
	do
		for pkg in ${pkglist[@]}
		do
			pkg_rpmlist=$(cat ${project}-${ar}-${pkg}_rpmlist)
			if [ -n "${pkg_rpmlist}" ];then
				for pkg_rpm in ${pkg_rpmlist[@]}
				do
					if [[ ${source_rpmlist[@]} =~ ${pkg_rpm} ]];then
						echo "[WARNING]: ${pkg_rpm} has been published, will delete from dailybuild ${update_path}/source"
						cmd="rm -f ${update_path}/source/Packages/${pkg_rpm}"
						ssh_cmd ${source_ip} "${cmd}"
						sed -i "/^${pkg%%:*}$/d" pkglist
					fi
					if [[ ${bin_rpmlist[@]} =~ ${pkg_rpm} ]];then
						echo "[WARNING]: ${pkg_rpm} has been published, will delete from dailybuild ${update_path}/${ar}"
						cmd="rm -f ${update_path}/${ar}/Packages/${pkg_rpm}"
						ssh_cmd ${source_ip} "${cmd}"
						sed -i "/^${pkg%%:*}$/d" pkglist
					fi
				done
			fi
		done
	done
	scp -i ${ssh_key} ${ssh_str} pkglist root@${source_ip}:${pkglist_file_path}
	rm -f pkglist
	echo "[INFO]: Finish delete published rpm from ${update_path}"
}

# Process the data
function parse_data(){
	compare_file=$1
	base_file=$2
	pkg_path=$3
	if [ -s ${base_file} ];then
		for line in `cat ${compare_file}`
		do
			grep "^${line}$" ${base_file}
			if [[ $? -eq 0 ]];then
				if [[ ${action} == "del_pkg_rpm" ]];then
					echo "${pkg_path}目录中多余二进制:${line}" >> check_result
				fi
			else
				if [[ ${action} != "del_pkg_rpm" ]];then
					echo "${pkg_path}目录中缺少二进制:${line}" >> check_result
				fi
			fi
		done
	fi
}

# Check packages binaries
function check_update_rpm() {
	echo "Start checking update directory package binaries..."
	rm -f arm_rpmlist x86_rpmlist src_rpmlist check_result
	if [[ ${action} == "del_pkg_rpm" ]];then
		for pkg in ${pkglist[@]}
		do
			ccb ls -p ${project} ${pkg} -a aarch64 | grep "\.rpm" | sed 's/"//g;s/,//g;s/ //g' >> arm_rpmlist
			ccb ls -p ${project} ${pkg} -a x86_64 | grep "\.rpm" | sed 's/"//g;s/,//g;s/ //g' >> x86_rpmlist
		done
	else
		for pkg in ${pkglist[@]}
		do
			cat ${project}-aarch64-${pkg}_rpmlist >> arm_rpmlist
			cat ${project}-x86_64-${pkg}_rpmlist >> x86_rpmlist
		done
	fi
	cat arm_rpmlist x86_rpmlist | grep "\.src.rpm" | sort | uniq >> src_rpmlist
	sed -i '/.src.rpm/d' arm_rpmlist x86_rpmlist
	sed -i 's/^ *//g' arm_rpmlist src_rpmlist x86_rpmlist
	pkg_arm_path="${update_path}/aarch64/Packages"
	pkg_src_path="${update_path}/source/Packages"
	pkg_x86_path="${update_path}/x86_64/Packages"
	cmd="cd ${pkg_arm_path} && ls *.rpm > /tmp/update_arm_rpmlist && cd ${pkg_src_path} && ls *.rpm > /tmp/update_src_rpmlist && cd ${pkg_x86_path} && ls *.rpm > /tmp/update_x86_rpmlist"
	ssh_cmd ${source_ip} "${cmd}"
	scp -i ${ssh_key} ${ssh_str} root@${source_ip}:/tmp/update_arm_rpmlist ${work_path}
	scp -i ${ssh_key} ${ssh_str} root@${source_ip}:/tmp/update_src_rpmlist ${work_path}
	scp -i ${ssh_key} ${ssh_str} root@${source_ip}:/tmp/update_x86_rpmlist ${work_path}
	cmd="cd /tmp && rm -f update_arm_rpmlist update_src_rpmlist update_x86_rpmlist"
	ssh_cmd ${source_ip} "${cmd}"

	parse_data arm_rpmlist update_arm_rpmlist ${pkg_arm_path}
	parse_data src_rpmlist update_src_rpmlist ${pkg_src_path}
	parse_data x86_rpmlist update_x86_rpmlist ${pkg_x86_path}
	echo "======================检查结果汇总======================"
	if [ -s check_result ];then
		if [[ ${action} == "del_pkg_rpm" ]];then
			echo "删除${update_path}目录中软件包(${pkglist[@]})的二进制失败!"
			rm -f *_rpmlist check_result
			exit 1
		fi
		cat check_result
		rm -f *arm_rpmlist *src_rpmlist *x86_rpmlist check_result
		exit 1
	else
		if [[ ${action} == "del_pkg_rpm" ]];then
			echo "删除${update_path}目录中软件包(${pkglist[@]})的二进制成功!"
		fi
		echo "经过检查后，${update_path}目录中软件包(${pkglist[@]})的二进制无缺失且无多余！"
		rm -f *arm_rpmlist *src_rpmlist *x86_rpmlist check_result
	fi
}

# Create UPDATE directory and add package binaries
function copy_rpm() {
	cmd="if [ ! -d ${update_path} ];then mkdir -p ${update_path} && cd ${update_path} && mkdir -p aarch64/Packages x86_64/Packages source/Packages && touch pkglist;fi"
	ssh_cmd ${source_ip} "${cmd}"
	rm -f pkglist
	scp -i ${ssh_key} ${ssh_str} root@${source_ip}:${pkglist_file_path} ${work_path}
	arch=(aarch64 x86_64)
	for pkg in ${pkglist[@]}
	do
		for ar in ${arch[@]}
		do
			rpm_dir="${project}-${ar}-${pkg}"
			for i in {1..5}
			do
				ccb download os_project=${project} packages=${pkg} architecture=${ar} -b all -s -d 2>/dev/null
				if [ $? -ne 0 ];then
					if [ ${i} -eq 5 ];then
						echo "error: ccb download package:${pkg} failed."
						exit 1
					else
						echo "error: ccb download package:${pkg} failed, will try again."
					fi

				else
					break
				fi

			done
			ls ${rpm_dir}/*.rpm | awk -F'/' '{print $NF}' > ${rpm_dir}_rpmlist
			scp -i ${ssh_key} ${ssh_str} ./${rpm_dir}/*.src.rpm root@${source_ip}:${update_path}/source/Packages/
			rm -f ${rpm_dir}/*.src.rpm
			scp -i ${ssh_key} ${ssh_str} ./${rpm_dir}/*.rpm root@${source_ip}:${update_path}/${ar}/Packages/
			rm -rf ${rpm_dir}
		done
		echo ${pkg%%:*} >> pkglist
	done
	sort -u pkglist -o pkglist
	scp -i ${ssh_key} ${ssh_str} pkglist root@${source_ip}:${pkglist_file_path}
	rm -f pkglist
}

# Delete UPDATE directory
function del_update_dir(){
	cmd="if [ -d ${update_path} ];then rm -rf ${update_path} && echo \"删除${update_path}目录成功.\";fi"
	ssh_cmd ${source_ip} "${cmd}"
}

# Update packages binaries
function update_rpm(){
	cmd="if [ ! -d ${update_path} ];then echo \"error: ${update_path} is not exist.\" && exit 1;fi"
	ssh_cmd ${source_ip} "${cmd}"
	echo "开始更新${update_path}目录中软件包(${pkglist[@]})的二进制!"
	del_pkg_rpm
	copy_rpm
}

# Delete packages binaries
function del_pkg_rpm() {
	rm -f ${csv_file_name}
	scp -i ${ssh_key} ${ssh_str} root@${source_ip}:${csv_file_path} ${work_path}
	for pkg in ${pkglist[@]}
	do
		rpms=$(grep "^${pkg}," ${csv_file_name} | awk -F',' '{print $NF}')
		for name in ${rpms[@]}
		do
			cmd="cd ${update_path} && find . -name ${name} | xargs rm -f"
			ssh_cmd ${source_ip} "${cmd}"
		done
	done
	if [[ ${action} == "del_pkg_rpm" ]];then
		rm -f pkglist
		scp -i ${ssh_key} ${ssh_str} root@${source_ip}:${pkglist_file_path} ${work_path}
		for pkg in ${pkglist[@]}
		do
			sed -i "/^${pkg%%:*}$/d" pkglist
		done	
		scp -i ${ssh_key} ${ssh_str} pkglist root@${source_ip}:${pkglist_file_path}
		rm -f pkglist
	fi
}
# Publish all packages binaries
function release_rpm(){
	cmd="if [ ! -d ${update_path} ];then echo \"error: ${update_path} is not exist.\" && exit 1;fi"
	ssh_cmd ${source_ip} "${cmd}"
	
	cmd="if [ ! -d ${backup_path} ];then mkdir -p ${backup_path}/aarch64/Packages ${backup_path}/x86_64/Packages ${backup_path}/source/Packages;fi"
	ssh_cmd ${source_ip} "${cmd}"
	
	cmd="if [ ! -d ${release_path} ];then mkdir -p ${release_path}/aarch64/Packages ${release_path}/x86_64/Packages ${release_path}/source/Packages;fi"
	ssh_cmd ${release_ip} "${cmd}"

	if [[ "x${pkglist[@]}" == "x" ]];then
		echo "start release ${update_path} directory all rpms file."
		for arch in ${arch_list[@]}
		do
			rm -rf ${arch} && mkdir ${arch}
			# backup rpm
			cmd="cp -rf ${update_path}/${arch}/Packages/*.rpm ${backup_path}/${arch}/Packages/"
			ssh_cmd ${source_ip} "${cmd}"

			# release rpm
			scp -i ${ssh_key} ${ssh_str} root@${source_ip}:${update_path}/${arch}/Packages/*.rpm ./${arch}/
			scp -i ${ssh_key} ${ssh_str} ./${arch}/*.rpm root@${release_ip}:${release_path}/${arch}/Packages/
			rm -rf ${arch}
		done
		echo "release all rpms succeed."
	else
		flag=0
		rm -f ${csv_file_name} pkglist 
		scp -i ${ssh_key} ${ssh_str} root@${source_ip}:${pkglist_file_path} ${work_path}
		pkglist_file_content=$(cat pkglist)
		scp -i ${ssh_key} ${ssh_str} root@${source_ip}:${csv_file_path} ${work_path}
		rm -rf ${arch_list[@]} && mkdir ${arch_list[@]}
		for pkg in ${pkglist[@]}
		do
			if [[ ! ${pkglist_file_content[@]} =~ ${pkg} ]];then
				echo "warning: not find package:${pkg} in ${update_path} directory."
				continue
			fi
			rpms=$(grep "^${pkg}," ${csv_file_name} | awk -F',' '{print $NF}')
			for name in ${rpms[@]}
			do
				cmd="find ${update_path} -name ${name}"
				result=$(ssh_cmd ${source_ip} "${cmd}")
				if [ ! -z "${result}" ];then
					flag=1
					for res in ${result[@]}
					do
						for arch in ${arch_list[@]}
						do
							if [[ ${res} =~ "${update_dir}/${arch}" ]];then
								scp -i ${ssh_key} ${ssh_str} root@${source_ip}:${res} ./${arch}/
								break
							fi
						done
					done
				else
					echo "warning: not find ${name} in ${update_path} directory."
				fi
			done
		done
		rm -f ${csv_file_name}
		if [ ${flag} -eq 0 ];then
			echo "warning: nothing to release."
			exit 1
		fi
		echo "start release ${update_path} directory package:${pkglist[@]}"
		ls ${arch_list[@]}
		for arch in ${arch_list[@]}
		do
			# backup rpm
			scp -i ${ssh_key} ${ssh_str} ./${arch}/*.rpm root@${source_ip}:${backup_path}/${arch}/Packages/
			# release some package rpms
			scp -i ${ssh_key} ${ssh_str} ./${arch}/*.rpm root@${release_ip}:${release_path}/${arch}/Packages/
			rm -rf ${arch}
		done
		echo "release some packages rpms succeed."
	fi
}


# Main
function main() {
	if [ $# -lt 6 ] || [ $# -gt 7 ];then
		echo "Error: please check the params."
		usage
		exit 1
	fi
	action=$1
	project=$2
	update_dir=$3
	source_ip=$4
	release_ip=$5
	ssh_key=$6
	pkglist=$7

	if [ "x${update_dir}" == "x" ];then
		update_dir="update_"`date +%Y%m%d`
	fi

	if [ -z "${action}" ] || [ -z "${project}" ] || [ -z "${update_dir}" ] || [ -z "${source_ip}" ] || [ -z "${release_ip}" ] || [ -z "${ssh_key}" ];then
		echo "Error: please check the params."
		usage
		exit 1
	fi

	need_pkglist=(create del_pkg_rpm update)
	if [[ ${need_pkglist[@]} =~ ${action} ]];then
		if [ -z "${pkglist[@]}" ];then
			echo "Error: pkglist is empty."
			usage
			exit 1
		fi
	fi

	if [[ ${project} =~ "everything" ]];then
		tmp_str=${project%%:everything*}
		branch=${tmp_str%%-everything*}
		branch_path="/repo/openeuler/repo.openeuler.org/${branch}"
		update_path="${branch_path}/${update_dir}"
		backup_path="${branch_path}/update"
		release_path="/repo/openeuler/${branch}/update"
		publish_src_path=(/repo/openeuler/${branch}/source/Packages /repo/openeuler/${branch}/update/source/Packages)
		publish_bin_path=(/repo/openeuler/${branch}/everything /repo/openeuler/${branch}/debuginfo /repo/openeuler/${branch}/update)
	elif [[ ${project} =~ "epol" ]];then
		tmp_str=${project%%:epol*}
		branch=${tmp_str%%-epol*}
		branch_path="/repo/openeuler/repo.openeuler.org/${branch}/EPOL"
		update_path="${branch_path}/${update_dir}/main"
		backup_path="${branch_path}/update/main"
		release_path="/repo/openeuler/${branch}/EPOL/update/main"
		publish_src_path=(/repo/openeuler/${branch}/EPOL/update/main/source/Packages /repo/openeuler/${branch}/EPOL/main/source/Packages)
		publish_bin_path=(/repo/openeuler/${branch}/EPOL/update/main /repo/openeuler/${branch}/EPOL/main)
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
		publish_src_path=(/repo/openeuler/${branch}/EPOL/multi_version/${pkg}/${ver}/source/Packages /repo/openeuler/${branch}/EPOL/update/multi_version/${pkg}/${ver}/source/Packages)
		publish_bin_path=(/repo/openeuler/${branch}/EPOL/multi_version/${pkg}/${ver} /repo/openeuler/${branch}/EPOL/update/multi_version/${pkg}/${ver})
	else
		echo "error: the project name is not standard."
		exit 1
	fi
	
	work_path=${PWD}
	pkglist=${pkglist//,/ }
	arch_list=(aarch64 source x86_64)
	need_modify_json=(create del_update_dir release)
	need_modify_pkglist=(create del_pkg_rpm update)
	json_file_name="${branch}-update.json"
	json_file_path="${branch_path}/${json_file_name}"
	csv_file_name="${branch}.csv"
	csv_file_path="${update_path}/${csv_file_name}"
	commit_file_name="${branch}-package-commit.txt"
	commit_file_path="${update_path}/${commit_file_name}"
	pkglist_file_path="${update_path}/pkglist"
	ssh_str="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
	
	install_jq
	install_createrepo
	if [ ${action} == "create" ];then
		copy_rpm
		update_json_file
		save_csv_file
		check_update_rpm
		remove_published_rpm
		update_repodata ${source_ip} ${update_path}
		save_pkg_commits
	elif [ ${action} == "update" ];then
		update_rpm
		save_csv_file
		check_update_rpm
		remove_published_rpm
		update_repodata ${source_ip} ${update_path}
		save_pkg_commits
	elif [ ${action} == "del_update_dir" ];then
		del_update_dir
		update_json_file
	elif [ ${action} == "del_pkg_rpm" ];then
		del_pkg_rpm
		check_update_rpm
		save_csv_file
		update_repodata ${source_ip} ${update_path}
		save_pkg_commits
	elif [ ${action} == "release" ];then
		release_rpm
		update_repodata ${source_ip} ${backup_path}
		update_repodata ${release_ip} ${release_path}
		update_json_file
	else
		echo "error, please check parameters"
		exit 1
	fi
}

main "$@"
