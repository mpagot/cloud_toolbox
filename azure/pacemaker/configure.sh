#!/bin/bash -e

# Create two mostly identical VM and configure a cluster

. ./utils.sh

test_step "VALIDATION OF THE CONFIGURATIONS"

echo "MYAZRG=${MYAZRG}"
echo "MYAZVNET=${MYAZVNET}"
echo "MYAZSNET=${MYAZSNET}"
echo "MYAZPIPPRE=${MYAZPIPPRE}"
echo "MYAZNSG=${MYAZNSG}"
echo "MYAZNICPRE=${MYAZNICPRE}"
echo "MYAZVM=${MYAZVM}"
echo "MYAZVMUSR=${MYAZVMUSR}"


test_step "GET USERNAME AND IP"
export MYUSER=$(get_user)
export MYPUBIP1=$(get_ip "1")
export MYPUBIP2=$(get_ip "2")

test_step "CHECK SSH CONNECTIVITY"
check_ssh_connectivity $MYPUBIP1
check_ssh_connectivity $MYPUBIP2

test_step "CREATE AND SHARE INTERNAL SSH KEYS"
for i in $(seq 2); do
  this_vm="${MYAZVM}-${i}"
  this_ip=$(get_ip "${i}")

  ssh $MYUSER@$this_ip sudo [ -d "/root/.ssh" ] || test_die "Missing /root/.ssh"

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

test_step "ZYPPER REFRESH"
ssh $MYUSER@$MYPUBIP1 sudo zypper refresh || test_die "Something wrong during zypper refresh on $MYUSER@$MYPUBIP1"
ssh $MYUSER@$MYPUBIP2 sudo zypper refresh || test_die "Something wrong during zypper refresh on $MYUSER@$MYPUBIP2"

test_step "CHECK FOR COROSYNC AND PACEMAKER PRESENCE"
ssh $MYUSER@$MYPUBIP1 zypper se -i -s corosync pacemaker
ssh $MYUSER@$MYPUBIP2 zypper se -i -s corosync pacemaker

# Seems not needed
#test_step "GENERATE AND SHARE COROSYNC KEY"
#ssh $MYUSER@$MYPUBIP1 sudo corosync-keygen
#ssh $MYUSER@$MYPUBIP1 sudo ls -lai /etc/corosync/authkey
#ssh $MYUSER@$MYPUBIP1 sudo cp /etc/corosync/authkey /tmp
#ssh $MYUSER@$MYPUBIP1 sudo chown $MYUSER /tmp/authkey
#scp $MYUSER@$MYPUBIP1:/tmp/authkey /tmp
#ssh $MYUSER@$MYPUBIP1 rm /tmp/authkey
#scp /tmp/authkey $MYUSER@$MYPUBIP2:/tmp/authkey
#rm /tmp/authkey
#ssh $MYUSER@$MYPUBIP2 sudo mv /tmp/authkey /etc/corosync
#ssh $MYUSER@$MYPUBIP2 sudo chown root: /etc/corosync/authkey
#ssh $MYUSER@$MYPUBIP2 sudo chmod 400 /etc/corosync/authkey
#ssh $MYUSER@$MYPUBIP2 sudo ls -lai /etc/corosync/authkey

test_step "CREATE THE CLUSTER"
ssh $MYUSER@$MYPUBIP1 sudo crm cluster init -y -N "${MYAZVM}-1" -N "${MYAZVM}-2"
# Join seems not to be needed
# ssh $MYUSER@$MYPUBIP2 sudo crm cluster join -y -c "${MYAZVM}-1"

