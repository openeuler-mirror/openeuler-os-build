#!/bin/bash
passwd="1234"
expect -c "
spawn $@
expect {
\"*yes/no*\" {send \"yes\n\"}
\"*assword*\" {send \"$passwd\n\"}
eof
}
catch wait result;
exit [lindex \$result 3]
"
