#/bin/env python3
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
save update project package info
"""

import os
import sys
import yaml
import argparse

par = argparse.ArgumentParser()
par.add_argument("-p", "--project", default=None,
        help="project name", required=True)
par.add_argument("-ud", "--update_dir", default=None,
        help="update directory name", required=True)
par.add_argument("-tag", "--tag_time", default=None,
        help="tag time name", required=True)
par.add_argument("-ip", "--ipaddr", default=None,
        help="machine ip address", required=True)
par.add_argument("-guser", "--gitee_user", default=None,
        help="gitee user", required=True)
par.add_argument("-gpwd", "--gitee_pwd", default=None,
        help="gitee password", required=True)
args = par.parse_args()

branch = args.project.split(":")[0]
tag_str = branch + "-update-" + args.tag_time


def download_repo():
    """
    download repo 
    """
    tmpdir = os.popen("mktemp -d").read().split("\n")[0]
    repo_name = "openeuler-update-projects"
    repo_path = os.path.join(tmpdir, repo_name)
    for i in range(5):
        cmd = "rm -rf %s && git clone --depth 1 https://%s:%s@gitee.com/compass-ci/%s %s" % \
                (repo_path, args.gitee_user, args.gitee_pwd, repo_name, repo_path)
        if os.system(cmd) == 0:
            break
    if os.path.exists(repo_path):
        return repo_path
    else:
        print("git clone %s failed" % repo_name)
        sys.exit(1)

def get_pkglist():
    """
    get pkglist
    """
    pkglist = []
    file_name = "/tmp/pkglist"
    if os.path.exists(file_name):
        os.remove(file_name)
    url = f"http://{args.ipaddr}/repo.openeuler.org/{branch}/{args.update_dir}/pkglist"
    cmd = f"wget -q -c -O {file_name} {url}"
    if os.system(cmd) != 0:
        print("Exec cmd failed, cmd:%s" % cmd)
        sys.exit(1)
    if os.path.getsize(file_name):
        cmd = f"cat {file_name}"
        result = os.popen(cmd).read().split('\n')
        pkglist = [x for x in result if x != '']
        print("pkglist: %s" % pkglist)
    else:
        print("pkglist is empty")
        sys.exit(1)
    os.remove(file_name)
    return pkglist

def get_project_config():
    """
    get project config
    """
    print("get project config")
    cmd = f"ccb select projects os_project={args.project}"
    result = os.popen(cmd).read()
    if not result:
        print("Exec cmd failed, cmd:%s" % cmd)
        sys.exit(1)
    data = yaml.safe_load(result)
    project_config = data[0]['_source']
    return project_config

def get_package_config(pkglist):
    """
    get package config
    """
    print("get package gitee_url and branch")
    snapshot_id_list = []
    package_repos = []
    cmd = f"ccb select builds os_project={args.project} build_type=full,incremental,specified published_status=4 --sort create_time:desc --size 20 -f snapshot_id"
    res = os.popen(cmd).read()
    if not res:
        print("Exec cmd failed, cmd:%s" % cmd)
        sys.exit(1)
    result = yaml.safe_load(res)
    for data in result:
        snapshot_id = data['_source']['snapshot_id']
        if snapshot_id not in snapshot_id_list:
            snapshot_id_list.append(snapshot_id)
    for snapshot_id in snapshot_id_list:
        if len(package_repos) == len(pkglist):
            break
        cmd = f"ccb select snapshots _id={snapshot_id} -f spec_commits"
        res = os.popen(cmd).read()
        if not res:
            print("Exec cmd failed, cmd:%s" % cmd)
            sys.exit(1)
        result = yaml.safe_load(res)
        spec_commits = result[0]['_source']['spec_commits']
        for pkg in pkglist:
            tmp_dict = {}
            if pkg in spec_commits and pkg not in package_repos:
                pkg_data = spec_commits.get(pkg)
                tmp_dict['spec_name'] = pkg
                tmp_dict['spec_url'] = pkg_data.get('spec_url')
                tmp_dict['spec_branch'] = pkg_data.get('spec_branch')
                package_repos.append(tmp_dict)
    return package_repos

def construct_data(project_config, package_repos):
    """
    construct some data
    """
    config_dict = {}
    config_dict['os_project'] = tag_str
    config_dict['spec_branch'] = project_config['spec_branch']
    config_dict['package_repos'] = package_repos
    config_dict['build_targets'] = project_config['build_targets']
    config_dict['bootstrap_rpm_repo'] = project_config['bootstrap_rpm_repo']
    tmp_str = f"build_tag: {tag_str}\n"
    config_dict['build_env_macros'] = yaml.safe_load(tmp_str + project_config['build_env_macros'])
    return config_dict

def write_yaml_file(repo_path, content):
    print("yaml content:%s" % content)
    update_path = os.path.join(repo_path, args.tag_time)
    if not os.path.exists(update_path):
        os.makedirs(update_path)
    file_name = branch + ".yaml"
    yaml_file = os.path.join(update_path, file_name)
    with open(yaml_file, 'w', encoding='utf-8') as f:
        yaml.dump(content, f, default_flow_style=False, sort_keys=False)

def push_data(repo_path):
    """
    push data to git repo
    """
    try:
        cmd = f"cd {repo_path} && git add * && git commit -m 'update project package info' && git push"
        for i in range(10):
            if os.system(cmd) == 0:
                break
    except AttributeError as e:
        print(e)
    finally:
        cmd = f"rm -rf {repo_path}"
        _ = os.system(cmd)

def save_project_package_data():
    pkglist = get_pkglist()
    package_repos = get_package_config(pkglist)
    project_config = get_project_config()
    content = construct_data(project_config, package_repos)
    repo_path = download_repo()
    write_yaml_file(repo_path, content)
    push_data(repo_path)


save_project_package_data()
