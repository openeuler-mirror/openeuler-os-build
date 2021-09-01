import os
import sys
import time
import threading
import platform
import subprocess
import argparse


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
            if "package" in line:
                pkg = line.split("package")[1].split("requires")[0].strip()
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
    print("=================== exclude rpm list start ======================")
    print(os.popen("cat %s && rm -rf %s/*.rpm" % (delete_rpm_list_file, rpm_path)).read())
    print("=================== exclude rpm list end ======================")


par = argparse.ArgumentParser()
par.add_argument("-d", "--dest_rpm_path", help="path for rpm", required=True)
par.add_argument("-l", "--rpm_list_file", help="file for rpm list", required=True)
par.add_argument("-f", "--check_log_file", help="file for checking log", required=True)
par.add_argument("-e", "--exclude_rpm_list_file", help="file for rpms which are exclude", required=True)
par.add_argument("-c", "--config", help="config file repofile", default=None, required=False)
par.add_argument("-r", "--repo", help="name of repo", default=None, required=False)
args = par.parse_args()

t1 = threading.Thread(target=check_dep, args=(args.rpm_list_file, args.check_log_file, args.exclude_rpm_list_file, args.dest_rpm_path, args.config, args.repo))
t1.start()
t2 = threading.Thread(target=kill_yumdownloader, args=(args.dest_rpm_path, t1))
t2.start()
