#!/bin/bash
# -----------------------------------------------------------------------
# Author: wangchong
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
# Description: Copy DevStation build artifacts from two branches into a test directory
#              with kernel-version-specific subdirectories.
# Usage: bash copy_devstation_to_testdir.sh <branch> <branch_2> <dirname> <dirname_2> <ip> <ssh_key> <prefix>
#   branch   : Source branch for kernel-6.18 artifacts (e.g. EBS-openEuler-26.09-DevStation)
#   branch_2 : Source branch for kernel-6.6 artifacts  (e.g. EBS-openEuler-26.09)
#   dirname  : Directory name under branch  (e.g. 2024-01-01-10-30-00)
#   dirname_2: Directory name under branch_2
#   ip       : Remote server IP
#   ssh_key  : SSH private key path (update_key)
#   prefix   : Prefix for the test directory name (e.g. test)
# -----------------------------------------------------------------------

branch=$1
branch_2=$2
dirname=$3
dirname_2=$4
ip=$5
update_key=$6
prefix=$7

branch_path="/repo/openeuler/dailybuild/${branch}"
branch_2_path="/repo/openeuler/dailybuild/${branch_2}"
iso_path="${branch_path}/${dirname}"
iso_path_2="${branch_2_path}/${dirname_2}"
test_dirname="${prefix}_${dirname}"

ssh -i ${update_key} -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ServerAliveInterval=60 root@${ip} "
# Step 1: Verify branch_path exists
if [ ! -d ${branch_path} ];then
    echo 'ERROR: ${branch_path} does not exist, please check your branch!'
    exit 1
fi

# Step 2: Verify branch_2_path exists
if [ ! -d ${branch_2_path} ];then
    echo 'ERROR: ${branch_2_path} does not exist, please check your branch_2!'
    exit 1
fi

# Step 3: Verify source dir1 exists (under branch)
if [ ! -d ${iso_path} ];then
    echo 'ERROR: ${iso_path} does not exist, please check your dirname!'
    exit 1
fi

# Step 4: Verify source dir2 exists (under branch_2)
if [ ! -d ${iso_path_2} ];then
    echo 'ERROR: ${iso_path_2} does not exist, please check your dirname_2!'
    exit 1
fi

# Step 5: Prepare test directory
cd ${branch_path}
if [ -d ${test_dirname} ];then
    rm -rf ${test_dirname}
fi
mkdir -p ${test_dirname}/26.09-with-kernel-6.18
mkdir -p ${test_dirname}/26.09-with-kernel-6.6

# Step 6: Copy dirname contents -> 26.09-with-kernel-6.18
date
echo 'INFO: copying ${branch}/${dirname} -> ${test_dirname}/26.09-with-kernel-6.18, please wait...'
cp ${iso_path}/* ${test_dirname}/26.09-with-kernel-6.18/ -rf
if [ \$? -ne 0 ];then
    echo 'ERROR: copy ${branch}/${dirname} failed!'
    exit 1
fi
echo 'INFO: copy 26.09-with-kernel-6.18 succeed!'
date

# Step 7: Copy dirname_2 contents -> 26.09-with-kernel-6.6 (exclude DevStation, docker_img, stratovirt_img)
echo 'INFO: copying ${branch_2}/${dirname_2} -> ${test_dirname}/26.09-with-kernel-6.6, please wait...'
cd ${iso_path_2}
shopt -s extglob
cp -rf !(DevStation|docker_img|stratovirt_img) ${branch_path}/${test_dirname}/26.09-with-kernel-6.6/
if [ \$? -ne 0 ];then
    echo 'ERROR: copy ${branch_2}/${dirname_2} failed!'
    exit 1
fi
echo 'INFO: copy 26.09-with-kernel-6.6 succeed!'
date

# Step 8: Verify both target directories are non-empty
count_618=\$(ls -1 ${test_dirname}/26.09-with-kernel-6.18 2>/dev/null | wc -l)
count_66=\$(ls -1 ${test_dirname}/26.09-with-kernel-6.6 2>/dev/null | wc -l)
echo \"INFO: 26.09-with-kernel-6.18 has \${count_618} items\"
echo \"INFO: 26.09-with-kernel-6.6 has \${count_66} items\"

if [ \${count_618} -eq 0 ];then
    echo 'ERROR: 26.09-with-kernel-6.18 is empty after copy!'
    exit 1
fi
if [ \${count_66} -eq 0 ];then
    echo 'ERROR: 26.09-with-kernel-6.6 is empty after copy!'
    exit 1
fi
echo 'INFO: all copy operations completed successfully!'
"
