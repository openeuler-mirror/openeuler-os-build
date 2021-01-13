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
          'make_iso_everysrc', 'make_debug_everything', 'push_lts_dir', 'make_netinst_iso', 'get_epol_rpms']


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
        if self.env["LOCAL_BUILD"] == "1":
            logger.info("start to set_release_dir")
            code = trace_execute("bash {0} {1}".format(self.local_build_shell_path, "set_release_dir"), env=self.env,
                                 logger=logger)
            if code != 0 and code != "0":
                return False
        return True

    def set_obs_project(self, obs_standard_prj, obs_epol_prj, obs_extras_prj):
        """
        obs_standard_prj:
        obs_epo_prj:
        obs_extras_prj:
        """
        cmd = "sed -i 's/OBS_STANDARD_PROJECT=.*/OBS_STANDARD_PROJECT=%s/g' script/setup_env.sh" % obs_standard_prj
        rmsg = os.popen(cmd).read()
        print(rmsg)
        cmd = "sed -i 's/OBS_EPOL_PROJECT=.*/OBS_EPOL_PROJECT=%s/g' script/setup_env.sh" % obs_epol_prj
        rmsg = os.popen(cmd).read()
        print(rmsg)
        cmd = "sed -i 's/OBS_EXTRAS_PROJECT=.*/OBS_EXTRAS_PROJECT=%s/g' script/setup_env.sh" % obs_extras_prj
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
            code = trace_execute("bash -x {0} {1}".format(
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
    print("* make_tar                        *")
    print("* make_hmi                        *")
    print("* make_iso                        *")
    print("* make_livecd                     *")
    print("* build_and_wait                  *")
    print("* make_iso_debug                  *")
    print("* make_netinst_iso                *")
    print("* make_compile_env                *")
    print("* make_euleros_certdb             *")
    print("* update_release_info             *")
    print("* make_upgrade_patch              *")
    print("* make_docker_image               *")
    print("* make_raspi_image                *")
    print("* make_container_tools            *")
    print("* make_tools_othertools           *")
    print("* make_tools_lib_storage          *")
    print("* make_tools_debug_tools          *")
    print("* get_epol_rpms                   *")
    print("*                                 *")
    print("***********************************")
    return -1


if __name__ == "__main__":
    import argparse
    par = argparse.ArgumentParser()
    par.add_argument("-i", "--step_info",
                     help="what you want to do", required=True)
    par.add_argument("-s", "--obs_standard_prj",
                     help="obs standard project", required=True)
    par.add_argument("-ep", "--obs_epol_prj",
                     help="obs epol project", required=True)
    par.add_argument("-ex", "--obs_extras_prj",
                     help="obs extras project", required=True)
    args = par.parse_args()

    build = Build()
    build.set_obs_project(args.obs_standard_prj,
                          args.obs_epol_prj, args.obs_extras_prj)
    one_step = args.step_info
    if one_step == "clean":
        ret = build.clean()
    elif one_step not in PARAMS:
        ret = usage()
    else:
        ret = build.build(one_step)
    exit(ret)
