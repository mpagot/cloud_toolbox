#!/bin/bash -eu

# Check the deployment before to start testing and changing it

. ./utils.sh

test_step "deployment"
az group list --query "[?name=='${MY_GROUP}'].name" -o tsv | wc -l | grep 1 || test_die "Resource group"
az vm list -g "${MY_GROUP}" --query "[].name" -o tsv | \
    wc -l | grep 1 || test_die "There's not exactly one VM"

MY_PUBIP_ADDR="$(get_pub_ip)"

test_step "[${MY_VM}] vm get-instance-view"
az vm get-instance-view \
    --name "${MY_VM}" \
    --resource-group "${MY_GROUP}" \
    --query "instanceView.statuses[1].[code,displayStatus]" \
    -o tsv | grep -c running | grep 2 || test_die "VM ${MY_VM} is not running"

