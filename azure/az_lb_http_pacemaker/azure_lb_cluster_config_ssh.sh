#!/bin/bash -eu

# Prepare all the ssh connections within the 2 internal VMs
. ./utils.sh

MY_PUBIP_ADDR="$(get_pub_ip)"
MY_INTERNAL_KEY="id_rsa" # no other names works, this is the only key filename added by default
HOSTKEYCHECK="accept-new"
[[ $MY_OS =~ "12-sp5" ]] && HOSTKEYCHECK=no

test_step "Clean up known_hosts on the machine running the test script"
ssh-keygen -R $MY_PUBIP_ADDR
test_step "Accept bastion host key"
ssh -i $MYSSHKEY -o StrictHostKeyChecking=$HOSTKEYCHECK $MY_USERNAME@$MY_PUBIP_ADDR whoami
if [[ $MY_OS =~ "12-sp5" ]]; then
  MY_SSH_USERS="${MY_USERNAME} root"
else
  # then crm will be used in rootless mode
  MY_SSH_USERS="${MY_USERNAME}"
fi
for NUM in $(seq $MY_NUM); do
  this_vm="${MYNAME}-vm-0${NUM}"

  echo "this_vm:${this_vm}"
  ssh-keygen -R $this_vm
  #test_step "[${this_vm}] accept the bastion key"
  #ssh_bastion 'ssh -o StrictHostKeyChecking='"${HOSTKEYCHECK}"' '"${MY_USERNAME}@${this_vm}"' whoami'

  test_step "[${this_vm}] accept the host key for the internal VM on the machine running the test script"
  # This is for the first connection between:
  # -  the local machine running the test (e.g. your laptop)
  # -  each one of the two internal VM
  ssh "${MY_USERNAME}@${this_vm}" \
      -oProxyCommand="ssh ${MY_USERNAME}@${MY_PUBIP_ADDR} -i $MYSSHKEY -W %h:%p" \
      -oStrictHostKeyChecking=$HOSTKEYCHECK \
      -i $MYSSHKEY \
      whoami

  test_step "[${this_vm}] reach with ssh ProxyCmmand and check hostname"
  ssh_proxy $this_vm "hostname" | grep "${this_vm}" || test_die "VM ${this_vm} is not reachable with ProxyCommand"

  for this_user in ${MY_SSH_USERS}; do
    this_home=$(ssh_proxy $this_vm "echo ~$this_user")
    #this_home=$( ssh_proxy $this_vm "getent passwd $this_user | cut -d: -f6" )
    this_home_ssh="${this_home}/.ssh"
    this_tmp="/tmp/${this_vm}/${this_user}"
    if [[ $this_user =~ "root" ]]; then
      this_own="root:root"
    else
      this_own="${this_user}:users"
    fi

    test_step "[${this_vm}] Check if the folder ${this_home_ssh} exist in the ${this_vm}"
    ssh_proxy $this_vm "sudo [ -d ${this_home_ssh} ]" || test_die "Missing ${this_home_ssh}"

    test_step "[${this_vm}] Check if the key ${this_home_ssh}/${MY_INTERNAL_KEY} exist in the ${this_vm}"
    if ssh_proxy $this_vm "sudo [ -f ${this_home_ssh}/${MY_INTERNAL_KEY} ]" ; then
      echo "The key is already there"
      #continue
    fi

    test_step "[${this_vm}] Generate a ssh key pair the machine running the test script in the folder ${this_tmp}"
    rm -rf "${this_tmp}"
    mkdir -p "${this_tmp}"
    ssh-keygen \
      -N "" \
      -t rsa \
      -C "Temp internal cluster key for ${this_user} on ${this_vm}" \
      -f "${this_tmp}/${MY_INTERNAL_KEY}"
    test_step "[${this_vm}] Move the temp key for user:${this_user} from the machine running the test script to the internal VM"
    for this_key in "${MY_INTERNAL_KEY}" "${MY_INTERNAL_KEY}.pub"; do
      scp_proxy "${this_tmp}/${this_key} ${MY_USERNAME}@${this_vm}:/tmp/${this_key}"
      ssh_proxy $this_vm "sudo mv /tmp/${this_key} ${this_home_ssh}/${this_key}"
      ssh_proxy $this_vm "sudo chown ${this_own} ${this_home_ssh}/${this_key}"
      ssh_proxy $this_vm "sudo chmod 0600 ${this_home_ssh}/${this_key}"
    done
  done
done

for this_user in ${MY_SSH_USERS}; do
  this_home=$(ssh_proxy $this_vm "echo ~$this_user")
  this_home_ssh="${this_home}/.ssh"
  this_src_vm="${MYNAME}-vm-01"
  this_dst_vm="${MYNAME}-vm-02"
  test_step "Put ${this_src_vm} pub key as authorized key in ${this_dst_vm} for user ${this_user}"
  this_pub_key="$(cat /tmp/${this_src_vm}/${this_user}/${MY_INTERNAL_KEY}.pub)"
  if [[ $this_user =~ "root" ]]; then
    ssh_proxy "${this_dst_vm}" \
        "sudo sh -c 'echo \"${this_pub_key}\" >> ${this_home_ssh}/authorized_keys'" || \
            test_die "Unable to write on ${this_home_ssh}/authorized_keys"
  else
    ssh_proxy "${this_dst_vm}" \
        "echo \"${this_pub_key}\" >> ${this_home_ssh}/authorized_keys" || \
            test_die "Unable to write on ${this_home_ssh}/authorized_keys"
  fi

  this_src_vm="${MYNAME}-vm-02"
  this_dst_vm="${MYNAME}-vm-01"
  test_step "Put ${this_src_vm} pub key as authorized key in ${this_dst_vm}"
  this_pub_key="$(cat /tmp/${MYNAME}-vm-02/${this_user}/${MY_INTERNAL_KEY}.pub)"
  if [[ $this_user =~ "root" ]]; then
    ssh_proxy "${this_dst_vm}" \
        "sudo sh -c 'echo \"${this_pub_key}\" >> ${this_home_ssh}/authorized_keys'" || \
            test_die "Unable to write on ${this_home_ssh}/authorized_keys"
  else
    ssh_proxy "${this_dst_vm}" \
        "echo \"${this_pub_key}\" >> ${this_home_ssh}/authorized_keys" || \
            test_die "Unable to write on ${this_home_ssh}/authorized_keys"
  fi
done

for NUM in $(seq $MY_NUM); do
  this_vm="${MYNAME}-vm-0${NUM}"
  echo "this_vm:${this_vm}"

  test_step "[${this_vm}] Accept host key between the two internal VM"
  for OTHER_NUM in $(seq $MY_NUM); do
    if [ "$NUM" -eq "$OTHER_NUM" ]; then
        continue
    fi
    other_vm="${MYNAME}-vm-0${OTHER_NUM}"
    for this_user in ${MY_SSH_USERS}; do
      my_cmd="ssh ${this_user}@${other_vm} -oStrictHostKeyChecking=${HOSTKEYCHECK} whoami"
      if [[ $this_user =~ "root" ]]; then
        my_cmd="sudo ${my_cmd}"
      fi
      ssh_proxy $this_vm "${my_cmd}" || test_die "User ${this_user} on VM ${this_vm} is not able to ssh ${other_vm}"
    done
  done
done
