#!/bin/bash -eu

# Create in Azure:
# - 2 VM as redundant nodes running an http server
#   each VM has a simple web server installed (by cloud-init script)
#   the 2 VMs are part of a pacemaker cluster
# - 1 Static private IP for the frontend
# - 1 LB to assign the front end IP
# - the cluster has a azure-lb RA
# - the LB health probe is pointed to the port exposed by RA

. ./utils.sh

$AZ --version

# Create a resource group to contain all the resources
echo "--> az group create -g $MY_GROUP -l $MY_REGION"
$AZ group create -g $MY_GROUP -l $MY_REGION

# Create a VNET only needed later when creating the VM
echo "--> az network vnet create"
$AZ network vnet create \
  -n $MY_VNET \
  -g $MY_GROUP \
  -l $MY_REGION \
  --address-prefixes '192.168.0.0/16' \
  --subnet-name $MY_SUBNET \
  --subnet-prefixes "${MY_PRIV_IP_RANGE}.0/24"


# Create a Network Security Group only needed later when creating the VM
echo "--> az network nsg create"
$AZ network nsg create \
    --resource-group $MY_GROUP \
    --name $MY_NSG


# Create the public IP for the bastion VM
echo "[BASTION]--> az network public-ip create"
$AZ network public-ip create \
    --resource-group $MY_GROUP \
    --name $MY_PUBIP \
    --version IPv4 \
    --sku Standard \
    --allocation-method Static

# Create the public IP for the NAT gateway
echo "[NAT GATEWAY]--> az network public-ip create"
$AZ network public-ip create \
    --resource-group $MY_GROUP \
    --name $MY_NAT_PUBIP \
    --sku Standard \
    --location $MY_REGION \
    --zone 1

echo "--> az network nat gateway create"
$AZ network nat gateway create \
    --resource-group $MY_GROUP \
    --name $MY_NAT \
    --public-ip-addresses $MY_NAT_PUBIP \
    --idle-timeout 10 \
    --location $MY_REGION

echo "--> az network vnet subnet update for nat-gateway"
$AZ network vnet subnet update \
    --resource-group $MY_GROUP \
    --vnet-name $MY_VNET \
    --name $MY_SUBNET \
    --nat-gateway $MY_NAT

# Create the load balancer entity.
# Mostly this one is just a "group" definition
# to link back-end (2 VMs) and front-end (the Pub IP) resources
# SKU Standard (and not Basic) is needed to get some Metrics
echo "--> az network lb create"
$AZ network lb create \
    -g $MY_GROUP \
    -n $MY_LB \
    --sku Standard \
    --vnet-name $MY_VNET \
    --subnet $MY_SUBNET \
    --backend-pool-name $MY_BE_POOL \
    --frontend-ip-name $MY_FIP_NAME \
    --private-ip-address $MY_FIP


# All the 2 VM will be later assigned to it.
# The load balancer does not explicitly knows about it
echo "--> az vm availability-set create"
$AZ vm availability-set create \
  -n $MY_AS \
  -l $MY_REGION \
  -g $MY_GROUP \
  --platform-fault-domain-count 2

[[ $MY_OS =~ "12-sp5" ]] && VM_TRUSTLAUNCH="--security-type Standard"

# Create Bastion at first so if something goes
# wrong we have a point to look inside
echo "--> az vm create -n $MY_BASTION"
$AZ vm create \
  -n $MY_BASTION \
  -g $MY_GROUP \
  -l $MY_REGION \
  --size Standard_B1s \
  --image $MY_OS $VM_TRUSTLAUNCH \
  --admin-username $MY_USERNAME \
  --vnet-name $MY_VNET \
  --subnet $MY_SUBNET \
  --public-ip-address $MY_PUBIP \
  --ssh-key-values "${MYSSHKEY}.pub"

if [[ "${AZ_CLOUDINIT}" -eq 1 ]]; then
  VM_CUSTOMDATA="--custom-data cloud-init-web.txt"
else
  VM_CUSTOMDATA=" "
fi

