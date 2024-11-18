#!/bin/bash
# --------------------------------------------------------------------------------------------------------------------
# Author: wangchong
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
# Decription: Create an UPDATE directory to add, delete, update, check and publish package binaries
# Function introduction and use method:
# 1. copy_rpm: create UPDATE directory and add the binaries of the package
#    Usage: bash pkg_rpm_update.sh <obs_project> <pkgnamelist> <machine_key> "create" <standard/EPOL> [UPDATE_DIR]
#    Attention: In this function, if the UPDATE_DIR parameter is null, the default value is ""update_"`date +%Y%m%d`"
# 2. del_pkg_rpm: delete the binaries of package in the UPDATE directory
#    Usage: bash pkg_rpm_update.sh <obs_project> <pkgnamelist> <machine_key> "del_pkg_rpm" <UPDATE_DIR> <standard/EPOL>
# 3. update_rpm: update the binaries of package in the UPDATE directory
#    Usage: bash pkg_rpm_update.sh <obs_project> <pkgnamelist> <machine_key> "update" <UPDATE_DIR> <standard/EPOL>
# 4. del_update_dir: delete UPDATE directory
#    Usage: bash pkg_rpm_update.sh <obs_project> <UPDATE_DIR> <machine_key> "del_update_dir" <standard/EPOL>
# 5. release_rpm: publish the binaries of all packages in the UPDATE directory to the official website
#    Usage: bash pkg_rpm_update.sh <obs_project> <UPDATE_DIR> <machine_key> "release" <standard/EPOL>
# --------------------------------------------------------------------------------------------------------------------

# Insert the UPDATE directory name into the JSON file
function insert_dir(){
	if [[ $1 == "history" ]] || [[ $1 == "update" ]];then
		line=`grep "$2\"$" $3`
		if [ ! -n "${line}" ];then
			sed -i "/\"$1\"/ a\		{\n			\"dir\": \"$2\"\n		}," $3
		fi
	fi
}

# Delete the UPDATE directory name in the JSON file
function delete_dir(){
	if [[ $1 == "update" ]];then
		line=`grep "$2\"$" $3`
		if [ -n "${line}" ];then
			sed -i -e "/$2\"$/{n;d}" -e "\$!N;/\n.*$2\"$/!P;D" $3
			sed -i "/$2\"$/d" $3
		else
			exit 0
		fi
	fi
}

# Update the contents of the JSON file
function update_json_file(){
	action=$1
	update_dir=$2
	json_file=$3
	local pkglist=$4
	if [[ ${action} == "create" ]];then
		insert_dir "update" ${update_dir} ${json_file}
	elif [[ ${action} == "del_update_dir" ]];then
		delete_dir "update" ${update_dir} ${json_file}
	elif [[ ${action} == "release" ]];then
		if [[ "x${pkglist}" == "x" ]];then
			delete_dir "update" ${update_dir} ${json_file}
		fi
		insert_dir "history" ${update_dir} ${json_file}
	fi
}

# search package commits
function search_pkg_commits(){
	local project=$1
	local pkg_name=$2
	local update_key=$3
	local update_path=$4
	local branch_name=$5
	local action=$6

	commit_file="${branch_name}-package-commit.txt"
	ssh -i ${update_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${update_ip} "
if [ ! -f "${update_path}/${commit_file}" ];then
	touch ${update_path}/${commit_file}
fi
"
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_path}/${commit_file} ./
	if [ ! -f ${commit_file} ];then
		touch ${commit_file}
	fi

	if [[ ${action} == "delete" ]];then
		for pkg in ${pkg_name[@]}
		do
			if [[ ${pkg} =~ ":" ]];then
				sed -i "/^${pkg##*:}:/d" ${commit_file}
			else
				sed -i "/^${pkg}:/d" ${commit_file}
			fi
		done
	elif [[ ${action} == "create" ]];then
		snapshot_id_list=$(ccb select builds os_project=${project} build_type=full,incremental,specified status=201,202 published_status=4 --sort create_time:desc --size 10 -f snapshot_id | jq -r '.[]._source.snapshot_id' | awk '!a[$0]++')
		if [ "x${snapshot_id_list}" == "x" ];then
			echo "Failed to ccb get the last 10 snapshot_id"
			exit 1
		fi
		rm -f pkglist
		scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_path}/pkglist ./
		latest_pkg=$(cat pkglist)
		for pkg in ${pkg_name[@]}
		do
			if [[ ${pkg} =~ ":" ]];then
				local pkg=${pkg##*:}
			fi
			if [[ ${latest_pkg[@]} =~ ${pkg} ]];then
				for snapshot_id in ${snapshot_id_list[@]}
				do
					commit_id=$(ccb select snapshots _id=${snapshot_id} -f spec_commits | jq -r ".[0]._source.spec_commits[\"${pkg}\"].commit_id")
					if [[ ${commit_id} != "null" ]];then
						break
					fi
				done
				sed -i "/^${pkg}:/d" ${commit_file}
				if [[ ${commit_id} == "null" ]];then
					echo "${pkg}:" >> ${commit_file}
				else
					echo "${pkg}:${commit_id}" >> ${commit_file}
				fi
			fi
		done
		rm -f pkglist
	fi
	scp -i ${update_key} -o StrictHostKeyChecking=no ${commit_file} root@${update_ip}:${update_path}/${commit_file}
}


