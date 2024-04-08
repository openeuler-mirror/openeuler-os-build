import os
import sys
import time
import threading
import platform
import subprocess
import argparse
import shutil
from concurrent.futures import ThreadPoolExecutor


def kill_yumdownloader(rpm_path, thr):
    cmd = "ls %s | grep '\.rpm'" % rpm_path
    res = os.popen(cmd).read()
    time_old = time.time()
    while not res:
        time.sleep(5)
        res = os.popen(cmd).read()
        time_now = time.time()
        time_differ = int(time_now - time_old)
        if time_differ > 3600:
            break
        if not thr.is_alive():
            break
    cmd = "ps -ef | grep yumdownloader | awk '{print $2}' | xargs kill -9"
    os.system(cmd)


def get_exclude_rpm(repo_name):
    """
    get exclude rpmlist
    """
    exclude_rpmlist = []
    repo_path = os.path.join(os.getcwd(), repo_name)
    if os.path.exists(repo_path):
        shutil.rmtree(repo_path)
    git_url = f"https://gitee.com/src-openeuler/{repo_name}.git"
    if args.project == "openEuler:Mainline":
        branch = "master"
    else:
        branch = args.project.replace(":", "-")
    cmd = "git clone --depth 1 %s -b %s" % (git_url, branch)
    if os.system(cmd) != 0:
        print("Git clone oemaker failed!")
        sys.exit(1)
    else:
        print("Git clone oemaker success!")
    cmd = "xmllint --xpath \"//packagelist[@type='exclude']/node()\" %s/rpmlist.xml \
            | grep packagereq | cut -d '>' -f 2 | cut -d '<' -f 1" % repo_path
    ret = os.popen(cmd).read().split('\n')
    exclude_rpmlist = [ x for x in ret if x != "" ]
    shutil.rmtree(repo_path)
    print("oemaker rpmlist.xml exclude rpm:%s" % exclude_rpmlist)
    return exclude_rpmlist

def set_rpm_list(rpm_list_file, arch, rpm_path, config=None, repo=None):
    if config and repo:
        para = "-c %s --repo %s" % (config, repo)
    elif config:
        para = "-c %s" % config
    else:
        para = "" 
    cmd = "yum list --installroot=%s --available %s | grep -E '\.%s|\.noarch' | grep -v 'debugsource' | grep -v 'debuginfo'| awk '{print $1 \" \" $2 \" \" $1 \"-\" $2}' > %s" % (rpm_path, para, arch, rpm_list_file)
    print(cmd)
    if os.system(cmd) == 0:
        cmd = "sed -i 's/\.{0}-/-/g' {1} && sed -i 's/\.noarch-/-/g' {2}".format(arch, rpm_list_file, rpm_list_file)
        if os.system(cmd) == 0:
            pass
        else:
            return 1
    else:
        return 1
    return 0


def set_exclude(f, arch, err, rpm_list_file, delete_rpm_list_file):
    rpm_list = []
    print("--------------------------------------------------------------")
    for line in err.splitlines():
        if "requires" in line:
            print(line)
            f.write("%s\n" % line)
            if " package " in line:
                pkg = line.split(" package ")[1].split("requires")[0].strip()
                if pkg not in rpm_list:
                    rpm_list.append(pkg)
        if "needed by" in line:
            print(line)
            f.write("%s\n" % line)
            pkg = line.split("needed by")[1].strip()
            if pkg not in rpm_list:
                rpm_list.append(pkg)
        if "obsoletes" in line:
            print(line)
            f.write("%s\n" % line)
            pkg = line.split("provided by")[1].strip()
            if pkg not in rpm_list:
                rpm_list.append(pkg)
    for p in rpm_list:
        if "noarch" in p:
            pkg = p.replace(".noarch", "")
        if arch in p:
            pkg = p.replace(".%s" % arch, "")
        cmd = "cat %s | grep %s | awk '{print $1}' >> %s && sed -i '/%s/d' %s" % (rpm_list_file, pkg, delete_rpm_list_file, \
                pkg, rpm_list_file)
        if os.system(cmd) == 0:
            pass
        else:
            print("======== unable install %s" % p)


