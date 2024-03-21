# configurable parameters
if [ -z "${MYNAME}" ]
then
  echo "MYNAME must be set to derive all the other settings"
  exit 1
fi

if [ -z "${MYSSHKEY}" ]
then
  echo "MYSSHKEY must be set to derive all the other settings"
  exit 1
fi

if [ ! -f "${MYSSHKEY}" ]
then
  echo "provided ssh key file MYSSHKEY:${MYSSHKEY} couldn't be found"
  exit 1
fi

if [ ! -f "${MYSSHKEY}.pub" ]
then
  echo "Public key associated to the provided ssh key file MYSSHKEY:${MYSSHKEY} couldn't be found"
  exit 1
fi

MY_USERNAME=cloudadmin
MY_NUM="${MY_NUM:-"2"}"
MY_REGION="${MY_REGION:-"northeurope"}"
MY_OS="${MY_OS:-"SUSE:sles-sap-15-sp5:gen2:latest"}"
MY_PRIV_IP_RANGE="${MY_PRIV_IP_RANGE:-"192.168.1"}"

# set of names reused more than one time
MY_GROUP="${MYNAME}_lb_rg"
MY_SUBNET="${MYNAME}_sn"
MY_NSG="${MYNAME}_nsg"
MY_AS="${MYNAME}_as"
MY_VNET="${MYNAME}_vnet"
MY_PUBIP="${MYNAME}_pubip"
MY_LB="${MYNAME}_loadbalancer"
MY_BE_POOL="${MYNAME}_backend_pool"
MY_HPROBE="${MYNAME}_health"
MY_HPROBE_PORT="62500"
MY_FIP_NAME="${MYNAME}_frontend_ip"
MY_FIP="${MY_PRIV_IP_RANGE}.50"
MY_BASTION="${MYNAME}-vm-bastion"

print_howto () {
  MY_PUBIP_ADDR="$(get_pub_ip)"
  echo "------------------------------------------------------"
  echo "|   Bastion ssh -i ${MYSSHKEY} ${MY_USERNAME}@${MY_PUBIP_ADDR}"
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