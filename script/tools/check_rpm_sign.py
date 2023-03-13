import os
import sys
import shutil
import platform
import argparse
from concurrent.futures import ThreadPoolExecutor


par = argparse.ArgumentParser()
par.add_argument("-r", "--repo", help="repo name for yum", required=True)
args = par.parse_args()

def get_repo_rpmlist():
    bin_rpm = []
    source_rpm = []
    cmd = "yum list --installroot=/tmp/test 2>/dev/null | awk '{print $1}'"
    ret = os.popen(cmd).read().split()
    arch = platform.machine()
    for name in ret:
        if "noarch" in name or arch in name:
            bin_rpm.append(name)
        elif ".src" in name:
            source_rpm.append(name)
        else:
            continue
    return source_rpm, bin_rpm

def download_source_rpm(check_path):
    cmd = "yumdownloader --installroot=/tmp/test --destdir=%s --source \
            `yum list --installroot=/tmp/test | grep '%s' | grep '\.src' \
            | awk '{print $1}' | xargs`" % (check_path, args.repo)
    ret = os.system(cmd)

def download_bin_rpm(check_path):
    cmd = "yumdownloader --installroot=/tmp/test --destdir=%s \
            `yum list --installroot=/tmp/test | grep '%s' | grep -v '\.src' \
            | awk '{print $1}' | xargs`" % (check_path, args.repo)
    ret = os.system(cmd)

def check_rpm_sign(check_path, rpm_name, not_sign_rpm, sign_rpm):
    cmd = f'rpm -Kv {check_path}/{rpm_name} | grep "key ID [a-z0-9]*: OK" >/dev/null'
    ret = os.system(cmd)
    if ret != 0:
        if rpm_name not in not_sign_rpm:
            not_sign_rpm.append(rpm_name)
    else:
        sign_rpm.append(rpm_name)

def check(check_path, rpm_type, not_sign_rpm, sign_rpm):
    if rpm_type == "source": 
        download_source_rpm(check_path)
    else:
        download_bin_rpm(check_path)
    rpms = os.listdir(check_path)
    with ThreadPoolExecutor(100) as executor:
        for rpm in rpms:
            executor.submit(check_rpm_sign, check_path, rpm, not_sign_rpm, sign_rpm)
    shutil.rmtree(check_path)

def check_all_rpm_sign():
    sign_rpm = []
    not_sign_rpm = []
    check_path = "/tmp/check_sign"
    if os.path.exists(check_path):
        shutil.rmtree(check_path)
    source_rpmlist, bin_rpmlist = get_repo_rpmlist()
    print("[INFO]: There are %s source rpm in the repo" % len(source_rpmlist))
    print("[INFO]: There are %s bin rpm in the repo" % len(bin_rpmlist))
    if source_rpmlist:
        check(check_path, "source", not_sign_rpm, sign_rpm)
    if bin_rpmlist:
        check(check_path, "bin", not_sign_rpm, sign_rpm)
    if not_sign_rpm:
        print("[ERROR]: The following rpm is not sign")
        print("\n".join(not_sign_rpm))
        sys.exit(1)
    else:
        print("[INFO]: %s rpms have been signed" % len(sign_rpm))

check_all_rpm_sign()
