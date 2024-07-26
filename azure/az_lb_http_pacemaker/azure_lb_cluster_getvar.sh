. ./utils.sh

export MY_PUBIP_ADDR="$(get_pub_ip)"
export MYSSHKEY="${MYSSHKEY}"
export MY_USERNAME="${MY_USERNAME}"
export MY_PUBIP_ADDR="${MY_PUBIP_ADDR}"


print_howto

echo ""
echo ""
echo " ... or now that settings has been exported for you ..."
echo ""
echo "-----------------------------------------------------------------"
echo "|   Bastion ssh -i \${MYSSHKEY} \${MY_USERNAME}@\${MY_PUBIP_ADDR}"
echo "-----------------------------------------------------------------"
