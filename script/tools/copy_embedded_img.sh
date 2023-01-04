#!/bin/bash

#Usage: bash copy_embedded_img.sh source_user source_ip source_pwd source_dir daily_ip ssh_key latest_iso_dir copy_date_data_only

function cp_embedded_img()
{
	source_user=$1
	source_ip=$2
	source_pwd=$3
	source_dir=$4
	dest_ip=$5
	ssh_key=$6
	latest_iso_dir=$7
	copy_date_data_only=$8
	local copydir="${source_dir}"
	res=$(ssh -i ${ssh_key} -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ServerAliveInterval=60 root@${dest_ip} "
if [ ! -e ${latest_iso_dir} ]; then
	mkdir -p ${latest_iso_dir}
fi
cd ${latest_iso_dir}
if [ ! -d embedded_img ];then
	mkdir embedded_img
else
	allFile=\$(ls ./embedded_img/)
	for oneFile in \${allFile[@]}; do 
		if [[ \${oneFile} != \"gcc\" ]]; then
			rm -rf embedded_img/\${oneFile}
		fi
	done
	echo \"[INFO]: old embedded_img directory will deleted.\"
fi
")
	if [ -n "$res" ];then
		echo $res
	fi
	echo source_user="${source_user}"
	if [[ -z "${source_user}" ]];then
		echo "copy files at this host"
		ret=0
	else
	copydir="tmpdir"
	mkdir "${copydir}"
	expect <<-END1
		set timeout 3600
		spawn scp -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ServerAliveInterval=60 -r ${source_user}@${source_ip}:${source_dir}/* ./${copydir}
		expect {
			-re "\[P|p]assword:" {
				send "${source_pwd}\r"
			}
			timeout {
				send_user "connection to ${source_ip} time out: \$expect_out(buffer)\n"
				exit 13
			}
	}
		expect eof {
			catch wait result
			exit [lindex \${result} 3]
		}
	END1
		ret=$?
	fi
	if [ $ret -ne 0 ];then
		echo "[ERROR]: scp failed."
		exit 1
	else
		find ${copydir}/ -type f
		echo "=================================="
		if [ -z ${copy_date_data_only} ]; then
			scp -v -i ${ssh_key} -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ServerAliveInterval=60 -r "${copydir}"/* root@${dest_ip}:${latest_iso_dir}/embedded_img/
		else
			copyDateDir=$(ls -r ${copydir}/ | head -1)
			scp -v -i ${ssh_key} -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ServerAliveInterval=60 -r "${copydir}"/${copyDateDir}/* root@${dest_ip}:${latest_iso_dir}/embedded_img/
		fi
		if [ $? -ne 0 ];then
			echo "[ERROR]: scp embedded_img to dailybuild failed."
			exit 1
		else
			echo "[INFO]: scp embedded_img to dailybuild succeed."
			exit 0
		fi
	fi
}

cp_embedded_img "$@"
