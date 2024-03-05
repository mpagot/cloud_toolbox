#!/bin/bash -e

# Print some usefull commands to interact to deployed cluster
# To be executed after the deploy.sh

. ./utils.sh

echo "----- VALIDATION OF THE CONFIGURATIONS -----"

echo "MYAZRG=${MYAZRG}"
echo "MYAZVNET=${MYAZVNET}"
echo "MYAZSNET=${MYAZSNET}"
echo "MYAZPIPPRE=${MYAZPIPPRE}"
echo "MYAZNSG=${MYAZNSG}"
echo "MYAZNICPRE=${MYAZNICPRE}"
echo "MYAZVM=${MYAZVM}"
echo "MYAZVMUSR=${MYAZVMUSR}"

echo "----- GET USERNAME AND IP -----"
export MYUSER=$(az vm list --resource-group ${MYAZRG} --query '[0].osProfile.adminUsername' -o tsv)
export MYPUBIP1=$(az network public-ip show --ids $(az network nic show --ids $(az vm show \
    --resource-group ${MYAZRG} \
    --name "${MYAZVM}-1" \
    --query "networkProfile.networkInterfaces[0].id" -o tsv) \
    --query "ipConfigurations[0].publicIPAddress.id" -o tsv) --query "ipAddress" -o tsv)
export MYPUBIP2=$(az network public-ip show --ids $(az network nic show --ids $(az vm show \
    --resource-group ${MYAZRG} \
    --name "${MYAZVM}-2" \
    --query "networkProfile.networkInterfaces[0].id" -o tsv) \
    --query "ipConfigurations[0].publicIPAddress.id" -o tsv) --query "ipAddress" -o tsv)

echo "MYUSER:${MYUSER}"
echo "MYPUBIP1:${MYPUBIP1} --> ssh $MYUSER@$MYPUBIP1"
echo "MYPUBIP2:${MYPUBIP2} --> ssh $MYUSER@$MYPUBIP2"
echo "Delete cmd: az group delete --name ${MYAZRG} -y"

