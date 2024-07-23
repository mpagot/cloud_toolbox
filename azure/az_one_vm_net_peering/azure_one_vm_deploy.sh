#!/bin/bash -eu

# Create in Azure:
# - 1 VM with 1 Public IP

. ./utils.sh

check_sshkey_env

$AZ --version


# Create a resource group to contain all the resources
echo "--> az group create -g $MY_GROUP -l $MY_REGION"
$AZ group create -g $MY_GROUP -l $MY_REGION


# Create a VNET only needed later when creating the VM
echo "--> az network vnet create"
$AZ network vnet create \
  -n $MY_VNET \
  -g $MY_GROUP \
  -l $MY_REGION

# Create the only one public IP in this deployment,
# it will be assigned to the 3rd VM (bastion role)
echo "--> az network public-ip create"
$AZ network public-ip create \
    --resource-group $MY_GROUP \
    --name $MY_PUBIP \
    --version IPv4 \
    --sku Basic \
    --allocation-method Static


echo "--> az vm create -n $MY_VM"
$AZ vm create \
  -n $MY_VM \
  -g $MY_GROUP \
  -l $MY_REGION \
  --size Standard_B1s \
  --image $MY_OS \
  --admin-username $MY_USERNAME \
  --vnet-name $MY_VNET \
  --public-ip-address $MY_PUBIP \
  --ssh-key-values "${MYSSHKEY}.pub"
#  --subnet $MY_SUBNET \

if [[ -n "${AZ_BOOTLOG}" ]]; then
  echo "--> create all components needed to get boot log"
  $AZ storage account create \
      -g $MY_GROUP \
      --name $MY_STORAGE_ACCOUNT \
      --location $MY_REGION
      #                    --sku Standard_LRS

  endpoint="$($AZ storage account show \
      -g $MY_GROUP \
      --name $MY_STORAGE_ACCOUNT \
      --query="primaryEndpoints.blob" \
      -o tsv)"

  for NUM in $(seq $MY_NUM); do
    THIS_VM="${MYNAME}-vm-0${NUM}"
    $AZ vm boot-diagnostics enable \
      --name $THIS_VM \
      --resource-group $MY_GROUP \
      --storage $endpoint
  done
fi

print_howto
