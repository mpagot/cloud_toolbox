#!/bin/bash -eu

# 1. get the webpage using the LB floating IP. It should be from VM1 at the test beginning
# 2. turn off the VM1
# 3. get the webpage using the LB floating IP. It should be from VM2

. ./utils.sh

MY_PUBIP_ADDR="$(get_pub_ip)"

test_step "Check cluster preconditions"
test_connectivity
test_on_vm "${MYNAME}-vm-01"
test_other_vm "${MYNAME}-vm-02"
ssh_node1 'sudo crm configure show' | grep -c cli-prefer- | grep 0 || test_die "Cluster already have some cli-prefer- and it should not at the beginning of the test"


test_step "Move the ${MY_MOVE_RES} resource to VM2"
# This step is using crm to explicitly move rsc_ip_00 to VM-02
# as the IP resource is grouped with the az loadbalancer one,
# the load balancer entity in Azure is notified about the move
# and change the routing from the frontend IP to the
# backend IP of the VM-02
ssh_node1 'sudo crm resource move '"${MY_MOVE_RES} ${MYNAME}-vm-02" || test_die "Error in resource move"
sleep 30

# use curl to probe the webserver using the frontend IP
# until the reply come from the VM-02
wait_for_takeover "${MYNAME}-vm-02"
test_connectivity
test_on_vm "${MYNAME}-vm-02"
test_other_vm "${MYNAME}-vm-01"

ssh_node1 'sudo crm configure show' | grep -E "cli-prefer-.*${MYNAME}-vm-02" || test_die "Cluster should now have one cli-prefer- with ${MYNAME}-vm-02"
ssh_node1 'sudo crm configure show' | grep -c cli-prefer- | grep 1 || test_die "Cluster should now have one cli-prefer-"

# Slow down, take a break, then check again, nothing should be changed.
test_step "Check again later"
sleep 30
test_connectivity
test_web "${MYNAME}-vm-02"

#################################################################################
# Repeat the same but this time from VM-02 to VM-01
test_step "Move back the IpAddr2 resource to VM1"
ssh_node1 'sudo crm resource move '"${MY_MOVE_RES} ${MYNAME}-vm-01" || test_die "Error in resource move"
sleep 30

wait_for_takeover "${MYNAME}-vm-01"
test_connectivity
test_on_vm "${MYNAME}-vm-01"
test_other_vm "${MYNAME}-vm-02"

test_step "Clear all location constrain used during the test"
ssh_node1 'sudo crm resource clear '"${MY_MOVE_RES}"
sleep 30

test_step "Check cluster after the clear"
ssh_node1 'sudo crm configure show' | grep -c cli-prefer- | grep 0 || test_die "Cluster should no more have some cli-prefer-"
ssh_node1 'sudo crm status'

# Slow down, take a break, then check again, nothing should be changed.
test_step "Check again later"
sleep 30
test_connectivity
test_web "${MYNAME}-vm-01"
