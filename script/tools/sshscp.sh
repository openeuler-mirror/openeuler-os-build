#!/bin/bash
# Author: yhon
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e
exelocal=1

######################
# function descriptionsshcmd cmd testmathineip [password] [user]
# Globals:
# Arguments:user:root password:default huawei
# Returns:13: it means can not connect the mathine or password is wrong
#			0: command execute successfully
#			others: command execute wrongly
######################
function sshcmd_comm()
{

	srccommand="$1"
	descommand="$2"
	password=${3-huawei}
	local r_option="$4"
	timeout=180
	if [ "$1x" = "x" ]; then
		echo "ssh_password cmd targetip [password] [user]"
		return 1
	fi

        if [ "x${srccommand}" = "x" -o "x${descommand}" = "x" ];then
                echo "wrong "
                exit 1
        fi

	if [ "${r_option}" = "1" ]; then
		r_option="-r"
	else
		r_option=""
	fi
	expect <<-END1
		## set infinite timeout, because some commands maybe execute long time.
		set timeout -1

		## remotly exectue command
		spawn scp -i ~/.ssh/super_publish_rsa -o "ConnectTimeout ${timeout}" ${SCPPORT} "${r_option}" "${srccommand}" "${descommand}"

		expect {

			#first connect, no public key in ~/.ssh/known_hosts

			#"Are you sure you want to continue connecting (yes/no)?"
			"*yes/no*" {

				send "yes\r"

			}

			## already has public key in ~/.ssh/known_hosts
			-re "\[P|p]assword:" {

				send "${password}\r"
          		}

			## connect target mathine time out
			timeout {
				send_user "connection to ${targetip} timed out: \$expect_out(buffer)\n"
				exit 13
        		}

			## Do not need input password. Becauese of ssh
			eof {
				catch wait result
				#send_user  [lindex \${result} 3]
				exit [lindex \${result} 3]
			}
       		}

		### We have input password,and the command may have been execute,except password is wrong or connctione is broken.
       		expect {
			## check exit status of the proccess of ssh
		 	eof {
				catch wait result
				exit [lindex \${result} 3]
			}

			## Password is wrong!
	        	-re "\[P|p]assword:" {
				send_user "invalid password or account. \$expect_out(buffer)\n"
                		exit 13
        		}

			## timeout again
			timeout {
				send_user "connection to ${targetip} timed out : \$expect_out(buffer)\n"
				exit 13
			}

    	}

	END1

	return $?
}


######################
# 清空/root/.ssh/known_hosts 文件
# Globals:
# Arguments:
# Returns:
######################
function delete_known_hosts()
{
    [ ! -d /root/.ssh ] && mkdir -p /root/.ssh
	known_hosts=/root/.ssh/known_hosts
	> "${known_hosts}"
}

######################
# 使用说明
# Globals:
# Arguments:
# Returns:
######################
function usage()
{
    echo "Usage: sshscp.sh -s src -d destination [-p login_password] -r"
	echo "       r: scp directory"
}


src=""
des=""
loginuser="root"
loginpassword="huawei"

while getopts "p:s:d:hr" OPTIONS
do
        case "${OPTIONS}" in
                p) loginpassword="${OPTARG}";;
                s) src="${OPTARG}";;
                d) des="${OPTARG}";;
		r) r_option_value=1;;
		h) usage; exit 1
		;;
                \?) echo "ERROR - Invalid parameter"; echo "ERROR - Invalid parameter" >&2;usage;exit 1;;
                *) echo "ERROR - Invalid parameter"; echo "ERROR - Invalid parameter" >&2; usage;exit 1;;
        esac
done


if [ "x${src}" = "x" -o "x${des}" = "x" ];then
        usage
        exit 1
fi

delete_known_hosts
for src_item in $(echo "${src}")
        do
        sshcmd_comm "${src_item}" "${des}" "${loginpassword}" "${r_option_value}"
        done
exit $?
