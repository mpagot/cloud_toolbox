#!/bin/bash -eu

# Check the deployment before to start testing and changing it

. ./utils.sh

test_step "deployment"
az group list --query "[?name=='${MY_GROUP}'].name" -o tsv | wc -l | grep 1 || test_die "Resource group"
az vm list -g "${MY_GROUP}" --query "[?name=='${MY_BASTION}'].name" -o tsv | \
    wc -l | grep 1 || test_die "Bastion"
az vm list -g "${MY_GROUP}" --query "[?name!='${MY_BASTION}'].name" -o tsv | \
    wc -l | grep $MY_NUM || test_die "Nodes is not ${MY_NUM}"

MY_PUBIP_ADDR="$(get_pub_ip)"

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

  test_step "[${this_vm}] reach with ssh ProxyCmmand and check hostname"
  ssh "${MY_USERNAME}@${this_vm}" \
      -oProxyCommand="ssh ${MY_USERNAME}@${MY_PUBIP_ADDR} -i $MYSSHKEY -W %h:%p" \
      -i $MYSSHKEY \
      hostname | grep "${this_vm}" || test_die "VM ${this_vm} is not reachable with ProxyCommand"
done
