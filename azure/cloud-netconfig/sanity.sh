. ./utils.sh

test_step "Check that the resource group ${MYAZRG} exist"
az group list \
  --query "[].name" -o tsv \
  | grep ${MYAZRG}
echo "Result:$?"

test_step "Check that the VM is running (from the point of view of the CSP)"
az vm list \
  --resource-group ${MYAZRG} \
  -d \
  --query "[?powerState=='VM running'].name" -o tsv \
  | grep ${MYAZVM}
echo "Result:$?"

test_step "Check the VM username"
az vm list \
  --resource-group ${MYAZRG} \
  --query '[0].osProfile.adminUsername' -o tsv \
  | grep ${MYAZVMUSR}
echo "Result:$?"


for i in $(seq 2); do
  test_step "Get the Public Ip $i"
  THIS_PUBIP=$(az network public-ip show \
    --resource-group ${MYAZRG} \
    --name "${MYAZPIPPRE}-$i" \
    --query 'ipAddress' -o tsv)
  echo "Public Ip $i is ${THIS_PUBIP}"

  test_step "Check for ssh port on ${THIS_PUBIP}"
  nc -vz -w 1 $THIS_PUBIP 22
  echo "Result:$?"

  test_step "Add ${THIS_PUBIP} to known_hosts"
  ssh-keyscan $THIS_PUBIP | tee -a ~/.ssh/known_hosts

  SSH_DST="${MYAZVMUSR}@${THIS_PUBIP}"
  echo "--> SSH_DST:${SSH_DST}"
done

test_step "Check is-system-running"
ssh ${SSH_DST} sudo systemctl is-system-running


test_step "Print (no check for the moment) the OS release description"
ssh ${SSH_DST} cat /etc/os-release

test_step "Check that cloud-netconfig is installed"
# zypper ref is neede for PAYG images
ssh ${SSH_DST} sudeo zypper ref
ssh ${SSH_DST} zypper se -s -i cloud-netconfig
ssh ${SSH_DST} cat /etc/default/cloud-netconfig
ssh ${SSH_DST} sudo journalctl |grep -E 'cloud-netconfig\\['

test_step "Print the NIC configuration"
ssh ${SSH_DST} ip a show eth0
ssh ${SSH_DST} ip -br -c addr show eth0
ssh ${SSH_DST} hostname -i
ssh ${SSH_DST} cat /etc/host.conf | grep multi

test_step "Check to have exactly 3 IPv4 IpConfigs"
ssh ${SSH_DST} ip a show eth0 | grep -c 'inet ' | grep 3

# CSP has internal API to query how the resources are configured on the cloud side.
# cloud-netconfig query this API from within the running VM to adjust
# the OS configuration to what is configured on the cloud side.
# check if the CSP API is reachable from within the VM (cloud-netconfig will use it too)
ssh ${SSH_DST} \
  curl -s -H Metadata:true --noproxy '*': \
  http://169.254.169.254/metadata/instance/network/interface/\?api-version\=2021-02-01 \
  | python3 -m json.tool


