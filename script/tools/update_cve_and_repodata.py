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
update cve xml and index.txt
modify repodata with updateinfo
"""

import os
import sys
import uuid
import shutil
import argparse
import datetime
import traceback
from obs import ObsClient


par = argparse.ArgumentParser()
par.add_argument("-f", "--flag", default=None,
        help="cve or updateinfo or hotpatch", required=True)
par.add_argument("-ak", "--AK", default=None,
        help="Access Key", required=True)
par.add_argument("-sk", "--SK", default=None,
        help="Secret Key", required=True)
par.add_argument("-s", "--server", default=None,
        help="domain name", required=True)
par.add_argument("-bn", "--bucketname", default=None,
        help="obs bucket demo name", required=True)
par.add_argument("-fn", "--filename", default=None,
        help="name of file to download", required=True)
par.add_argument("-ip", "--ipadd", default=None,
        help="release machine ip address", required=True)
par.add_argument("-key", "--sshkey", default=None,
        help="ssh key", required=True)
args = par.parse_args()

def createFile(localfile):
    """
    create local file
    """
    if os.path.exists(localfile):
        shutil.rmtree(localfile)
    f = open(localfile, "w")
    f.close()

def construct_obsClient(args):
    """
    create obs client
    """
    obsClient = ObsClient(access_key_id=args.AK, secret_access_key=args.SK, server=args.server)
    return obsClient

def download_withfile(args, obsClient, name, localfile):
    """
    downloads the objects in the bucket as a file
    """
    try:
        resp = obsClient.getObject(args.bucketname, name, downloadPath=localfile)
        print("resp.status:", resp.status)
        if resp.status < 300:
            print("Succeed to download %s" % name)
        else:
            print("Failed to download %s" % name)
            print("errorCode:", resp.errorCode)
            print("errorMessage:", resp.errorMessage)
    except:
        print(traceback.format_exc())
        sys.exit(1)

def download_xmlfile(args, cvrf_path, obsClient):
    """
    downloads cve xml file
    """
    update_path = os.path.join(cvrf_path, "update_fixed.txt")
    
    bugfix_cvrf = os.path.join(os.getcwd(), os.path.join("bugFix", "cvrf"))
    if os.path.exists(bugfix_cvrf):
        shutil.rmtree(bugfix_cvrf)
    os.makedirs(bugfix_cvrf)
    
    hotpatch_cvrf = os.path.join(os.getcwd(), "hotpatch_cvrf")
    if os.path.exists(hotpatch_cvrf):
        shutil.rmtree(hotpatch_cvrf)
    os.makedirs(hotpatch_cvrf)

    if os.path.exists(update_path):
        if os.path.getsize(update_path):
            with open(update_path, "r") as f:
                filemsg = f.readlines()
            for line in filemsg:
                if line:
                    line = line.replace('\n', '')
                    year = line.split('/')[0]
                    if "openEuler-HotPatchSA" in line:
                        year_path = os.path.join(hotpatch_cvrf, year)
                        localfile = os.path.join(hotpatch_cvrf, line)
                    elif "openEuler-SA" in line:
                        year_path = os.path.join(cvrf_path, year)
                        localfile = os.path.join(cvrf_path, line)
                    elif "openEuler-BA" in line:
                        year_path = os.path.join(bugfix_cvrf, year)
                        localfile = os.path.join(bugfix_cvrf, line)
                    else:
                        print("There are some problems in the update_fixed.txt file.")
                        sys.exit(1)

                    if not os.path.exists(year_path):
                        os.makedirs(year_path)
                    name = os.path.join("cvrf", line)
                    createFile(localfile)
                    download_withfile(args, obsClient, name, localfile)
        else:
            return -1
    else:
        return -1

def download_csaffile(args, csaf_path, obsClient, dir_name):
    """
    downloads csaf file
    """
    update_path = os.path.join(csaf_path, "update_fixed.txt")
    
    if os.path.exists(update_path):
        if os.path.getsize(update_path):
            with open(update_path, "r") as f:
                filemsg = f.readlines()
            for line in filemsg:
                if line:
                    line = line.replace('\n', '')
                    year = line.split('/')[0]
                    year_path = os.path.join(csaf_path, year)
                    localfile = os.path.join(csaf_path, line)

                    if not os.path.exists(year_path):
                        os.makedirs(year_path)
                    name = os.path.join("csaf", os.path.join(dir_name, line))
                    createFile(localfile)
                    download_withfile(args, obsClient, name, localfile)
        else:
            return -1
    else:
        return -1

def upload_xml_file(args, uploadfile, cvrf_name):
    """
    upload xml files to publish server
    """
    print("Uploading xml file to publish server.")
    if cvrf_name == "SA" or cvrf_name == "HotPatchSA":
        dest_dir = "/repo/openeuler/security/data/"
    elif cvrf_name == "BA":
        dest_dir = "/repo/openeuler/bugFix/data/"
def upload_xml_file(args, uploadfile, cvrf_name):
    """
    upload xml files to publish server
    """
    print("Uploading xml file to publish server.")
    if cvrf_name == "SA" or cvrf_name == "HotPatchSA":
        dest_dir = "/repo/openeuler/security/data/"
    elif cvrf_name == "BA":
        dest_dir = "/repo/openeuler/bugFix/data/"
    else:
        dest_dir = "/repo/openeuler/security/data/csaf/"
    cmd = "ssh -i %s -o StrictHostKeyChecking=no root@%s 'if [ ! -d %s ];then mkdir -p %s;fi'" % (args.sshkey, args.ipadd, dest_dir, dest_dir)
    if os.system(cmd) != 0:
        print("Fail to create directory:%s" % dest_dir)

    cmd = "scp -i %s -o StrictHostKeyChecking=no -r %s root@%s:%s" % (args.sshkey, uploadfile, args.ipadd, dest_dir)
    if os.system(cmd) == 0:
        print("Succeed to upload file!")
    else:
        print("Failed to upload file!")
        sys.exit(1)

def upload_updateinfo_file(args, uploadfile):
    """
    upload updateinfo files to publish server
    """
    print("Uploading updateinfo file to publish server.")
    cmd = "scp -i %s -o StrictHostKeyChecking=no %s root@%s:/repo/" % (args.sshkey, uploadfile, args.ipadd)
    if os.system(cmd) == 0:
        print("Succeed to upload file!")
    else:
        print("Failed to upload file!")
        sys.exit(1)

def modify_repo(args, branch, xmlfile):
    """
    modify repodata
    """
    msg = []
    archive = ['aarch64', 'x86_64', 'source']
    if args.flag == "updateinfo":
        repo_path = f"/repo/openeuler/{branch}/update"
    if args.flag == "updateinfo-hotpatch":
        repo_path = f"/repo/openeuler/{branch}/hotpatch_update"
    for arch in archive:
        cmd = "ssh -i %s -o StrictHostKeyChecking=no root@%s 'modifyrepo /repo/%s %s/%s/repodata'" %(
                args.sshkey, args.ipadd, xmlfile, repo_path, arch)
        if os.system(cmd) == 0:
            print("Succeed to modify %s %s repodata" % (branch, arch))
        else:
            tmp = "Fail to modify %s %s repodata" % (branch, arch)
            print(tmp)
            msg.append(tmp)
    return msg

def update_cve(args):
    """
    update cve or hotpatch xml file
    """
    cvrf_path = os.path.join(os.getcwd(), "cvrf")
    if os.path.exists(cvrf_path):
        shutil.rmtree(cvrf_path)
    os.makedirs(cvrf_path)
    
    for name in args.filename.split(','):
        localfile = os.path.join(cvrf_path, name)
        createFile(localfile)
        obsClient = construct_obsClient(args)
        name = os.path.join("cvrf", name)
        download_withfile(args, obsClient, name, localfile)
    
    ret = download_xmlfile(args, cvrf_path, obsClient)
    update_path = os.path.join(cvrf_path, "update_fixed.txt")
    if os.path.exists(update_path):
        os.remove(update_path)
    
    if ret == -1:
        print("Nothing to update !")
    else:
        all_index_txt = os.path.join(os.getcwd(), "index.txt")
        cvrf_index_txt = os.path.join(cvrf_path, "index.txt")
        shutil.copy(cvrf_index_txt, all_index_txt)
        hotpatch_path = os.path.join(os.getcwd(), "hotpatch_cvrf")
        hotpatch_index_txt = os.path.join(hotpatch_path, "index.txt")
        bugfix_path = os.path.join(os.getcwd(), os.path.join("bugFix", "cvrf"))
        bugfix_index_txt = os.path.join(bugfix_path, "index.txt")
        f_all = open(all_index_txt, "r")
        f_sa = open(cvrf_index_txt, "w")
        f_hotpatch = open(hotpatch_index_txt, "w")
        f_bugfix = open(bugfix_index_txt, "w")
        for line in f_all:
            if line:
                if "openEuler-HotPatchSA" in line:
                    f_hotpatch.write(line)
                elif "openEuler-SA" in line:
                    f_sa.write(line)
                elif "openEuler-BA" in line:
                    f_bugfix.write(line)
        f_all.close()
        f_sa.close()
        f_hotpatch.close()
        f_bugfix.close()
        upload_xml_file(args, cvrf_path, "SA")
        upload_xml_file(args, hotpatch_path, "HotPatchSA")
        upload_xml_file(args, bugfix_path, "BA")

def update_repo(args):
    """
    update repodata by updateinfo or updateinfo-hotpatch
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
            ret = modify_repo(args, branch, xmlfile)
            if ret:
                error_msg.extend(ret)
    if os.path.exists(updateinfo_path):
        shutil.rmtree(updateinfo_path)
    if error_msg:
        print(">>>Have some problems<<<")
        for msg in error_msg:
            print(msg)
        sys.exit(1)

