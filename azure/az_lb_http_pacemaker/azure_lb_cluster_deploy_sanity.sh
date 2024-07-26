#!/bin/bash -eu

# Check the deployment before to start testing and changing it

. ./utils.sh

test_step "Resource group"
az group list --query "[?name=='${MY_GROUP}'].name" -o tsv | \
    wc -l | grep 1 || test_die "Resource group"

test_step "Bastion"
az vm list -g "${MY_GROUP}" --query "[?name=='${MY_BASTION}'].name" -o tsv | \
    wc -l | grep 1 || test_die "Bastion"
az vm list -g "${MY_GROUP}" --query "[?name!='${MY_BASTION}'].name" -o tsv | \
    wc -l | grep $MY_NUM || test_die "Nodes is not ${MY_NUM}"

test_step "Public IP"
az network public-ip list -g $MY_GROUP --query '[].name' -o tsv | \
    wc -l | grep 2 || test_die "There's not exactly 2 PubIP"
az network public-ip show -g $MY_GROUP -n $MY_PUBIP --query 'ipAddress' || test_die "No Public IP named ${MY_PUBIP}"
MY_PUBIP_ADDR="$(get_pub_ip)"

test_step "Internal virtual machines"
for NUM in $(seq $MY_NUM); do
  this_vm="${MYNAME}-vm-0${NUM}"
  echo "###########################################################################"
  echo "# -------> this_vm:${this_vm}"

  test_step "[${this_vm}] vm get-instance-view"
  az vm get-instance-view \
      --name "${this_vm}" \
      --resource-group "${MY_GROUP}" \
      --query "instanceView.statuses[1].[code,displayStatus]" \
      -o tsv | grep -c running | grep 2 || test_die "VM ${this_vm} is not running"
done
