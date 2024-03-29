#!/bin/bash -e

# Print some usefull commands to interact to deployed cluster
# To be executed after the deploy.sh

. ./utils.sh

validate_options

echo "----- GET USERNAME AND IP -----"
export MYUSER=$(get_user)
export MYPUBIP1=$(get_ip "1")
export MYPUBIP2=$(get_ip "2")


echo "MYUSER:${MYUSER}"
echo "MYPUBIP1:${MYPUBIP1} --> ssh $MYUSER@$MYPUBIP1"
echo "MYPUBIP2:${MYPUBIP2} --> ssh $MYUSER@$MYPUBIP2"
echo "Delete cmd: az group delete --name ${MYAZRG} -y"

