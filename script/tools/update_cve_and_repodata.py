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

import sys
import argparse
from update_repodata import update_cve
from update_repodata import update_repo
from update_repodata import update_csaf
from update_repodata import update_bugfix
from update_repodata import update_osv

par = argparse.ArgumentParser()
par.add_argument("-f", "--flag", default=None,
        help="cve or csaf or updateinfo or updateinfo-hotpatch or bugfix or osv", required=True)
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

if __name__ == '__main__':
    if args.flag == "cve":
        update_cve(args)
    elif args.flag == "csaf":
        update_csaf(args)
    elif args.flag == "updateinfo" or args.flag == "updateinfo-hotpatch":
        update_repo(args)
    elif args.flag == "bugfix":
        update_bugfix(args)
    elif args.flag == "osv":
        update_osv(args)
    else:
        print("The flag include cve, csaf, updateinfo, updateinfo-hotpatch, bugfix and osv.")
        sys.exit(1)
