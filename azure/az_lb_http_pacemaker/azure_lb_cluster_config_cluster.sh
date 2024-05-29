#!/bin/bash -eu

# Prepare the cluster
. ./utils.sh

MY_PUBIP_ADDR="$(get_pub_ip)"

test_step "[${MYNAME}-vm-01] crm init"
ssh_proxy "${MYNAME}-vm-01" \
    'sudo crm cluster init -y --name DONALDUCK' || test_die "Fails in crm cluster init"
test_step "[${MYNAME}-vm-02] crm join"
ssh_proxy "${MYNAME}-vm-02" \
    "sudo crm cluster join -y -c \"${MY_USERNAME}@${MYNAME}-vm-01\"" || test_die "Fails in crm cluster join"

test_step "[${MYNAME}-vm-01] crm configure"
ssh_proxy "${MYNAME}-vm-01" \
    sudo crm configure property maintenance-mode=true
ssh_proxy "${MYNAME}-vm-01" \
    sudo crm configure primitive rsc_ip_00 ocf:heartbeat:IPaddr2 meta target-role=Started operations \\\$id=rsc_ip_RES-operations op monitor interval=10s timeout=20s params ip=${MY_FIP}  || test_die "Fails in create IPaddr2 resource"
ssh_proxy "${MYNAME}-vm-01" \
    sudo crm configure primitive rsc_alb_00 azure-lb port=62500 op monitor timeout=20s interval=10 || test_die "Fails in create azure-lb resource"
ssh_proxy "${MYNAME}-vm-01" \
    sudo crm configure group rsc_grp_00 rsc_alb_00 rsc_ip_00 || test_die "Fails in create group"
ssh_proxy "${MYNAME}-vm-01" \
    sudo crm configure property maintenance-mode=false
