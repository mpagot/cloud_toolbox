#!/bin/bash -eu

# Prepare all the ssh connections within the 2 internal VMs
. ./utils.sh

check_sshkey_env

MY_PUBIP_ADDR="$(get_pub_ip)"


if [[ ! -v AZ_NP_MIRROR_IP ]]; then
  echo "AZ_NP_MIRROR_IP must be set before to start. It is the public IP address of the repo mirror"
  exit 1
elif [[ -z "${AZ_NP_MIRROR_IP}" ]]; then
  echo "AZ_NP_MIRROR_IP must not be empty before to start. It is the public IP address of the repo mirror"
  exit 1
fi


if [[ ! -v AZ_NP_MIRROR_HOSTNAME ]]; then
  echo "AZ_NP_MIRROR_HOSTNAME must be set before to start. It is the hostname of the repo"
  exit 1
elif [[ -z "${AZ_NP_MIRROR_HOSTNAME}" ]]; then
  echo "AZ_NP_MIRROR_HOSTNAME must not be empty before to start. It is the hostname of the repo"
  exit 1
fi

if [[ ! -v AZ_NP_REPO ]]; then
  echo "AZ_NP_REPO must be set before to start. It is the repo to add"
  exit 1
elif [[ -z "${AZ_NP_REPO}" ]]; then
  echo "AZ_NP_REPO must not be empty before to start. It is the repo to add"
  exit 1
fi


test_step "Change /etc/hosts"
ssh_vm "echo \"$AZ_NP_MIRROR_IP $AZ_NP_MIRROR_HOSTNAME\" | sudo tee -a /etc/hosts"
ssh_vm "cat /etc/hosts"

test_step "Add repo"
ssh_vm "sudo zypper lr"
ssh_vm "sudo zypper --no-gpg-checks ar -f -n TEST_0 ${AZ_NP_REPO} TEST_0"
ssh_vm "sudo zypper ref" || test_die "rc:$? with zypper ref"
ssh_vm "sudo zypper lr"
