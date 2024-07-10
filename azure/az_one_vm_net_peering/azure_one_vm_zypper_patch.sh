#!/bin/bash -eu

# Prepare all the ssh connections within the 2 internal VMs
. ./utils.sh

check_sshkey_env

MY_PUBIP_ADDR="$(get_pub_ip)"

#PATCH_CMD="zypper patch -y"
PATCH_CMD="zypper --non-interactive patch --auto-agree-with-licenses --no-recommends"

test_step "Check the repos"
ssh_vm "sudo zypper lr"

test_step "Zypper patch"
set +e
ssh_vm "sudo ${PATCH_CMD}"
last_zy_result=$?
echo "Zypper exit with $last_zy_result"

if [[ $last_zy_result -eq 103 ]]; then
  ssh_vm "sudo ${PATCH_CMD}"
  last_zy_result=$?
  echo "Zypper exit with $last_zy_result"
  if [[ $last_zy_result -eq 102 ]]; then
    ssh_vm zypper ps -s
    ssh_vm sudo reboot now
  fi
fi

ssh_vm zypper ps -s
last_zy_result=$?
echo "Zypper exit with $last_zy_result"
ssh_vm sudo zypper needs-rebooting
last_zy_result=$?
echo "Zypper exit with $last_zy_result"
ssh_vm sudo zypper patch -D -y
last_zy_result=$?
echo "Zypper exit with $last_zy_result"
set -e
