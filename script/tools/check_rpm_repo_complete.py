#!/bin/env python3

import os
import sys
import csv
import yaml
import argparse
import shutil
from concurrent.futures import ThreadPoolExecutor


par = argparse.ArgumentParser()
par.add_argument("-c", "--config", help="config file for repo", default=None, required=True)
par.add_argument("-r", "--repo", help="name of repo", default=None, required=True)
par.add_argument("-p", "--project", help="name of project", default=None, required=True)
par.add_argument("-f", "--logfile", help="not in repo rpm list file", default=None, required=True)
par.add_argument("-rf", "--resultfile", help="check result csv file", default=None, required=True)
args = par.parse_args()


def git_clone(git_url, repo_name, branch):
    """
    git clone gitee repo
    """
    repo_path = os.path.join(os.getcwd(), repo_name)
    if os.path.exists(repo_path):
        shutil.rmtree(repo_path)
    cmd = "git clone --depth 1 %s -b %s" % (git_url, branch)
    if os.system(cmd) != 0:
        print("Git clone %s failed!" % repo_name)
        sys.exit(1)
    else:
        print("Git clone %s success!" % repo_name)
    return repo_path

def get_release_pkg_list():
    """
    get release pkg list
    """
    release_pkglist = []
    repo_name = "release-management"
    git_url = f"https://gitee.com/openeuler/{repo_name}.git"
    repo_path = git_clone(git_url, repo_name, "master")
    if args.project == "openEuler:Mainline":
        branch = "master"
    elif args.project.endswith(":Epol"):
        branch = args.project.replace(":Epol", "").replace(":", "-")
        path_name = ["epol"]
    else:
        branch = args.project.replace(":", "-")
        path_name = ["baseos", "everything-exclude-baseos"]
    for name in path_name:
        yaml_path = os.path.join(repo_path, branch, name, "pckg-mgmt.yaml")
        if os.path.exists(yaml_path):
            with open(yaml_path, "r", encoding="utf-8") as f:
                result = yaml.load(f, Loader=yaml.FullLoader)
            for pckg in result['packages']:
                if pckg['name'] not in release_pkglist:
                    release_pkglist.append(pckg['name'])
    shutil.rmtree(repo_path)
    return release_pkglist

def get_exclude_rpm_list():
    """
    get oemaker exclude rpm list
    """
    exclude_rpmlist = []
    if args.project == "openEuler:Mainline" or args.project == "openEuler:Epol":
        branch = "master"
    elif args.project.endswith(":Epol"):
        branch = args.project.replace(":Epol", "").replace(":", "-")
    else:
        branch = args.project.replace(":", "-")
    repo_name = "oemaker"
    git_url = f"https://gitee.com/src-openeuler/{repo_name}.git"
    repo_path = git_clone(git_url, repo_name, branch)
    cmd = "xmllint --xpath \"//packagelist[@type='exclude']/node()\" %s/rpmlist.xml \
            | grep packagereq | cut -d '>' -f 2 | cut -d '<' -f 1" % repo_path
    ret = os.popen(cmd).read().split('\n')
    exclude_rpmlist = [ x for x in ret if x != "" ]
    shutil.rmtree(repo_path)
    print("oemaker rpmlist.xml exclude rpm:%s" % exclude_rpmlist)
    return exclude_rpmlist

def get_repo_rpm_list():
    """
    get repo all rpms
    """
    tmp_path = "/tmp/_repo_rpm"
    if os.path.exists(tmp_path):
        shutil.rmtree(tmp_path)
    cmd = "yum list --installroot=%s --available -c %s --repo %s | grep %s | awk '{print $1,$2}'" % (tmp_path, args.config, args.repo, args.repo)
    output = os.popen(cmd).read().split('\n')
    result = [ x for x in output if x != "" ]
    if result:
        del(result[0])
    repo_rpm_list = []
    repo_rpm_detail = []
    arch_list = [".aarch64", ".x86_64", ".noarch", ".src"]
    for line in result:
        tmp_dict = {}
        tmp = line.split()
        for arch in arch_list:
            if arch in tmp[0]:
                new_tmp = tmp[0].split(arch)
                name = new_tmp[0]
                if ":" in tmp[1]:
                    version = tmp[1].split(":")[1]
                else:
                    version = tmp[1]
                rpm_name = f"{name}-{version}{arch}.rpm"
                break
        if rpm_name not in repo_rpm_list:
            repo_rpm_list.append(rpm_name)
        tmp_dict["name"] = name
        tmp_dict["version"] = version
        tmp_dict["arch"] = arch
        repo_rpm_detail.append(tmp_dict)
    return repo_rpm_list, repo_rpm_detail

