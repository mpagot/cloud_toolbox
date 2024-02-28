. ./utils.sh

az network nic ip-config show \
  --resource-group ${MYAZRG} \
  --name ipconfig2 \
  --nic-name "${MYAZNICPRE}-1"

test_step "Delete the IpConfig2"



az network nic ip-config delete \
  --resource-group ${MYAZRG} \
  --name ipconfig2 \
  --nic-name "${MYAZNICPRE}-1"
