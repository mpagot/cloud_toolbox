# configurable parameters
if [[ ! -v MYNAME ]]; then
  echo "MYNAME must be set to derive all the other settings"
  exit 1
elif [[ -z "${MYNAME}" ]]; then
  echo "MYNAME must have an non empty value to derive all the other settings"
  exit 1
fi

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

MY_USERNAME=cloudadmin
AZ="${AZ:-"az"}"
MY_TMP="${MY_TMP:-"/tmp"}"
MY_REMOTE_TMP="${MY_REMOTE_TMP:-"/tmp"}"
MY_NUM="${MY_NUM:-"2"}"
MY_REGION="${MY_REGION:-"northeurope"}"
MY_OS="${MY_OS:-"SUSE:sles-sap-15-sp5:gen2:latest"}"
MY_PRIV_IP_RANGE="${MY_PRIV_IP_RANGE:-"192.168.1"}"

# set of names reused more than one time
MY_GROUP="${MYNAME}_lb_rg"
MY_VNET="${MYNAME}_vnet"
MY_SUBNET="${MYNAME}_sn"
MY_NSG="${MYNAME}_nsg"
MY_AS="${MYNAME}_as"
MY_PUBIP="${MYNAME}_pubip"
MY_NAT_PUBIP="${MYNAME}_nat_pubip"
MY_NAT="${MYNAME}_nat"
MY_LB="${MYNAME}_loadbalancer"
MY_BE_POOL="${MYNAME}_backend_pool"
MY_HPROBE="${MYNAME}_health"
MY_HPROBE_PORT="62500"
MY_FIP_NAME="${MYNAME}_frontend_ip"
MY_FIP="${MY_PRIV_IP_RANGE}.50"
MY_BASTION="${MYNAME}-vm-bastion"
MY_MOVE_RES="rsc_web_00"


# Storage account name must be between 3 and 24 characters in length
# and use numbers and lower-case letters only.
AZ_BOOTLOG="${AZ_BOOTLOG:-"0"}"
if [[ AZ_BOOTLOG -eq 1 ]]; then
  echo "AZ_BOOTLOG:${AZ_BOOTLOG} enabled."
  [[ -n "${AZ_BOOTLOG}" ]] && MY_STORAGE_ACCOUNT=$(echo "${MYNAME//_/}storageaccount" | tr '[:upper:]' '[:lower:]')
  [[ "${#MY_STORAGE_ACCOUNT}" -gt 24 ]] && test_die "Too long storageaccount name ${MY_STORAGE_ACCOUNT}"
fi
AZ_CLOUTINIT_TIMEOUT="${AZ_CLOUTINIT_TIMEOUT:-600}"

# Enable or disable cloud-init. It is enabled by default
AZ_CLOUDINIT="${AZ_CLOUDINIT:-"1"}"
if [[ "${AZ_CLOUDINIT}" -eq 1 ]]; then
  echo "AZ_CLOUDINIT:${AZ_CLOUDINIT} enabled"
fi

