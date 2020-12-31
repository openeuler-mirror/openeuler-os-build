#!/bin/bash
# Author: liusirui
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e
#******************************
# bep_clean_files
#******************************
function bep_clean_files()
{
    cat bep_clean.conf | while read files;do
        [ -n "$files" ] && echo > "$files"
    done
}

#******************************
# bep_remove_files
#******************************
function bep_remove_files()
{
    set +e
    cat bep_remove.conf | while read files;do
        wildcard="$(echo "$files" | grep "*")"
        if [ -n "$wildcard" ];then
            tmp_file="$(echo "$files" | sed 's/*//g')"
            [ -n "$tmp_file" ] && rm -rf "$tmp_file"*
        else
            [ -n "$files" ] && rm -rf "$files"
        fi
    done
    set -e
}

bep_remove_files
bep_clean_files
exit 0
