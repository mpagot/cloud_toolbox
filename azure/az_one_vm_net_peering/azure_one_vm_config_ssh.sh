#!/bin/bash -eu

# Prepare all the ssh connections within the 2 internal VMs
. ./utils.sh

check_sshkey_env

MY_PUBIP_ADDR="$(get_pub_ip)"

test_step "Clean up known_hosts on the machine running the test script"
ssh-keygen -R $MY_PUBIP_ADDR
test_step "Accept bastion host key"
ssh -i $MYSSHKEY -o StrictHostKeyChecking=accept-new $MY_USERNAME@$MY_PUBIP_ADDR whoami || test_die "Issue in VM first connection"

test_step "Test ssh without extra args"
ssh_vm whoami | grep $MY_USERNAME || test_die "Issue in VM connection"