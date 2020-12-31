#!/usr/bin/env python
# -*- coding=utf-8 -*-
# init log file,two ways for log,one is log file other one is console output
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
"""
log
"""
import logging
import os.path
import time

CUR_DIR = os.path.dirname(os.path.realpath(__file__))


def log_init():
    """
    init log handle
    """
    log = logging.getLogger()
    log.setLevel(logging.INFO)

    # set log file location,the file on the output dir
    log_path = os.path.join(os.path.join(CUR_DIR, ".."), "output")
    if not os.path.exists(log_path):
        os.makedirs(log_path)
    # set log format
    formatter = logging.Formatter("%(asctime)s - %(filename)s[line:%(lineno)d] - %(levelname)s: %(message)s")

    # if log file path exist, init log file handler
    if os.path.exists(log_path):
        rq = time.strftime('build', time.localtime(time.time()))
        logfile = os.path.join(log_path, "{0}.log".format(rq))

        # set file handler
        fh = logging.FileHandler(logfile, mode='w')
        fh.setLevel(logging.DEBUG)
        fh.setFormatter(formatter)
        log.addHandler(fh)

    # set console output handler
    ch = logging.StreamHandler()
    ch.setLevel(logging.INFO)
    ch.setFormatter(formatter)
    log.addHandler(ch)

    return log