def check_dep(rpm_list_file, check_log_file, delete_rpm_list_file, rpm_path, config=None, repo=None):
    if config and repo:
        if "Epol" in repo:
            para = "-c %s --repo obs-standard,%s" % (config, repo)
        elif "multi_version" in repo:
            para = "-c %s --repo obs-standard,obs-Epol,%s" % (config, repo)
        else:
            para = "-c %s --repo %s" % (config, repo)
    elif config:
        para = "-c %s" % config
    else:
        para = ""
    cmd = "rm -rf %s && rm -rf %s && rm -rf %s && rm -rf %s/*.rpm && touch %s" % (rpm_list_file, check_log_file, delete_rpm_list_file, rpm_path, delete_rpm_list_file)
    if os.system(cmd) == 0:
        pass
    arch = platform.machine()
    if set_rpm_list(rpm_list_file, arch, rpm_path, config=config, repo=repo):
        sys.exit(1)
    delete_list = []
    time_old = time.time()
    cmd="yumdownloader --resolve --installroot=%s --destdir=%s $(cat %s | awk '{print $1}' | tr '\n' ' ') %s" % (rpm_path, rpm_path, rpm_list_file, para)
    p=subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8")
    out, err = p.communicate()
    with open(check_log_file, 'w') as f:
        while err:
            if "Problem" not in err and "No package" not in err:
                break
            set_exclude(f, arch, err, rpm_list_file, delete_rpm_list_file)

            time_now = time.time()
            time_differ = int(time_now - time_old)
            if time_differ > 3600:
                break

            cmd="yumdownloader --resolve --installroot=%s --destdir=%s $(cat %s | awk '{print $1}' | tr '\n' ' ') %s" % (rpm_path, rpm_path, rpm_list_file, para)
            p=subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8")
            out, err = p.communicate()
    cmd = "sed -i 's/\.noarch//g' %s && sed -i 's/\.%s//g' %s" % (delete_rpm_list_file, arch, delete_rpm_list_file)
    if os.system(cmd) == 0:
        pass
    if ":Epol" not in args.project:
        repo_name = "oemaker"
        exclude_rpmlist = get_exclude_rpm(repo_name)
        if exclude_rpmlist:
            with open(args.exclude_rpm_list_file, "r") as f:
                res = f.read().splitlines()
                delete_rpm_list = [x for x in res if x != '']
            if delete_rpm_list:
                with open(args.exclude_rpm_list_file, "w") as f:
                    for rpm in delete_rpm_list:
                        if rpm not in exclude_rpmlist:
                            f.write(rpm)
                            f.write("\n")
    print("=================== exclude rpm list start ======================")
    print(os.popen("cat %s && rm -rf %s/*.rpm" % (delete_rpm_list_file, rpm_path)).read())
    print("=================== exclude rpm list end ======================")


def get_pkg_rpms(pkg, arch, pkg_rpms_list):
    """
    get a package all rpms
    """
    cmd = f"osc ls -b {args.project} {pkg} standard_{arch} {arch} 2>/dev/null | grep rpm"
    res = os.popen(cmd).read().split()
    rpm_list = [x for x in res if x != '']
    new_rpm_list = []
    if rpm_list:
        for rpm in rpm_list:
            if rpm.endswith(".src.rpm"):
                rpm_name = rpm
            else:
                rpm_name = rpm.rsplit("-", 2)[0]
            new_rpm_list.append(rpm_name)
        pkg_rpms_list.append(new_rpm_list)

