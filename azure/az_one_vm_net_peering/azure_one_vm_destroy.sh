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

# Delete the resource group to contain all the resources
$AZ group delete --name $MY_GROUP -y

$AZ network vnet peering delete --resource-group $AZ_NP_RG --vnet-name $AZ_NP_VNET -n "${AZ_NP_VNET}-${MY_VNET}"