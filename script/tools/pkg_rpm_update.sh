#!/bin/bash

update_ip="121.36.84.172"
release_ip="121.36.97.194"

function insert_dir(){
	if [[ $1 == "history" ]] || [[ $1 == "update" ]];then
		line=`grep "$2\"$" $3`
		if [ ! -n "${line}" ];then
			sed -i "/\"$1\"/ a\		{\n			\"dir\": \"$2\"\n		}," $3
		fi
	fi
}

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

function update_json_file(){
	action=$1
	update_dir=$2
	json_file=$3
	if [[ ${action} == "create" ]];then
		insert_dir "update" ${update_dir} ${json_file}
	elif [[ ${action} == "del_update_dir" ]];then
		delete_dir "update" ${update_dir} ${json_file}
	elif [[ ${action} == "release" ]];then
		delete_dir "update" ${update_dir} ${json_file}
		insert_dir "history" ${update_dir} ${json_file}
	fi
}

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
	else
		echo "package family is error!"
		exit 0
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
		scp -i ${update_key} -o StrictHostKeyChecking=no binaries/*.src.rpm root@${update_ip}:${update_path}/source/Packages/
		rm -f binaries/*.src.rpm
		scp -i ${update_key} -o StrictHostKeyChecking=no binaries/*.rpm root@${update_ip}:${update_path}/aarch64/Packages/
		rm -rf binaries
		osc getbinaries ${obs_proj} ${pkg} standard_x86_64 x86_64 --source --debug 2>/dev/null
		scp -i ${update_key} -o StrictHostKeyChecking=no binaries/*.src.rpm root@${update_ip}:${update_path}/source/Packages/
		rm -f binaries/*.src.rpm
		scp -i ${update_key} -o StrictHostKeyChecking=no binaries/*.rpm root@${update_ip}:${update_path}/x86_64/Packages/
		rm -rf binaries
		echo ${pkg} >> pkglist_bak
	done
	rm -f pkglist
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
	elif [ ${pkg_place} == "EPOL" ];then
		branch_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL"
	fi
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${branch_dir}/${json_file} .
	update_json_file "create" ${date_dir} ${json_file}
	scp -i ${update_key} -o StrictHostKeyChecking=no ${json_file} root@${update_ip}:${branch_dir}/
	check_update_rpm ${obs_proj} ${date_dir} ${pkg_place} ${update_key} ${pkglist} "create"
}

function release_rpm(){
	obs_proj=$1
	release_dir=$2	
	update_key=$3
	pkg_place=$4
	if [[ ${obs_proj} =~ "Epol" ]];then
		bak=`echo ${obs_proj%%:Epol}`
		branch_name=`echo ${bak//:/-}`
	else
		branch_name=`echo ${obs_proj//:/-}`
	fi
	if [ ${pkg_place} == "standard" ];then
		repo_path="/repo/openeuler/${branch_name}/update"
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/${release_dir}"
		bak_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/update"
	elif [ ${pkg_place} == "EPOL" ];then
		repo_path="/repo/openeuler/${branch_name}/EPOL/update"
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${release_dir}"
		bak_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/update"
	else
		echo "package family is error!"
		exit 0
	fi
	path_list="aarch64 x86_64 source"
	ssh -i ${update_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${update_ip} "
if [ ! -d ${update_dir} ];then
	echo "${update_dir} is not exist..."
	exit 1
fi
"
        echo "开始发布${update_dir}目录中的所有的二进制到194机器!"
	for path in ${path_list}
        do
		mkdir $path
		## backup update_xxxx dir rpm into update dir
		ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cp -rf ${update_dir}/${path}/Packages/*.rpm ${bak_dir}/${path}/Packages/"
		ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${bak_dir} && createrepo -d ${path}"
		## release rpm to website
		scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_dir}/${path}/Packages/*.rpm ./$path/
		scp -i ${update_key} -o StrictHostKeyChecking=no ./$path/*.rpm root@${release_ip}:${repo_path}/${path}/Packages/
		ssh -i ${update_key} -o StrictHostKeyChecking=no root@${release_ip} "cd ${repo_path} && createrepo -d ${path}"
		rm -rf $path
        done
	echo "备份及发布${update_dir}成功!"
	if [ ${pkg_place} == "standard" ];then
		branch_dir="/repo/openeuler/repo.openeuler.org/${branch_name}"
	elif [ ${pkg_place} == "EPOL" ];then
		branch_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL"
	fi
	json_file="${branch_name}-update.json"
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${branch_dir}/${json_file} .
	update_json_file "release" ${release_dir} ${json_file}
	scp -i ${update_key} -o StrictHostKeyChecking=no ${json_file} root@${update_ip}:${branch_dir}/
}

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
	else
		echo "package family is error!"
		exit 0
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

# delete update dir pkg binary rpm
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
	else
		echo "package family is error!"
		exit 0
	fi
	pkg_aarch_path="${update_path}/aarch64/Packages"
	pkg_x86_path="${update_path}/x86_64/Packages"
	source_path="${update_path}/source/Packages"
	pkgs=${pkglist//,/ }
	for pkg in $pkgs
	do
		osc ls -b ${obs_proj} ${pkg} standard_aarch64 aarch64 2>/dev/null | grep rpm > aarch_rpmlist.txt
		osc ls -b ${obs_proj} ${pkg} standard_x86_64 x86_64 2>/dev/null | grep rpm > x86_rpmlist.txt
		src_rpm=`cat aarch_rpmlist.txt | grep "src.rpm"`
		rpm_name=`echo ${src_rpm%%-[0-9]*}`
		tmp=`echo ${src_rpm%%.oe1*}`
		version=`echo ${tmp#*-}`
		if [ `echo ${version} | grep ^[a-zA-Z]` ];then
			version=`echo ${version#*-}`
		fi
		big_version=`echo ${version%%-*}`
		sed -i '/src.rpm/d' aarch_rpmlist.txt
		sed -i '/src.rpm/d' x86_rpmlist.txt
		for line in `cat aarch_rpmlist.txt`
		do
			name=`echo ${line%%-[0-9]*}`
			ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${pkg_aarch_path} && ls ${name}-*.rpm 2>/dev/null | grep ${big_version} | xargs rm 2>/dev/null"
		done
		for line2 in `cat x86_rpmlist.txt`
		do
			name2=`echo ${line2%%-[0-9]*}`
			ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${pkg_x86_path} && ls ${name2}-*.rpm 2>/dev/null | grep ${big_version} | xargs rm 2>/dev/null"
		done
		ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${source_path} && ls ${rpm_name}-*.src.rpm 2>/dev/null | grep ${big_version} | xargs rm 2>/dev/null"
	done
	rm -f *_rpmlist.txt

	if [[ ${flag} == "delete" ]];then
		rm -f pkglist
		scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_path}/pkglist .
		for pkg in ${pkgs}
		do
			sed -i "/^$pkg$/d" pkglist
		done	
		scp -i ${update_key} -o StrictHostKeyChecking=no pkglist root@${update_ip}:${update_path}/
		check_update_rpm ${obs_proj} ${up_dir} ${pkg_place} ${update_key} ${pkglist} "delete"
	fi
}

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
	fi
	json_file="${branch_name}-update.json"
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${branch_dir}/${json_file} .
	update_json_file "del_update_dir" ${up_dir} ${json_file}
	scp -i ${update_key} -o StrictHostKeyChecking=no ${json_file} root@${update_ip}:${branch_dir}/
}

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
	ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${pkg_aarch_path} && ls *.rpm > update_arch_rpm && cd ${pkg_x86_path} && ls *.rpm > update_x86_rpm && cd ${source_path} && ls *.rpm > update_src_rpm"
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${pkg_aarch_path}/update_arch_rpm .
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${pkg_x86_path}/update_x86_rpm .
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${source_path}/update_src_rpm .
	ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${pkg_aarch_path} && rm -f update_arch_rpm && cd ${pkg_x86_path} && rm -f update_x86_rpm && cd ${source_path} && rm -f update_src_rpm"
	parse_data arch_rpm_list update_arch_rpm ${pkg_aarch_path} ${action}
	parse_data src_rpm_list update_src_rpm ${source_path} ${action}
	parse_data x86_rpm_list update_x86_rpm ${pkg_x86_path} ${action}
	echo "======================检查结果汇总======================"
	if [ -s check_result ];then
		if [[ ${action} == "delete" ]];then
			echo "删除${update_path}目录中软件包(${pkglist})的二进制失败!"
			rm -f update_*_rpm *_rpm_list check_result
			exit 1
		fi
		cat check_result
		rm -f update_*_rpm *_rpm_list check_result
		exit 1
	else
		if [[ ${action} == "delete" ]];then
			echo "删除${update_path}目录中软件包(${pkglist})的二进制成功!"
		fi
		echo "经过检查后，${update_path}目录中软件包(${pkglist})的二进制无缺失且无多余！"
		rm -f update_*_rpm *_rpm_list check_result
		exit 0	
	fi
}

function parse_data(){
	compare_file=$1
	base_file=$2
	pkg_path=$3
	action=$4
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
}

function prepare_env(){
	ssh -i $1 -o StrictHostKeyChecking=no root@${update_ip} "apt-get install -y createrepo &>/dev/null"
}

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
	elif [ ${4} == "update" ];then
		update_rpm $1 $2 $3 $5 $6
	elif [ ${4} == "del_pkg_rpm" ];then
		del_pkg_rpm $1 $2 $3 $5 "delete" $6
	fi
else
	echo "error, please check parameters"
	exit 4
fi
