#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e

######################
# make images slim 
# Globals:
# Arguments:
# Returns:
######################
function make_images_slim()
{
    cd "${PROJECT_PATH}"/current/
    IMAGES_SLIM=images-slim.tar.gz
    if [ -f "${IMAGES_SLIM}" ]; then
        rm -rf "${IMAGES_SLIM}"
    fi
    [ -n "IMAGES_SLIM${SHA256SUM}" ] && rm -rf "IMAGES_SLIM${SHA256SUM}"
    # Change file permission mode to meet security needs
    set +e
    chmod 600 image-slim/Dockerfile
    chmod 700 image-slim/image-slim.sh
    chmod 600 image-slim/README
    chmod 600 image-slim/slim.json
    chmod 600 image-slim/slim.repo
    chmod 700 image-slim/slim.sh
    chmod 700 image-slim/tailor-post.sh
    chmod 700 image-slim/tailor.py
    set -e

    # fix bep check
    rm -rf image-slim/.git

    tar czf "${IMAGES_SLIM}" image-slim
    create_checksum "${IMAGES_SLIM}"
    RELEASEDIR=$(get_release_dir)
    RELEASE_DIR="${RELEASEDIR}DockerStack/"
    SSH_CMD="mkdir -p ${RELEASE_DIR}"
    sshcmd "${SSH_CMD}"
    sshscp "${IMAGES_SLIM} ${IMAGES_SLIM}${SHA256SUM}" "${RELEASE_DIR}"
    chmod_http
    if [ $? -ne 0 ]; then
        log_error "Failed in chmod_http"
    fi
    [ -f "${IMAGES_SLIM}" ] && rm -rf "${IMAGES_SLIM}"
    [ -n "IMAGES_SLIM${SHA256SUM}" ] && rm -rf "IMAGES_SLIM${SHA256SUM}"

}
