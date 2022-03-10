#!/bin/bash

#Usage: bash copy_embedded_img.sh source_user source_ip source_pwd source_dir daily_ip ssh_key latest_iso_dir 

function cp_embedded_img()
{
	source_user=$1
	source_ip=$2
	source_pwd=$3
	source_dir=$4
	dest_ip=$5
	ssh_key=$6
	latest_iso_dir=$7
	res=$(ssh -i ${ssh_key} -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ServerAliveInterval=60 root@${dest_ip} "
cd ${latest_iso_dir}
if [ ! -d embedded_img ];then
	mkdir embedded_img
else
	rm -rf embedded_img
	echo "[INFO]: old embedded_img directory will deleted."
fi
")
	if [ -n "$res" ];then
		echo $res
	fi
	mkdir tmpdir
	expect <<-END1
		set timeout 2700
		spawn scp -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ServerAliveInterval=2700 -r ${source_user}@${source_ip}:${source_dir}/* ./tmpdir/
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
	if [ $? -ne 0 ];then
		echo "[ERROR]: scp failed."
		exit 1
	else
		scp -i ${ssh_key} -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ServerAliveInterval=2700 -r tmpdir/* root@${dest_ip}:${latest_iso_dir}/embedded_img/
		if [ $? -ne 0 ];then
			echo "[ERROR]: scp embedded_img to dailybuild failed."
			exit 1
		else
			echo "[INFO]: scp embedded_img to dailybuild succeed."
			exit 0
		fi
	fi
}

cp_embedded_img $@
