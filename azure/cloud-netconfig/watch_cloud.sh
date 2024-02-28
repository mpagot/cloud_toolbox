. ./utils.sh

THIS_PUBIP=$(az network public-ip show \
    --resource-group ${MYAZRG} \
    --name "${MYAZPIPPRE}-1" \
    --query 'ipAddress' -o tsv)

SSH_DST="${MYAZVMUSR}@${THIS_PUBIP}"


# CSP has internal API to query how the resources are configured on the cloud side.
# cloud-netconfig query this API from within the running VM to adjust
# the OS configuration to what is configured on the cloud side.
# check if the CSP API is reachable from within the VM (cloud-netconfig will use it too)

ssh ${SSH_DST} \
  curl -s -H Metadata:true --noproxy ''*'': \
  http://169.254.169.254/metadata/instance/network/interface/\?api-version\=2021-02-01 \
  | python3 -m json.tool

