# configurable parameters
if [[ ! -v MYNAME ]]; then
  echo "MYNAME must be set to derive all the other settings"
  exit 1
elif [[ -z "${MYNAME}" ]]; then
  echo "MYNAME must have an non empty value to derive all the other settings"
  exit 1
fi


MY_USERNAME=cloudadmin
AZ="${AZ:-"az"}"
MY_REGION="${MY_REGION:-"northeurope"}"
MY_OS="${MY_OS:-"SUSE:sles-sap-15-sp5:gen2:latest"}"
MY_PRIV_IP_RANGE="${MY_PRIV_IP_RANGE:-"192.168.1"}"

# set of names reused more than one time
MY_GROUP="${MYNAME}_1vm_rg"
MY_SUBNET="${MYNAME}_sn"
MY_VNET="${MYNAME}_vnet"
MY_PUBIP="${MYNAME}_pubip"
MY_VM="${MYNAME}-vm"
# Storage account name must be between 3 and 24 characters in length
# and use numbers and lower-case letters only.
[[ -n "${AZ_1V_BOOTLOG}" ]] && MY_STORAGE_ACCOUNT="${MYNAME//_/}storageaccount"

print_howto () {
  MY_PUBIP_ADDR="$(get_pub_ip)"
  echo "------------------------------------------------------"
  echo "|   Bastion 'ssh -i ${MYSSHKEY} ${MY_USERNAME}@${MY_PUBIP_ADDR}"''
  echo "|"
  echo "|   Internal VM 'ssh ${MY_USERNAME}@${MYNAME}-vm-01 -oProxyCommand=\"ssh ${MY_USERNAME}@${MY_PUBIP_ADDR} -i ${MYSSHKEY} -W %h:%p\" -i ${MYSSHKEY}"
  echo "|"
  echo "|   Destroy all with 'az group delete --name $MY_GROUP -y'"
  echo "------------------------------------------------------"
}

get_pub_ip () {
  az network public-ip show -g $MY_GROUP -n $MY_PUBIP --query 'ipAddress' -o tsv
}

test_step () {
  echo "##############################"
  echo "# $1"
  echo "##############################"
}

test_die () {
  echo "DIE : $1"
  exit 1
}

ssh_vm () {
  if [ -z "${MY_PUBIP_ADDR}" ]
  then
    echo "MY_PUBIP_ADDR must be set before to call ssh_vm()"
  else
    ssh -i $MYSSHKEY $MY_USERNAME@$MY_PUBIP_ADDR "$*"
  fi
}


test_connectivity () {
  for NUM in $(seq $MY_NUM); do
    this_vm="${MYNAME}-vm-0${NUM}"
    test_step "[${this_vm}] connectivity"
    for OTHER_NUM in $(seq $MY_NUM); do
      if [ "$NUM" -eq "$OTHER_NUM" ]; then
        continue
      fi
      other_vm="${MYNAME}-vm-0${OTHER_NUM}"
      test_step "[${this_vm}]-->[${other_vm}] ping IP"
      ssh_proxy $this_vm "ping -c 5 192.168.1.4${OTHER_NUM}" || test_die "${this_vm} is not able to ping ${other_vm} at 192.168.1.4${OTHER_NUM}"
      test_step "[${this_vm}]-->[${other_vm}] ping name"
      ssh_proxy $this_vm "ping -c 5 ${other_vm}" || test_die "${this_vm} is not able to ping ${other_vm} by name"
      test_step "[${this_vm}]-->[${other_vm}] ssh"
      ssh_proxy $this_vm "ssh ${MY_USERNAME}@${other_vm} whoami" || test_die "${this_vm} is not able to ssh ${other_vm}"
      #test_step "[${this_vm}]-->[${other_vm}] sudo ssh"
      #ssh_proxy $this_vm "sudo ssh ${MY_USERNAME}@${other_vm} whoami" || test_die "${this_vm} is not able to sudo ssh ${other_vm}"
    done
  done
}

check_key_env () {
  if [[ ! -v MYSSHKEY ]]; then
    echo "MYSSHKEY must be set"
    exit 1
  elif [[ -z "${MYSSHKEY}" ]]; then
    echo "MYSSHKEY must have an non empty value"
    exit 1
  elif [[ ! -f "${MYSSHKEY}" ]]; then
    echo "provided ssh key file MYSSHKEY:${MYSSHKEY} couldn't be found"
    exit 1
  elif [[ ! -f "${MYSSHKEY}.pub" ]]; then
    echo "Public key associated to the provided ssh key file MYSSHKEY:${MYSSHKEY} couldn't be found"
    exit 1
  fi
}