print_howto () {
  MY_PUBIP_ADDR="$(get_pub_ip)"
  echo "------------------------------------------------------"
  echo "|   Bastion"
  echo "|       'ssh -i ${MYSSHKEY} ${MY_USERNAME}@${MY_PUBIP_ADDR}'"
  echo "|"
  echo "|   or"
  echo "|"
  echo "|       'ssh -i \${MYSSHKEY} ${MY_USERNAME}@${MY_PUBIP_ADDR}'"
  echo "|"
  echo "|   Internal VM"
  echo "|       'ssh ${MY_USERNAME}@${MYNAME}-vm-01 -oProxyCommand=\"ssh ${MY_USERNAME}@${MY_PUBIP_ADDR} -i ${MYSSHKEY} -W %h:%p\" -i ${MYSSHKEY}'"
  echo "|"
  echo "|   or"
  echo "|"
  echo "|       'ssh ${MY_USERNAME}@${MYNAME}-vm-01 -oProxyCommand=\"ssh ${MY_USERNAME}@${MY_PUBIP_ADDR} -i \${MYSSHKEY} -W %h:%p\" -i \${MYSSHKEY}'"
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

ssh_bastion () {
  if [ -z "${MY_PUBIP_ADDR}" ]
  then
    echo "MY_PUBIP_ADDR must be set before to call ssh_bastion()"
  else
    ssh -i $MYSSHKEY $MY_USERNAME@$MY_PUBIP_ADDR "$*"
  fi
}

ssh_proxy () {
  if [ -z "${MY_PUBIP_ADDR}" ]; then
    echo "MY_PUBIP_ADDR must be set before to call ssh_proxy()"
    return
  fi
  if [ -z "${MY_USERNAME}" ]; then
    echo "MY_USERNAME must be set before to call ssh_proxy()"
    return
  fi
  if [ -z "${MYSSHKEY}" ]; then
    echo "MYSSHKEY must be set before to call ssh_proxy()"
    return
  fi

  vm_name=$1
  shift 1

  ssh "${MY_USERNAME}@$vm_name" \
      -oProxyCommand="ssh ${MY_USERNAME}@${MY_PUBIP_ADDR} -i ${MYSSHKEY} -W %h:%p" \
      -i $MYSSHKEY \
      $*
}

scp_proxy () {
  if [ -z "${MY_PUBIP_ADDR}" ]; then
    echo "MY_PUBIP_ADDR must be set before to call scp_proxy()"
    return
  fi
  if [ -z "${MY_USERNAME}" ]; then
    echo "MY_USERNAME must be set before to call scp_proxy()"
    return
  fi
  if [ -z "${MYSSHKEY}" ]; then
    echo "MYSSHKEY must be set before to call scp_proxy()"
    return
  fi
  scp -oProxyCommand="ssh ${MY_USERNAME}@${MY_PUBIP_ADDR} -i ${MYSSHKEY} -W %h:%p" -i "${MYSSHKEY}" $*
}

ssh_proxy_check_package () {
  vm_name=$1
  package_name=$2

  set +e
  ssh_proxy $this_vm zypper se -i -s $package_name
  rc_zypper=${PIPESTATUS[0]};
  set -e
  if [ $rc_zypper -eq 106 ]; then
    ssh_proxy $this_vm zypper lr || test_die "Failure at listing repos"
    ssh_proxy $this_vm sudo zypper ref -f || test_die "Failure at refreshing repos"
    ssh_proxy $this_vm sudo zypper clean --all || test_die "Failure at clean all"
    set +e
    ssh_proxy $this_vm zypper se -i -s package_name
    echo "RC:$?"
    set -e
    # Disable it for error 106
    #test_die "Failure zypper rc:$rc_zypper"
  elif [ $rc_zypper -ne 0 ]; then
    test_die "Failure zypper rc:$rc_zypper"
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

get_web () {
  ssh_bastion 'curl -s http://'"${MY_FIP}" | grep $1
}

test_web () {
  get_web $1 || test_die "rc:$? http web page is not served by $1"
}

wait_for_takeover () {
  counter=0
  success=0
  while [[ $counter -lt "60" ]]; do
    if get_web $1; then
      echo "Webserver on $1 takes over"
      success=1
      break
    fi

    echo "Attempt $((counter + 1)): String not found. Sleeping for 10 seconds..."
    sleep 10
    ((counter++))
  done

  # Check if the loop exited due to timeout
  if [[ $success -eq 0 ]]; then
    test_die  "Take over does not take place"
  fi
}


# Check the status on the VM that is supposed to have
# the resources
test_on_vm () {
  # check on the cluster side
  ssh_proxy $1 sudo crm status || test_die "crm status fails on $1"
  for res in rsc_web_00 rsc_alb_00 rsc_ip_00; do
    ssh_proxy $1 sudo crm resource failcount $res show $1 | grep -E "value=0" || test_die "Fail count is not 0 for resource $res in $1"
    ssh_proxy $1 sudo crm resource locate $res | grep -E "is running on: $1" || test_die "Resource $res is not running on $1"
  done

  # check on the web server side
  # test that the web page is reachable from the bastion
  # using the Azure LB front end IP
  test_web $1
  # test that the web page is reachable from the bastion
  # using the VM hostname there the web server is supposed to run
  ssh_bastion "curl -s http://$1" | grep "$1" || test_die "$1 does not have http web page reachable at http://$1"
  ssh_proxy $1 ps -xa | grep nginx || test_die "Nginx process not running on $1"

  # check IP
  ssh_proxy $1  'ip a show eth0' | grep ${MY_FIP} || test_die "VirtualIP ${MY_FIP} should be on $1"

}

# Check the status on the VM that is supposed not to have
# the resources
test_other_vm () {
  # check on the cluster side
  ssh_proxy $1 sudo crm status || test_die "crm status fails on $1"
  set +e
  for res in rsc_web_00 rsc_alb_00 rsc_ip_00; do
    ssh_proxy $1 sudo crm resource locate $res | grep -E "is running on: $1"
    rc=$?; [[ $rc -ne 0 ]] || test_die "rc:$? Resource $res is running on $1 and should not"
  done
  get_web $1
  rc=$?; [[ $rc -ne 0 ]] || test_die "rc:$? The web page is provided by $1 and should not"
  ssh_bastion "curl -s http://$1" | grep "$1" 
  rc=$?; [[ $rc -ne 0 ]] || test_die "rc:$? $1 has http web page reachable at http://$1 and should not"
  ssh_proxy $1 ps -xa | grep nginx
  rc=$?; [[ $rc -ne 0 ]] || test_die "rc:$? Nginx process running on $1 and should not"
  set -e
  # check IP
  ssh_proxy $1  'ip a show eth0'
}

ssh_node1 () {
  ssh_proxy "${MYNAME}-vm-01" $*
}

ssh_node2 () {
  ssh_proxy "${MYNAME}-vm-02" $*
}
