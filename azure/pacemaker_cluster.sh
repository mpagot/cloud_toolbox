#!/bin/bash -e

# Create two mostly identical VM and configure a cluster


echo "----- VALIDATION OF THE CONFIGURATIONS -----"

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
for i in $(seq 2); do
    az vm create \
        --resource-group ${MYAZRG} \
        --name "${MYAZVM}-$i" \
        --image "${MYAZOS}" \
        --generate-ssh-keys
done

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
ssh -l $MYUSER -o UpdateHostKeys=yes -o StrictHostKeyChecking=accept-new $MYUSER@$MYPUBIP1 test || echo "Something wrong with $MYUSER@$MYPUBIP1"
ssh -l $MYUSER -o UpdateHostKeys=yes -o StrictHostKeyChecking=accept-new $MYUSER@$MYPUBIP2 test || echo "Something wrong with $MYUSER@$MYPUBIP2"

echo "----- ZYPPER REFRESH -----"
ssh $MYUSER@$MYPUBIP1 sudo zypper refresh || echo "Something wrong during zypper refresh on $MYUSER@$MYPUBIP1"
ssh $MYUSER@$MYPUBIP2 sudo zypper refresh || echo "Something wrong during zypper refresh on $MYUSER@$MYPUBIP2"

echo "----- CHECK FOR COROSYNC AND PACEMAKER PRESENCE -----"
ssh $MYUSER@$MYPUBIP1 zypper se -i -s corosync pacemaker
ssh $MYUSER@$MYPUBIP2 zypper se -i -s corosync pacemaker

echo "----- GENERATE AND SHARE COROSYNC KEY -----"
ssh $MYUSER@$MYPUBIP1 sudo corosync-keygen
ssh $MYUSER@$MYPUBIP1 sudo ls -lai /etc/corosync/authkey 
ssh $MYUSER@$MYPUBIP1 sudo cp /etc/corosync/authkey /tmp
ssh $MYUSER@$MYPUBIP1 sudo chown $MYUSER /tmp/authkey
scp $MYUSER@$MYPUBIP1:/tmp/authkey /tmp
ssh $MYUSER@$MYPUBIP1 rm /tmp/authkey
scp /tmp/authkey $MYUSER@$MYPUBIP2:/tmp/authkey
rm /tmp/authkey
ssh $MYUSER@$MYPUBIP2 sudo mv /tmp/authkey /etc/corosync
ssh $MYUSER@$MYPUBIP2 sudo chown root: /etc/corosync/authkey
ssh $MYUSER@$MYPUBIP2 sudo chmod 400 /etc/corosync/authkey
ssh $MYUSER@$MYPUBIP2 sudo ls -lai /etc/corosync/authkey 



echo "----- PROVIDE DELETE CMD -----"
echo "Delete cmd: az group delete --name ${MYAZRG}  -y"