#!/bin/bash -eu

# Check the deployment before to start testing and changing it

. ./utils.sh

MY_PUBIP_ADDR="$(get_pub_ip)"

test_step "Check bastion connectivity"
ssh -i $MYSSHKEY $MY_USERNAME@$MY_PUBIP_ADDR whoami

test_step "Check bastion HTTPS to smt-azure.susecloud.net"
# echo QUIT is a hotfix to avoid openssl
# to hang forever
set +e
ssh -i $MYSSHKEY $MY_USERNAME@$MY_PUBIP_ADDR \
  'echo QUIT | openssl s_client -connect smt-azure.susecloud.net:443'
rc_ssl=${PIPESTATUS[0]};
set -e

SC_REPO_SCRIPT="sc-repocheck.py"
if [ $rc_ssl -ne 0 ]; then
  test_step "Get the ${SC_REPO_SCRIPT}"
  SC_REPO_TMP="${MY_TMP}/${SC_REPO_SCRIPT}"
  curl -o "${SC_REPO_TMP}" --silent \
    "https://raw.githubusercontent.com/rfparedes/susecloud-repocheck/main/${SC_REPO_SCRIPT}"

  test_step "Upload and run the ${SC_REPO_SCRIPT} on the bastion"
  scp -i $MYSSHKEY \
    "${SC_REPO_TMP}" \
    "${MY_USERNAME}@${MY_PUBIP_ADDR}:${MY_REMOTE_TMP}/"
  set +e
  ssh -i $MYSSHKEY $MY_USERNAME@$MY_PUBIP_ADDR \
    "sudo python3 ${MY_REMOTE_TMP}/${SC_REPO_SCRIPT}" |& tee "${MY_TMP}/${SC_REPO_SCRIPT}.bastion.log"
  rc=${PIPESTATUS[0]};
  set -e
  if [ $rc -ne 0 ]; then
    grep "Debug data location" "${MY_TMP}/${SC_REPO_SCRIPT}.${this_vm}.log"
    test_die "${SC_REPO_SCRIPT} fails on the bastion"
  fi
  test_die "SSL test fails on the bastion rc_ssl:$rc_ssl"
fi