def update_csaf(args):
    """
    update csaf file
    """
    dir_list = ["advisories", "cve"]
    for dir_name in dir_list:
        csaf_path = os.path.join(os.getcwd(), os.path.join("csaf", dir_name))
        if os.path.exists(csaf_path):
            shutil.rmtree(csaf_path)
        os.makedirs(csaf_path)

        for name in args.filename.split(','):
            localfile = os.path.join(csaf_path, name)
            createFile(localfile)
            obsClient = construct_obsClient(args)
            name = os.path.join("csaf", os.path.join(dir_name, name))
            download_withfile(args, obsClient, name, localfile)
    
        ret = download_csaffile(args, csaf_path, obsClient, dir_name)
        update_path = os.path.join(csaf_path, "update_fixed.txt")
        if os.path.exists(update_path):
            os.remove(update_path)
    
        if ret == -1:
            print("dir %s Nothing to update !" % dir_name)
        else:
            upload_xml_file(args, csaf_path, dir_name)

if __name__ == '__main__':
    if args.flag == "cve":
        update_cve(args)
    if args.flag == "csaf":
        update_csaf(args)
    elif args.flag == "updateinfo" or args.flag == "updateinfo-hotpatch":
        update_repo(args)
    else:
        print("flag include cve, updateinfo and hotpatch.")
