. ./utils.sh

THIS_PUBIP=$(az network public-ip show \
    --resource-group ${MYAZRG} \
    --name "${MYAZPIPPRE}-1" \
    --query 'ipAddress' -o tsv)

SSH_DST="${MYAZVMUSR}@${THIS_PUBIP}"

ssh ${SSH_DST} ip a show eth0 | grep 'inet '
