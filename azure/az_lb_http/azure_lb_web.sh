
# configureble parameters
MY_USERNAME=cloudadmin
MY_REGION=northeurope
MY_OS=SUSE:sles-sap-15-sp5:gen2:latest
MY_PREFIX=my

# set of names reused more than one time
MY_GROUP="${MY_PREFIX}_lb_rg"
MY_SUBNET="${MY_PREFIX}_sn"
MY_NSG="${MY_PREFIX}_nsg"
MY_AS="${MY_PREFIX}_as"
MY_VNET="${MY_PREFIX}_vnet"
MY_PUBIP="${MY_PREFIX}_pubip"
MY_LB="${MY_PREFIX}_loadbalancer"
MY_BE_POOL="${MY_PREFIX}_backend_pool"
MY_HPROBE="${MY_PREFIX}_health"
MY_FIP="${MY_PREFIX}_frontend_ip"


# Create a resource group to contein all the resources
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
# it will be assigned and managed by the load balancer
echo "--> az network public-ip create"
az network public-ip create \
    --resource-group $MY_GROUP \
    --name $MY_PUBIP \
    --version IPv4 \
    --sku Basic \
    --allocation-method Static


# Create the load balancer entity.
# Mostly this one is just a "group" definition
# to link backend (3 VMs) and frontend (the Pub IP) resources
echo "--> az network lb create"
az network lb create \
    -g $MY_GROUP \
    -n $MY_LB \
    --sku Basic \
    --public-ip-address $MY_PUBIP \
    --backend-pool-name $MY_BE_POOL \
    --frontend-ip-name $MY_FIP


# All the 3 VM will be later assigned to it.
# The load balancer does not explicitly knows about it
echo "--> az vm availability-set create"
az vm availability-set create \
  -n $MY_AS \
  -l $MY_REGION \
  -g $MY_GROUP


# Create 3:
#   - VMs
#   - for each of them open port 80
#   - link their NIC/ip-configs to the load balancer to be managed
for NUM in 1 2 3
do
  THIS_VM="${MY_PREFIX}-vm-0${NUM}"

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
    --public-ip-address "" \
    --availability-set $MY_AS \
    --nsg $MY_NSG \
    --custom-data cloud-init-web.txt \
    --generate-ssh-keys


  echo "--> az vm open-port -n $MY_PREFIX-vm-0$NUM"
  az vm open-port -g $MY_GROUP --name $THIS_VM --port 80


  # the nested az commands is to get the NIC and the ipconfig names
  # directly from the just created VM metadata
  echo "--> az network nic ip-config address-pool add"
  az network nic ip-config address-pool add \
    -g $MY_GROUP \
    --lb-name $MY_LB \
    --address-pool $MY_BE_POOL \
    --ip-config-name $(az network nic show --id $(az vm show -g $MY_GROUP -n $THIS_VM --query 'networkProfile.networkInterfaces[0].id' -o tsv) --query 'ipConfigurations[0].name' -o tsv) \
    --nic-name $(az network nic show --id $(az vm show -g $MY_GROUP -n $THIS_VM --query 'networkProfile.networkInterfaces[0].id' -o tsv) --query 'name' -o tsv)
done


# Health probe is using the port 80
# to understand if each of the VM and nginx in them
# are OK.
echo "--> az network lb probe create"
az network lb probe create \
    --resource-group $MY_GROUP \
    --lb-name $MY_LB \
    --name $MY_HPROBE \
    --port 80 \
    --protocol Tcp \
    --interval 5 \
    --probe-threshold 2


# Configure the load balancer behavior
echo "--> az network lb rule create"
az network lb rule create \
    -g $MY_GROUP \
    --lb-name $MY_LB \
    -n "${MY_PREFIX}_lbrule" \
    --protocol Tcp \
    --frontend-ip-name $MY_FIP --frontend-port 80 \
    --backend-pool-name $MY_BE_POOL --backend-port 80 \
    --probe-name $MY_HPROBE


echo "------------------------------------------------------"
echo "|   Open the page at http://$(az network public-ip show -g $MY_GROUP -n $MY_PUBIP --query 'ipAddress' -o tsv)"
echo "|   Destroy all with 'az group delete --name $MY_GROUP -y'"
echo "------------------------------------------------------"
