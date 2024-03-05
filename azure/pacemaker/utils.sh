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
