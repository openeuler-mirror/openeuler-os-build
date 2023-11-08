#!/bin/bash
# yum_conf

function chroot_init()
{
	root_path="/usr1/openeuler"
	if [ -d ${root_path} ];then
		rm -rf ${root_path}
	fi
	mkdir -p ${root_path}
	
	yum install lsof -y
	yum install -c ${yum_conf} --installroot=${root_path} -y pigz expect wget bash \
		vim grep patch tar gzip bzip2 openssh-clients yum perl createrepo_c \
		dnf-utils git -x glibc32

	mkdir -m 755 -p ${root_path}/dev/pts
	test -d ${root_path}/dev/shm || rm -f ${root_path}/dev/shm
	mkdir -m 755 -p ${root_path}/dev/shm
	mount --bind /dev ${root_path}/dev/
	while read com file mode arg
	do
		rm -f ${root_path}/dev/$file
		if [[ $com = ln ]];then
			ln -s $arg ${root_path}/dev/$file
	    		continue
		fi
		$com -m $mode ${root_path}/dev/$file $arg
	done << DEVLIST
	mknod null    666 c 1 3
	mknod zero    666 c 1 5
	mknod full    622 c 1 7
	mknod random  666 c 1 8
	mknod urandom 644 c 1 9
	mknod tty     666 c 5 0
	mknod ptmx    666 c 5 2
	mknod loop-control 600 c 10 237
	mknod loop0   640 b 7 0
	mknod loop1   640 b 7 1
	mknod loop2   640 b 7 2
	mknod loop3   640 b 7 3
	ln    fd      777 /proc/self/fd
	ln    stdin   777 fd/0
	ln    stdout  777 fd/1
	ln    stderr  777 fd/2
DEVLIST
	
	mount -n -tdevpts -omode=0620,gid=5 none ${root_path}/dev/pts
	mkdir -p ${root_path}/proc ${root_path}/sys
	mount --bind /sys ${root_path}/sys
	mount --bind /proc ${root_path}/proc
	
	cp make_docker.sh "${root_path}/home/"
	cp "/etc/resolv.conf" "${root_path}/etc/"
	rm -f "${root_path}/etc/yum.repos.d"/*
	cp "${yum_conf}" "${root_path}/etc/yum.repos.d/"
}

function chroot_clean()
{
	if [ -d "${root_path}" ];then
		for openeuler_pid in $(lsof | grep "${root_path}" | awk '{print $2}')
		do
			kill -9 "${openeuler_pid}"
		done
		umount -f "${root_path}/proc"
		umount -f "${root_path}/sys"
		umount -f "${root_path}/dev/pts"
		umount -f "${root_path}/dev"
		rm -rf ${root_path}
	fi
}

function chroot_run()
{
	chroot_init
	chroot "${root_path}" /bin/bash --login -c "$@"
	chroot_clean
}
