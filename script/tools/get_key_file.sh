#!/bin/bash
######################################
# description: copy super_publish_rsa
# Usage: get_key_file destination
######################################

function get_key_file(){
	destdir=$1
	if [ ! -d "${destdir}" ];then
		mkdir -p ${destdir}
	fi
	expect <<-END1
		set timeout 60
		spawn scp -o StrictHostKeyChecking=no -o ServerAliveInterval=60 ${dogshenguser81}@${OBS_UI_IP}:/root/.ssh/super_publish_rsa ${destdir}
		expect {
			-re "\[P|p]assword:" {
				send "${dogshengpwd81}\r"
			}
			timeout {
				send_user "connection to ${OBS_UI_IP} time out: \$expect_out(buffer)\n"
				exit 13
			}
	}
		expect eof {
			catch wait result
			exit [lindex \${result} 3]
		}
	END1
}
