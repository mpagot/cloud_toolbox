#!/bin/bash -eu

# Prepare all the ssh connections within the 2 internal VMs
. ./utils.sh

MY_PUBIP_ADDR="$(get_pub_ip)"
MY_INTERNAL_KEY="id_rsa" # no other names works, this is the only key filename added by default

test_step "Clean up known_hosts on the machine running the test script"
ssh-keygen -R $MY_PUBIP_ADDR
test_step "Accept bastion host key"
ssh -i $MYSSHKEY -o StrictHostKeyChecking=accept-new $MY_USERNAME@$MY_PUBIP_ADDR whoami

for NUM in $(seq $MY_NUM); do
  this_vm="${MYNAME}-vm-0${NUM}"

  echo "-------> this_vm:${this_vm}"
  ssh-keygen -R $this_vm
  #test_step "[${this_vm}] accept the bastion key"
  #ssh_bastion 'ssh -o StrictHostKeyChecking=accept-new '"${MY_USERNAME}@${this_vm}"' whoami'

  test_step "[${this_vm}] accept the host key for the internal VM on the machine running the test script"
  ssh "${MY_USERNAME}@${this_vm}" \
      -oProxyCommand="ssh ${MY_USERNAME}@${MY_PUBIP_ADDR} -i $MYSSHKEY -W %h:%p" \
      -oStrictHostKeyChecking=accept-new \
      -i $MYSSHKEY \
      whoami

  test_step "[${this_vm}] reach with ssh ProxyCmmand and check hostname"
  ssh_proxy $this_vm "hostname" | grep "${this_vm}" || test_die "VM ${this_vm} is not reachable with ProxyCommand"

  test_step "[${this_vm}] Check if the folder /home/${MY_USERNAME}/.ssh exist in the ${this_vm}"
  ssh_proxy $this_vm "sudo [ -d /home/${MY_USERNAME}/.ssh ]" || test_die "Missing /home/${MY_USERNAME}/.ssh"

  test_step "[${this_vm}] Check if the key /home/${MY_USERNAME}/.ssh/${MY_INTERNAL_KEY} exist in the ${this_vm}"
  if ssh_proxy $this_vm "sudo [ -f /home/${MY_USERNAME}/.ssh/${MY_INTERNAL_KEY} ]" ; then
    echo "The key is already there"
    #continue
  fi

  this_tmp="/tmp/${this_vm}/${MY_USERNAME}"
  test_step "[${this_vm}] Generate a ssh key pair the machine running the test script in the folder ${this_tmp}"
  rm -rf "${this_tmp}"
  mkdir -p "${this_tmp}"
  ssh-keygen \
    -N "" \
    -t rsa \
    -C "Temp internal cluster key for cloudadmin on ${this_vm}" \
    -f "${this_tmp}/${MY_INTERNAL_KEY}"

  test_step "[${this_vm}] Move the temp key from the machine running the test script to the internal VM"
  for this_key in "${MY_INTERNAL_KEY}" "${MY_INTERNAL_KEY}.pub"; do
    scp_proxy "${this_tmp}/${this_key} ${MY_USERNAME}@${this_vm}:/tmp/${this_key}"
    ssh_proxy $this_vm "sudo mv /tmp/${this_key} /home/${MY_USERNAME}/.ssh/${this_key}"
    ssh_proxy $this_vm "sudo chown ${MY_USERNAME}:users /home/${MY_USERNAME}/.ssh/${this_key}"
    ssh_proxy $this_vm "sudo chmod 0600 /home/${MY_USERNAME}/.ssh/${this_key}"
  done
done

test_step "Put ${MYNAME}-vm-01 pub key as authorized key in ${MYNAME}-vm-02"
MY_PUB_KEY_VM1="$(cat /tmp/${MYNAME}-vm-01/${MY_USERNAME}/${MY_INTERNAL_KEY}.pub)"
ssh_proxy "${MYNAME}-vm-02" "echo \"${MY_PUB_KEY_VM1}\" >> /home/${MY_USERNAME}/.ssh/authorized_keys"

test_step "Put ${MYNAME}-vm-02 pub key as authorized key in ${MYNAME}-vm-01"
MY_PUB_KEY_VM2="$(cat /tmp/${MYNAME}-vm-02/${MY_USERNAME}/${MY_INTERNAL_KEY}.pub)"
ssh_proxy "${MYNAME}-vm-01" "echo \"${MY_PUB_KEY_VM2}\" >> /home/${MY_USERNAME}/.ssh/authorized_keys"

for NUM in $(seq $MY_NUM); do
  this_vm="${MYNAME}-vm-0${NUM}"
  echo "-------> this_vm:${this_vm}"

  test_step "[${this_vm}] Accept host key between the two internal VM"
  for OTHER_NUM in $(seq $MY_NUM); do
    if [ "$NUM" -eq "$OTHER_NUM" ]; then
        continue
    fi
    other_vm="${MYNAME}-vm-0${OTHER_NUM}"
    ssh_proxy $this_vm "ssh ${MY_USERNAME}@${other_vm} -oStrictHostKeyChecking=accept-new whoami" || test_die "${this_vm} is not able to ssh ${other_vm}"
  done
done