#!/bin/bash
# Author: xielaili
# Copyright Huawei Technologies Co., Ltd. 2010-2018. All rights reserved.
set -e
execcmd=""
machineip=""
machineport=""
loginuser=root
loginpassword=huawei


######################
# funcntion description: sshcmd cmd testmathineip [password] [user]
# Globals:
# Arguments:user:root password:default huawei
# Returns:13: it means can not connect the mathine or password is wrong
#		  0: command execute successfully
#		  others: command execute wrongly
######################
function sshcmd_comm()
{
    cmd="$1"
	testip="$2"
	password=${3}
	user=${4-root}
    if [ $# == 5 ];then
        testport="$5"
    else
        testport=""
    fi
	timeout=180

	if [ "$1x" = "x" ]; then
		echo "ssh_password cmd targetip [password] [user]"
		return 1
	fi

	 if [ "x${testip}" = "x" ]; then
                testip="${testmachine}"
        fi

	cmd=${cmd//\"/\\\"}
	cmd=${cmd//\$/\\\$}
    
        if [ "x${testip}" = "x" -o "x${cmd}" = "x" ];then
                echo "isup  time testmathine [password] [user]"
                exit 1
        fi
    if [ -n "${testport}" ];then
        tport="-p ${testport}"
    else
        tport=""
    fi
	expect <<-END1
		## set infinite timeout, because some commands maybe execute long time.
		set timeout -1

		## remotly exectue command
		spawn ssh -o "ConnectTimeout ${timeout}" -i ~/.ssh/super_publish_rsa ${tport} "${user}@${testip}" "${cmd}"
		expect {

			#first connect, no public key in ~/.ssh/known_hosts

			#"Are you sure you want to continue connecting (yes/no)?"
			"*yes/no*" {

				send "yes\r"

			}
            ## already has public key in ~/.ssh/known_hots
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


while getopts "c:m:p:u:P:h" OPTIONS
do
        case "${OPTIONS}" in
                c) execcmd="${OPTARG}";;
                m) machineip="${OPTARG}";;
                u) loginuser="${OPTARG}";;
                p) loginpassword="${OPTARG}";;
                P) machineport="${OPTARG}";;
                \?) echo "ERROR - Invalid parameter"; echo "ERROR - Invalid parameter" >&2;usage;exit 1;;
                *) echo "ERROR - Invalid parameter"; echo "ERROR - Invalid parameter" >&2; usage;exit 1;;
        esac
done

######################
# delet known hosts
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
# display uasge
# Globals:
# Arguments:
# Returns:
######################
function usage()
{
        echo "Usage: sshcmd.sh -c "command" -m "machinetip" [-P machineport] [-u login_user] [-p login_password]"
}

if [ "x${execcmd}" = "x" -o "x${machineip}" = "x" ];then
        usage
        exit 1
fi

delete_known_hosts
sshcmd_comm "${execcmd}" "${machineip}" "${loginpassword}" "${loginuser}" "${machineport}"

exit $?
