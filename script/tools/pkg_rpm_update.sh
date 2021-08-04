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
	pkglist=$4
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

# Create UPDATE directory and add package binaries
function copy_rpm(){
	obs_proj=$1
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
	if [[ ${obs_proj} =~ "Epol" ]];then
		bak=`echo ${obs_proj%%:Epol}`
		branch_name=`echo ${bak//:/-}`
	else
		branch_name=`echo ${obs_proj//:/-}`
	fi
	if [ ${pkg_place} == "standard" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/${date_dir}"
	elif [ ${pkg_place} == "EPOL" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${date_dir}"
	elif [ ${pkg_place} == "EPOL-main" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${date_dir}/main"
	elif [ ${pkg_place} == "EPOL-multi_version" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${date_dir}/multi_version"
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
	pkgs=${pkglist//,/ }
	for pkg in ${pkgs}
	do
		osc getbinaries ${obs_proj} ${pkg} standard_aarch64 aarch64 --source --debug 2>/dev/null
		scp -i ${update_key} -o StrictHostKeyChecking=no binaries/*.src.rpm root@${update_ip}:${update_path}/source/Packages/ 2>/dev/null
		rm -f binaries/*.src.rpm 2>/dev/null
		scp -i ${update_key} -o StrictHostKeyChecking=no binaries/*.rpm root@${update_ip}:${update_path}/aarch64/Packages/ 2>/dev/null
		rm -rf binaries 2>/dev/null
		osc getbinaries ${obs_proj} ${pkg} standard_x86_64 x86_64 --source --debug 2>/dev/null
		scp -i ${update_key} -o StrictHostKeyChecking=no binaries/*.src.rpm root@${update_ip}:${update_path}/source/Packages/ 2>/dev/null
		rm -f binaries/*.src.rpm 2>/dev/null
		scp -i ${update_key} -o StrictHostKeyChecking=no binaries/*.rpm root@${update_ip}:${update_path}/x86_64/Packages/ 2>/dev/null
		rm -rf binaries 2>/dev/null
		echo ${pkg} >> pkglist_bak
	done
	rm -f pkglist 2>/dev/null
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_path}/pkglist .
	cat pkglist_bak >> pkglist
	cat pkglist | sort | uniq > pkglist_bak
	mv pkglist_bak pkglist
	scp -i ${update_key} -o StrictHostKeyChecking=no pkglist root@${update_ip}:${update_path}/
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
	update_json_file "create" ${date_dir} ${json_file}
	scp -i ${update_key} -o StrictHostKeyChecking=no ${json_file} root@${update_ip}:${branch_dir}/
	check_update_rpm ${obs_proj} ${date_dir} ${pkg_place} ${update_key} ${pkglist} "create"
}

# Publish all packages binaries
function release_rpm(){
	obs_proj=$1
	release_dir=$2	
	update_key=$3
	pkg_place=$4
	pkglist=$5	
	if [[ ${obs_proj} =~ "Epol" ]];then
		bak=`echo ${obs_proj%%:Epol}`
		branch_name=`echo ${bak//:/-}`
	else
		branch_name=`echo ${obs_proj//:/-}`
	fi
	if [[ ${pkg_place} =~ "EPOL" ]];then
		branch_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL"
	fi
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
		repo_path="/repo/openeuler/${branch_name}/EPOL/update/main/update"
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${release_dir}/main"
		bak_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/update/main/update"
	elif [ ${pkg_place} == "EPOL-multi_version" ];then
		repo_path="/repo/openeuler/${branch_name}/EPOL/update/multi_version/update"
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${release_dir}/multi_version"
		bak_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/update/multi_version/update"
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
			ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${bak_dir} && createrepo -d ${path}"
			# release rpm to website
			scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_dir}/${path}/Packages/*.rpm ./$path/
			scp -i ${update_key} -o StrictHostKeyChecking=no ./$path/*.rpm root@${release_ip}:${repo_path}/${path}/Packages/
			ssh -i ${update_key} -o StrictHostKeyChecking=no root@${release_ip} "cd ${repo_path} && createrepo -d ${path}"
			rm -rf $path
		done
		echo "备份及发布${update_dir}成功!"
		scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${branch_dir}/${json_file} .
		update_json_file "release" ${release_dir} ${json_file}
		scp -i ${update_key} -o StrictHostKeyChecking=no ${json_file} root@${update_ip}:${branch_dir}/
	else
		pkgs=${pkglist//,/ }
		arch_list="aarch64 x86_64"
		rm -rf ${path_list} NOT_FOUND binrpmlist
		mkdir ${path_list} && touch NOT_FOUND
		for pkg in ${pkgs}
		do
			flag=0
			res=`osc ls ${obs_proj} 2>/dev/null | grep ^${pkg}$`
			if [[ "x${res}" == "x" ]];then
				echo "===Error: ${obs_proj} ${pkg} is not exists!!!==="
				exit 1
			fi
			for arch in ${arch_list}
			do
				osc ls -b ${obs_proj} ${pkg} standard_${arch} ${arch} 2>/dev/null | grep rpm > binrpmlist
				if [ ! -s binrpmlist ];then
					continue
				else
					if [[ ${flag} == 0 ]];then
						src_rpm=`cat binrpmlist | grep "src.rpm"`
						src_rpm_name=`echo ${src_rpm%%-[0-9]*}`
						result=`ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${update_dir}/source/Packages/ && ls | grep ${src_rpm_name}-[0-9]*.rpm"`
						if [[ "x${result}" == "x" ]];then
							echo "$src_rpm_name-xxx.oe1.src.rpm" >> NOT_FOUND
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
						name=`echo ${line%%-[0-9]*}`
						result=`ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${update_dir}/${arch}/Packages/ && ls | grep ${name}-[0-9]*.rpm"`
						if [[ "x${result}" == "x" ]];then
							echo "${name}-xxx.oe1.${arch}.rpm" >> NOT_FOUND
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
			echo "==========Error: Not Found some binaries rpm in ${update_dir} directory=========="
			cat NOT_FOUND
			echo "===================="
			exit 1
		else
			echo "开始发布${update_dir}目录中软件包${pkgs}的二进制到194机器!"
			ls ${path_list}
			for arch in ${path_list}
			do
				# backup update_xxxx dir some packages binaries rpm into update dir
				scp -i ${update_key} -o StrictHostKeyChecking=no ./${arch}/*.rpm root@${update_ip}:${bak_dir}/${arch}/Packages/
				ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${bak_dir} && createrepo -d ${arch}"
				# release some packages binaries rpm to website
				scp -i ${update_key} -o StrictHostKeyChecking=no ./${arch}/*.rpm root@${release_ip}:${repo_path}/${arch}/Packages/
				ssh -i ${update_key} -o StrictHostKeyChecking=no root@${release_ip} "cd ${repo_path} && createrepo -d ${arch}"
				rm -rf ${arch}
			done
			echo "备份及发布成功!"
			scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${branch_dir}/${json_file} .
			for pkg in ${pkgs}
			do
				release_pkg="${release_dir}/${pkg}"
				update_json_file "release" ${release_pkg} ${json_file} ${pkgs}
			done
			scp -i ${update_key} -o StrictHostKeyChecking=no ${json_file} root@${update_ip}:${branch_dir}/
		fi
	fi
}

# Update packages binaries
function update_rpm(){
	obs_proj=$1
	pkglist=$2
	update_key=$3
	up_dir=$4
	pkg_place=$5
	
	if [[ ${obs_proj} =~ "Epol" ]];then
		bak=`echo ${obs_proj%%:Epol}`
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
	elif [ ${pkg_place} == "EPOL-multi_version" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}/multi_version"
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

# Delete packages binaries
function del_pkg_rpm(){
	obs_proj=$1
	pkglist=$2
	update_key=$3
	up_dir=$4
	flag=$5
	pkg_place=$6
	if [[ ${obs_proj} =~ "Epol" ]];then
		bak=`echo ${obs_proj%%:Epol}`
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
	elif [ ${pkg_place} == "EPOL-multi_version" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}/multi_version"
	else
		echo "package family is error!"
		exit 1
	fi
	pkg_aarch_path="${update_path}/aarch64/Packages"
	pkg_x86_path="${update_path}/x86_64/Packages"
	source_path="${update_path}/source/Packages"
	pkgs=${pkglist//,/ }
	for pkg in $pkgs
	do
		osc ls -b ${obs_proj} ${pkg} standard_aarch64 aarch64 2>/dev/null | grep rpm > aarch_rpmlist.txt
		osc ls -b ${obs_proj} ${pkg} standard_x86_64 x86_64 2>/dev/null | grep rpm > x86_rpmlist.txt
		if [ -s aarch_rpmlist.txt ];then
			src_rpm=`cat aarch_rpmlist.txt | grep "src.rpm"`
		else
			src_rpm=`cat x86_rpmlist.txt | grep "src.rpm"`
		fi
		rpm_name=`echo ${src_rpm%%-[0-9]*}`
		tmp=`echo ${src_rpm%%.oe1*}`
		version=`echo ${tmp#*-}`
		if [ `echo ${version} | grep ^[a-zA-Z]` ];then
			version=`echo ${version#*-}`
		fi
		big_version=`echo ${version%%-*}`
		sed -i '/src.rpm/d' aarch_rpmlist.txt
		sed -i '/src.rpm/d' x86_rpmlist.txt
		if [ -s aarch_rpmlist.txt ];then
			for line in `cat aarch_rpmlist.txt`
			do
				name=`echo ${line%%-[0-9]*}`
				ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${pkg_aarch_path} && ls ${name}-*.rpm 2>/dev/null | grep ${big_version} | xargs rm 2>/dev/null"
			done
		fi
		if [ -s x86_rpmlist.txt ];then
			for line2 in `cat x86_rpmlist.txt`
			do
				name2=`echo ${line2%%-[0-9]*}`
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
			sed -i "/^$pkg$/d" pkglist
		done	
		scp -i ${update_key} -o StrictHostKeyChecking=no pkglist root@${update_ip}:${update_path}/
		ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${update_path} && createrepo -d aarch64 && createrepo -d x86_64 && createrepo -d source"
		check_update_rpm ${obs_proj} ${up_dir} ${pkg_place} ${update_key} ${pkglist} "delete"
	fi
}

# Delete UPDATE directory
function del_update_dir(){
	obs_proj=$1
	up_dir=$2
	update_key=$3
	pkg_place=$4

	if [[ ${obs_proj} =~ "Epol" ]];then
		bak=`echo ${obs_proj%%:Epol}`
		branch_name=`echo ${bak//:/-}`
	else
		branch_name=`echo ${obs_proj//:/-}`
	fi
	if [ ${pkg_place} == "standard" ];then
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/${up_dir}"
	elif [ ${pkg_place} == "EPOL" ];then
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}"
	elif [ ${pkg_place} == "EPOL-main" ];then
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}/main"
	elif [ ${pkg_place} == "EPOL-multi_version" ];then
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}/multi_version"
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
	update_json_file "del_update_dir" ${up_dir} ${json_file}
	scp -i ${update_key} -o StrictHostKeyChecking=no ${json_file} root@${update_ip}:${branch_dir}/
}

# Check packages binaries
function check_update_rpm(){
	echo "Start checking update directory package binaries..."
	obs_proj=$1
	update_dir=$2
	pkg_place=$3
	update_key=$4
	pkglist=$5
	action=$6
	if [[ ${obs_proj} =~ "Epol" ]];then
		bak=`echo ${obs_proj%%:Epol}`
		branch_name=`echo ${bak//:/-}`
	else
		branch_name=`echo ${obs_proj//:/-}`
	fi
	if [ ${pkg_place} == "standard" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/${update_dir}"
	elif [ ${pkg_place} == "EPOL" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${update_dir}"
	elif [ ${pkg_place} == "EPOL-main" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${update_dir}/main"
	elif [ ${pkg_place} == "EPOL-multi_version" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${update_dir}/multi_version"
	fi
	pkg_aarch_path="${update_path}/aarch64/Packages"
	pkg_x86_path="${update_path}/x86_64/Packages"
	source_path="${update_path}/source/Packages"
	pkgs=${pkglist//,/ }
	for pkg in ${pkgs}
	do
		osc ls -b ${obs_proj} ${pkg} standard_aarch64 aarch64 2>/dev/null | grep -Ev "standard_|_buildenv|_statistics" >> arch_rpm_list
		osc ls -b ${obs_proj} ${pkg} standard_x86_64 x86_64 2>/dev/null | grep -Ev "standard_|_buildenv|_statistics" >> x86_rpm_list
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
		exit 0	
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
	ssh -i $1 -o StrictHostKeyChecking=no root@${update_ip} "apt-get install -y createrepo &>/dev/null"
}

# Main function
function main(){
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
