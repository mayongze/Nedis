#/bin/bash
SHELL_FOLDER=$(dirname $(readlink -f "$0"))
configPath=$1
#替换upstream
sed -i "s!include.*;!include $configPath;!" $SHELL_FOLDER/nginx-test.conf
if [ $? != 0 ];then
exit 1
fi
$SHELL_FOLDER/../sbin/nginx -t -c $SHELL_FOLDER/nginx-test.conf
