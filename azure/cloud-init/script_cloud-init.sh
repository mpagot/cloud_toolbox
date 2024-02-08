#!/bin/bash -e

# Create two mostly identical VM but pass a custom cloud-init.txt at only one of them
# then inspect differences

echo "----- VALIDATION OF THE CONFIGURATIONS -----"

if [ ! -f "$1" ]
then
  echo "cloud-init.txt file has to be provided as first script argument"
  exit 1
else
  CLOUDINIT=$1
fi

echo "------- Content of the ${CLOUDINIT} -------"
cat $CLOUDINIT
echo "-------------------------------------------"

MYAZREG="${MYAZREG:-"eastus2"}"
MYAZOS="${MYAZOS:-"SUSE:sles-sap-15-sp5:gen2:latest"}"

if [ -z "${MYNAME}" ]
then
  echo "MYNAME must be set to derive all the other settings"
  exit 1
fi
MYAZRG="${MYAZRG:-"${MYNAME}ResourceGroup"}"
MYAZVNET="${MYAZVNET:-"${MYNAME}VNet"}"
MYAZSNET="${MYAZSNET:-"${MYNAME}BackEndSubnet"}"
MYAZPIPPRE="${MYAZPIPPRE:-"${MYNAME}PublicIp"}"
MYAZNSG="${MYAZNSG:-"${MYNAME}NSG"}"
MYAZNICPRE="${MYAZNICPRE:-"${MYNAME}NIC"}"
MYAZVM="${MYAZVM:-"${MYNAME}VM"}"

echo "MYAZRG=${MYAZRG}"
echo "MYAZVNET=${MYAZVNET}"
echo "MYAZSNET=${MYAZSNET}"
echo "MYAZPIPPRE=${MYAZPIPPRE}"
echo "MYAZNSG=${MYAZNSG}"
echo "MYAZNICPRE=${MYAZNICPRE}"
echo "MYAZVM=${MYAZVM}"

echo "----- CREATE RESOURCE GROUP -----"
az group create \
    --name ${MYAZRG} \
    --location ${MYAZREG}

echo "----- CREATE 2 VMs -----"
az vm create \
    --resource-group ${MYAZRG} \
    --name "${MYAZVM}-1" \
    --image "${MYAZOS}" \
    --generate-ssh-keys


az vm create \
    --resource-group ${MYAZRG} \
    --name "${MYAZVM}-2" \
    --image "${MYAZOS}" \
    --custom-data "${CLOUDINIT}" \
    --generate-ssh-keys

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
echo "Delete cmd: az group delete --name ${MYAZRG}  -y"


echo "----- CHECK SSH CONNECTIVITY -----"
ssh -l cloudadmin -o UpdateHostKeys=yes -o StrictHostKeyChecking=accept-new $MYUSER@$MYPUBIP1 test
ssh -l cloudadmin -o UpdateHostKeys=yes -o StrictHostKeyChecking=accept-new $MYUSER@$MYPUBIP2 test

echo "----- ZYPPER REFRESH -----"
ssh $MYUSER@$MYPUBIP1 sudo zypper refresh
ssh $MYUSER@$MYPUBIP2 sudo zypper refresh

echo "----- CHECK FOR CLUSTERTOOLS2 PRESENCE -----"
! ssh $MYUSER@$MYPUBIP1 zypper se -i -s ClusterTools2
ssh $MYUSER@$MYPUBIP2 zypper se -i -s ClusterTools2

echo "----- CHECK FOR CLOUD-INIT LOGS -----"

# Both has to have cloud-init
ssh $MYUSER@$MYPUBIP1 sudo journalctl |grep -E 'cloud-init'
ssh $MYUSER@$MYPUBIP2 sudo journalctl |grep -E 'cloud-init'

# Only VM2 has to have ClusterTools2 managed by cloud-init
! ssh $MYUSER@$MYPUBIP1 sudo journalctl |grep -E 'cloud-init'|grep ClusterTools2
ssh $MYUSER@$MYPUBIP2 sudo journalctl |grep -E 'cloud-init'|grep ClusterTools2

echo "----- CHECK FOR CLOUD-INIT WARNINGS -----"
! ssh $MYUSER@$MYPUBIP1 sudo grep WARNING /var/log/cloud-init.log
! ssh $MYUSER@$MYPUBIP2 sudo grep WARNING /var/log/cloud-init.log

echo "----- PROVIDE DELETE CMD -----"
echo "Delete cmd: az group delete --name ${MYAZRG}  -y"