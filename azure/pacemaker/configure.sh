#!/bin/bash -e

# Create two mostly identical VM and configure a cluster

. ./utils.sh

validate_options

test_step "GET USERNAME AND IP"
export MYUSER="${MYUSER:-$(get_user)}"
export MYIP1="${MYIP1:-$(get_ip "1")}"
export MYIP2="${MYIP2:-$(get_ip "2")}"

test_step "CHECK SSH CONNECTIVITY"
check_ssh_connectivity $MYIP1
check_ssh_connectivity $MYIP2

test_step "CREATE AND SHARE INTERNAL SSH KEYS"
for i in $(seq 2); do
  this_vm="${MYAZVM}-${i}"
  echo "Get the IP of the ${this_vm}"
  this_ip=$(get_ip "${i}")

  echo "Check if the folder /root/.ssh exist of the ${this_vm}"
  ssh $MYUSER@$this_ip sudo [ -d "/root/.ssh" ] || test_die "Missing /root/.ssh"

  echo "Check if the key /root/.ssh/id_rsa exist of the ${this_vm}"
  if ssh $MYUSER@$this_ip sudo [ -f "/root/.ssh/id_rsa" ] ; then
    echo "The key is already there"
    continue
  fi

  # Generate public/private keys for root on hana hosts
  this_tmp="/tmp/${this_vm}/root"
  echo "Generate a temp key on the JumpHost in the folder ${this_tmp}"
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
#if ssh $MYUSER@$MYIP1 sudo grep 'Temp internal cluster key for root on' /root/.ssh/authorized_keys ; then
#    echo "The key is already authorized"
#fi

scp "/tmp/${MYAZVM}-1/root/id_rsa.pub" \
  "$MYUSER@$MYIP2:/tmp/id_rsa.pub"
scp "/tmp/${MYAZVM}-2/root/id_rsa.pub" \
  "$MYUSER@$MYIP1:/tmp/id_rsa.pub"

# Add vm1 pub key in authorized_keys of vm2
ssh $MYUSER@$MYIP1 sudo sh -c '"cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys"'
ssh $MYUSER@$MYIP2 sudo sh -c '"cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys"'

test_step "ZYPPER REFRESH"
ssh $MYUSER@$MYIP1 sudo zypper refresh || test_die "Something wrong during zypper refresh on $MYUSER@$MYIP1"
ssh $MYUSER@$MYIP2 sudo zypper refresh || test_die "Something wrong during zypper refresh on $MYUSER@$MYIP2"

test_step "CHECK FOR COROSYNC AND PACEMAKER PRESENCE"
ssh $MYUSER@$MYIP1 zypper se -i -s corosync pacemaker
ssh $MYUSER@$MYIP2 zypper se -i -s corosync pacemaker

# Seems not needed
#test_step "GENERATE AND SHARE COROSYNC KEY"
#ssh $MYUSER@$MYIP1 sudo corosync-keygen
#ssh $MYUSER@$MYIP1 sudo ls -lai /etc/corosync/authkey
#ssh $MYUSER@$MYIP1 sudo cp /etc/corosync/authkey /tmp
#ssh $MYUSER@$MYIP1 sudo chown $MYUSER /tmp/authkey
#scp $MYUSER@$MYIP1:/tmp/authkey /tmp
#ssh $MYUSER@$MYIP1 rm /tmp/authkey
#scp /tmp/authkey $MYUSER@$MYIP2:/tmp/authkey
#rm /tmp/authkey
#ssh $MYUSER@$MYIP2 sudo mv /tmp/authkey /etc/corosync
#ssh $MYUSER@$MYIP2 sudo chown root: /etc/corosync/authkey
#ssh $MYUSER@$MYIP2 sudo chmod 400 /etc/corosync/authkey
#ssh $MYUSER@$MYIP2 sudo ls -lai /etc/corosync/authkey

test_step "CREATE THE CLUSTER"
ssh $MYUSER@$MYIP1 sudo crm cluster init -y -N "${MYAZVM}-1" -N "${MYAZVM}-2"
# Join seems not to be needed
# ssh $MYUSER@$MYIP2 sudo crm cluster join -y -c "${MYAZVM}-1"

ssh $MYUSER@$MYIP1 "sudo crm configure primitive \
      ${MYAZVIPRES} \
      ocf:heartbeat:IPaddr2 \
      meta \
      target-role=\"Started\" \
      operations \
      \\\$id=\"${MYAZVIPRES}-operations\" \
      op monitor interval=\"10s\" timeout=\"20s\" \
      params ip=\"${MYAZVIP}\""