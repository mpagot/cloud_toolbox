#!/bin/sh

# 1. get the webpage using the LB floating IP. It should be from VM1 at the test beginning
# 2. turn off the VM1
# 3. get the webpage using the LB floating IP. It should be from VM2

. ./utils.sh

MY_PUBIP_ADDR="$(get_pub_ip)"
MY_MOVE_RES="rsc_ip_00"

get_web () {
  ssh_bastion 'curl -s http://'"${MY_FIP}" | grep $1
}

test_web () {
  ssh_bastion 'curl -s http://'"${MY_FIP}" | grep $1 || test_die "http web page is not served by $1"
}

wait_for_takeover () {
  counter=0
  while [[ $counter -lt "60" ]]; do
    if get_web $1; then
      echo "Webserver on $1 takes over"
      break
    fi

    echo "Attempt $((counter + 1)) of $max_retries: String not found. Sleeping for 10 seconds..."
    sleep 10
    ((counter++))
  done

  # Check if the loop exited due to timeout
  if [[ $counter -eq "10" ]]; then
    test_die  "Take over does not take place"
  fi
}

ssh_node () {
  ssh_bastion 'ssh '"${MY_USERNAME}@${MYNAME}-vm-01 $*"
}


test_step "Check cluster preconditions"
ssh_node 'sudo crm configure show' | grep -c cli-prefer- | grep 0 || test_die "Cluster already have some cli-prefer- and it should not at the beginning of the test"
ssh_node 'sudo crm status'

test_step "Check ip address preconditions"
ssh_node 'ip a show eth0' | grep ${MY_FIP} || test_die "VirtualIP ${MY_FIP} should be on ${MYNAME}-vm-01"
ssh_bastion 'ssh '"${MY_USERNAME}@${MYNAME}-vm-02"' ip a show eth0'
test_web "${MYNAME}-vm-01"


test_step "Move the IpAddr2 resource to VM2"
ssh_node 'sudo crm resource move '"${MY_MOVE_RES} ${MYNAME}-vm-02" || test_die "Error in resource move"
sleep 30

test_step "Check cluster immediately after the move"
ssh_node 'sudo crm configure show' | grep -c cli-prefer- | grep 1 || test_die "Cluster should now have one cli-prefer-"
ssh_node 'sudo crm configure show' | grep -E "cli-prefer-.*${MYNAME}-vm-02" || test_die "Cluster should now have one cli-prefer- with ${MYNAME}-vm-02"
ssh_node 'sudo crm status'

test_step "Check ip address immediately after the move"
ssh_node 'ip a show eth0'
ssh_bastion 'ssh '"${MY_USERNAME}@${MYNAME}-vm-02"' ip a show eth0' | grep ${MY_FIP} || test_die "VirtualIP ${MY_FIP} should be on ${MYNAME}-vm-02"

wait_for_takeover "${MYNAME}-vm-02"

# Slow down, take a break, then check again, nothing should be changed.
test_step "Check again later"
sleep 30
test_web "${MYNAME}-vm-02"

test_step "Move back the IpAddr2 resource to VM1"
ssh_node 'sudo crm resource move '"${MY_MOVE_RES} ${MYNAME}-vm-01" || test_die "Error in resource move"
sleep 30

test_step "Check cluster immediately after the move"
ssh_node 'sudo crm configure show' | grep -c cli-prefer- | grep 1 || test_die "Cluster should now have one cli-prefer-"
ssh_node 'sudo crm configure show' | grep -E "cli-prefer-.*${MYNAME}-vm-01" || test_die "Cluster should now have one cli-prefer- with ${MYNAME}-vm-01"
ssh_node 'sudo crm status'

test_step "Check ip address immediately after the move"
ssh_node 'ip a show eth0' | grep ${MY_FIP} || test_die "VirtualIP ${MY_FIP} should be on ${MYNAME}-vm-01"
ssh_bastion 'ssh '"${MY_USERNAME}@${MYNAME}-vm-02"' ip a show eth0'

wait_for_takeover "${MYNAME}-vm-01"

test_step "Clear all location constrain used during the test"
ssh_node 'sudo crm resource clear '"${MY_MOVE_RES}"
sleep 30

test_step "Check cluster after the clear"
ssh_node 'sudo crm configure show' | grep -c cli-prefer- | grep 0 || test_die "Cluster should no more have some cli-prefer-"
ssh_node 'sudo crm status'


# Slow down, take a break, then check again, nothing should be changed.
test_step "Check again later"
sleep 30
test_web "${MYNAME}-vm-01"
