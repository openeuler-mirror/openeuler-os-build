#!/bin/bash
# Author: sync DevStation build artifacts from EBS-openEuler-26.09 to EBS-openEuler-26.09-DevStation
# Usage: bash sync_devstation.sh
# Prerequisites:
#   1. SSH key-based access to the release server
#   2. EBS-openEuler-26.09 dailybuild with DevStation/ISO and DevStation/virtual_machine_img exists
#   3. EBS-openEuler-26.09-DevStation dailybuild directory has been created (release_tmp exists)
#
# Note: openeuler_ARM64 and openeuler_X86 release_tmp point to the same dailybuild directory,
#       so we only need to read one of them and copy once.

set -e

######################
# Configuration - modify as needed
######################
RELEASE_SERVER_IP="${RELEASE_SERVER_IP:-172.16.1.43}"
RELEASE_SERVER_PORT="${RELEASE_SERVER_PORT:-30322}"
SSH_KEY="${SSH_KEY:-~/.ssh/super_publish_rsa}"
HTTP_DIR="${HTTP_DIR:-/repo/openeuler/dailybuild}"
RELEASE_HTTP_URL="${RELEASE_HTTP_URL:-http://121.36.84.172/dailybuild}"

SOURCE_PRE_VERSION="EBS-openEuler-26.09"
TARGET_PRE_VERSION="EBS-openEuler-26.09-DevStation"

# DevStation subdirectories to merge from source into target
SUBDIRS=("ISO" "virtual_machine_img")

######################
# SSH options
######################
if [ -n "${RELEASE_SERVER_PORT}" ]; then
    SSH_OPTS="-p ${RELEASE_SERVER_PORT}"
else
    SSH_OPTS=""
fi
SSH_CMD="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_OPTS} root@${RELEASE_SERVER_IP}"

######################
# Helper functions
######################
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
    exit 1
}

# Get latest dailybuild directory from remote release_tmp file
# Arguments: $1 = PRE_VERSION
get_latest_build_dir() {
    local pre_version=$1
    local release_tmp_path="${HTTP_DIR}/${pre_version}/openeuler_ARM64/release_tmp"
    local build_dir

    log_info "Reading ${release_tmp_path}"
    build_dir=$(${SSH_CMD} "cat '${release_tmp_path}'" 2>/dev/null) || true
    if [ -z "${build_dir}" ]; then
        log_error "Failed to read ${release_tmp_path}. Does the dailybuild exist for ${pre_version}?"
    fi
    echo "${build_dir}"
}

######################
# Main
######################
log_info "=== Starting DevStation artifact sync ==="
log_info "Source: ${SOURCE_PRE_VERSION}"
log_info "Target: ${TARGET_PRE_VERSION}"

SOURCE_DIR=$(get_latest_build_dir "${SOURCE_PRE_VERSION}")
TARGET_DIR=$(get_latest_build_dir "${TARGET_PRE_VERSION}")
log_info "Source build dir: ${SOURCE_DIR}"
log_info "Target build dir: ${TARGET_DIR}"

# Verify source DevStation directory exists
if ! ${SSH_CMD} "[ -d '${SOURCE_DIR}/DevStation' ]" 2>/dev/null; then
    log_error "Source DevStation directory not found: ${SOURCE_DIR}/DevStation"
fi
log_info "Source DevStation directory verified: ${SOURCE_DIR}/DevStation"

# Step 1: Copy DevStation subdirectories into target
for subdir in "${SUBDIRS[@]}"; do
    SRC_SUBDIR="${SOURCE_DIR}/DevStation/${subdir}"
    DST_SUBDIR="${TARGET_DIR}/${subdir}"

    if ! ${SSH_CMD} "[ -d '${SRC_SUBDIR}' ]" 2>/dev/null; then
        log_info "Warning: ${SRC_SUBDIR} not found, skipping"
        continue
    fi

    ${SSH_CMD} "mkdir -p '${DST_SUBDIR}'"
    log_info "Copying ${SRC_SUBDIR}/ -> ${DST_SUBDIR}/"
    ${SSH_CMD} "cp -a '${SRC_SUBDIR}/'* '${DST_SUBDIR}/'"

    SRC_COUNT=$(${SSH_CMD} "ls -1 '${SRC_SUBDIR}' 2>/dev/null | wc -l" 2>/dev/null) || true
    DST_COUNT=$(${SSH_CMD} "ls -1 '${DST_SUBDIR}' 2>/dev/null | wc -l" 2>/dev/null) || true
    log_info "Copied: source has ${SRC_COUNT} items, target now has ${DST_COUNT} items"
done

# Step 2: Write release_iso_DevStation and release_everything_DevStation
#         for both openeuler_ARM64 (aarch64) and openeuler_X86 (x86_64)
sub_dir="${TARGET_DIR#${HTTP_DIR}/}"
log_info ""
log_info "=== Writing release files ==="

for arch_info in "openeuler_ARM64 aarch64" "openeuler_X86 x86_64"; do
    read -r version_arch iso_arch <<< "${arch_info}"

    # Find DevStation standard DVD ISO (copied from source)
    dev_iso=$(${SSH_CMD} "ls ${TARGET_DIR}/ISO/${iso_arch}/openEuler-*-DevStation-${iso_arch}-dvd.iso 2>/dev/null | head -1") || true
    if [ -n "${dev_iso}" ]; then
        dev_iso_name=$(basename "${dev_iso}")
        dev_iso_url="${RELEASE_HTTP_URL}/${sub_dir}/ISO/${iso_arch}/${dev_iso_name}"
        ${SSH_CMD} "echo '${dev_iso_url}' > '${HTTP_DIR}/${TARGET_PRE_VERSION}/${version_arch}/release_iso_DevStation'; chmod 644 '${HTTP_DIR}/${TARGET_PRE_VERSION}/${version_arch}/release_iso_DevStation'"
        log_info "release_iso_DevStation (${version_arch}): ${dev_iso_url}"
    else
        log_info "Warning: DevStation DVD ISO not found for ${iso_arch}, skipping release_iso_DevStation"
    fi

    # Find DevStation Everything ISO (already built in target)
    everything_iso=$(${SSH_CMD} "ls ${TARGET_DIR}/ISO/${iso_arch}/openEuler-*-DevStation-everything-${iso_arch}-dvd.iso 2>/dev/null | head -1") || true
    if [ -n "${everything_iso}" ]; then
        everything_iso_name=$(basename "${everything_iso}")
        everything_iso_url="${RELEASE_HTTP_URL}/${sub_dir}/ISO/${iso_arch}/${everything_iso_name}"
        ${SSH_CMD} "echo '${everything_iso_url}' > '${HTTP_DIR}/${TARGET_PRE_VERSION}/${version_arch}/release_everything_DevStation'; chmod 644 '${HTTP_DIR}/${TARGET_PRE_VERSION}/${version_arch}/release_everything_DevStation'"
        log_info "release_everything_DevStation (${version_arch}): ${everything_iso_url}"
    else
        log_info "Warning: Everything ISO not found for ${iso_arch}, skipping release_everything_DevStation"
    fi
done

log_info ""
log_info "=== DevStation artifact sync completed ==="
