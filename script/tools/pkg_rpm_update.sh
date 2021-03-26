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
	if [ "x${up_dir}" == "x" ];then
		date_dir="update_"`date +%Y%m%d`
	else
		date_dir=${up_dir}
	fi
	branch_name=`echo ${obs_proj//:/-}`
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
fi
"
	pkgs=${pkglist//,/ }
	for pkg in ${pkgs}
	do
		osc getbinaries ${obs_proj} ${pkg} standard_aarch64 aarch64 --source --debug
		scp -i ${update_key} -o StrictHostKeyChecking=no binaries/*.src.rpm root@${update_ip}:${update_path}/source/Packages/
		rm -f binaries/*.src.rpm
		scp -i ${update_key} -o StrictHostKeyChecking=no binaries/*.rpm root@${update_ip}:${update_path}/aarch64/Packages/
		rm -rf binaries
		osc getbinaries ${obs_proj} ${pkg} standard_x86_64 x86_64 --source --debug
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

	json_file="${branch_name}-update.json"
	if [ ${pkg_place} == "standard" ];then
		branch_dir="/repo/openeuler/repo.openeuler.org/${branch_name}"
	elif [ ${pkg_place} == "EPOL" ];then
		branch_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL"
	fi
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${branch_dir}/${json_file} .
	update_json_file "create" ${date_dir} ${json_file}
	scp -i ${update_key} -o StrictHostKeyChecking=no ${json_file} root@${update_ip}:${branch_dir}/
	check_update_rpm ${obs_proj} ${date_dir} ${pkg_place} ${update_key}
}

function release_rpm(){
	branch_name=`echo ${1//:/-}`
	release_dir=$2	
	update_key=$3
	pkg_place=$4
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
	
	branch_name=`echo ${1//:/-}`
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
	del_pkg_rpm ${obs_proj} ${pkglist} ${up_dir} ${update_key} "update" ${pkg_place} 
	copy_rpm ${obs_proj} ${pkglist} ${update_key} ${pkg_place} ${up_dir}
}

# delete update dir pkg binary rpm
function del_pkg_rpm(){
	obs_proj=$1
	pkglist=$2
	up_dir=$3
	update_key=$4
	flag=$5
	pkg_place=$6
	branch_name=`echo ${obs_proj//:/-}`
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
		check_update_rpm ${obs_proj} ${up_dir} ${pkg_place} ${update_key}
	fi
}

function del_update_dir(){
	branch_name=`echo ${1//:/-}`
	up_dir=$2
	update_key=$3
	pkg_place=$4

	if [ ${pkg_place} == "standard" ];then
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/${up_dir}"
	elif [ ${pkg_place} == "EPOL" ];then
		update_dir="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${up_dir}"
	else
		echo "package family is error!"
		exit 0
	fi
	ssh -i ${update_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${update_ip} "
if [ ! -d ${update_dir} ];then
	echo "${update_dir} is not exist..."
	exit 5
else
	rm -rf ${update_dir}
	echo "rm ${update_dir} success!"
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
	branch_name=`echo ${obs_proj//:/-}`
	if [ ${pkg_place} == "standard" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/${update_dir}"
	elif [ ${pkg_place} == "EPOL" ];then
		update_path="/repo/openeuler/repo.openeuler.org/${branch_name}/EPOL/${update_dir}"
	fi
	pkg_aarch_path="${update_path}/aarch64/Packages"
	pkg_x86_path="${update_path}/x86_64/Packages"
	source_path="${update_path}/source/Packages"
	rm -f pkglist
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${update_path}/pkglist .
	for pkg in `cat pkglist`
	do
		osc ls -b ${obs_proj} ${pkg} standard_aarch64 aarch64 2>/dev/null | grep -Ev "standard_|_buildenv|_statistics" >> arch_rpm_bak
		osc ls -b ${obs_proj} ${pkg} standard_x86_64 x86_64 2>/dev/null | grep -Ev "standard_|_buildenv|_statistics" >> x86_rpm_bak
	done
	cat arch_rpm_bak x86_rpm_bak | grep "src.rpm" >> src_rpm_bak
	sed -i '/.src.rpm/d' arch_rpm_bak x86_rpm_bak
	sed -i 's/^ *//g' arch_rpm_bak src_rpm_bak x86_rpm_bak
	cat arch_rpm_bak | sort | uniq > arch_rpm_list
	cat src_rpm_bak | sort | uniq > src_rpm_list
	cat x86_rpm_bak | sort | uniq > x86_rpm_list
	rm -f arch_rpm_bak src_rpm_bak x86_rpm_bak
	ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${pkg_aarch_path} && ls *.rpm > arch_rpm_bak && cd ${pkg_x86_path} && ls *.rpm > x86_rpm_bak && cd ${source_path} && ls *.rpm > src_rpm_bak"
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${pkg_aarch_path}/arch_rpm_bak .
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${pkg_x86_path}/x86_rpm_bak .
	scp -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip}:${source_path}/src_rpm_bak .
	ssh -i ${update_key} -o StrictHostKeyChecking=no root@${update_ip} "cd ${pkg_aarch_path} && rm -f arch_rpm_bak && cd ${pkg_x86_path} && rm -f x86_rpm_bak && cd ${source_path} && rm -f src_rpm_bak"
	cat arch_rpm_bak | sort | uniq > update_arch_rpm
	cat src_rpm_bak | sort | uniq > update_src_rpm
	cat x86_rpm_bak | sort | uniq > update_x86_rpm
	rm -f arch_rpm_bak src_rpm_bak x86_rpm_bak
	diff -Nur update_arch_rpm arch_rpm_list > diff_arch_list
	diff -Nur update_src_rpm src_rpm_list > diff_src_list
	diff -Nur update_x86_rpm x86_rpm_list > diff_x86_list
	sed -i '1,3d' diff_arch_list diff_src_list diff_x86_list
	parse_patch_data diff_arch_list ${pkg_aarch_path}
	parse_patch_data diff_src_list ${source_path}
	parse_patch_data diff_x86_list ${pkg_x86_path}
	echo "======================检查结果汇总======================"
	if [ -s check_result ];then
		cat check_result
		rm -f update_*_rpm diff_*_list check_result pkglist
		exit 1
	else
		echo "经过检查后，${update_path}目录中二进制无缺失且无多余！"
		rm -f update_*_rpm diff_*_list check_result pkglist
		exit 0	
	fi
}

function parse_patch_data(){
	diff_list=$1
	pkg_path=$2
	if [ -s ${diff_list} ];then
		rdt=`grep "^-" ${diff_list} | sed 's/^-*//g' | sed ':a;N;s/\n/ /;ba;'`
		miss=`grep "^+" ${diff_list} | sed 's/^+*//g' | sed ':a;N;s/\n/ /;ba;'`
		if [ -n "${rdt}" ];then
			echo "${pkg_path}目录中多余二进制：${rdt}" >> check_result
		fi
		if [ -n "${miss}" ];then
			echo "${pkg_path}目录中缺少二进制：${miss}" >> check_result
		fi
	fi
}

if [ $1 == "openEuler:Mainline" ];then
	echo "openEuler:Mainline not need update"
	exit 3
fi

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