# Create UPDATE directory and add package binaries
function copy_rpm(){
	local obs_proj=$1
	pkglist=$2
	update_key=$3
	pkg_place=$4
	up_dir=$5
	action=$6
	if [ "x${up_dir}" == "x" ];then
		date_dir="update_"`date +%Y%m%d`
	else
		date_dir=${up_dir}
	fi

	if [[ ${obs_proj} =~ ":Epol" ]];then
		bak=`echo ${obs_proj%%:Epol*}`
		branch_name=`echo ${bak//:/-}`
	else
		branch_name=`echo ${obs_proj//:/-}`
	fi
	real_dir=${date_dir}
	if [ ${pkg_place} == "standard" ];then
		publish_path=(/repo/openeuler/${branch_name}/source /repo/openeuler/${branch_name}/update /repo/openeuler/${branch_name}/everything /repo/openeuler/${branch_name}/debuginfo)
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/${date_dir}"
	elif [ ${pkg_place} == "EPOL" ];then
		publish_path=(/repo/openeuler/${branch_name}/EPOL/update /repo/openeuler/${branch_name}/EPOL)
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${date_dir}"
	elif [ ${pkg_place} == "EPOL-main" ];then
		publish_path=(/repo/openeuler/${branch_name}/EPOL/update/main /repo/openeuler/${branch_name}/EPOL/main)
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${date_dir}/main"
		real_dir="${date_dir}|main"
	elif [[ ${pkg_place} == "EPOL-multi_version" ]] && [[ ${obs_proj} =~ "Multi-Version" ]];then
		tmp=`echo ${obs_proj##*Multi-Version:}`
		pkg=`echo ${tmp%:*}`
		ver=`echo ${tmp#*:}`
		publish_path=(/repo/openeuler/${branch_name}/EPOL/update/multi_version/${pkg}/${ver} /repo/openeuler/${branch_name}/EPOL/multi_version/${pkg}/${ver})
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${date_dir}/multi_version/${pkg}/${ver}"
		real_dir="${date_dir}|multi_version|${pkg}|${ver}"
	else
		echo "package family is error!"
		exit 1
	fi
	ssh -i ${update_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${update_ip} "
if [ ! -d ${update_path} ];then
	mkdir -p ${update_path} && cd ${update_path}
	mkdir -p aarch64/Packages x86_64/Packages source/Packages
	touch pkglist
fi
"
	rm -f pkglist
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_path}/pkglist .
	pkgs=${pkglist//,/ }
	arch=(aarch64 x86_64)
	for p in ${ebs_proj_list[@]}
	do
		if [[ ${obs_proj} =~ ${p} ]];then
			download_type="ccb"
			if [[ ${obs_proj} =~ "Multi-Version" ]];then
				obs_proj=`echo ${obs_proj//:/_}`
			elif [[ ${obs_proj} =~ "Epol" ]];then
				bak=`echo ${obs_proj//:/-}`
				obs_proj=`echo ${bak//-Epol/:epol}`
			else
				obs_proj="`echo ${obs_proj//:/-}`:everything"
			fi
		fi
	done
	for pkg in ${pkgs}
	do
		if [[ ${download_type} == "ccb" ]];then
			for ar in ${arch[@]}
			do
				rpm_dir="${obs_proj}-${ar}-${pkg}"
				ccb download os_project=${obs_proj} packages=${pkg} architecture=${ar} -b all -s -d 2>/dev/null
				if [ $? -ne 0 ];then
					echo "ccb download error."
					exit 1
				fi
				ls ${rpm_dir}/*.rpm | awk -F'/' '{print $NF}' > ${rpm_dir}_rpmlist
				scp -i ${update_key} -o StrictHostKeyChecking=no ./${rpm_dir}/*.src.rpm root@${update_ip}:${update_path}/source/Packages/ 2>/dev/null
				rm -f ${rpm_dir}/*.src.rpm 2>/dev/null
				scp -i ${update_key} -o StrictHostKeyChecking=no ./${rpm_dir}/*.rpm root@${update_ip}:${update_path}/${ar}/Packages/ 2>/dev/null
				rm -rf ${rpm_dir} 2>/dev/null
			done
		else
			for ar in ${arch[@]}
			do
				osc getbinaries ${obs_proj} ${pkg} standard_${ar} ${ar} --source --debug 2>/dev/null
				ls binaries/*.rpm | awk -F'/' '{print $NF}' > "${obs_proj}-${ar}-${pkg}_rpmlist"
				scp -i ${update_key} -o StrictHostKeyChecking=no binaries/*.src.rpm root@${update_ip}:${update_path}/source/Packages/ 2>/dev/null
				rm -f binaries/*.src.rpm 2>/dev/null
				scp -i ${update_key} -o StrictHostKeyChecking=no binaries/*.rpm root@${update_ip}:${update_path}/${ar}/Packages/ 2>/dev/null
				rm -rf binaries 2>/dev/null
			done
		fi
		if [[ ${pkg} =~ ":" ]];then
			echo ${pkg##*:} >> pkglist
		else
			echo ${pkg} >> pkglist
		fi
	done
	sort -u pkglist -o pkglist
	scp -i ${update_key} -o StrictHostKeyChecking=no pkglist root@${update_ip}:${update_path}/
	rm -f pkglist
	ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${update_path} && createrepo -d aarch64 && createrepo -d x86_64 && createrepo -d source"
	if [[ $? -eq 0 ]];then
		if [[ ${action} == "update" ]];then
			echo "更新软件包(${pkglist})的二进制成功!"
		else
			echo "新增软件包(${pkglist})的二进制到${update_path}目录成功!"
		fi
	else
		if [[ ${action} == "update" ]];then
			echo "更新软件包(${pkglist})的二进制失败!"
		else
			echo "新增软件包(${pkglist})的二进制到${update_path}目录失败!"
		fi
	fi
	json_file="${branch_name}-update.json"
	if [ ${pkg_place} == "standard" ];then
		branch_dir="/repo/openeuler/repo.openeuler.org/${branch_name}"
	elif [[ ${pkg_place} =~ "EPOL" ]];then
		branch_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL"
	fi
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${branch_dir}/${json_file} .
	update_json_file "create" ${real_dir} ${json_file}
	scp -i ${update_key} -o StrictHostKeyChecking=no ${json_file} root@${update_ip}:${branch_dir}/
	check_update_rpm ${obs_proj} ${update_path} ${update_key} ${pkglist} "create"
	remove_published_rpm ${obs_proj} ${pkglist} ${publish_path} ${update_path} ${update_key} ${pkg_place}
	pkg_rpm_csv ${obs_proj} ${pkglist} ${update_key} ${update_path} ${branch_name} "update"
	search_pkg_commits ${obs_proj} "${pkgs}" ${update_key} ${update_path} ${branch_name} "create"
}

# Remove published rpms in update_xxx
function remove_published_rpm(){
	local obs_proj=$1
	pkglist=$2
	publish_path=$3
	update_path=$4
	update_key=$5
	pkg_place=$6
	arch=(aarch64 x86_64)
	unset source_rpmlist
	pkgs=${pkglist//,/ }
	echo "[INFO]: Start delete published rpm from ${update_path}"
	rm -f pkglist
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_path}/pkglist .
	echo "${publish_path[@]}"
	if [[ "${pkg_place}" == "standard" ]];then
		for path in ${publish_path[@]}
		do
			if [[ "${path}" =~ "source" ]];then
				tmp_source_rpmlist=$(ssh -i ${update_key} -o StrictHostKeyChecking=no root@${release_ip} "cd ${path}/Packages && ls *.src.rpm")
				source_rpmlist+=(${tmp_source_rpmlist[@]})
			elif [[ "${path}" =~ "update" ]];then
				tmp_source_rpmlist=$(ssh -i ${update_key} -o StrictHostKeyChecking=no root@${release_ip} "cd ${path}/source/Packages && ls *.src.rpm")
				source_rpmlist+=(${tmp_source_rpmlist[@]})
			fi
		done
		unset publish_path[0]
	else
		for path in ${publish_path[@]}
		do
			tmp_source_rpmlist=$(ssh -i ${update_key} -o StrictHostKeyChecking=no root@${release_ip} "cd ${path}/source/Packages && ls *.src.rpm")
			source_rpmlist+=(${tmp_source_rpmlist[@]})
		done
	fi
	for ar in ${arch[@]}
	do
		src_flag=0
		arch_flag=0
		unset rpmlist
		for path in ${publish_path[@]}
		do
			tmp_rpmlist=$(ssh -i ${update_key} -o StrictHostKeyChecking=no root@${release_ip} "cd ${path}/${ar}/Packages && ls *.rpm")
			rpmlist+=(${tmp_rpmlist[@]})
		done
		for pkg in ${pkgs}
		do
			pkg_rpmlist=$(cat ${obs_proj}-${ar}-${pkg}_rpmlist)
			if [ -n "${pkg_rpmlist}" ];then
				for pkg_rpm in ${pkg_rpmlist[@]}
				do
					if [[ "${pkg_rpm}" =~ ".src.rpm" ]];then
						if [[ "${source_rpmlist[@]}" =~ "${pkg_rpm}" ]];then
							echo "[WARNING]: ${pkg_rpm} has been published, will delete from dailybuild ${update_path}/source"
							ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "rm -f ${update_path}/source/Packages/${pkg_rpm}"
							src_flag=1
							if [[ ${pkg} =~ ":" ]];then
								sed -i "/^${pkg##*:}$/d" pkglist
							else
								sed -i "/^${pkg}$/d" pkglist
							fi
						fi
					fi
					if [[ "${rpmlist[@]}" =~ "${pkg_rpm}" ]];then
						echo "[WARNING]: ${pkg_rpm} has been published, will delete from dailybuild ${update_path}/${ar}"
						ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "rm -f ${update_path}/${ar}/Packages/${pkg_rpm}"
						arch_flag=1
						sed -i "/^${pkg}$/d" pkglist
						if [[ ${pkg} =~ ":" ]];then
							sed -i "/^${pkg##*:}$/d" pkglist
						else
							sed -i "/^${pkg}$/d" pkglist
						fi
					fi
				done
			fi
		done
		if [ ${src_flag} -eq 1 ];then
			ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${update_path} && rm -rf source/repodata && createrepo -d source"
		fi
		if [ ${arch_flag} -eq 1 ];then
			ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${update_path} && rm -rf ${ar}/repodata && createrepo -d ${ar}"
		fi
	done
	scp -i ${update_key} -o StrictHostKeyChecking=no pkglist root@${update_ip}:${update_path}/
	rm -f pkglist
	echo "[INFO]: Finish delete published rpm from ${update_path}"
}

# Publish all packages binaries
function release_rpm(){
	local obs_proj=$1
	release_dir=$2	
	update_key=$3
	pkg_place=$4
	pkglist=$5	
	if [[ ${obs_proj} =~ ":Epol" ]];then
		bak=`echo ${obs_proj%%:Epol*}`
		branch_name=`echo ${bak//:/-}`
	else
		branch_name=`echo ${obs_proj//:/-}`
	fi
	if [[ ${pkg_place} =~ "EPOL" ]];then
		branch_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL"
	fi
	real_dir=${release_dir}
	if [ ${pkg_place} == "standard" ];then
		repo_path="/repo/openeuler/${branch_name}/update"
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/${release_dir}"
		bak_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/update"
		branch_dir="/repo/openeuler/repo.openeuler.org/${branch_name}"
	elif [ ${pkg_place} == "EPOL" ];then
		repo_path="/repo/openeuler/${branch_name}/EPOL/update"
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${release_dir}"
		bak_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/update"
	elif [ ${pkg_place} == "EPOL-main" ];then
		repo_path="/repo/openeuler/${branch_name}/EPOL/update/main"
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${release_dir}/main"
		bak_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/update/main"
		real_dir="${release_dir}|main"
	elif [[ ${pkg_place} == "EPOL-multi_version" ]] && [[ ${obs_proj} =~ "Multi-Version" ]];then
		tmp=`echo ${obs_proj##*Multi-Version:}`
		pkg=`echo ${tmp%:*}`
		ver=`echo ${tmp#*:}`
		repo_path="/repo/openeuler/${branch_name}/EPOL/update/multi_version/${pkg}/${ver}"
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${release_dir}/multi_version/${pkg}/${ver}"
		bak_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/update/multi_version/${pkg}/${ver}"
		real_dir="${release_dir}|multi_version|${pkg}|${ver}"
	else
		echo "package family is error!"
		exit 1
	fi
	path_list="aarch64 x86_64 source"
	ssh -i ${update_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${update_ip} "
if [ ! -d ${update_dir} ];then
	echo "${update_dir} is not exist..."
	exit 1
fi
if [ ! -d ${bak_dir} ];then
	mkdir -p ${bak_dir} && cd ${bak_dir}
	mkdir -p aarch64/Packages x86_64/Packages source/Packages
fi
"
	ssh -i ${update_key} -o StrictHostKeyChecking=no root@${release_ip} "
if [ ! -d ${repo_path} ];then
	mkdir -p ${repo_path} && cd ${repo_path}
	mkdir -p aarch64/Packages x86_64/Packages source/Packages
fi
"
	json_file="${branch_name}-update.json"
	if [[ "x${pkglist}" == "x" ]];then
		echo "开始发布${update_dir}目录中的所有的二进制到194机器!"
		for path in ${path_list}
		do
			mkdir $path
			# backup update_xxxx dir rpm into update dir
			ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cp -rf ${update_dir}/${path}/Packages/*.rpm ${bak_dir}/${path}/Packages/"
			ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${bak_dir} && createrepo -d ${path} --workers 32"
			# release rpm to website
			scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_dir}/${path}/Packages/*.rpm ./$path/
			scp -i ${update_key} -o StrictHostKeyChecking=no ./$path/*.rpm root@${release_ip}:${repo_path}/${path}/Packages/
			ssh -i ${update_key} -o StrictHostKeyChecking=no root@${release_ip} "cd ${repo_path} && rm -rf ${path}/repodata && createrepo -d ${path} --workers 32"
			rm -rf $path
		done
		echo "备份及发布${update_dir}成功!"
		scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${branch_dir}/${json_file} .
		update_json_file "release" ${real_dir} ${json_file}
		scp -i ${update_key} -o StrictHostKeyChecking=no ${json_file} root@${update_ip}:${branch_dir}/
	else
		pkgs=${pkglist//,/ }
		arch_list="aarch64 x86_64"
		rm -rf ${path_list} NOT_FOUND binrpmlist
		mkdir ${path_list} && touch NOT_FOUND
		for p in ${ebs_proj_list[@]}
		do
			if [[ ${obs_proj} =~ ${p} ]];then
				download_type="ccb"
				if [[ ${obs_proj} =~ "Multi-Version" ]];then
					obs_proj=`echo ${obs_proj//:/_}`
				elif [[ ${obs_proj} =~ "Epol" ]];then
					bak=`echo ${obs_proj//:/-}`
					obs_proj=`echo ${bak//-Epol/:epol}`
				else
					obs_proj="`echo ${obs_proj//:/-}`:everything"
				fi
			fi
		done
		for pkg in ${pkgs}
		do
			flag=0
			if [[ ${download_type} != "ccb" ]];then
				res=`osc ls ${obs_proj} 2>/dev/null | grep ^${pkg}$`
				if [[ "x${res}" == "x" ]];then
					echo "===Error: ${obs_proj} ${pkg} is not exists!!!==="
					exit 1
				fi
			fi
			for arch in ${arch_list}
			do
				if [[ ${download_type} == "ccb" ]];then
					ccb download os_project=${obs_proj} packages=${pkg} architecture=${arch} -b all -s -d &>/dev/null
					if [ $? -ne 0 ];then
						echo "ccb download error."
						exit 1
					fi
					ls ${obs_proj}-${arch}-${pkg}/*.rpm | awk -F'/' '{print $NF}' > binrpmlist
				else
					osc ls -b ${obs_proj} ${pkg} standard_${arch} ${arch} 2>/dev/null | grep rpm > binrpmlist
				fi
				if [ ! -s binrpmlist ];then
					continue
				else
					if [[ ${flag} == 0 ]];then
						src_rpm=`cat binrpmlist | grep "src.rpm"`
						tmp_name=`echo ${src_rpm%-*}`
						src_rpm_name=`echo ${tmp_name%-*}`
						result=`ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${update_dir}/source/Packages/ && ls | grep ^${src_rpm_name} | grep -E ${src_rpm_name}-[a-zA-Z0-9.]+-[a-zA-Z0-9]+.oe"`
						if [[ "x${result}" == "x" ]];then
							echo "$src_rpm_name-xxx.src.rpm" >> NOT_FOUND
							flag=1
						else
							scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_dir}/source/Packages/${result} ./source/
							if [ ! -f "source/${result}" ];then
								echo "===Error: scp ${result} failed!!!==="
								exit 1
							fi
						fi
					fi
					sed -i '/src.rpm/d' binrpmlist
					for line in `cat binrpmlist`
					do
						tmp_name=`echo ${line%-*}`
						name=`echo ${tmp_name%-*}`
						result=`ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${update_dir}/${arch}/Packages/ && ls | grep ^${name} | grep -E ${name}-[a-zA-Z0-9.]+-[a-zA-Z0-9]+.oe"`
						if [[ "x${result}" == "x" ]];then
							echo "${name}-xxx.${arch}.rpm" >> NOT_FOUND
						else
							scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_dir}/${arch}/Packages/${result} ./${arch}/
							if [ ! -f "${arch}/${result}" ];then
								echo "===Error: scp ${result} failed!!!==="
								exit 1
							fi
						fi
					done
				fi
			done
		done
		if [ -s NOT_FOUND ];then
			echo "==========Warning: Not Found some binaries rpm in ${update_dir} directory=========="
			cat NOT_FOUND
			echo "===================="
		fi
		echo "开始发布${update_dir}目录中软件包${pkgs}的二进制到194机器!"
		ls ${path_list}
		for arch in ${path_list}
		do
			# backup update_xxxx dir some packages binaries rpm into update dir
			scp -i ${update_key} -o StrictHostKeyChecking=no ./${arch}/*.rpm root@${update_ip}:${bak_dir}/${arch}/Packages/
			ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${bak_dir} && createrepo -d ${arch} --workers 32"
			# release some packages binaries rpm to website
			scp -i ${update_key} -o StrictHostKeyChecking=no ./${arch}/*.rpm root@${release_ip}:${repo_path}/${arch}/Packages/
			ssh -i ${update_key} -o StrictHostKeyChecking=no root@${release_ip} "cd ${repo_path} && rm -rf ${arch}/repodata && createrepo -d ${arch} --workers 32"
			rm -rf ${arch}
		done
		echo "备份及发布成功!"
		scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${branch_dir}/${json_file} .
		release_pkg="${real_dir}/"
		for pkg in ${pkgs}
		do
			release_pkg="${release_pkg}${pkg}|"
		done
		update_json_file "release" ${release_pkg} ${json_file} ${pkgs}
		scp -i ${update_key} -o StrictHostKeyChecking=no ${json_file} root@${update_ip}:${branch_dir}/
	fi
}

# Update packages binaries
function update_rpm(){
	local obs_proj=$1
	pkglist=$2
	update_key=$3
	up_dir=$4
	pkg_place=$5
	
	if [[ ${obs_proj} =~ ":Epol" ]];then
		bak=`echo ${obs_proj%%:Epol*}`
		branch_name=`echo ${bak//:/-}`
	else
		branch_name=`echo ${obs_proj//:/-}`
	fi
	if [ ${pkg_place} == "standard" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/${up_dir}"
	elif [ ${pkg_place} == "EPOL" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}"
	elif [ ${pkg_place} == "EPOL-main" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}/main"
	elif [[ ${pkg_place} == "EPOL-multi_version" ]] && [[ ${obs_proj} =~ "Multi-Version" ]];then
		tmp=`echo ${obs_proj##*Multi-Version:}`
		pkg=`echo ${tmp%:*}`
		ver=`echo ${tmp#*:}`
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}/multi_version/${pkg}/${ver}"
	else
		echo "package family is error!"
		exit 1
	fi
	ssh -i ${update_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${update_ip} "
if [ ! -d ${update_path} ];then
	echo "${update_path} is not exist..."
	exit 2
fi
"
	echo "开始更新${update_path}目录中软件包(${pkglist})的二进制!"
	del_pkg_rpm ${obs_proj} ${pkglist} ${update_key} ${up_dir} "update" ${pkg_place} 
	copy_rpm ${obs_proj} ${pkglist} ${update_key} ${pkg_place} ${up_dir} "update"
}

# create pkg rpm info file
function pkg_rpm_csv(){
	project=$1
	pkglist=$2
	update_key=$3
	update_path=$4
	branch=$5
	action=$6
	pkgs=${pkglist//,/ }
	csv_file="${branch}.csv"
	ssh -i ${update_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${update_ip} "
if [ ! -f ${update_path}/${csv_file} ];then
	touch ${update_path}/${csv_file}
fi
"
	rm -f ${csv_file}
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_path}/${csv_file} .
	if [ ! -f "${csv_file}" ];then
		touch ${csv_file}
	fi

	for pkg in ${pkgs}
	do
		rpms=$(cat ${project}-aarch64-${pkg}_rpmlist ${project}-x86_64-${pkg}_rpmlist | sort | uniq)
		if [[ ${pkg} =~ ":" ]];then
			local pkg=${pkg##*:}
		fi
		sed -i "/${pkg},/d" ${csv_file}
		if [[ ${action} == "update" ]];then
			line="${pkg},${rpms[@]}"
			echo ${line} >> ${csv_file}
		fi
	done
	scp -i ${update_key} -o StrictHostKeyChecking=no ${csv_file} root@${update_ip}:${update_path}/
}

# Delete packages binaries
function del_pkg_rpm(){
	local obs_proj=$1
	pkglist=$2
	update_key=$3
	up_dir=$4
	flag=$5
	pkg_place=$6
	if [[ ${obs_proj} =~ ":Epol" ]];then
		bak=`echo ${obs_proj%%:Epol*}`
		branch_name=`echo ${bak//:/-}`
	else
		branch_name=`echo ${obs_proj//:/-}`
	fi
	if [ ${pkg_place} == "standard" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/${up_dir}"
	elif [ ${pkg_place} == "EPOL" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}"
	elif [ ${pkg_place} == "EPOL-main" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}/main"
	elif [[ ${pkg_place} == "EPOL-multi_version" ]] && [[ ${obs_proj} =~ "Multi-Version" ]];then
		tmp=`echo ${obs_proj##*Multi-Version:}`
		pkg=`echo ${tmp%:*}`
		ver=`echo ${tmp#*:}`
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}/multi_version/${pkg}/${ver}"
	else
		echo "package family is error!"
		exit 1
	fi
	pkg_aarch_path="${update_path}/aarch64/Packages"
	pkg_x86_path="${update_path}/x86_64/Packages"
	source_path="${update_path}/source/Packages"
	pkgs=${pkglist//,/ }
	for p in ${ebs_proj_list[@]}
	do
		if [[ ${obs_proj} =~ ${p} ]];then
			download_type="ccb"
			if [[ ${obs_proj} =~ "Multi-Version" ]];then
				obs_proj=`echo ${obs_proj//:/_}`
			elif [[ ${obs_proj} =~ "Epol" ]];then
				bak=`echo ${obs_proj//:/-}`
				obs_proj=`echo ${bak//-Epol/:epol}`
			else
				obs_proj="`echo ${obs_proj//:/-}`:everything"
			fi
		fi
	done
	for pkg in $pkgs
	do
		if [[ ${download_type} == "ccb" ]];then
			ccb download os_project=${obs_proj} packages=${pkg} architecture=aarch64 -b all -s -d &>/dev/null
			if [ $? -ne 0 ];then
				echo "ccb download error."
				exit 1
			fi
			ls ${obs_proj}-aarch64-${pkg}/*.rpm | awk -F'/' '{print $NF}' > aarch_rpmlist.txt
			ls ${obs_proj}-aarch64-${pkg}/*.rpm | awk -F'/' '{print $NF}' > ${obs_proj}-aarch64-${pkg}_rpmlist
			ccb download os_project=${obs_proj} packages=${pkg} architecture=x86_64 -b all -s -d &>/dev/null
			if [ $? -ne 0 ];then
				echo "ccb download error."
				exit 1
			fi
			ls ${obs_proj}-x86_64-${pkg}/*.rpm | awk -F'/' '{print $NF}' > x86_rpmlist.txt
			ls ${obs_proj}-x86_64-${pkg}/*.rpm | awk -F'/' '{print $NF}' > ${obs_proj}-x86_64-${pkg}_rpmlist
			rm -rf ${obs_proj}-aarch64-${pkg} ${obs_proj}-x86_64-${pkg}
		else
			osc ls -b ${obs_proj} ${pkg} standard_aarch64 aarch64 2>/dev/null | grep rpm > aarch_rpmlist.txt
			osc ls -b ${obs_proj} ${pkg} standard_x86_64 x86_64 2>/dev/null | grep rpm > x86_rpmlist.txt
		fi
		if [ -s aarch_rpmlist.txt ];then
			src_rpm=`cat aarch_rpmlist.txt | grep "src.rpm"`
		else
			src_rpm=`cat x86_rpmlist.txt | grep "src.rpm"`
		fi
		tmp_name=`echo ${src_rpm%-*}`
		rpm_name=`echo ${tmp_name%-*}`
		big_version=`echo ${tmp_name##*-}`
		sed -i '/src.rpm/d' aarch_rpmlist.txt
		sed -i '/src.rpm/d' x86_rpmlist.txt
		if [ -s aarch_rpmlist.txt ];then
			for line in `cat aarch_rpmlist.txt`
			do
				name=`echo ${line%-*-*}`
				ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${pkg_aarch_path} && ls ${name}-*.rpm 2>/dev/null | grep ${big_version} | xargs rm 2>/dev/null"
			done
		fi
		if [ -s x86_rpmlist.txt ];then
			for line2 in `cat x86_rpmlist.txt`
			do
				name2=`echo ${line2%-*-*}`
				ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${pkg_x86_path} && ls ${name2}-*.rpm 2>/dev/null | grep ${big_version} | xargs rm 2>/dev/null"
			done
		fi
		ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${source_path} && ls ${rpm_name}-*.src.rpm 2>/dev/null | grep ${big_version} | xargs rm 2>/dev/null"
	done
	rm -f *_rpmlist.txt 2>/dev/null

	if [[ ${flag} == "delete" ]];then
		rm -f pkglist 2>/dev/null
		scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_path}/pkglist .
		for pkg in ${pkgs}
		do
			if [[ ${pkg} =~ ":" ]];then
				sed -i "/^${pkg##*:}$/d" pkglist
			else
				sed -i "/^${pkg}$/d" pkglist
			fi
		done	
		scp -i ${update_key} -o StrictHostKeyChecking=no pkglist root@${update_ip}:${update_path}/
		ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${update_path} && createrepo -d aarch64 && createrepo -d x86_64 && createrepo -d source"
		check_update_rpm ${obs_proj} ${update_path} ${update_key} ${pkglist} "delete"
		pkg_rpm_csv ${obs_proj} ${pkglist} ${update_key} ${update_path} ${branch_name} "delete"
		search_pkg_commits ${obs_proj} "${pkgs}" ${update_key} ${update_path} ${branch_name} ${flag}
	fi
}

# Delete UPDATE directory
function del_update_dir(){
	local obs_proj=$1
	up_dir=$2
	update_key=$3
	pkg_place=$4

	if [[ ${obs_proj} =~ ":Epol" ]];then
		bak=`echo ${obs_proj%%:Epol*}`
		branch_name=`echo ${bak//:/-}`
	else
		branch_name=`echo ${obs_proj//:/-}`
	fi
	real_dir=${up_dir}
	if [ ${pkg_place} == "standard" ];then
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/${up_dir}"
	elif [ ${pkg_place} == "EPOL" ];then
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}"
	elif [ ${pkg_place} == "EPOL-main" ];then
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}/main"
		real_dir="${up_dir}|main"
	elif [[ ${pkg_place} == "EPOL-multi_version" ]] && [[ ${obs_proj} =~ "Multi-Version" ]];then
		tmp=`echo ${obs_proj##*Multi-Version:}`
		pkg=`echo ${tmp%:*}`
		ver=`echo ${tmp#*:}`
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}/multi_version/${pkg}/${ver}"
		real_dir="${up_dir}|multi_version|${pkg}|${ver}"
	else
		echo "package family is error!"
		exit 1
	fi
	ssh -i ${update_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${update_ip} "
if [ ! -d ${update_dir} ];then
	echo "删除${update_dir}目录失败!"
	exit 5
else
	rm -rf ${update_dir}
	echo "删除${update_dir}目录成功!"
fi
"
	if [ ${pkg_place} == "standard" ];then
		branch_dir="/repo/openeuler/repo.openeuler.org/${branch_name}"
	elif [ ${pkg_place} == "EPOL" ];then
		branch_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL"
	elif [[ ${pkg_place} =~ "EPOL-" ]];then
		exit 0
	fi
	json_file="${branch_name}-update.json"
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${branch_dir}/${json_file} .
	update_json_file "del_update_dir" ${real_dir} ${json_file}
	scp -i ${update_key} -o StrictHostKeyChecking=no ${json_file} root@${update_ip}:${branch_dir}/
}

# Check packages binaries
function check_update_rpm(){
	echo "Start checking update directory package binaries..."
	obs_proj=$1
	update_path=$2
	update_key=$3
	pkglist=$4
	action=$5
	pkg_aarch_path="${update_path}/aarch64/Packages"
	pkg_x86_path="${update_path}/x86_64/Packages"
	source_path="${update_path}/source/Packages"
	pkgs=${pkglist//,/ }
	for pkg in ${pkgs}
	do
		cat ${obs_proj}-aarch64-${pkg}_rpmlist >> arch_rpm_list
		cat ${obs_proj}-x86_64-${pkg}_rpmlist >> x86_rpm_list
	done
	cat arch_rpm_list x86_rpm_list | grep "src.rpm" | sort | uniq >> src_rpm_list
	sed -i '/.src.rpm/d' arch_rpm_list x86_rpm_list
	sed -i 's/^ *//g' arch_rpm_list src_rpm_list x86_rpm_list
	ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${pkg_aarch_path} && ls *.rpm > update_arch_rpm 2>/dev/null && cd ${pkg_x86_path} && ls *.rpm > update_x86_rpm 2>/dev/null && cd ${source_path} && ls *.rpm > update_src_rpm 2>/dev/null"
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${pkg_aarch_path}/update_arch_rpm . 2>/dev/null
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${pkg_x86_path}/update_x86_rpm . 2>/dev/null
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${source_path}/update_src_rpm . 2>/dev/null
	ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${pkg_aarch_path} && rm -f update_arch_rpm 2>/dev/null && cd ${pkg_x86_path} && rm -f update_x86_rpm 2>/dev/null && cd ${source_path} && rm -f update_src_rpm 2>/dev/null"
	parse_data arch_rpm_list update_arch_rpm ${pkg_aarch_path} ${action}
	parse_data src_rpm_list update_src_rpm ${source_path} ${action}
	parse_data x86_rpm_list update_x86_rpm ${pkg_x86_path} ${action}
	echo "======================检查结果汇总======================"
	if [ -s check_result ];then
		if [[ ${action} == "delete" ]];then
			echo "删除${update_path}目录中软件包(${pkglist})的二进制失败!"
			rm -f update_*_rpm *_rpm_list check_result 2>/dev/null
			exit 1
		fi
		cat check_result
		rm -f update_*_rpm *_rpm_list check_result 2>/dev/null
		exit 1
	else
		if [[ ${action} == "delete" ]];then
			echo "删除${update_path}目录中软件包(${pkglist})的二进制成功!"
		fi
		echo "经过检查后，${update_path}目录中软件包(${pkglist})的二进制无缺失且无多余！"
		rm -f update_*_rpm *_rpm_list check_result 2>/dev/null
	fi
}

# Process the data
function parse_data(){
	compare_file=$1
	base_file=$2
	pkg_path=$3
	action=$4
	if [ -s ${base_file} ];then
		for line in `cat ${compare_file}`
		do
			grep "^${line}$" ${base_file}
			if [[ $? -eq 0 ]];then
				if [[ ${action} == "delete" ]];then
					echo "${pkg_path}目录中多余二进制:${line}" >> check_result
				fi
			else
				if [[ ${action} != "delete" ]];then
					echo "${pkg_path}目录中缺少二进制:${line}" >> check_result
				fi
			fi
		done
	fi
}

# Prepare the environment
function prepare_env(){
	ssh -i $1 -o StrictHostKeyChecking=no root@${update_ip} "yum install -y createrepo &>/dev/null"
}

# Main function
function main(){
	ebs_proj_list=(openEuler:22.03:LTS:SP1 openEuler:22.03:LTS:SP2)
	if [ $1 == "openEuler:Mainline" ];then
		echo "openEuler:Mainline not need update"
		exit 3
	fi
	prepare_env $3
	if [ $# -eq 5 ];then
		if [ ${4} == "create" ];then
			copy_rpm $1 $2 $3 $5
		elif [ ${4} == "release" ];then
			release_rpm $1 $2 $3 $5
		elif [ ${4} == "del_update_dir" ];then
			del_update_dir $1 $2 $3 $5
		fi
	elif [ $# -eq 6 ];then
		if [ ${4} == "create" ];then
			copy_rpm $1 $2 $3 $5 $6
		elif [ ${4} == "release" ];then
			release_rpm $1 $2 $3 $5 $6
		elif [ ${4} == "update" ];then
			update_rpm $1 $2 $3 $5 $6
		elif [ ${4} == "del_pkg_rpm" ];then
			del_pkg_rpm $1 $2 $3 $5 "delete" $6
		fi
	else
		echo "error, please check parameters"
		exit 4
	fi
}

main "$@"
