MYAZREG="${MYAZREG:-"eastus2"}"
MYAZVMOS="${MYAZVMOS:-"SUSE:sles-sap-15-sp5:gen2:latest"}"

if [ -z "${MYNAME}" ]
then
  echo "MYNAME must be set to derive all the other settings"
  exit 1
fi

MYAZRG="${MYAZRG:-"${MYNAME}ResourceGroup"}"
MYAZVNET="${MYAZVNET:-"${MYNAME}VNet"}"
MYAZSNET="${MYAZSNET:-"${MYNAME}BackEndSubnet"}"
MYAZPIPPRE="${MYAZPIPPRE:-"${MYNAME}PublicIp"}"
MYAZNSG="${MYAZNSG:-"${MYNAME}NSG"}"
MYAZNICPRE="${MYAZNICPRE:-"${MYNAME}NIC"}"
MYAZVM="${MYAZVM:-"${MYNAME}VM"}"
MYAZVMUSR=cloudadmin

test_step () {
  echo "##############################"
  echo "# $1"
  echo "##############################"
}

test_die () {
  echo "DIE : $1"
  exit 1
}


get_user () {
  az vm list --resource-group ${MYAZRG} --query '[0].osProfile.adminUsername' -o tsv
}

get_ip () {
  az network public-ip show --ids $(az network nic show --ids $(az vm show \
    --resource-group ${MYAZRG} \
    --name "${MYAZVM}-$1" \
    --query "networkProfile.networkInterfaces[0].id" -o tsv) \
    --query "ipConfigurations[0].publicIPAddress.id" -o tsv) --query "ipAddress" -o tsv
}

check_ssh_connectivity () {
    ssh -l $MYUSER \
        -o UpdateHostKeys=yes -o StrictHostKeyChecking=accept-new \
        $MYUSER@$1 true \
        || test_die "Something wrong with $MYUSER@$1"
}