for NUM in $(seq $MY_NUM); do
  this_vm="${MYNAME}-vm-0${NUM}"
  echo "###########################################################################"
  echo "# -------> this_vm:${this_vm}"

  test_step "[${this_vm}] whoami"
  ssh_proxy $this_vm whoami | grep $MY_USERNAME || test_die "Remote user is not ${MY_USERNAME}"
  test_step "[${this_vm}] sudo whoami"
  ssh_proxy $this_vm sudo whoami | grep root || test_die "Remote user with sudo is not root"

  test_step "[${this_vm}] diagnostic logs"
  ssh_proxy $this_vm cat /etc/os-release
  ssh_proxy $this_vm uname -a
  ssh_proxy $this_vm zypper --version

  test_step "[${this_vm}] dmidecode"
  DMILOG="${MY_TMP}/dmidecode.${this_vm}.log"
  set +e
  ssh_proxy $this_vm 'sudo dmidecode' &> $DMILOG
  rc=${PIPESTATUS[0]};
  set -e
  if [ $rc -ne 0 ]; then
    cat $DMILOG || echo "No dmidecode output"
    test_die "dmidecode failure rc:$rc"
  fi
  grep -i microsoft "${MY_TMP}/dmidecode.log" || test_die "dmidecode does not contain Microsoft string"

  test_step "[${this_vm}] check product"
  ssh_proxy $this_vm cat /etc/products.d/SLES_SAP.prod || test_die "Issue reading SLES_SAP.prod"

  test_step "[${this_vm}] azuremetadata"
  ssh_proxy $this_vm azuremetadata --api latest || test_die "Issue with azuremetadata"

  test_step "[${this_vm}] registration"
  set +e
  SUSECONLOG="${MY_TMP}/suseconnect.${this_vm}.json"
  ssh_proxy $this_vm 'sudo SUSEConnect -s' > $SUSECONLOG
  rc=${PIPESTATUS[0]};
  set -e
  if [ $rc -ne 0 ]; then
    cat $SUSECONLOG || echo "No SUSEConnect output"
    test_die "SUSEConnect failure rc:$rc"
  fi
  cat $SUSECONLOG | jq '.[].status'

  test_step "[${this_vm}] check HTTPS to smt-azure.susecloud.net"
  # echo QUIT is a hotfix to avoid openssl
  # to hang forever
  set +e
  ssh_proxy $this_vm 'echo QUIT | openssl s_client -connect smt-azure.susecloud.net:443'
  rc_ssl=${PIPESTATUS[0]};
  set -e
  if [ $rc_ssl -ne 0 ]; then
    test_step "[${this_vm}] Upload and run the ${SC_REPO_SCRIPT}"
    scp_proxy "${SC_REPO_TMP} ${MY_USERNAME}@${this_vm}:${MY_REMOTE_TMP}/"
    set +e
    ssh_proxy $this_vm \
      "sudo python3 ${MY_REMOTE_TMP}/${SC_REPO_SCRIPT}" \
        |& tee "${MY_TMP}/${SC_REPO_SCRIPT}.${this_vm}.log"
    rc=${PIPESTATUS[0]};
    occurrence=$(grep -c "ERROR:" "${MY_TMP}/${SC_REPO_SCRIPT}.${this_vm}.log")
    set -e
    test_step "[${this_vm}] ${SC_REPO_SCRIPT} WARNINGS"
    grep "WARNING:" "${MY_TMP}/${SC_REPO_SCRIPT}.${this_vm}.log" || echo "No warnings in ${MY_TMP}/${SC_REPO_SCRIPT}.${this_vm}.log"
    test_step "[${this_vm}] ${SC_REPO_SCRIPT} ERRORS"
    grep "ERROR:" "${MY_TMP}/${SC_REPO_SCRIPT}.${this_vm}.log" || echo "No errors in ${MY_TMP}/${SC_REPO_SCRIPT}.${this_vm}.log"
    if [ $rc -ne 0 ] || [ $occurrence -ne 0 ]; then
      REMOTE_LOG=$(grep -o "Debug data location: /.*" "${MY_TMP}/${SC_REPO_SCRIPT}.${this_vm}.log" | sed s/Debug\ data\ location:\ //)
      test_step "[${this_vm}] Download ${REMOTE_LOG} locally to ${MY_TMP}"
      scp_proxy "${MY_USERNAME}@${this_vm}:${REMOTE_LOG}" "${MY_TMP}"
      test_die "${SC_REPO_SCRIPT} fails rc:${rc} errors:${occurrence} on ${this_vm}"
    fi
    test_die "SSL test fails on ${this_vm} rc_ssl:$rc_ssl"
  fi

  test_step "[${this_vm}] .ssh folder presence"
  # without '' in the next command, ~ is expanded locally and not on the remote VM
  ssh_proxy $this_vm 'ls -lai ~/.ssh' | grep -v '.pub' | grep -c 'id_rsa' | grep 1 || test_die "${MY_USERNAME} on node${NUM} has one private key needed to talk to the other node"
  test_step "[${this_vm}] authorized_keys"
  # disabled as it does not pass on vm2
  occurrence=$(ssh_proxy $this_vm 'cat ~/.ssh/authorized_keys | wc -l')
  [[ $occurrence -eq 3 ]] || \
      test_die "${MY_USERNAME} on node${NUM} should have 3 instead of ${occurrence} allowed keys in total, one is for the bastion"
  ssh_proxy $this_vm 'cat ~/.ssh/authorized_keys' | \
      wc -l | grep 3 || \
      test_die "${MY_USERNAME} on node${NUM} has 3 allowed keys in total, one is for the bastion"
  ssh_proxy $this_vm 'cat ~/.ssh/authorized_keys' | \
      grep 'Temp internal cluster key for' | \
      wc -l | grep 2 || \
      test_die "${MY_USERNAME} on node${NUM} has 2 allowed keys for the inter-nodes communication"
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
  ssh_proxy_check_package $this_vm nginx

  set +e
  ssh_proxy $this_vm sudo systemctl status nginx.service
  rc=$?; [[ $rc -ne 0 ]] || test_die "rc:$? ${this_vm} has nginx server running and should not"
  set -e
  ssh_bastion "curl -s http://${MY_FIP}" || test_die "${this_vm} does not have http web page reachable at http://${MY_FIP}"

  test_step "[${this_vm}] diagnostic logs: cloud-init"
  ssh_proxy_check_package $this_vm cloud-init
  ssh_proxy $this_vm 'sudo cloud-init status'
  ssh_proxy $this_vm 'sudo ls -lai /var/log/'
  ssh_proxy $this_vm 'sudo ls -lai /var/log/azure/run-command-handler'
  ssh_proxy $this_vm 'sudo cat /var/log/cloud-init.log | grep -v DEBUG'
  ssh_proxy $this_vm 'sudo cat /var/log/cloud-init-output.log'

  test_step "[${this_vm}] diagnostic logs: journalctl"
  ssh_proxy $this_vm sudo journalctl -b | grep -E "cloud-init\[.*(Failed|Warning)" || echo "No cloud-init errors in ${this_vm}"

  test_step "[${this_vm}] cloud-netconfig"
  ssh_proxy_check_package $this_vm cloud-netconfig
  ssh_proxy $this_vm 'sudo grep CLOUD_NETCONFIG_MANAGE /etc/default/cloud-netconfig' | grep "yes" || test_die "CLOUD_NETCONFIG_MANAGE is not yes in ${this_vm}"
  ssh_proxy $this_vm 'sudo journalctl -b |grep -E "cloud-netconfig\["'
done

test_connectivity