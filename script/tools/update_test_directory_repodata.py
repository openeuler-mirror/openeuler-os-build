#!/bin/env python3
# -*- encoding=utf8 -*-
#******************************************************************************
# Copyright (c) Huawei Technologies Co., Ltd. 2020-2020. All rights reserved.
# licensed under the Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#     http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR
# PURPOSE.
# See the Mulan PSL v2 for more details.
# Author: 
# Create: 
# ******************************************************************************
"""
modify test directory repodata with updateinfo
"""

import os
import sys
import shutil
import argparse
from update_repodata import createFile, upload_updateinfo_file
from update_repodata import construct_obsClient, download_withfile

my_par = argparse.ArgumentParser()
my_par.add_argument("-f", "--flag", default=None,
        help="cve or updateinfo or hotpatch", required=True)
my_par.add_argument("-ak", "--AK", default=None,
        help="Access Key", required=True)
my_par.add_argument("-sk", "--SK", default=None,
        help="Secret Key", required=True)
my_par.add_argument("-s", "--server", default=None,
        help="domain name", required=True)
my_par.add_argument("-bn", "--bucketname", default=None,
        help="obs bucket demo name", required=True)
my_par.add_argument("-fn", "--filename", default=None,
        help="name of file to download", required=True)
my_par.add_argument("-ip", "--ipadd", default=None,
        help="release machine ip address", required=True)
my_par.add_argument("-ud", "--updatedir", default=None,
        help="update directory name", required=True)
my_par.add_argument("-key", "--sshkey", default=None,
        help="ssh key", required=True)
args = my_par.parse_args()

def modify_repodata(args, branch, xmlfile):
    """
    modify repodata
    """
    msg = []
    archive = ['aarch64', 'x86_64', 'source']
    repo_path = f"/repo/openeuler/repo.openeuler.org/{branch}/{args.updatedir}"
    for arch in archive:
        cmd = "ssh -i %s -o StrictHostKeyChecking=no root@%s 'modifyrepo /repo/%s %s/%s/repodata'" %(
                args.sshkey, args.ipadd, xmlfile, repo_path, arch)
        if os.system(cmd) == 0:
            print("Succeed to modify %s %s %s repodata" % (branch, args.updatedir, arch))
        else:
            tmp = "Fail to modify %s %s %s repodata" % (branch, args.updatedir, arch)
            print(tmp)
            msg.append(tmp)
    return msg


def update_test_directory_repodata(args):
    """
    update test directory repodata by updateinfo or updateinfo-hotpatch
    """
    error_msg = []
    updateinfo_path = os.path.join(os.getcwd(), args.flag)
    if os.path.exists(updateinfo_path):
        shutil.rmtree(updateinfo_path)
    os.makedirs(updateinfo_path)
    localfile = os.path.join(updateinfo_path, args.filename)
    createFile(localfile)
    obsClient = construct_obsClient(args)
    name = os.path.join(args.flag, args.filename)
    download_withfile(args, obsClient, name, localfile)
    with open(localfile, "r") as f:
        filemsg = f.readlines()
    for line in filemsg:
        if line:
            line = line.replace('\n', '')
            branch, xmlfile = line.split('/')
            localfile = os.path.join(updateinfo_path, line)
            name = os.path.join(args.flag, line)
            branch_path = os.path.join(updateinfo_path, branch)
            if os.path.exists(branch_path):
                shutil.rmtree(branch_path)
            os.makedirs(branch_path)
            createFile(localfile)
            download_withfile(args, obsClient, name, localfile)
            upload_updateinfo_file(args, localfile)
            ret = modify_repodata(args, branch, xmlfile)
            if ret:
                error_msg.extend(ret)
    if os.path.exists(updateinfo_path):
        shutil.rmtree(updateinfo_path)
    if error_msg:
        print(">>>Have some problems<<<")
        for msg in error_msg:
            print(msg)
        sys.exit(1)

if __name__ == '__main__':
    if args.flag == "earlyupdateinfo" or args.flag == "earlyupdateinfo-hotpatch":
        update_test_directory_repodata(args)
    else:
        print("The flag include earlyupdateinfo and earlyupdateinfo-hotpatch.")
        sys.exit(1)
