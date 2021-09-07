#!/bin/bash
# usage: bash link_latest_dailybuild.sh <directory of iso> <ssh_key>
echo "--------------- start link to latest dailybuild ----------------"
DIR=$1
my_key=$2
ssh_ip=$3
Project=`echo $DIR | awk -F "/" '{print $NF}'`
files=`ssh -i $my_key -o StrictHostKeyChecking=no root@${ssh_ip} "ls $DIR | grep ^openeuler-"`
num=0
declare -a date_num
for file in $files
do
    echo $file
	if [[ $file == openeuler-* ]];then
		year=`echo $file | cut -d "-" -f 2`
		month=`echo $file | cut -d "-" -f 3`
		day=`echo $file | cut -d "-" -f 4`
		hour=`echo $file | cut -d "-" -f 5`
		min=`echo $file | cut -d "-" -f 6`
		sec=`echo $file | cut -d "-" -f 7`
   		file=`echo $file | sed 's/\r//g'`
		echo "$file +++++++"
		date=`date -d "$year-$month-$day $hour:$min:$sec" +%s`
		date_num[$num]=$date
		num=`expr $num + 1`
	fi
done

echo ${date_num[@]}
Max=${date_num[0]}
for I in ${!date_num[@]};do
	if [[ ${Max} -le ${date_num[${I}]} ]];then
		Max=${date_num[${I}]}
	fi
done

daily_dir="openeuler-`date -d @$Max +%Y-%m-%d-%H-%M-%S`"
echo "latest_dir:$daily_dir"
ssh -i $my_key -o StrictHostKeyChecking=no root@${ssh_ip} "cd $DIR && rm -rf $Project && ln -s $daily_dir $Project"
if [ $? -eq 0 ];then
	echo "Success to make soft link"
else
	echo "Fail to make soft link"
fi
