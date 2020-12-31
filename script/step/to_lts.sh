#!/bin/bash
echo "start to lts dir"
release_dir=$(cat /mnt/release/my_release_dir)
password=$(cat /mnt/dogshengpwd81)
#sshpass -p "$password" scp -o StrictHostKeyChecking=no -r root@121.36.84.172:${release_dir} /mnt/release/ARM64/
#rm -rf *.sh
