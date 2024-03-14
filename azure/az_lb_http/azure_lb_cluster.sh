# Create in Azure:
# 2 VM 
# 1 public IP
# 1 LB to dynamically assign the PublicIP to the 3 VM
# each VM has a simple web server installed (by cloud-init script)
# the VMs are part of a pacemaker cluster
# the cluster has a azure-lb RA
# the LB health probe is pointed to the port exposed by RA

# configurable parameters
if [ -z "${MYNAME}" ]
then
  echo "MYNAME must be set to derive all the other settings"
  exit 1
fi

MY_USERNAME=cloudadmin
MY_REGION=northeurope
MY_OS=SUSE:sles-sap-15-sp5:gen2:latest

# set of names reused more than one time
MY_GROUP="${MYNAME}_lb_rg"
MY_SUBNET="${MYNAME}_sn"
MY_NSG="${MYNAME}_nsg"
MY_AS="${MYNAME}_as"
MY_VNET="${MYNAME}_vnet"
MY_PUBIP="${MYNAME}_pubip"
MY_LB="${MYNAME}_loadbalancer"
MY_BE_POOL="${MYNAME}_backend_pool"
MY_HPROBE="${MYNAME}_health"
MY_HPROBE_PORT="62500"
MY_FIP="${MYNAME}_frontend_ip"
MY_BASTION="${MYNAME}-vm-bastion"


# Create a resource group to contain all the resources
echo "--> az group create -g $MY_GROUP -l $MY_REGION"
az group create -g $MY_GROUP -l $MY_REGION


# Create a VNET only needed later when creating the VM
echo "--> az network vnet create"
az network vnet create \
  -n $MY_VNET \
  -g $MY_GROUP \
  -l $MY_REGION \
  --address-prefixes '192.168.0.0/16' \
  --subnet-name $MY_SUBNET \
  --subnet-prefixes '192.168.1.0/24'


# Create a Network Security Group only needed later when creating the VM
echo "--> az network nsg create"
az network nsg create \
    --resource-group $MY_GROUP \
    --name $MY_NSG


# Create the only one public IP of this deployment,
# it will be assigned to the 3rd VM (bastion role)
echo "--> az network public-ip create"
az network public-ip create \
    --resource-group $MY_GROUP \
    --name $MY_PUBIP \
    --version IPv4 \
    --sku Basic \
    --allocation-method Static


# Create the load balancer entity.
# Mostly this one is just a "group" definition
# to link back-end (2 VMs) and front-end (the Pub IP) resources
echo "--> az network lb create"
az network lb create \
    -g $MY_GROUP \
    -n $MY_LB \
    --sku Basic \
    --backend-pool-name $MY_BE_POOL \
    --frontend-ip-name $MY_FIP


# All the 2 VM will be later assigned to it.
# The load balancer does not explicitly knows about it
echo "--> az vm availability-set create"
az vm availability-set create \
  -n $MY_AS \
  -l $MY_REGION \
  -g $MY_GROUP \
  --platform-fault-domain-count 2


# Create 2:
#   - VMs
#   - for each of them open port 80
#   - link their NIC/ipconfigs to the load balancer to be managed
for NUM in 1 2
do
  THIS_VM="${MYNAME}-vm-0${NUM}"

  # Notice as the VM creation refer to an external cloud-init
  # configuration file that is in charge to install and setup
  # the nginx server.
  echo "--> az vm create -n $THIS_VM"
  az vm create \
    -n $THIS_VM \
    -g $MY_GROUP \
    -l $MY_REGION \
    --size Standard_B1s \
    --image $MY_OS \
    --admin-username $MY_USERNAME \
    --vnet-name $MY_VNET \
    --subnet $MY_SUBNET \
    --public-ip-address $MY_PUBIP \
    --generate-ssh-keys


  echo "--> az vm open-port -n $MYNAME-vm-0$NUM"
  az vm open-port -g $MY_GROUP --name $THIS_VM --port 80


  # the nested az commands is to get the NIC and the ipconfig names
  # directly from the just created VM metadata
  echo "--> az network nic ip-config address-pool add"
  THIS_IP_CONFIG=$(az network nic show --id $(az vm show -g $MY_GROUP -n $THIS_VM --query 'networkProfile.networkInterfaces[0].id' -o tsv) --query 'ipConfigurations[0].name' -o tsv)
  THIS_NIC=$(az network nic show --id $(az vm show -g $MY_GROUP -n $THIS_VM --query 'networkProfile.networkInterfaces[0].id' -o tsv) --query 'name' -o tsv)
  az network nic ip-config address-pool add \
    -g $MY_GROUP \
    --lb-name $MY_LB \
    --address-pool $MY_BE_POOL \
    --ip-config-name ${THIS_IP_CONFIG} \
    --nic-name ${THIS_NIC}
done

echo "--> az vm create -n $THIS_VM"
az vm create \
  -n $MY_BASTION \
  -g $MY_GROUP \
  -l $MY_REGION \
  --size Standard_B1s \
  --image $MY_OS \
  --admin-username $MY_USERNAME \
  --vnet-name $MY_VNET \
  --subnet $MY_SUBNET \
  --public-ip-address "" \
  --availability-set $MY_AS \
  --nsg $MY_NSG \
  --custom-data cloud-init-web.txt \
  --generate-ssh-keys

# Health probe is using the port exposed by the cluster RA azure-lb
# to understand if each of the VM in the cluster is OK
# Is probably eventually the cluster itself that
# cares to monitor the below service (port 80)
echo "--> az network lb probe create"
az network lb probe create \
    --resource-group $MY_GROUP \
    --lb-name $MY_LB \
    --name $MY_HPROBE \
    --port ${MY_HPROBE_PORT} \
    --protocol Tcp \
    --interval 5 \
    --probe-threshold 2


# Configure the load balancer behavior
# These two are from qe-sap-deployment
#  - idle_timeout_in_minutes        = 30
#  - enable_floating_ip             = "true"
echo "--> az network lb rule create"
az network lb rule create \
    -g $MY_GROUP \
    --lb-name $MY_LB \
    -n "${MYNAME}_lbrule" \
    --protocol Tcp \
    --frontend-ip-name $MY_FIP --frontend-port 80 \
    --backend-pool-name $MY_BE_POOL --backend-port 80 \
    --idle-timeout 30 \
    --enable-floating-ip 1 \
    --probe-name $MY_HPROBE


echo "------------------------------------------------------"
echo "|   Bastion ssh cloudadmin@$(az network public-ip show -g $MY_GROUP -n $MY_PUBIP --query 'ipAddress' -o tsv)"
echo "|   Destroy all with 'az group delete --name $MY_GROUP -y'"
echo "------------------------------------------------------"