# Create 2:
#   - VMs
#   - for each of them open port 80
#   - link their NIC/ipconfigs to the load balancer to be managed
for NUM in $(seq $MY_NUM); do
  THIS_VM="${MYNAME}-vm-0${NUM}"

  # Notice as the VM creation refer to an external cloud-init
  # configuration file that is in charge to install and setup
  # the nginx server.
  echo "--> az vm create -n ${THIS_VM}"
  $AZ vm create \
    -n $THIS_VM \
    -g $MY_GROUP \
    -l $MY_REGION \
    --size Standard_B1s \
    --image $MY_OS $VM_TRUSTLAUNCH \
    --admin-username $MY_USERNAME \
    --vnet-name $MY_VNET \
    --subnet $MY_SUBNET \
    --public-ip-address "" \
    --availability-set $MY_AS \
    --nsg $MY_NSG $VM_CUSTOMDATA \
    --ssh-key-values "${MYSSHKEY}.pub"
  echo "Exit code for vm create rc:$?"

  if [[ "${AZ_CLOUDINIT}" -eq 1 ]]; then
    echo "--> check if run-command works for ${THIS_VM}"
    # Try to execute a very brief command like `exit 0`
    # This test is here as run-command does not terminate
    # even with internal `cloud-init status --wait` is over
    timeout $(( $AZ_CLOUTINIT_TIMEOUT + 30 )) $AZ vm run-command create \
      --run-command-name "testRuncommand" \
      -g $MY_GROUP \
      --vm-name $THIS_VM \
      --async-execution "false" \
      --run-as-user $MY_USERNAME \
      --timeout-in-seconds $AZ_CLOUTINIT_TIMEOUT \
      --script "exit 0"
    echo "Exit code for run-command rc:$?"

    echo "--> wait cloud-init to complete on ${THIS_VM} with timeout ${AZ_CLOUTINIT_TIMEOUT}"
    set +e
    timeout $(( $AZ_CLOUTINIT_TIMEOUT + 30 )) $AZ vm run-command create \
      --run-command-name "awaitCloudInitIsDone" \
      -g $MY_GROUP \
      --vm-name $THIS_VM \
      --async-execution "false" \
      --run-as-user $MY_USERNAME \
      --timeout-in-seconds $AZ_CLOUTINIT_TIMEOUT \
      --script "sudo cloud-init status --wait"

    WAIT_CLOUD_INIT_RC=$?
    set -e
    echo "Exit code for cloud-init status rc:$WAIT_CLOUD_INIT_RC"
    [[ $WAIT_CLOUD_INIT_RC -eq 0 ]] || test_die "cloud-init status --wait error"
  fi

  echo "--> az vm open-port -n $MYNAME-vm-0$NUM"
  $AZ vm open-port -g $MY_GROUP --name $THIS_VM --port 80
done

# Keep this loop separated from the other to hopefully
# give cloud-init more time to run
for NUM in $(seq $MY_NUM); do
  THIS_VM="${MYNAME}-vm-0${NUM}"

  THIS_NIC_ID=$(az vm show -g $MY_GROUP -n $THIS_VM --query 'networkProfile.networkInterfaces[0].id' -o tsv)
  THIS_IP_CONFIG=$(az network nic show --id $THIS_NIC_ID --query 'ipConfigurations[0].name' -o tsv)
  THIS_NIC=$(az network nic show --id $THIS_NIC_ID --query 'name' -o tsv)
  echo "--> az network nic ip-config address-pool add"
  echo "The just created VM ${THIS_VM} has THIS_IP_CONFIG:${THIS_IP_CONFIG} and THIS_NIC:${THIS_NIC}"

  # Change the IpConfig to use a static IP: https://documentation.suse.com/sle-ha/15-SP5/html/SLE-HA-all/article-installation.html#vl-ha-inst-quick-req-other
  echo "--> az network nic ip-config update"
  $AZ network nic ip-config update \
    --name $THIS_IP_CONFIG \
    --resource-group $MY_GROUP \
    --nic-name $THIS_NIC \
    --private-ip-address "${MY_PRIV_IP_RANGE}.4${NUM}"

  # Add the IpConfig to the LB pool
  echo "--> az network nic ip-config address-pool add"
  $AZ network nic ip-config address-pool add \
    -g $MY_GROUP \
    --lb-name $MY_LB \
    --address-pool $MY_BE_POOL \
    --ip-config-name $THIS_IP_CONFIG \
    --nic-name $THIS_NIC
done


# Health probe is using the port exposed by the cluster RA azure-lb
# to understand if each of the VM in the cluster is OK
# Is probably eventually the cluster itself that
# cares to monitor the below service (port 80)
echo "--> az network lb probe create"
$AZ network lb probe create \
    --resource-group $MY_GROUP \
    --lb-name $MY_LB \
    --name $MY_HPROBE \
    --port $MY_HPROBE_PORT \
    --protocol Tcp \
    --interval 5 \
    --probe-threshold 2


# Configure the load balancer behavior
# These two are from qe-sap-deployment
#  - idle_timeout_in_minutes        = 30
#  - enable_floating_ip             = "true"
echo "--> az network lb rule create"
$AZ network lb rule create \
    -g $MY_GROUP \
    --lb-name $MY_LB \
    -n "${MYNAME}_lbrule" \
    --protocol Tcp \
    --frontend-ip-name $MY_FIP_NAME --frontend-port 80 \
    --backend-pool-name $MY_BE_POOL --backend-port 80 \
    --idle-timeout 30 \
    --enable-floating-ip 1 \
    --probe-name $MY_HPROBE

if [[ "${AZ_BOOTLOG}" -eq 1 ]]; then
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
