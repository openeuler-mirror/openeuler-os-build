#!/bin/bash
# chkconfig: - 99 10
# description: extend root

set -e

extend_root(){
    ROOT_PART="$(findmnt / -o source -n)"  # /dev/mmcblk0p2
    ROOT_DEV="/dev/$(lsblk -no pkname "$ROOT_PART")"  # /dev/mmcblk0
    PART_NUM="$(echo "$ROOT_PART" | grep -o "[[:digit:]]*$")"  # 2

    PART_INFO=$(parted "$ROOT_DEV" -ms unit s p)
    #BYT;
    #/dev/mmcblk0:31116288s:sd/mmc:512:512:msdos:SD SC16G:;
    #1:16384s:1064959s:1048576s:fat32::boot, lba;
    #2:1064960s:31116287s:30051328s:ext4::;

    LAST_PART_NUM=$(echo "$PART_INFO" | tail -n 1 | cut -f 1 -d:)  # 2
    PART_START=$(echo "$PART_INFO" | grep "^${PART_NUM}" | cut -f 2 -d: | sed 's/[^0-9]//g')  # 1064960
    PART_END=$(echo "$PART_INFO" | grep "^${PART_NUM}" | cut -f 3 -d: | sed 's/[^0-9]//g')  # XXXX < 31116288
    ROOT_END=$(echo "$PART_INFO" | grep "^/dev"| cut -f 2 -d: | sed 's/[^0-9]//g')  # 31116288
    ((ROOT_END--)) # 31116287

    if [ $PART_END -lt $ROOT_END ]; then
        fdisk "$ROOT_DEV" <<EOF
p
d
$PART_NUM
n
p
$PART_NUM
$PART_START

p
w
EOF
        resize2fs $ROOT_PART
        echo "Extend $ROOT_PART finished." >> /var/log/extend-root.log
    else
        echo "Already the largest! Do not need extend any more!" >> /var/log/extend-root.log
    fi
    return 0
}

if extend_root; then
    rm -f /etc/rc.d/init.d/extend-root.sh
else
    echo "Fail to root!" >> /var/log/extend-root.log
fi
