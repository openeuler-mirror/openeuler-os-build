#!/bin/bash
# usage: bash delete_iso.sh <IP> <USER> <PASSWD> <directory of iso>
echo "--------------- start delete older iso ----------------"
DIR=$1
my_key=$2
ISO_DAYS=30
TODAY=`date +%s`
files=`ssh -i $my_key -o StrictHostKeyChecking=no root@121.36.84.172 "ls $DIR | grep openeuler-"`

for file in $files
do
    echo $file
	if [[ $file == openeuler-* ]];then
		year=`echo $file | cut -d "-" -f 2`
		month=`echo $file | cut -d "-" -f 3`
		day=`echo $file | cut -d "-" -f 4`
		hour=`echo $file | cut -d "-" -f 5`
		if [[ -z $hour ]];then
			echo "don't delete  $DIR/$file, check next"
			continue
		fi
   		file=`echo $file | sed 's/\r//g'`
		echo "$file +++++++"
		date=`date +%s -d "$year-$month-$day"`
		if [ `expr $TODAY - $date` -gt `expr $ISO_DAYS \* 24 \* 3600` ];then
			if [[ "x$file" != "x*" ]];then
				echo "delete directory $DIR/$file"
				ssh -i $my_key -o StrictHostKeyChecking=no root@121.36.84.172 "cd $DIR && rm -rf $file" 
			fi
		else
			echo "don't delete $DIR/$file"
		fi
	fi
done

echo "--------------- end delete older iso ----------------"
