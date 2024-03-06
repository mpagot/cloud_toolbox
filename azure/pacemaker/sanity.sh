#!/bin/bash -e

# Create two mostly identical VM and configure a cluster
# This file verify the environment before to start interacting with it

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


for i in $(seq 2); do
  this_vm="${MYAZVM}-${i}"
  test_step "[${this_vm}] GET USERNAME AND IP"
  this_ip=$(get_ip "${i}")
  SSH_DST="${MYAZVMUSR}@${this_ip}"
  echo "--> SSH_DST:${SSH_DST}"

  test_step "[${this_vm}] CHECK SSH CONNECTIVITY"
  check_ssh_connectivity $this_ip

  test_step "[${this_vm}] CHECK NET CONFIGURATION"
  ssh ${SSH_DST} ip a show eth0
  ssh ${SSH_DST} ip -br -c addr show eth0
  ssh ${SSH_DST} hostname -i
  ssh ${SSH_DST} cat /etc/host.conf | grep multi

  test_step "[${this_vm}] Check how many IPv4 IpConfigs"
  ssh ${SSH_DST} ip a show eth0 | grep -c 'inet '

  test_step "[${this_vm}] CHECK SSH KEYS"
  ssh ${SSH_DST} sudo [ -d "/root/.ssh" ] || test_die "Missing .ssh folder for root"
  ssh ${SSH_DST} sudo [ -f "/root/.ssh/id_rsa" ] || test_die "Missing private ssh key for root"
  #ssh ${SSH_DST} sudo ls -lai "/root/.ssh/"

  test_step "[${this_vm}] Check cluster"
  ssh ${SSH_DST} sudo crm status
done

test_step "[${this_vm}] Ping by hostname"
ssh ${MYUSER}@${MYPUBIP1} ping -c 3 ${MYAZVM}-2
ssh ${MYUSER}@${MYPUBIP2} ping -c 3 ${MYAZVM}-1

test_step "[${this_vm}] Ping using the private IP"
export MYPRIVIP1=$(ssh ${MYUSER}@${MYPUBIP1} ip a show eth0 | grep -oP '(?<=inet ).*(?=/24.*)')
export MYPRIVIP2=$(ssh ${MYUSER}@${MYPUBIP2} ip a show eth0 | grep -oP '(?<=inet ).*(?=/24.*)')
ssh ${MYUSER}@${MYPUBIP1} ping -c 3 ${MYPRIVIP2}
ssh ${MYUSER}@${MYPUBIP2} ping -c 3 ${MYPRIVIP1}

test_step "[${this_vm}] Passwordless root ssh"
ssh ${MYUSER}@${MYPUBIP1} sudo ssh root@${MYPRIVIP2} hostname | grep "${MYAZVM}-2"
ssh ${MYUSER}@${MYPUBIP1} sudo ssh root@${MYPRIVIP2} whoami | grep root
ssh ${MYUSER}@${MYPUBIP2} sudo ssh root@${MYPRIVIP1} hostname | grep "${MYAZVM}-1"
ssh ${MYUSER}@${MYPUBIP2} sudo ssh root@${MYPRIVIP1} whoami | grep root

