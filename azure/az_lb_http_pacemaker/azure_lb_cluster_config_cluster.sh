#!/bin/bash -eu

# Prepare the cluster
. ./utils.sh

MY_PUBIP_ADDR="$(get_pub_ip)"

maintenance () {
  ssh_proxy "${MYNAME}-vm-01" \
    sudo crm configure property maintenance-mode=$1
}

test_step "Disable the nginx service"
# Pacemaker will take care of it
ssh_proxy "${MYNAME}-vm-01" \
    sudo systemctl stop nginx.service || test_die "rc:$? Not able to stop nginx on ${MYNAME}-vm-01"
ssh_proxy "${MYNAME}-vm-02" \
    sudo systemctl stop nginx.service || test_die "rc:$? Not able to stop nginx on ${MYNAME}-vm-02"


test_step "[${MYNAME}-vm-01] crm init"
ssh_proxy "${MYNAME}-vm-01" \
    'sudo crm cluster init -y --name DONALDUCK' || test_die "Fails in crm cluster init"

test_step "[${MYNAME}-vm-02] crm join"
ssh_proxy "${MYNAME}-vm-02" \
    "sudo crm cluster join -y -c \"${MY_USERNAME}@${MYNAME}-vm-01\"" || test_die "Fails in crm cluster join"

test_step "[${MYNAME}-vm-01] crm configure"
maintenance "true"

# The cluster in this particular test only have two nodes
# and no fencing device, so disable STONITH
ssh_proxy "${MYNAME}-vm-01" \
    sudo crm configure property stonith-enabled=false

ssh_proxy "${MYNAME}-vm-01" \
    sudo crm configure property no-quorum-policy=ignore

# Create the resource to monitor the web server
ssh_proxy "${MYNAME}-vm-01" \
    sudo crm configure primitive rsc_web_00 \
    ocf:heartbeat:nginx \
    configfile=/etc/nginx/nginx.conf \
    op start timeout="40s" interval="0" \
    op stop timeout="60s" interval="0" \
    op monitor interval="10s" timeout="60s" \
    meta migration-threshold="10" || test_die "Fails to create the webserver resource"

# Create the resource to talk with the
# Azure load balancer health probe
ssh_proxy "${MYNAME}-vm-01" \
    sudo crm configure primitive rsc_alb_00 \
        azure-lb \
        port=62500 \
        op monitor timeout=20s interval=10 || test_die "Fails to create azure-lb resource"

# Create the resource for the virtual IP,
# is this any useful in Azure?
ssh_proxy "${MYNAME}-vm-01" \
    sudo crm configure primitive rsc_ip_00 \
        ocf:heartbeat:IPaddr2 \
        meta target-role=Started operations \
        \\\$id=rsc_ip_RES-operations \
        op monitor interval=10s timeout=20s \
        params ip=${MY_FIP}  || test_die "Fails to create IPaddr2 resource"

# Group all together so that if there's a problem
# with the web server on one of the two nodes,
# the load balancer is notified
ssh_proxy "${MYNAME}-vm-01" \
    sudo crm configure group \
    rsc_grp_00 \
    rsc_alb_00 rsc_ip_00 rsc_web_00 || test_die "Fails in create group"

maintenance "false"
