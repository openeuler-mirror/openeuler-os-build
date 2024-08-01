#======= release version info ======
export STANDARD_PROJECT=
export STANDARD_PROJECT_REPO=
export EPOL_PROJECT_REPO=
export THIRD_REPO=

export checkdep=true
export ARCH=$(uname -m)
export OS_NAME="openEuler"
export PRODUCTS=${OS_NAME}
tmp="$(echo ${STANDARD_PROJECT#*:})"
export OS_VERSION="$(echo ${tmp//:/-})"
export SHA256SUM=".sha256sum"
export OPENEULER_CHROOT_PATH="/usr1/openeuler"

export RELEASE_SERVER_IP="172.16.1.236"
export RELEASE_SERVER_PORT="30322"
if [[ ${ARCH} == "loongarch64" ]] || [[ ${ARCH} == "ppc64le" ]];then
    export RELEASE_SERVER_IP="121.36.84.172"
    export RELEASE_SERVER_PORT=""
fi
export RELEASE_HTTP_URL="http://121.36.84.172/dailybuild"
if [ -n "${RELEASE_SERVER_PORT}" ];then
    export SSHPORT="-p ${RELEASE_SERVER_PORT}"
    export SCPPORT="-P ${RELEASE_SERVER_PORT}"
else
    export SSHPORT=""
    export SCPPORT=""
fi
export RELEASE_ROOT_PATH="/repo/openeuler/dailybuild"
export RELEASE_VERSION_DIR="EBS-${OS_NAME}-${OS_VERSION}"
export RELEASE_ARCH_DIR="openEuler_${ARCH}"

export CONTAINER_NAME=$(echo ${OS_NAME}-${OS_VERSION} | tr A-Z a-z)
export VM_IMAGE_NAME="${OS_NAME}-${OS_VERSION}-${ARCH}.qcow2"
export RASPI_IMAGE_NAME="${OS_NAME}-${OS_VERSION}-raspi-${ARCH}.img"
export RISCV64_QEMU_IMAGE_NAME="${OS_NAME}-${OS_VERSION}-qemu-${ARCH}.qcow2"
export MICROVM_IMAGE_NAME="${OS_NAME}-${OS_VERSION}-stratovirt-${ARCH}.img"
export MICROVM_KERNEL_NAME="vmlinux.bin"
export STDANDARD_VM_KERNEL_NAME="std-vmlinux"

REPO_CONF=$(find -iname "repofile.conf")
cat>${REPO_CONF}<<-EOF
[main]
cachedir=/var/cache/yum/xxx
keepcache=0
debuglevel=2
logfile=/var/log/yum.log
exactarch=1
obsoletes=1
gpgcheck=1
plugins=1
installonly_limit=3
reposdir=/xxx

[standard]
name=standard
baseurl=${STANDARD_PROJECT_REPO}
enabled=1
gpgcheck=0

[epol]
name=epol
baseurl=${EPOL_PROJECT_REPO}
enabled=1
gpgcheck=0

EOF

cat ${REPO_CONF}