def set_exclude_pkg_all_rpms():
    """
    get all rpms of exclude rpm list and source rpms
    """
    with open(args.exclude_rpm_list_file, "r") as f:
        file_content = f.read().strip().splitlines()
    cmd = f"rm -f {args.final_exclude_rpm_list_file} {args.final_source_exclude_rpm_list_file} && touch {args.final_exclude_rpm_list_file} {args.final_source_exclude_rpm_list_file}"
    if os.system(cmd) == 0:
        pass
    if file_content:
        print("============ start search all rpms of exclude rpm list ===========")
        pkg_rpms_list = []
        arch = platform.machine()
        cmd = f"osc list {args.project} 2>/dev/null"
        res = os.popen(cmd).read().split()
        pkglist = [x for x in res if x != '']
        with ThreadPoolExecutor(100) as executor:
            for pkg in pkglist:
                executor.submit(get_pkg_rpms, pkg, arch, pkg_rpms_list)
        final_rpms_list = []
        rpms_reason_dict = {}
        for rpms in pkg_rpms_list:
            err_rpm_list = []
            for rpm in rpms:
                if rpm in file_content:
                    if rpm not in final_rpms_list:
                        final_rpms_list.extend(rpms)
                    err_rpm_list.append(rpm)
            if err_rpm_list:
                rpms_reason_dict.setdefault("install_problem", []).extend(err_rpm_list)
                rpms_reason_dict.setdefault("other_rpm_install_problem", []).extend(list(set(rpms) - set(err_rpm_list)))
        not_find = list(set(file_content) - set(final_rpms_list))
        if not_find:
            rpms_reason_dict.setdefault("install_problem", []).extend(not_find)
            final_rpms_list.extend(not_find)
        if final_rpms_list:
            f1 = open(args.final_exclude_rpm_list_file, "w")
            f2 = open(args.final_source_exclude_rpm_list_file, "w")
            for rpm in final_rpms_list:
                if rpm.endswith(".src.rpm"):
                    f2.write(rpm.rsplit("-", 2)[0])
                    f2.write("\n")
                else:
                    f1.write(rpm)
                    f1.write("\n")
            f1.close()
            f2.close()
        print("二进制包:")
        print(os.popen(f"cat {args.final_exclude_rpm_list_file}").read())
        print("源码包:")
        print(os.popen(f"cat {args.final_source_exclude_rpm_list_file}").read())
        print("============ end search all rpms of exclude rpm list ============")
        print("============ start reason for exclude rpm list ============")
        if rpms_reason_dict:
            for key, value in rpms_reason_dict.items():
                for rpm in value:
                    if rpm.endswith(".src.rpm"):
                        rpm_name = rpm.rsplit("-", 2)[0]
                        rpm_type = "源码包\t"
                    else:
                        rpm_name = rpm
                        rpm_type = "二进制包"
                    if key == "install_problem":
                        msg = "校验安装失败\t\t\t\t%s\t\t%s" % (rpm_type, rpm_name)
                    if key == "other_rpm_install_problem":
                        msg = "对应软件包其它二进制安装失败\t\t%s\t\t%s" % (rpm_type, rpm_name)
                    print(msg)
        print("============ end reason for exclude rpm list ==============")

par = argparse.ArgumentParser()
par.add_argument("-d", "--dest_rpm_path", help="path for rpm", required=True)
par.add_argument("-l", "--rpm_list_file", help="file for rpm list", required=True)
par.add_argument("-f", "--check_log_file", help="file for checking log", required=True)
par.add_argument("-e", "--exclude_rpm_list_file", help="file for rpms which are exclude", required=True)
par.add_argument("-c", "--config", help="config file repofile", default=None, required=False)
par.add_argument("-r", "--repo", help="name of repo", default=None, required=False)
par.add_argument("-sea", "--set_exclude_all_rpms", help="set all rpms of exclude package", default=None, required=False)
par.add_argument("-fe", "--final_exclude_rpm_list_file", help="file for all rpms which are exclude", required=False)
par.add_argument("-fes", "--final_source_exclude_rpm_list_file", help="file for source rpms which are exclude", required=False)
par.add_argument("-p", "--project", help="name of obs project", default=None, required=True)
args = par.parse_args()

t1 = threading.Thread(target=check_dep, args=(args.rpm_list_file, args.check_log_file, args.exclude_rpm_list_file, args.dest_rpm_path, args.config, args.repo))
t1.start()
t2 = threading.Thread(target=kill_yumdownloader, args=(args.dest_rpm_path, t1))
t2.start()
t1.join()
t2.join()
if args.set_exclude_all_rpms:
    set_exclude_pkg_all_rpms()
