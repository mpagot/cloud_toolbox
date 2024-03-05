#!/bin/bash -e

# Create two mostly identical VM and configure a cluster

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


echo "----- CHECK SSH CONNECTIVITY -----"
ssh -l $MYUSER -o UpdateHostKeys=yes -o StrictHostKeyChecking=accept-new $MYUSER@$MYPUBIP1 test || echo "Something wrong with $MYUSER@$MYPUBIP1"
ssh -l $MYUSER -o UpdateHostKeys=yes -o StrictHostKeyChecking=accept-new $MYUSER@$MYPUBIP2 test || echo "Something wrong with $MYUSER@$MYPUBIP2"

echo "----- CREATE AND SHARE INTERNAL SSH KEYS -----"
for this_vm in "${MYAZVM}-1" "${MYAZVM}-2"; do
  this_ip=$(az network public-ip show --ids $(az network nic show --ids $(az vm show \
    --resource-group ${MYAZRG} \
    --name "${this_vm}" \
    --query "networkProfile.networkInterfaces[0].id" -o tsv) \
    --query "ipConfigurations[0].publicIPAddress.id" -o tsv) --query "ipAddress" -o tsv)

  ssh $MYUSER@$this_ip sudo [ -d "/root/.ssh" ]

  # Generate public/private keys for root on hana hosts
  ssh $MYUSER@$this_ip sudo [ -f "/root/.ssh/id_rsa" ]
  echo $?

  # Generate a temp key on the JumpHost
  this_tmp="/tmp/${this_vm}/root"
  rm -rf "${this_tmp}"
  mkdir -p "${this_tmp}"
  ssh-keygen \
    -N '' \
    -C "Temp internal cluster key for root on ${this_vm}" \
    -f "${this_tmp}/id_rsa"

  for this_key in 'id_rsa' 'id_rsa.pub'; do
    scp "${this_tmp}/${this_key}" \
      $MYUSER@$this_ip:/tmp/${this_key}

    # mv /tmp/id_rsa /root/.ssh/id_rsa
    ssh $MYUSER@$this_ip sudo mv "/tmp/${this_key}" "/root/.ssh/${this_key}"

    # chown root:root /root/.ssh/id_rsa
    ssh $MYUSER@$this_ip sudo chown root:root "/root/.ssh/${this_key}"

    # chmod 0600 /root/.ssh/id_rsa
    ssh $MYUSER@$this_ip sudo chmod 0600 "/root/.ssh/${this_key}"
  done
  ssh $MYUSER@$this_ip sudo ls -lai "/root/.ssh/"
done

# Copy the pub key for root on vm1 to host vm2
scp "/tmp/${MYAZVM}-1/root/id_rsa.pub" \
  "$MYUSER@$MYPUBIP2:/tmp/id_rsa.pub"
scp "/tmp/${MYAZVM}-2/root/id_rsa.pub" \
  "$MYUSER@$MYPUBIP1:/tmp/id_rsa.pub"

# Add vm1 pub key in authorized_keys of vm2
ssh $MYUSER@$MYPUBIP1 sudo sh -c '"cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys"'
ssh $MYUSER@$MYPUBIP2 sudo sh -c '"cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys"'


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

# ssh $MYUSER@$MYPUBIP1 sudo crm cluster init -y --name "${MYAZVM}-1 ${MYAZVM}-2"
# ssh $MYUSER@$MYPUBIP2 sudo sudo crm cluster join -c "${MYAZVM}-1"
