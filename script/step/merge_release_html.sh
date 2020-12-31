#!/bin/bash
# Author: zhengxuye
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# merge release html 
# Globals:
# Arguments:
# Returns:
######################
function merge_release_html()
{
    set +e
    sshscp_from "${HTTP_DIR}/${PRE_VERSION}/${VERSION}/\*\.html" "./"
    set -e

    dst_html=dst.html
    if ! $(ls release_*.html &> /dev/null);then
        rm -f *.html
        echo "No html is avaliable !" > "${dst_html}"
    else
        cat $(ls release_*.html | head -n 1) > "${dst_html}"
        win_line=$(grep -n "Download on windows" "${dst_html}" | awk -F ':' '{print $1}')
        linux_line=$(grep -n "Download on linux" "${dst_html}" | awk -F ':' '{print $1}')
        ((linux_line="${linux_line}"+1))
        for file in $(ls release_*.html)
        do
            #skip the empty file
            contents=$(cat "${file}")
            if [ "x${contents}" == "x" ];then
                continue
            fi
            #exclude double link
            link=$(cat "${file}" | grep "Download on windows" | awk -F '"' '{print $2}')
            tar_name=${link##*/}
            if cat "${dst_html}" | grep "${tar_name}" &> /dev/null;then
                continue
            fi
            link=$(cat "${file}" | grep "Download on linux" | awk -F '"' '{print $2}')
            tar_name=${link##*/}
            if cat "${dst_html}" | grep "${tar_name}" &> /dev/null;then
                continue
            fi

            #insert new link
            win_link=$(cat "${file}" | grep "Download on windows")
            linux_lik=$(cat "${file}" | grep "Download on linux")
            sed -i "${win_line} a${win_link}" "${dst_html}"
            sed -i "${linux_line} a${linux_lik}" "${dst_html}"
            ((win_line="${win_line}"+1))
            ((linux_line="${linux_line}"+2))
        done
    fi
    CMD="rm -f ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/release_*.html"
    sshcmd "${CMD}"

    cat "${dst_html}" > release.html
    sshscp release.html "${HTTP_DIR}/${PRE_VERSION}/${VERSION}/"
    set +e
    CMD="chmod 755 ${HTTP_DIR}/${PRE_VERSION}/${VERSION}/release.html"
    sshcmd "${CMD}"
    set -e
    chmod_http
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi
    rm -f *.html
}
