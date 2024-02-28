. ./utils.sh

test_step "Create Azure ResourceGroup: ${MYAZRG}"
az group create \
    --name ${MYAZRG} \
    --location ${MYAZREG}


test_step "Create Vnet:${MYAZVNET} Subnet:${MYAZSNET}"
az network vnet create \
    --resource-group ${MYAZRG} \
    --location ${MYAZREG} \
    --name ${MYAZVNET} \
    --address-prefixes 10.1.0.0/16 \
    --subnet-name ${MYAZSNET} \
    --subnet-prefixes 10.1.0.0/24

test_step "Create 2 PublicIp"
for i in $(seq 2); do
      az network public-ip create \
        --resource-group ${MYAZRG} \
        --name "${MYAZPIPPRE}-$i" \
        --sku Standard \
        --version IPv4 \
        --zone 1 2 3 ; \
done

test_step "Create NSG"
az network nsg create \
    --resource-group ${MYAZRG} \
    --name ${MYAZNSG}

az network nsg rule create \
    --resource-group ${MYAZRG} \
    --nsg-name ${MYAZNSG} \
    --name "${MYAZNSG}RuleSSH" \
    --protocol '*' \
    --direction inbound \
    --source-address-prefix '*' \
    --source-port-range '*' \
    --destination-address-prefix '*' \
    --destination-port-range 22 \
    --access allow \
    --priority 200

test_step "Create 1 NIC and associate 3 IpConfig"
az network nic create \
    --resource-group ${MYAZRG} \
    --name "${MYAZNICPRE}-1" \
    --private-ip-address-version IPv4 \
    --vnet-name ${MYAZVNET} \
    --subnet ${MYAZSNET} \
    --network-security-group ${MYAZNSG} \
    --public-ip-address "${MYAZPIPPRE}-1"

az network nic ip-config create \
    --resource-group ${MYAZRG} \
    --name ipconfig2 \
    --nic-name "${MYAZNICPRE}-1" \
    --private-ip-address 10.1.0.5 \
    --private-ip-address-version IPv4 \
    --vnet-name ${MYAZVNET} \
    --subnet ${MYAZSNET} \
    --public-ip-address "${MYAZPIPPRE}-2"

az network nic ip-config create \
    --resource-group ${MYAZRG} \
    --name ipconfig3 \
    --nic-name "${MYAZNICPRE}-1" \
    --private-ip-address 10.1.0.6 \
    --private-ip-address-version IPv4 \
    --vnet-name ${MYAZVNET} \
    --subnet ${MYAZSNET}

test_step "Create VM"
az vm create \
    --resource-group ${MYAZRG} \
    --name ${MYAZVM} \
    --nics "${MYAZNICPRE}-1" \
    --image ${MYAZVMOS} \
    --admin-username ${MYAZVMUSR} \
    --authentication-type ssh \
    --generate-ssh-keys
