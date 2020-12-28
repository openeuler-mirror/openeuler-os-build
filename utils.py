#!/usr/bin/env python
# -*- coding:utf8 -*-
# build utils file
# Author: tianfengping yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
import os
import sys
import subprocess
import signal
import re

PY3 = sys.version_info >= (3, 0)


def trace_execute(cmd, cwd=None, env=None, logger=None):
    """
       # 执行shell命令
       @param cmd: 执行命令
       @param cwd: 执行命令对应目录
       @param env: 执行命令环境变量
       @param logger: 日志打印对象
       @return: 0/非0
       """
    p = subprocess.Popen(cmd, cwd=cwd, shell=True, stdout=subprocess.PIPE, env=env)
    return_code = p.poll()
    while True:
        next_line = p.stdout.readline().decode("utf-8", "ignore").strip()
        if next_line == "" and return_code is not None:
            break
        return_code = p.poll()
        if next_line != "" and re.findall(".*ignored\.$",next_line) == []:
            if logger is not None:
                logger.info(next_line)
            else:
                print(next_line)
    return return_code


def execute_shell_cmd_for_exitcode(cmd, cwd=None, log=None, timeout=-1, env=None):
    """
    # 执行shell命令
    @param cmd: 执行命令
    @param cwd: 执行命令对应目录
    @param log: 命令执行日志文件
    @param timeout: 执行命令超时时间(s), -1 -- 不超时
    @param env: 执行命令环境变量
    @return: 0/非0
    """
    exit_code, _, _ = execute_shell_cmd(cmd, cwd, log, timeout, env)
    return exit_code


def execute_shell_cmd_for_output(cmd, cwd=None, log=None, timeout=-1, env=None):
    """
    # 执行shell命令
    @param cmd: 执行命令
    @param cwd: 执行命令对应目录
    @param log: 命令执行日志文件
    @param timeout: 执行命令超时时间(s), -1 -- 不超时
    @param env: 执行命令环境变量
    @return: cmd标准输出内容
    """
    _, output, _ = execute_shell_cmd(cmd, cwd, log, timeout, env)
    return output


def execute_shell_cmd(cmd, cwd=None, log=None, timeout=-1, env=None):
    """
    Execute shell command
    @param cmd: shell command
    @param cwd: current work direction
    @param log: file-like object
    @param timeout: timeout in sec ( -1 --- no timeout)
    @param env: environment variable dict
    @return: (return_code, stdout_data, stderr_data)
    """
    if isinstance(log, int) or hasattr(log, "fileno"):
        std_out, std_err = log, log
    else:
        std_out = subprocess.PIPE
        std_err = subprocess.PIPE
    return execute_cmd(cmd, cwd, shell=True, timeout=timeout, env=env, stderr=std_err, stdout=std_out)


def execute_cmd(args, cwd=None, shell=False, timeout=-1,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=None):
    """
    Execute outer command with a timeout after which it will be forcibly killed.
    @param args: 执行命令
    @param cwd:  执行命令对应目录
    @param shell: 是否为shell命令
    @param timeout: 执行命令超时时间(s), -1 -- 不超时
    @param stdout: 标准输出
    @param stderr: 异常输出
    @param env: 执行命令环境变量
    @return: (return_code, stdout_data, stderr_data)
    """

    class Alarm(Exception):
        pass

    def alarm_handler(signum, frame):
        """
        alarm 信号处理
        @param signum: 信号number
        @param frame:
        @return:
        """
        raise Alarm

    p = subprocess.Popen(args, shell=shell, cwd=cwd,
                         stdin=subprocess.PIPE, stdout=stdout, stderr=stderr, env=env)
    if timeout != -1:
        signal.signal(signal.SIGALRM, alarm_handler)
        signal.alarm(timeout)
    try:
        stdout_data, stderr_data = p.communicate()
        if timeout != -1:
            signal.alarm(0)
        if PY3:
            # python3. process.communicate returns bytes
            stdout_data = str(stdout_data, "utf-8")  # stdoutdata
            stderr_data = str(stderr_data, "utf-8")  # stderrdata
        return_code = p.returncode
        return return_code, stdout_data, stderr_data
    except Alarm:
        pids = [p.pid]
        pids.extend(get_process_children(p.pid))
        for pid in pids:
            # process might have died before getting to this line
            # so wrap to avoid OSError: no such process
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        return -9, None, None


def get_process_children(ppid):
    """
    # 获取一个进程所有子进程
    @param ppid: 进程id
    @return: 子进程list
    """

    def get_children(pid):
        p = subprocess.Popen("ps --no-headers -o pid --ppid {0}".format(pid), shell=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, _ = p.communicate()
        if not stdout.strip():
            return
        for p in stdout.split():
            children_pids.append(int(p))
            get_children(p)

    children_pids = []
    try:
        import psutil
        proc = psutil.Process(int(ppid))
        for child in proc.children(recursive=True):
            children_pids.append(child.pid)
        children_pids.append(int(ppid))
    except ImportError:
        get_children(ppid)
    except:
        pass
    return children_pids


def cp(src, dst):
    """
    file copy
    @param src: source dir/file
    @param dst: destination dir/file
    @return: True/False
    """
    if not src or not dst:
        return False
    stderr = sys.stderr
    stdout = sys.stdout
    p = subprocess.Popen("cp -rf {0} {1}".format(src, dst), shell=True, stderr=stderr, stdout=stdout)
    rt = p.wait()
    return rt == 0


def makedir(path, force=False, logger=None):
    """
    create a directory
    @param path: directory path
    @param logger: var for logger
    @param force: whether remove path if it exists, default false
    """
    if force and os.path.isdir(path):
        rm(path)
    if not os.path.isdir(path):
        try:
            os.makedirs(path)
        except:
            if logger is not None:
                logger.exception("Fatal error in os.makedirs", exc_info=True)
            else:
                print("Fatal error in os.makedirs")


def mv(src, dst):
    """
    mv command
    @param src: 源文件
    @param dst: 目的文件
    """
    # shutil.move(src, dst)
    if not src or not dst:
        return False
    stderr = sys.stderr
    stdout = sys.stdout
    p = subprocess.Popen("mv -f '{0}' '{1}'".format(src, dst), shell=True, stderr=stderr, stdout=stdout)
    rt = p.wait()
    return rt == 0


def rm(path, logger=None):
    """os.unlink and shutil.rmtree replacement"""
    stderr = sys.stderr
    stdout = sys.stdout
    if path == "" or path == "/":
        if logger is not None:
            logger.error("rm -rf path cannot be null or /")
        else:
            print("rm -rf path cannot be null or /")
        exit(1)
    p = subprocess.Popen("rm -rf {0}".format(path), shell=True, stderr=stderr, stdout=stdout)
    rt = p.wait()
    return rt == 0


def is_exist_dir(dir_path):
    """
    @param dir_path: 文件夹目录
    @return: True/False
    """
    return os.path.exists(dir_path)


def is_exist_file(file_path):
    """
    @param file_path: 文件目录
    @return: True/False
    """
    return os.path.isfile(file_path)
