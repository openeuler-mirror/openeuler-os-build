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
# Create: 2022-03-21
# ******************************************************************************

import os
import re
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
    url = "%s/Main-%s-build/lastBuild/buildNumber" % (baseurl, args.branch)
    res = get_requests_result(url)
    lastbuildnumber = res.text
    log.info("Main-%s-build lastbuildnumber:%s" % (args.branch, lastbuildnumber))
    return lastbuildnumber

def get_subjob_url(lastbuildnumber):
    """
    get build job info
    """
    url = "%s/Main-%s-build/%s/console" % (baseurl, args.branch, lastbuildnumber)
    res = get_requests_result(url)
    html = etree.HTML(res.text)
    result = html.xpath('//a[contains(@href, "openEuler-build")]/text()')
    subjob_url_list = []
    short_url_list = []
    for tmp in result:
        if "#" in tmp:
            t = tmp.replace(" #", "/").split()[2]
            if "make_iso/" in t:
                base_iso_url = baseurl + "/" + t + "/consoleFull"
                short_url_list.append(t)
                subjob_url_list.append(base_iso_url)
    return subjob_url_list, short_url_list

def search_source_rpm(bin_rpm):
    """
    search bin rpm source name
    """
    source_rpm = None
    cmd = "dnf repoquery --source %s 2>/dev/null" % bin_rpm
    res = os.popen(cmd).read()
    if res:
        for line in res.split('\n'):
            if "src.rpm" in line:
                source_rpm = res.rsplit('-', 2)[0]
                break
    else:
        log.error("%s failed" % cmd)
    return source_rpm

def check_make_iso_output(subjob_url_list, short_list):
    """
    check iso build log
    """
    final_result = {}
    for surl, url in zip(short_list, subjob_url_list):
        res = get_requests_result(url)
        output = res.text
        result = []
        bin_rpm_list = []
        if re.search("build fail", output):
            log.error("%s build iso fail!" % surl)
            
            # cannot find rpm in obs repo
            re_cp = re.compile(r'cannot find.*in yum repo')
            str_ = re.findall(re_cp, output)
            if str_:
                for s in str_:
                    tmp = {}
                    bin_rpm = s.split(' ')[2]
                    if bin_rpm in bin_rpm_list:
                        continue
                    bin_rpm_list.append(bin_rpm)
                    source_rpm = search_source_rpm(bin_rpm)
                    tmp['type'] = "Not-found-in-obs-repo"
                    tmp['binary'] = bin_rpm
                    tmp['source'] = source_rpm
                    tmp['project'] = args.branch.replace('-', ':')
                    tmp['arch'] = surl.split('-')[2]
                    result.append(tmp)
            
            # install rpm failed
            re_cp = re.compile(r'Problem .*')
            str_ = re.findall(re_cp, output)
            if str_:
                for s in str_:
                    tmp = {}
                    bin_rpm = re.search('package (.*)requires', s).group(1).rsplit('-', 2)[0]
                    if bin_rpm in bin_rpm_list:
                        continue
                    bin_rpm_list.append(bin_rpm)
                    source_rpm = search_source_rpm(bin_rpm)
                    tmp['type'] = "Package-install-problem"
                    tmp['binary'] = bin_rpm
                    tmp['source'] = source_rpm
                    tmp['project'] = args.branch.replace('-', ':')
                    tmp['arch'] = surl.split('-')[2]
                    result.append(tmp)
            
            # exec lorax failed
            re_cp = re.compile(r'mkfs exited with a non-zero return code: 1')
            str_ = re.findall(re_cp, output)
            if str_:
                tmp = {}
                tmp['type'] = "Exec-lorax-fail"
                tmp['binary'] = None
                tmp['source'] = None
                tmp['project'] = args.branch.replace('-', ':')
                tmp['arch'] = surl.split('-')[2]
                result.append(tmp)
            
            final_result.setdefault(surl, result)
        else:
            log.info("%s build iso succeed!" % surl)
    return final_result

def write_email_message(final_result, lastbuildnumber):
    """
    write iso result message
    """
    if final_result:
        log.info(final_result)
        msg = ""
        line = ""
        job_url = ""
        main_job_url = init_url + "/Main-" + args.branch + "-build/" + lastbuildnumber
        for key,value in final_result.items():
            sub_url = init_url + "/" + key
            job_url = job_url + "<h4>Sub job jenkins url: <a href='{0}'>{0}</a></h4>".format(sub_url)
            for tmp in value:
                line = line + """
                <tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>
                """ %(tmp['type'], tmp['binary'], tmp['source'], tmp['project'], tmp['arch'])
        msg = """
        <h2>Hello:</h2>
        <h3>Main job jenkins url: <a href="%s">%s</a></h3>
        %s
        <table border=8>
        <tr><th>ERROR_TYPE</th><th>BINARY_PACKAGE_NAME</th><th>SOURCE_PACKAGE_NAME</th><th>OBS_PROJECT</th><th>ARCHITECTURE</th></tr>
        %s
        </table>
        <p>Please solve it as soon as possible.</p>
        <p>Thanks ~^V^~!!!</p>
        """ % (main_job_url, main_job_url, job_url, line)
    return msg

def send_email(message):
    """
    send email
    """
    msg = MIMEText(message, 'html')
    msg['Subject'] = Header("[%s ISO Build Failed Notice]" % args.branch, "utf-8")
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

if not args.buildnumber:
    lastbuildnumber = get_main_job_last_build()
else:
    lastbuildnumber = args.buildnumber
subjob_url_list, short_list = get_subjob_url(lastbuildnumber)
final_result = check_make_iso_output(subjob_url_list, short_list)
message = write_email_message(final_result, lastbuildnumber)
if message:
    send_email(message)