def get_pkg_rpms(pkg, arch, pkg_rpm_list, pkg_rpm_dict):
    """
    get a package all rpm
    """
    cmd = f"osc ls -b {args.project} {pkg} standard_{arch} {arch} 2>/dev/null | grep rpm"
    rpm_list = os.popen(cmd).read().split()
    new_rpm_list = [rpm for rpm in rpm_list if rpm != '']
    if new_rpm_list:
        pkg_rpm_list.extend(new_rpm_list)
        pkg_rpm_dict[pkg] = new_rpm_list

def get_release_all_pkg_rpms(release_pkg_list):
    """
    get rpms of all pkg
    """
    pkg_rpm_list = []
    pkg_rpm_dict = {}
    cmd = "arch"
    arch = os.popen(cmd).read().strip()
    with ThreadPoolExecutor(100) as executor:
        for pkg in release_pkg_list:
            executor.submit(get_pkg_rpms, pkg, arch, pkg_rpm_list, pkg_rpm_dict)
    return pkg_rpm_list, pkg_rpm_dict

def delete_exclude_rpm(not_in_repo_rpm):
    """
    delete exclude rpm
    """
    final_rpm = []
    if not args.project.endswith(":Epol"):
        exclude_rpmlist = get_exclude_rpm_list()
        if exclude_rpmlist:
            for repo_rpm in not_in_repo_rpm:
                rpm_name = repo_rpm.rsplit("-", 2)[0]
                if rpm_name not in exclude_rpmlist:
                    final_rpm.append(repo_rpm)
    else:
        final_rpm = not_in_repo_rpm
    return final_rpm

def write_file(result):
    if os.path.exists(args.logfile):
        with open(args.logfile, "w") as f:
            for line in result:
                f.write(line)
                f.write("\n")

def write_csv(header, data):
    with open(args.resultfile, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, header)
        writer.writeheader()
        writer.writerows(data)

def check_repo_complete():
    """
    check project all pkg rpm equal repo all rpm
    """
    print("========== start check release package rpm in repo ==========")
    release_pkg_list = get_release_pkg_list()
    all_pkg_rpm_list, all_pkg_rpm_dict = get_release_all_pkg_rpms(release_pkg_list)
    print("all_pkg_rpm_list:%s" % all_pkg_rpm_list)
    repo_rpm_list, repo_rpm_detail = get_repo_rpm_list()
    print("repo_rpm_list:%s" % repo_rpm_list)
    not_in_repo_rpm = list(set(all_pkg_rpm_list) - set(repo_rpm_list))
    print("total of all_pkg_rpm_list:", len(all_pkg_rpm_list))
    print("total of repo_rpm_list:", len(repo_rpm_list))
    if not_in_repo_rpm:
        final_result = delete_exclude_rpm(not_in_repo_rpm)
        print("[FAILED] some package rpm not in repo without exclude rpm")
        print("total of different:", len(final_result))
        print("Error_type\t\tPackage_name\t\tRpm_Type\t\tOBS\t\t\t\t\t\tEBS")
        if final_result:
            write_file(final_result)
            data = []
            for err_rpm in final_result:
                in_repo_rpm = ""
                package_name = None
                tmp = {}
                if ".src.rpm" in err_rpm:
                    rpm_type = "source_rpm"
                else:
                    rpm_type = "binary_rpm"
                for pkg, rpms in all_pkg_rpm_dict.items():
                    if err_rpm in rpms:
                        package_name = pkg
                        break
                name = err_rpm.rsplit("-", 2)[0]
                for repo_rpm in repo_rpm_detail:
                    if name == repo_rpm["name"] and repo_rpm["arch"] in err_rpm:
                        error_type = "version_different"
                        in_repo_rpm = f"{repo_rpm['name']}-{repo_rpm['version']}{repo_rpm['arch']}.rpm"
                        break
                if in_repo_rpm:
                    ebs = in_repo_rpm
                else:
                    error_type = "not_find_in_repo"
                    ebs = "None"
                tmp["error_type"] = error_type
                tmp["package_name"] = package_name
                tmp["rpm_type"] = rpm_type
                tmp["OBS"] = err_rpm
                tmp["EBS"] = ebs
                data.append(tmp)
                print("\t".join(tmp.values()))
            header = ["error_type", "package_name", "rpm_type", "OBS", "EBS"]
            write_csv(header, data)
    else:
        print("[SUCCESS] all package rpm in repo")
    print("========== end check release package rpm in repo ==========")


check_repo_complete()
