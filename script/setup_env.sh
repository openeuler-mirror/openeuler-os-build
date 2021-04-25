#======= release version info ======
export OBS_STANDARD_PROJECT="openEuler:Mainline"
export OBS_EPOL_PROJECT="openEuler:Epol"
export OBS_EXTRAS_PROJECT="openEuler:Extras"
export OBS_EPOL_MULTI_VERSION_LIST=
#===================================
export OPENEULER_CHROOT_PATH="/usr1/openeuler"
export OS_NAME="openEuler"
tmp="$(echo ${OBS_STANDARD_PROJECT#*:})"
export OS_VERSION="$(echo ${tmp//:/-})"

export OBS_UI_IP="172.16.1.81"
export OBS_SERVER_IP="172.16.1.95"
export RELEASE_SERVER_IP="172.16.1.29"
export RELEASE_SERVER_PORT="30322"
if [ -n "${RELEASE_SERVER_PORT}" ];then
    export SSHPORT="-p ${RELEASE_SERVER_PORT}"
    export SCPPORT="-P ${RELEASE_SERVER_PORT}"
else
    export SSHPORT=""
    export SCPPORT=""
fi
export ARCH=$(uname -m)
export RELEASE_HTTP_URL="http://121.36.84.172/dailybuild"

SUB_STANDARD_REPO_URL="$(echo ${OBS_STANDARD_PROJECT//:/:\/})"
SUB_EPOL_REPO_URL="$(echo ${OBS_EPOL_PROJECT//:/:\/})"
SUB_EXTRAS_REPO_URL="$(echo ${OBS_EXTRAS_PROJECT//:/:\/})"
export OBS_STANDARD_REPO_URL="http://${OBS_SERVER_IP}:82/${SUB_STANDARD_REPO_URL}/standard_${ARCH}"
export OBS_EPOL_REPO_URL="http://${OBS_SERVER_IP}:82/${SUB_EPOL_REPO_URL}/standard_${ARCH}"
export OBS_EXTRAS_REPO_URL="http://${OBS_SERVER_IP}:82/${SUB_EXTRAS_REPO_URL}/standard_${ARCH}"
export OBS_BRINGINRELY_URL="http://${OBS_SERVER_IP}:88/bringInRely/standard_${ARCH}"


export RELEASE_ROOT_PATH="/repo/openeuler/dailybuild"
export RELEASE_VERSION_DIR="${OS_NAME}-${OS_VERSION}"
export RELEASE_ARCH_DIR="openEuler_${ARCH}"

export CONTAINER_NAME=$(echo ${RELEASE_VERSION_DIR} | tr A-Z a-z)
export VM_IMAGE_NAME="${RELEASE_VERSION_DIR}-${ARCH}.qcow2"
export RASPI_IMAGE_NAME="${RELEASE_VERSION_DIR}-raspi-${ARCH}.img"
export MICROVM_IMAGE_NAME="${RELEASE_VERSION_DIR}-stratovirt-${ARCH}.img"
export MICROVM_KERNEL_NAME="vmlinux.bin"

export PRODUCTS=${OS_NAME}

export SHA256SUM=".sha256sum"

export jenkins_build="1"

OBS_REPO_CONF=$(find -iname "obs-repo.conf")
cat>${OBS_REPO_CONF}<<EOF
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

#  This is the default, if you make this bigger yum won't see if the metadata
# is newer on the remote and so you'll "gain" the bandwidth of not having to
# download the new metadata and "pay" for it by yum not having correct
# information.
#  It is esp. important, to have correct metadata, for distributions like
# Fedora which don't keep old packages around. If you don't like this checking
# interupting your command line usage, it's much better to have something
# manually check the metadata once an hour (yum-updatesd will do this).
# metadata_expire=90m

# PUT YOUR REPOS HERE OR IN separate files named file.repo
# in /etc/yum.repos.d
[obs-standard]
name=obs-standard
baseurl=${OBS_STANDARD_REPO_URL}/
enabled=1
gpgcheck=0

[obs-Extras]
name=obs-Extras
baseurl=${OBS_EXTRAS_REPO_URL}/
enabled=1
gpgcheck=0

[obs-Epol]
name=obs-Epol
baseurl=${OBS_EPOL_REPO_URL}/
enabled=1
gpgcheck=0

EOF

cat ${OBS_REPO_CONF}

