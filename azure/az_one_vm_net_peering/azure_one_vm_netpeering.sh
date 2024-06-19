#!/bin/bash -eu

# Create in Azure:
# - 1 VM with 1 Public IP

. ./utils.sh

if [[ ! -v AZ_NP_RG ]]; then
  echo "AZ_NP_RG must be set before to start. It is the resource group of the other side of the peering that you like to connect your ${MY_GROUP} too"
  exit 1
elif [[ -z "${AZ_NP_RG}" ]]; then
  echo "AZ_NP_RG must not be empty before to start. It is the resource group of the other side of the peering that you like to connect your ${MY_GROUP} too"
  exit 1
fi

if [[ ! -v AZ_NP_VNET ]]; then
  echo "AZ_NP_VNET must be set before to start. It is the VNET to connect to in ${AZ_NP_RG}"
  exit 1
elif [[ -z "${AZ_NP_VNET}" ]]; then
  echo "AZ_NP_VNET must not be empty before to start. It is the VNET to connect to in ${AZ_NP_RG}"
  exit 1
fi

$AZ --version

# Check the resource group to contain all the resources
echo "--> az group show -g $MY_GROUP"
$AZ group show -g $MY_GROUP
$AZ group show -g $AZ_NP_RG

count=$($AZ network vnet peering list -g $AZ_NP_RG --vnet-name $AZ_NP_VNET --output tsv --query "[].name" | grep -c $MYNAME)
echo "count:$count"

$AZ network vnet peering create \
  --name "${MY_VNET}-${AZ_NP_VNET}" \
  --allow-vnet-access \
  --output table \
  --resource-group $MY_GROUP \
  --vnet-name $MY_VNET \
  --remote-vnet "$(az network vnet show --query id --output tsv --resource-group $AZ_NP_RG -n $AZ_NP_VNET)"

$AZ network vnet peering create \
  --name "${AZ_NP_VNET}-${MY_VNET}" \
  --allow-vnet-access \
  --output table \
  --resource-group $AZ_NP_RG \
  --vnet-name $AZ_NP_VNET \
  --remote-vnet "$(az network vnet show --query id --output tsv --resource-group $MY_GROUP -n $MY_VNET)"

$AZ network vnet peering list -g $AZ_NP_RG --vnet-name $AZ_NP_VNET --output tsv --query "[].name" | grep $MYNAME
