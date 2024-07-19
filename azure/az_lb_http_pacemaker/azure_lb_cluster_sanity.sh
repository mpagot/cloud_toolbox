#!/bin/bash -eu

# Check the deployment before to start testing and changing it

. ./utils.sh

MY_PUBIP_ADDR="$(get_pub_ip)"

for NUM in $(seq $MY_NUM); do
  this_vm="${MYNAME}-vm-0${NUM}"
  echo "###########################################################################"
  echo "# -------> this_vm:${this_vm}"

  test_step "[${this_vm}] whoami"
  ssh_proxy $this_vm whoami | grep $MY_USERNAME || test_die "Remote user is not ${MY_USERNAME}"
  test_step "[${this_vm}] sudo whoami"
  ssh_proxy $this_vm sudo whoami | grep root || test_die "Remote user with sudo is not root"
  test_step "[${this_vm}] ls .ssh"
  # without '' in the next command, ~ is expanded locally and not on the remote VM
  ssh_proxy $this_vm 'ls -lai ~/.ssh' | grep -v '.pub' | grep -c 'id_rsa' | grep 1 || test_die "${MY_USERNAME} on node${NUM} has one private key needed to talk to the other node"
  test_step "[${this_vm}] authorized_keys"
  # disabled as it does not pass on vm2
  occurrence=$(ssh_proxy $this_vm 'cat ~/.ssh/authorized_keys | wc -l')
  [[ $occurrence -eq 3 ]] || test_die "${MY_USERNAME} on node${NUM} should have 3 instead of ${occurrence} allowed keys in total, one is for the bastion"
  ssh_proxy $this_vm 'cat ~/.ssh/authorized_keys' | wc -l | grep 3 || test_die "${MY_USERNAME} on node${NUM} has 3 allowed keys in total, one is for the bastion"
  ssh_proxy $this_vm 'cat ~/.ssh/authorized_keys' | grep 'Temp internal cluster key for' | wc -l | grep 2 || test_die "${MY_USERNAME} on node${NUM} has 2 allowed keys for the inter-nodes communication"

  if [ $NUM -eq 1 ]; then
    # ignore for the moment internal nodes keys for root
    # as they are:
    #   - self generated by crm init
    #   - are only on VM01
    #   - are not shared
    test_step "[${this_vm}] ls root .ssh on ${this_vm}"
    ssh_proxy $this_vm sudo ls -lai /root/.ssh
    ssh_proxy $this_vm sudo cat /root/.ssh/id_rsa.pub
    ssh_proxy $this_vm sudo cat /root/.ssh/authorized_keys
  fi
  test_step "[${this_vm}] homes"
  ssh_proxy $this_vm sudo find /home/ -type d -mindepth 1 -maxdepth 1 | wc -l | grep 1 || test_die "Only home for ${MY_USERNAME} is expected at this point"
  test_step "[${this_vm}] passwd"
  ssh_proxy $this_vm sudo cat /etc/passwd | grep -c -E "root|${MY_USERNAME}|hacluster" | grep 3 || test_die "node${NUM} has root, hacluster and ${MY_USERNAME}"
  test_step "[${this_vm}] private ip"
  ssh_proxy $this_vm ip a show eth0 | grep -E "inet .*192\.168\.1\.4${NUM}" || test_die "node${NUM} do not have private IP 192.168.1.4${NUM}"

  test_step "[${this_vm}] cluster"
  ssh_proxy $this_vm sudo crm status || test_die "node${NUM} fails calling crm status"
  ssh_proxy $this_vm sudo crm configure show || test_die "node${NUM} fails calling crm configure "
  occurrence=$(ssh_proxy $this_vm sudo crm configure show | grep -c primitive)
  [[ $occurrence -eq 3 ]] || test_die "Cluster on node${NUM} has ${occurrence} primitives instead of expected 3"
  ssh_proxy $this_vm '[ -f /usr/lib/ocf/resource.d/heartbeat/nginx ]'
  ssh_proxy $this_vm rpm -qf /usr/lib/ocf/resource.d/heartbeat/nginx

  test_step "[${this_vm}] load balancer"
  ssh_proxy $this_vm 'curl -H "Metadata:true" --noproxy "*" "http://169.254.169.254:80/metadata/loadbalancer?api-version=2020-10-01" | python3 -m json.tool'

  test_step "[${this_vm}] webserver"
  ssh_proxy $this_vm zypper se -i -s nginx || test_die "${this_vm} does not have nginx installed"
  set +e
  ssh_proxy $this_vm sudo systemctl status nginx.service
  rc=$?; [[ $rc -ne 0 ]] || test_die "rc:$? ${this_vm} has nginx server running and should not"
  set -e
  ssh_bastion "curl -s http://${MY_FIP}" || test_die "${this_vm} does not have http web page reachable at http://${MY_FIP}"

  test_step "[${this_vm}] diagnostic logs"
  ssh_proxy $this_vm cat /etc/os-release
  ssh_proxy $this_vm uname -a
  ssh_proxy $this_vm zypper --version

  test_step "[${this_vm}] diagnostic logs: cloud-init"
  ssh_proxy $this_vm 'sudo ls -lai /var/log/'
  ssh_proxy $this_vm 'sudo ls -lai /var/log/azure/run-command-handler'
  ssh_proxy $this_vm 'sudo cat /var/log/cloud-init.log | grep -v DEBUG'
  #ssh_proxy $this_vm 'sudo cat /var/log/cloud-init-output.log'

  test_step "[${this_vm}] diagnostic logs: journalctl"
  ssh_proxy $this_vm sudo journalctl -b | grep -E "cloud-init\[.*(Failed|Warning)" || echo "No cloud-init errors in ${this_vm}"

  test_step "[${this_vm}] cloud-netconfig"
  ssh_proxy $this_vm 'zypper se -s -i cloud-netconfig' || test_die "cloud-netconfig not installed in ${this_vm}"
  ssh_proxy $this_vm 'sudo grep CLOUD_NETCONFIG_MANAGE /etc/default/cloud-netconfig' | grep "yes" || test_die "CLOUD_NETCONFIG_MANAGE is not yes in ${this_vm}"
  ssh_proxy $this_vm 'sudo journalctl -b |grep -E "cloud-netconfig\["'
done

test_connectivity