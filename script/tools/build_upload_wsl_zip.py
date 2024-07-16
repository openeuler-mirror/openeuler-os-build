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

import os
import sys
import logging
import argparse
import requests
import shutil
import jenkins
from datetime import datetime, timedelta
import time

logging.basicConfig(level=logging.INFO,
        format="%(asctime)s - %(filename)s[line:%(lineno)d] - %(levelname)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
        )
log = logging.getLogger(__name__)

par = argparse.ArgumentParser()
par.add_argument("-ju", "--jenkins_user", help="jenkins user name", required=True)
par.add_argument("-jt", "--jenkins_api_token", help="jenkins api token", required=True)
par.add_argument("-jn", "--job_name", help="jenkins job name", required=True)
par.add_argument("-k", "--ssh_key", help="ssh key", required=True)
par.add_argument("-r", "--release", help="release name", required=True)
par.add_argument("-p", "--publish", help="publish flag", required=True)
par.add_argument("-ip", "--ipaddr", help="server ip address", required=True)
par.add_argument("-t", "--target_path", help="target path", required=True)
args = par.parse_args()


def get_requests_result(url):
    """
    follow url get data
    """
    response = requests.get(url)
    if response.status_code != 200:
        log.error(response)
        raise requests.HTTPError("")
    return response

def build_jenkins_job():
    """
    build jenkins job
    """
    job_url = None
    file_name = None
    baseuri, branch, date_dir = args.target_path.split("/")

    server = jenkins.Jenkins("https://openeulerjenkins.osinfra.cn", username=args.jenkins_user, password=args.jenkins_api_token, timeout=120)
    if not server.job_exists(args.job_name):
        log.error("%s is not exists" % args.job_name)
        sys.exit(1)
    ret = server.build_job(args.job_name, parameters={"release": args.release, \
            "publish": args.publish, "server": f"http://{args.ipaddr}", \
            "baseuri": baseuri, "branch": branch, "date": date_dir})
    time.sleep(60)

    last_build_number = server.get_job_info(args.job_name)['lastBuild']['number']
    log.info("last build number:%s" % last_build_number)
    end_time = datetime.now() + timedelta(minutes=30)
    while True:
        job_state = server.get_build_info(args.job_name, last_build_number)['result']
        log.info("build result:%s" % job_state)
        if job_state == "SUCCESS":
            break
        elif job_state == "FAILURE":
            log.error("job build failed")
            sys.exit(1)
        elif datetime.now() > end_time:
            log.error("waiting for job build timeout 30 minutes")
            server.stop_build(args.job_name, last_build_number)
            sys.exit(1)
        else:
            time.sleep(60)
    
    build_info = server.get_build_info(args.job_name, last_build_number)
    job_url = build_info['url']
    files = build_info['artifacts']
    for tmp in files:
        if tmp['fileName'].endswith('.zip'):
            file_name = tmp['fileName']
    log.info("job url:%s" % job_url)
    return job_url, file_name

def download_file(job_url, file_name):
    """
    download file
    """
    wsl_path = os.path.join(os.getcwd(), "WSL")
    if os.path.exists(wsl_path):
        shutil.rmtree(wsl_path)
    os.makedirs(wsl_path)
    sha256sum_file_name = file_name + ".sha256sum"
    all_file = [file_name, sha256sum_file_name]
    for name in all_file:
        file_url = os.path.join(job_url, "artifact", name)
        local_file_path = os.path.join(wsl_path, name)
        req = get_requests_result(file_url)
        with open(local_file_path, "wb") as f:
            f.write(req.content)
        if os.path.exists(local_file_path) and os.path.getsize(local_file_path) > 0:
            log.info("download file:%s succeed" % name)
        else:
            log.error("download file:%s failed" % name)
            sys.exit(1)
    cmd = f"ls -lh {wsl_path}"
    _ = os.system(cmd)
    return wsl_path

def upload_file(source_dir):
    """
    upload file to server
    """
    dest_dir = os.path.join("/repo/openeuler", args.target_path)
    cmd = f"scp -i {args.ssh_key} -o StrictHostKeyChecking=no -r {source_dir} root@{args.ipaddr}:{dest_dir}/"
    ret = os.system(cmd)
    if ret == 0:
        log.info("upload file succeed")
    else:
        log.error("upload file failed")


job_url, file_name = build_jenkins_job()
source_dir = download_file(job_url, file_name)
upload_file(source_dir)
