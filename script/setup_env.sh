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
export RELEASE_SERVER_IP="172.16.1.236"
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
export OBS_BRINGINRELY_URL=
export OBS_STANDARD_THIRD_REPO_URL=

obs_master_project=(openEuler:BaseTools openEuler:C openEuler:Common_Languages_Dependent_Tools openEuler:Erlang openEuler:Golang openEuler:Java openEuler:KernelSpace openEuler:Lua openEuler:Meson openEuler:MultiLanguage openEuler:Nodejs openEuler:Ocaml openEuler:Perl openEuler:Python openEuler:Qt openEuler:Ruby)
if [[ ${OBS_STANDARD_PROJECT} == "openEuler:Mainline" ]];then
	for p in ${obs_master_project[@]}
	do
		tmp="$(echo ${p//:/:\/})"
		tmp_url="http://${OBS_SERVER_IP}:82/${tmp}/standard_${ARCH}"
		TMP_STANDARD_REPO_URL="${tmp_url} ${TMP_STANDARD_REPO_URL}"
	done
	export OBS_STANDARD_REPO_URL="${TMP_STANDARD_REPO_URL}${OBS_STANDARD_REPO_URL}"
fi

export RELEASE_ROOT_PATH="/repo/openeuler/dailybuild"
export RELEASE_VERSION_DIR="${OS_NAME}-${OS_VERSION}"
export RELEASE_ARCH_DIR="openEuler_${ARCH}"

export CONTAINER_NAME=$(echo ${RELEASE_VERSION_DIR} | tr A-Z a-z)
export VM_IMAGE_NAME="${RELEASE_VERSION_DIR}-${ARCH}.qcow2"
export RASPI_IMAGE_NAME="${RELEASE_VERSION_DIR}-raspi-${ARCH}.img"
export MICROVM_IMAGE_NAME="${RELEASE_VERSION_DIR}-stratovirt-${ARCH}.img"
export MICROVM_KERNEL_NAME="vmlinux.bin"
export STDANDARD_VM_KERNEL_NAME="std-vmlinux"

export PRODUCTS=${OS_NAME}

export SHA256SUM=".sha256sum"

export jenkins_build="1"

export checkdep=true

OBS_REPO_CONF=$(find -iname "obs-repo.conf")
cat>${OBS_REPO_CONF}<<-EOF
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
if [[ ${OBS_STANDARD_PROJECT} == "openEuler:Mainline" ]];then
	i=1
	for repo_url in ${OBS_STANDARD_REPO_URL[@]}
	do
		repo_name="obs_standard_${i}"
		cat>>${OBS_REPO_CONF}<<-EOF
		[${repo_name}]
		name=${repo_name}
		baseurl=${repo_url}/
		enabled=1
		gpgcheck=0

		EOF
		let i+=1
	done
else
	cat>>${OBS_REPO_CONF}<<-EOF
	[obs-standard]
	name=obs-standard
	baseurl=${OBS_STANDARD_REPO_URL}/
	enabled=1
	gpgcheck=0
	EOF
fi
cat ${OBS_REPO_CONF}
