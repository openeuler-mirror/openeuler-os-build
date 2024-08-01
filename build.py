#!/usr/bin/env python
# -*- coding=utf-8 -*-
# EulerOS build main file
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
"""
make image
"""
import os
import sys
from log import log_init
from utils import rm, trace_execute

CUR_DIR = os.path.dirname(os.path.realpath(__file__))
PARAMS = ['all', 'set_release_dir', 'update_release_info', 'build_and_wait', 'make_tar', 'make_hmi',
          'make_iso', 'make_docker_image', 'make_raspi_image', 'make_microvm_image', 'make_compile_env_cross',
          'make_compile_env_cross_storage', 'make_iso_debug', 'make_livecd', 'make_compile_env',
          'make_compile_env_storage', 'make_euleros_certdb', 'make_vm_qcow2', 'make_compile_tools', 'make_images_slim',
          'make_tools_lib_storage', 'make_container_tools', 'make_tools_debug_tools', 'make_upgrade_patch',
          'make_tools_dockertools', 'make_other_tools', 'upload_to_cmc', 'make_upload_cmc_image', 'make_iso_everything',
          'make_iso_everysrc', 'make_debug_everything', 'push_lts_dir', 'make_netinst_iso', 'get_epol_rpms', 'make_edge_iso', 'make_desktop_iso', 'make_riscv64_qemu_image']


class Build(object):
    """
    build
    """
    version = ""
    obs_ip = ""
    local_dist_dir = ""
    local_build_shell_path = ""
    local_project_path = ""
    env = os.environ.copy()

    def __init__(self):
        """
        初始化构建过程中需要用到的本地目录和构建所需要的参数
        """
        self.init_dir()

    def init_dir(self):
        """
        初始化构建过程中需要用到的本地目录
        """
        self.local_project_path = os.path.join(CUR_DIR, "..", "..")
        self.local_dist_dir = os.path.join(CUR_DIR, "..", "output")
        self.local_build_shell_path = os.path.join(
            CUR_DIR, "script", "make_version.sh")
        return True

    def prepare_env(self, logger):
        """
        注入shell构建脚本所需要的环境变量
        @param logger: for log handle
        """
        logger.info("*   start  prepare_env  *")
        self.env["MYVERSION"] = self.version
        self.env["OUTPUT_PATH"] = self.local_dist_dir
        self.env["PROJECT_PATH"] = self.local_project_path
        self.env["ISCI"] = "0"
        return True

    def set_obs_project(self, standard_prj, standard_prj_repo, epol_prj_repo, check_dep):
        """
        standard_prj:
        standard_prj_repo:
        epo_prj_repo:
        """
        cmd = "sed -i 's/STANDARD_PROJECT=.*/STANDARD_PROJECT=%s/g' script/setup_env.sh" % standard_prj
        rmsg = os.popen(cmd).read()
        print(rmsg)
        cmd = "perl -pi -e 's#STANDARD_PROJECT_REPO=.*#STANDARD_PROJECT_REPO=%s#g' script/setup_env.sh" % standard_prj_repo
        rmsg = os.popen(cmd).read()
        print(rmsg)
        cmd = "perl -pi -e 's#EPOL_PROJECT_REPO=.*#EPOL_PROJECT_REPO=%s#g' script/setup_env.sh" % epol_prj_repo
        rmsg = os.popen(cmd).read()
        print(rmsg)
        cmd = "sed -i 's/checkdep=.*/checkdep=%s/g' script/setup_env.sh" % check_dep
        rmsg = os.popen(cmd).read()
        print(rmsg)

    def clean(self):
        """
        清空构建目录
        """
        print("start clean output dir")
        rm(os.path.join(self.local_dist_dir, "*"))
        rm(os.path.join(CUR_DIR, "__pycache__"))
        rm(os.path.join(CUR_DIR, "*.pyc"))
        print("end")
        return 0

    def build(self, step=None):
        """
        执行本地构建
        @param step: 本地构建步骤名，详情参考使用说明
        """
        self.clean()

        logger = log_init()
        if not self.prepare_env(logger):
            return -1

        if step:
            cmd = 'echo "export STEP=%s" >> script/setup_env.sh' % step
            if os.system(cmd) != 0:
                logger.error("build fail")
                return -1
            cmd = "bash -x reset_release_server_ip.sh"
            if os.system(cmd) != 0:
                logger.error("build fail")
                return -1
            code = trace_execute("bash {0} {1}".format(
                self.local_build_shell_path, step), env=self.env, logger=logger)
            if code != 0 and code != "0":
                logger.error("build fail")
                return -1
            else:
                logger.info("build success")
                return 0
        else:
            logger.error("step be required")
            return -1


def usage():
    """
    build 使用说明
    """
    print(" zero or one parameter be needed   ")
    print("***********************************")
    print("*   usage for this build script   *")
    print("*                                 *")
    print("* build.py COMMAND                *")
    print("*                                 *")
    print("* Commands:                       *")
    print("* all                     default *")
    print("* clean                           *")
    print("* set_release_dir                 *")
    print("* get_epol_rpms                   *")
    print("* make_iso                        *")
    print("* make_edge_iso                   *")
    print("* make_desktop_iso                *")
    print("* make_netinst_iso                *")
    print("* make_iso_everysrc               *")
    print("* make_iso_everything             *")
    print("* make_debug_everything           *")
    print("* make_hmi                        *")
    print("* make_raspi_image                *")
    print("* make_docker_image               *")
    print("* make_microvm_image              *")
    print("* make_riscv64_qemu_image         *")
    print("*                                 *")
    print("***********************************")
    return -1


if __name__ == "__main__":
    import argparse
    par = argparse.ArgumentParser()
    par.add_argument("-i", "--step_info",
                     help="what you want to do", required=True)
    par.add_argument("-sp", "--standard_prj",
                     help="standard project", required=True)
    par.add_argument("-spr", "--standard_prj_repo",
                     help="standard project repo", required=True)
    par.add_argument("-epr", "--epol_prj_repo",
                     help="epol project repo", required=True)
    par.add_argument("-c", "--check_dep", default="false",
                     help="check rpm dependence", required=False)
    args = par.parse_args()

    build = Build()
    build.set_obs_project(args.standard_prj,
                          args.standard_prj_repo, args.epol_prj_repo,
                          args.check_dep)
    one_step = args.step_info
    if one_step == "clean":
        ret = build.clean()
    elif one_step not in PARAMS:
        ret = usage()
    else:
        ret = build.build(one_step)
    exit(ret)
