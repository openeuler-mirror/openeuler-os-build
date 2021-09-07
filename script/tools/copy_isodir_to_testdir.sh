#!/bin/bash
# -----------------------------------------------------------------------
# Author: wangchong
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
# Decription: Copy iso directory to prefixed with test_ directory
# Usage: bash copy_isodir_to_testdir.sh <branch> <iso_dir> <ip> <ssh_key>
# -----------------------------------------------------------------------

branch=$1
dirname=$2
ip=$3
update_key=$4
branch_path="/repo/openeuler/dailybuild/${branch}"
iso_path="${branch_path}/${dirname}"
test_dirname="test_${dirname}"

ssh -i ${update_key} -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ServerAliveInterval=60 root@${ip} "
if [ -d ${branch_path} ];then
	if [ -d ${iso_path} ];then
		cd ${branch_path}
		if [ -d ${test_dirname} ];then
			rm -rf ${test_dirname}
		fi
		date
		echo "INFO: copying iso dir to test dir, please wait..."
		cp ${dirname} ${test_dirname} -rf
		if [ $? -eq 0 ] && [ -d ${test_dirname} ];then
			echo "INFO: copy succeed!"
			date
			exit 0
		else
			echo "ERROR: copy failed!"
			exit 1
		fi
	else
		echo "ERROR: ${iso_path} is not exists, please check your iso dirname!"
		exit 1
	fi
else
	echo "ERROR: ${branch_path} is not exists, please check your branch!"
fi
"
