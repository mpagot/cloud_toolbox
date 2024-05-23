#!/bin/bash -eu

# Prepare all the ssh connections within the 2 internal VMs
# create the cluster
. ./utils.sh

MY_PUBIP_ADDR="$(get_pub_ip)"
MY_INTERNAL_KEY="id_rsa" # no other names works, this is the only key filename added by default

ssh -i $MYSSHKEY -o StrictHostKeyChecking=accept-new $MY_USERNAME@$MY_PUBIP_ADDR whoami
# Upload the private key to be able to use it to communicate between the bastion and the nodes,
# all the VM has the .pub key uploaded directly by the az vm create
scp -i $MYSSHKEY $MYSSHKEY $MY_USERNAME@$MY_PUBIP_ADDR:.ssh/

for NUM in $(seq $MY_NUM); do
  this_vm="${MYNAME}-vm-0${NUM}"

  echo "-------> this_vm:${this_vm}"
  ssh_bastion 'ssh -o StrictHostKeyChecking=accept-new '"${MY_USERNAME}@${this_vm}"' whoami'

  echo "Check if the folder /home/${MY_USERNAME}/.ssh exist in the ${this_vm}"
  ssh_bastion 'ssh '"${MY_USERNAME}@${this_vm}"' sudo [ -d "/home/'"${MY_USERNAME}"'/.ssh" ]' || test_die "Missing /home/${MY_USERNAME}/.ssh"

  echo "Check if the key /home/${MY_USERNAME}/.ssh/${MY_INTERNAL_KEY} exist in the ${this_vm}"
  if ssh_bastion 'ssh '"${MY_USERNAME}@${this_vm}"' sudo [ -f "/home/'"${MY_USERNAME}"'/.ssh/'"${MY_INTERNAL_KEY}"'" ]' ; then
    echo "The key is already there"
    #continue
  fi

  # Generate public/private keys for cloudadmin on hana hosts
  this_tmp="/tmp/${this_vm}/root"
  echo "Generate a temp key on the JumpHost in the folder ${this_tmp}"
  ssh_bastion 'rm -rf '"${this_tmp}"
  ssh_bastion 'mkdir -p '"${this_tmp}"
  ssh_bastion 'ssh-keygen \
    -N "" \
    -t rsa \
    -C "Temp internal cluster key for cloudadmin on '"${this_vm}"'" \
    -f '"${this_tmp}/${MY_INTERNAL_KEY}"

  for this_key in "${MY_INTERNAL_KEY}" "${MY_INTERNAL_KEY}.pub"; do
    ssh_bastion 'scp '"${this_tmp}/${this_key}"' '"${MY_USERNAME}@${this_vm}:/tmp/${this_key}"
    ssh_bastion 'ssh '"${MY_USERNAME}@${this_vm}"' sudo mv /tmp/'"${this_key}"' /home/'"${MY_USERNAME}"'/.ssh/'"${this_key}"
    ssh_bastion 'ssh '"${MY_USERNAME}@${this_vm}"' sudo chown '"${MY_USERNAME}"':users /home/'"${MY_USERNAME}"'/.ssh/'"${this_key}"
    ssh_bastion 'ssh '"${MY_USERNAME}@${this_vm}"' sudo chmod 0600 /home/'"${MY_USERNAME}"'/.ssh/'"${this_key}"
  done
done

MY_PUB_KEY_VM1="$(ssh_bastion 'cat /tmp/'"${MYNAME}-vm-01/root/${MY_INTERNAL_KEY}.pub")"
ssh_bastion 'ssh '"${MY_USERNAME}@${MYNAME}-vm-02"' "echo "'"${MY_PUB_KEY_VM1}"'" >> '"/home/${MY_USERNAME}/.ssh/authorized_keys"'"'

MY_PUB_KEY_VM2="$(ssh_bastion 'cat /tmp/'"${MYNAME}-vm-02/root/${MY_INTERNAL_KEY}.pub")"
ssh_bastion 'ssh '"${MY_USERNAME}@${MYNAME}-vm-01"' "echo "'"${MY_PUB_KEY_VM2}"'" >> '"/home/${MY_USERNAME}/.ssh/authorized_keys"'"'

ssh_bastion 'ssh '"${MY_USERNAME}@${MYNAME}-vm-01"' sudo crm cluster init -y --name DONALDUCK' || test_die "Fails in crm cluster init"
ssh_bastion 'ssh '"${MY_USERNAME}@${MYNAME}-vm-02"' sudo crm cluster join -y -c '"${MY_USERNAME}@${MYNAME}-vm-01" || test_die "Fails in crm cluster join"

ssh_bastion 'ssh '"${MY_USERNAME}@${MYNAME}-vm-01"' sudo crm configure property maintenance-mode=true'
ssh_bastion 'ssh '"${MY_USERNAME}@${MYNAME}-vm-01"' sudo crm configure primitive rsc_ip_00 ocf:heartbeat:IPaddr2 meta target-role="Started" operations \\\$id="rsc_ip_RES-operations" op monitor interval="10s" timeout="20s" params ip="'"${MY_FIP}"'"'  || test_die "Fails in create IPaddr2 resource"
ssh_bastion 'ssh '"${MY_USERNAME}@${MYNAME}-vm-01"' sudo crm configure primitive rsc_alb_00 azure-lb port=62500 op monitor timeout=20s interval=10' || test_die "Fails in create azure-lb resource"
ssh_bastion 'ssh '"${MY_USERNAME}@${MYNAME}-vm-01"' sudo crm configure group rsc_grp_00 rsc_alb_00 rsc_ip_00' || test_die "Fails in create group"
ssh_bastion 'ssh '"${MY_USERNAME}@${MYNAME}-vm-01"' sudo crm configure property maintenance-mode=false'