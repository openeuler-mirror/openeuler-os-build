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
# Author: wangchong
# Create: 2022-05-11
# ******************************************************************************

import os
import re
import shutil
import logging
import argparse
import requests
import smtplib
from email.mime.text import MIMEText
from email.header import Header
from lxml import etree
from urllib import parse

logging.basicConfig(level=logging.INFO,
        format="%(asctime)s - %(filename)s[line:%(lineno)d] - %(levelname)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
        )
log = logging.getLogger(__name__)

par = argparse.ArgumentParser()
par.add_argument("-u", "--user", help="jenkins user name", required=True)
par.add_argument("-w", "--passwd", help="jenkins user password", required=True)
par.add_argument("-su", "--server_user", help="email user name", required=True)
par.add_argument("-sw", "--server_passwd", help="email user password", required=True)
par.add_argument("-tu", "--to_addr", help="recive email user", required=True)
par.add_argument("-b", "--branch", help="branch name", required=True)
par.add_argument("-num", "--buildnumber", help="main iso job build number", required=False, default=None)
args = par.parse_args()
args.passwd = parse.quote_plus(args.passwd)

init_url = "https://openeulerjenkins.osinfra.cn/job/openEuler-OS-build/job"
baseurl = "https://%s:%s@openeulerjenkins.osinfra.cn/job/openEuler-OS-build/job" % (args.user, args.passwd)

def git_clone():
    """
    git clone oemaker
    """
    repo_path = os.path.join(os.getcwd(), "oemaker")
    if os.path.exists(repo_path):
        shutil.rmtree(repo_path)
    git_url = "https://gitee.com/src-openeuler/oemaker.git"
    if args.branch == "openEuler-Mainline":
        branch = "master"
    else:
        branch = args.branch
    cmd = "git clone --depth 1 %s -b %s" % (git_url, branch)
    if os.system(cmd) != 0:
        print("Git clone oemaker failed!")
        sys.exit(1)
    return repo_path

def get_exclude_rpm(repo_path):
    """
    get oemaker exclude rpmlist
    """
    cmd = "xmllint --xpath \"//packagelist[@type='exclude']/node()\" %s/rpmlist.xml \
            | grep packagereq | cut -d '>' -f 2 | cut -d '<' -f 1" % repo_path
    ret = os.popen(cmd).read().split('\n')
    exclude_rpmlist = [ x for x in ret if x != "" ]
    shutil.rmtree(repo_path)
    log.info("exclude rpm:%s" % exclude_rpmlist)
    return exclude_rpmlist

def get_requests_result(url):
    """
    follow url get data
    """
    response = requests.get(url)
    if response.status_code != 200:
        log.error(response)
        raise requests.HTTPError("")
    return response

def get_main_job_last_build():
    """
    get jobs last build number
    """
    url = "%s/check-rpm-install-dependence-%s/lastBuild/buildNumber" % (baseurl, args.branch)
    res = get_requests_result(url)
    lastbuildnumber = res.text
    log.info("check-rpm-install-dependence-%s lastbuildnumber:%s" % (args.branch, lastbuildnumber))
    return lastbuildnumber

def get_subjob_url(lastbuildnumber):
    """
    get build job info
    """
    url = "%s/check-rpm-install-dependence-%s/%s/console" % (baseurl, args.branch, lastbuildnumber)
    res = get_requests_result(url)
    html = etree.HTML(res.text)
    result = html.xpath('//a[contains(@href, "check_rpm_install_dependence")]/text()')
    job_url_list = []
    short_job_url = []
    for tmp in result:
        if "#" in tmp:
            t = tmp.replace(" #", "/").split()[2]
            job_url = baseurl + "/" + t + "/consoleFull"
            short_job_url.append(t)
            job_url_list.append(job_url)
    return job_url_list, short_job_url

def parse_msg(subjob_url_list, short_list, exclude_rpmlist):
    """
    parse jenkins job build log
    """
    final_result = {}
    allpkgs = []
    for surl, url in zip(short_list, subjob_url_list):
        pkglist = []
        flag = False
        res = get_requests_result(url)
        output = res.text.split('\n')
        for line in output:
            if "list start" in line:
                flag = True
                continue
            elif "list end" in line:
                break
            if flag:
                if line and line not in exclude_rpmlist:
                    pkglist.append(line)
                    allpkgs.append(line)
        final_result.setdefault(surl, pkglist)
    log.info("Final cannot install rpm:%s" % allpkgs)
    return final_result, allpkgs

def write_email_message(final_result, allpkgs, lastbuildnumber):
    """
    write message
    """
    if final_result:
        log.info(final_result)
        msg = ""
        pkgs = ""
        line = ""
        main_job_url = init_url + "/check-rpm-install-dependence-" + args.branch + "/" + lastbuildnumber + "/console"
        log.info(main_job_url)
        for key,value in final_result.items():
            sub_url = init_url + "/" + key + "/console"
            if "standard_" in key:
                check_item = "ISO"
            else:
                check_item = "Epol"
            if "_aarch64" in key:
                arch = "aarch64"
            else:
                arch = "x86_64"
            line = line + """
            <tr>%s二进制范围<td></td><td>%s</td><td><a href="%s">%s</a></td></tr>
            """ % (check_item, arch, sub_url, sub_url)
        for pkg in list(set(allpkgs)):
            pkgs = pkgs + "%s<br>" %(pkg)
        msg = """
        <h2>Hello:</h2>
        <h3>根据OBS工程repo源检查软件包安装问题，其日志链接如下：</h3>
        <table border=8>
        <tr><th>安装校验项</th><th>架构</th><th>jenkins任务地址</th></tr>
        %s
        </table>
        <p>%s分支的软件包二进制安装失败，列表如下：</p>
        %s
        <p>这些问题会阻塞ISO的构建，请尽快解决，谢谢~^V^~!!!</p>
        """ % (line, args.branch, pkgs)
    return msg

def send_email(message):
    """
    send email
    """
    msg = MIMEText(message, 'html')
    msg['Subject'] = Header("[%s分支软件包二进制安装失败]" % args.branch, "utf-8")
    msg['From'] = Header(args.server_user)
    msg['To'] = Header(args.to_addr)
    smtp_server = "smtp.163.com"
    try:
        server = smtplib.SMTP_SSL(smtp_server)
        server.login(args.server_user, args.server_passwd)
        server.sendmail(args.server_user, args.to_addr.split(','), msg.as_string())
        server.quit()
        log.info("send email succeed!")
    except smtplib.SMTPException as e:
        raise SystemExit("send email failed, reason:%s" % e)

repo_path = git_clone()
exclude_rpmlist = get_exclude_rpm(repo_path)
if not args.buildnumber:
    lastbuildnumber = get_main_job_last_build()
else:
    lastbuildnumber = args.buildnumber
job_url_list, short_job_url = get_subjob_url(lastbuildnumber)
final_result, allrpm = parse_msg(job_url_list, short_job_url, exclude_rpmlist)
message = write_email_message(final_result, allrpm, lastbuildnumber)
if message:
    send_email(message)
