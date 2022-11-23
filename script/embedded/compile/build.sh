#!/bin/bash
SCRIPTS_DIR=$(cd $(dirname $0);pwd)
set -x
set -e

set_env()
{
PLATFORM="$1"
SRC_DIR="/usr1/openeuler/src"
[[ -z "${PLATFORM}" ]] && PLATFORM="aarch64-std"
#PLATFORM="qemu-arm"
#PLATFORM="qemu-aarch64"
BUILD_DIR="${SRC_DIR}/build/build-${PLATFORM}"
if [ "$(whoami)" == "root" ];then
    useradd -m openeuler || echo ""
    username="openeuler"
    chown -R ${username}:users "${SRC_DIR}"
fi
chown -R ${username}:users "${SRC_DIR}"
ROOTFS_DIR="/usr1/openeuler/rootfs/${PLATFORM}"
OUTPUT_DIR="/usr1/output/${PLATFORM}"
TOP_OUTPUT_DIR="/usr1/output/"
    case $PLATFORM in
    "aarch64-std" | "aarch64-pro" | "raspberrypi4-64")
        group="arm64";;
    "arm-std")
        group="arm32";;
    "x86-64-std")
        group="x86_64";;
    *)
        echo "unknown machine";exit 1
    esac
}

create_checksum_for_release()
{
    local releasedir="$1"
    pushd "${releasedir}"
    local filelist="$(find . -type f | grep -Ev "\.sha256sum")"
    for fname in $filelist
    do
        sha256sum "${fname}" | awk -F"[ /]" '{print $1,$NF}' > "${fname}".sha256sum
    done
    popd

}

main()
{
whoami
local archlist="$1"
Is_delete_worspace="$2"
local is_download_code="$3"
local is_install_tools="$4"
[[ -z "$is_download_code" ]] && { is_download_code="yes"; }
[[ -z "$is_install_tools" ]] && { is_install_tools="no"; }
local build_image_name="$5"
local meta_branch="$6"
local software_branch="$7"

chmod a+r "${SCRIPTS_DIR}"/*.sh
##download codes and install tools
local datetime="$(date +%Y%m%d%H%M%S)"
[[ "${is_download_code}" == "yes" ]] && sh -x "${SCRIPTS_DIR}"/download.sh "$is_install_tools" "$meta_branch" "$software_branch"
#[[ -z "${archlist}" ]] && archlist="qemu-arm qemu-aarch64 raspberrypi4-64"
[[ -z "${archlist}" ]] && archlist="arm-std aarch64-std aarch64-pro raspberrypi4-64"
[[ -z "${build_image_name}" ]] && build_image_name="openeuler-image"

#delete log file from dnf
rm -f /tmp/hawkey.log
for arch in $archlist
do
    set_env "$arch"
    arch="$(echo $arch|sed "s|qemu-||g")"
    mkdir -p "${TOP_OUTPUT_DIR}/${datetime}/source-list/"
    ##compile
    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
    chown -R "${username}":users "${BUILD_DIR}"
    if [[ "${PLATFORM}" == "aarch64-std" ]];then
        sh "${SRC_DIR}"/yocto-meta-openeuler/scripts/compile.sh "dsoftbus"
    fi
    cat > "${BUILD_DIR}"/build.sh << EOF
#!/bin/bash
set -e
whoami || echo ""
rm -f "${BUILD_DIR}"/source.log
export DATETIME="$datetime"
source "${SRC_DIR}"/yocto-meta-openeuler/scripts/compile.sh "${PLATFORM}" "${BUILD_DIR}" > "${BUILD_DIR}"/source.log
if [ -e /opt/buildtools/nativesdk/environment-setup-x86_64-pokysdk-linux ]; then
    source /opt/buildtools/nativesdk/environment-setup-x86_64-pokysdk-linux
fi
bitbake_opt="\$(grep "You can now run " ${BUILD_DIR}/source.log | awk -F"'" '{print \$2}')"
#\${bitbake_opt}
echo "bitbake ${build_image_name}"

bitbake ${build_image_name}
if [[ ${build_image_name} != "openeuler-image-tiny" ]]; then
    bitbake ${build_image_name} -c do_populate_sdk
fi

EOF

    sudo -E -u "${username}" sh -x "${BUILD_DIR}"/build.sh || exit 1
    local destdir="${TOP_OUTPUT_DIR}/${datetime}/${group}/${arch}"
    mkdir -p "$destdir" || exit 1
    cp -a "${BUILD_DIR}"/output/${datetime}/* "$destdir" || exit 1
    [[ "${Is_delete_worspace}" == "yes" ]] && rm -rf "${BUILD_DIR}"
done

pushd "${TOP_OUTPUT_DIR}/"
test -d ./dailybuild || mkdir ./dailybuild
pushd ./dailybuild || exit 1
rm -rf *
ln -sf ../"${datetime}" "${datetime}"
popd
popd
if [ ! -f "${SRC_DIR}/manifest.xml" ]; then
    python3 {SCRIPTS_DIR}/manifest.py ${SRC_DIR}
fi
cp -a "${SRC_DIR}"/manifest.xml "${TOP_OUTPUT_DIR}/${datetime}/source-list/"
create_checksum_for_release "${TOP_OUTPUT_DIR}/${datetime}"
echo "INFO: ALL successfully!"
}

main "$@"
