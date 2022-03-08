#!/bin/env python3
# -*- encoding=utf8 -*-
#******************************************************************************
# Copyright (c) Huawei Technologging.es Co., Ltd. 2020-2020. All rights reserved.
# licensed under the Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#     http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR
# PURPOSE.
# See the Mulan PSL v2 for more details.
# Author: dongjie
# Create: 2022-03-02
# ******************************************************************************
import os
import sys
import yaml
import requests
import argparse
import logging
from bs4 import BeautifulSoup

LOG_FORMAT = "%(asctime)s - %(filename)s[line:%(lineno)d] - %(levelname)s: %(message)s"
DATE_FORMAT = "%Y-%m-%d %H:%M:%S"
logging.basicConfig(level=logging.DEBUG, format=LOG_FORMAT, datefmt=DATE_FORMAT)


class CheckDailyBuild(object):
    """
    The entrance check for daily build
    """

    def __init__(self, **kwargs):
        """
        kawrgs: dict,init dict by 'a': 'A' style
        rooturl: the daily build page url
        main_branch:choose which branch you need to check
        """
        self.kwargs = kwargs
        self.rooturl = self.kwargs['daily_build_url']
        self.main_branch = self.kwargs['main_branch']
        self.dirflag = self.kwargs['dir_flag']
        self.datebranch = self.kwargs['date_branch']
        self.standard_dir = self.load_standard()

    def html_downloader(self, url):
        """
        download url html content
        """
        user_agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/98.0.4758.102 Safari/537.36'
        headers = {'User-Agent': user_agent}
        r = requests.get(url, headers=headers)
        if r.status_code == 200:
            r.encoding = 'utf-8'
            logging.info("this html page download success！{}".format(url))
            return r.text
        else:
            logging.error("this html page download failed！{}".format(url))
        return ''

    def html_parser(self, url, html_content):
        """
        parse html content
        """
        url_list = []
        soup = BeautifulSoup(html_content, "html.parser")
        tr_content = soup.find_all('tr')
        for line in tr_content:
            td_content = line.find_all('td')
            if td_content:
                dir_url = td_content[0].find('a', href=True)
                size = td_content[1].text
                if dir_url:
                    if dir_url['href'] != '../' and size == '-':
                        url_list.append(url + dir_url['href'])
                    elif dir_url['href'] != '../' and size != '-':
                        if not self.check_is_rpm(dir_url['href']):
                            url_list.append(url + dir_url['href'] + '|ISFILE/')
        return url_list

    def check_is_rpm(self, filename):
        """
        file type filter
        """
        if filename.endswith(".rpm"):
            return True

    def start_check(self, main_branch_url):
        """
        get choose branch need check dir
        """
        dir_map = {}
        html_content = self.html_downloader(main_branch_url)
        if html_content:
            current_dir = self.html_parser(main_branch_url, html_content)
            dir_map[main_branch_url] = []
            for first_dir in current_dir:
                dir_split = first_dir.split('/')[5]
                if dir_split.startswith(self.dirflag):
                    dir_map[main_branch_url].append(first_dir)
        else:
            logging.error(
                "error url can not open,please check your input：{}".format(main_branch_url))
            raise SystemExit("*******PLEASE CHECK YOUR INPUT ARGS*******")
        return dir_map

    def check_every_dir(self, dir_map):
        """
        check choose branch and get every dir compare
        """
        for dir_url, dir_list in dir_map.items():
            if dir_list:
                c_branch = dir_url.split("/")[-2]
                for c_dir in dir_list:
                    origin_dir = c_dir
                    dir_result = self.check_current_dir(c_dir, origin_dir, [])
                    self.compare_standard(dir_result, c_branch, c_dir)

    def check_current_dir(self, c_dir, origin_dir, temp_list):
        try:
            this_page = self.html_downloader(c_dir)
            page_dir = self.html_parser(c_dir, this_page)
            for item in page_dir:
                item_name = item.replace(origin_dir, '')
                if 'ISFILE/' in item_name:
                    item_name = item_name.replace('|ISFILE/', '')
                temp_list.append(item_name)
                if item.split('|')[-1] != 'ISFILE/':
                    self.check_current_dir(item, origin_dir, temp_list)
        except Exception as e:
            logging.info("error url can not open:{}".format(c_dir))
            logging.info("error url can not open:{}".format(e))
        return temp_list

    def load_standard(self):
        """
        read config standard openeuler dir yaml file
        """
        try:
            with open('./standard.yaml', 'r', encoding='utf-8') as f:
                result = yaml.load(f, Loader=yaml.FullLoader)
                return result
        except Exception as e:
            logging.info("error read standard.yaml,please check")

    def compare_standard(self, dir_list, current_branch, c_dir):
        """
        branch dir compare with standard dir
        """
        standard_dir = self.standard_dir
        for key, c_standard in standard_dir.items():
            for current_dir in c_standard:
                if '*' in current_dir:
                    current_dir = current_dir.replace('*', current_branch)
                if current_dir not in dir_list:
                    logging.error(
                        'this dir not found,link url:{}{}'.format(
                            c_dir, current_dir))

    def _get_main_branch(self):
        if self.datebranch:
            dir_map = {}
            complete_key = "{}/{}/".format(self.rooturl, self.main_branch)
            complete_value = "{}/{}/{}/".format(
                self.rooturl, self.main_branch, self.datebranch)
            dir_map[complete_key] = [complete_value]
        else:
            main_branch_url = "{}/{}/".format(self.rooturl, self.main_branch)
            dir_map = self.start_check(main_branch_url)
        self.check_every_dir(dir_map)

    def run(self):
        self._get_main_branch()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dirflag",
        default="openeuler-2022-",
        help="which date branch you want to check,eg:openeuler-2022-03-04-09-22-07")
    parser.add_argument(
        "--rooturl",
        help="daily build page root url,eg:                                                                                                                                                            http://ip/dailybuild")
    parser.add_argument(
        "--branch",
        help="which branch you want to check,eg:openEuler-22.03-LTS")
    parser.add_argument(
        "--datebranch",
        help="which date branch you want to check,eg:openeuler-2022-03-04-09-22-07")
    kw = {
        "daily_build_url": args.rooturl,
        "main_branch": args.branch,
        "date_branch": args.datebranch,
        "dir_flag": args.dirflag
    }
    check = CheckDailyBuild(**kw)
    check.run()
