# repo_url


function kiwi_init()
{
	if [ ! -f /usr/share/perl5/vendor_perl/Env.pm ]; then
		cp "${docker_config}/Env.pm" /usr/share/perl5/vendor_perl/
	fi

	if which kiwi &> /dev/null; then
		echo "kiwi has been ok"
	else
		cat /etc/yum.repos.d/my.repo
		yum clean all
		yum install -y python3-setuptools python3-docopt python3-future libisofs libburn libisoburn kde-filesystem ostree-libs xorriso kiwi umoci containers-common skopeo
	fi
	umask_value=$(umask)
	if [ "x${umask_value}" != "x0022" ]; then
		umask 0022
	fi
	if [ ! -d /var/run/screen/S-root ]; then
		mkdir -p /var/run/screen/S-root
	fi
	chmod 700 /var/run/screen/S-root
}

function make_image()
{
	ARCH="$(uname -m)"

	rm -rf /tmp/openeuler-os-build
	git clone -b master https://gitee.com/openeuler/openeuler-os-build /tmp/openeuler-os-build
	if [ $? -ne 0 ];then
		echo "[ERROR] clone openeuler-os-build failed"
		exit 1
	fi

	docker_config="/tmp/openeuler-os-build/script/config/docker_image"
	img_dir="/result/docker_image/image"
	repo_dir="/result/docker_image/repository"
	cfg_dir="/result/docker_image/config"
	rm -rf "${img_dir}" && mkdir -p "${img_dir}"
	rm -rf "${repo_dir}" && mkdir -p "${repo_dir}"
	rm -rf "${cfg_dir}" && mkdir -p "${cfg_dir}"

	kiwi_init

	rm -rf /var/adm/fillup-templates/ && mkdir -p /var/adm/fillup-templates/
	cp "${docker_config}/passwd" /var/adm/fillup-templates/passwd.aaa_base
	cp "${docker_config}/group" /var/adm/fillup-templates/group.aaa_base

	version_time="openeuler-$(date +%Y-%m-%d-%H-%M-%S)"
	sed -i "s#IMAGE_NAME#${version_time}#" "${docker_config}/config.xml"
	sed -i 's/container=.*>/container=\"'${branch}'\">/g' "${docker_config}/config.xml"
	sed -i "/obs_repo_here/a <repository type=\"rpm-md\"><source path=\"${repo_url}\" \/></repository>" "${docker_config}/config.xml"
	cp "${docker_config}/config.xml" "${cfg_dir}"
	cp "${docker_config}/images.sh" "${cfg_dir}"

	rm -rf /tmp/openeuler-os-build
	rm -rf /var/cache/kiwi/yum

	kiwi compat --build "${cfg_dir}" -d "${img_dir}"
	if [ $? -ne 0 ];then
		echo "[ERROR] Failed on kiwi build docker image"
		exit 1
	fi

	docker_img_name="openEuler-docker.${ARCH}.tar.xz"
	cd "${img_dir}"
	tmp_name=$(ls *.tar.xz)
	mv "${tmp_name}" "${docker_img_name}"
	sha256sum "${docker_img_name}" > "${docker_img_name}.sha256sum"
	echo "[INFO] make docker image success"
}


make_image
