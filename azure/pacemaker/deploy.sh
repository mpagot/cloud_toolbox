#!/bin/bash -e

# Create two mostly identical VM and configure a cluster

. ./utils.sh

test_step "VALIDATION OF THE CONFIGURATIONS"

echo "MYAZRG=${MYAZRG}"
echo "MYAZVNET=${MYAZVNET}"
echo "MYAZSNET=${MYAZSNET}"
echo "MYAZPIPPRE=${MYAZPIPPRE}"
echo "MYAZNSG=${MYAZNSG}"
echo "MYAZNICPRE=${MYAZNICPRE}"
echo "MYAZVM=${MYAZVM}"
echo "MYAZVMUSR=${MYAZVMUSR}"

test_step "CREATE RESOURCE GROUP"
az group create \
    --name ${MYAZRG} \
    --location ${MYAZREG}

test_step "CREATE 2 VMs"
for i in $(seq 2); do
  az vm create \
      --resource-group ${MYAZRG} \
      --name "${MYAZVM}-$i" \
      --image "${MYAZVMOS}" \
      --admin-username ${MYAZVMUSR} \
      --authentication-type ssh \
      --generate-ssh-keys
done

. ./help_interactive.sh
