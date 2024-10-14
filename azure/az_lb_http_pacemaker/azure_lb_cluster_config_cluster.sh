#!/bin/bash -eu

# Prepare the cluster
. ./utils.sh

MY_PUBIP_ADDR="$(get_pub_ip)"

maintenance () {
  ssh_proxy "${MYNAME}-vm-01" \
    sudo crm configure property maintenance-mode=$1
}

if [[ "${AZ_CLOUDINIT}" -eq 0 ]]; then
  for NUM in $(seq $MY_NUM); do
    this_vm="${MYNAME}-vm-0${NUM}"

    test_step "[${this_vm}] install nginx"
    if [[ $MY_OS =~ "12-sp5" ]]; then
      # nginx not available in 12sp5 repos
      ssh_proxy $this_vm sudo zypper addrepo -G -t yum -c 'http://nginx.org/packages/sles/12' nginx
      ssh_proxy $this_vm wget http://nginx.org/keys/nginx_signing.key
      ssh_proxy $this_vm sudo rpm --import nginx_signing.key
      ssh_proxy $this_vm sudo zypper ref
      ssh_proxy $this_vm sudo zypper install nginx
    else
      ssh_proxy $this_vm sudo zypper in -y nginx || test_die "Error installing nginx on ${this_vm}"
    fi

    test_step "[${this_vm}] configure the page"
    this_tmp="/tmp/${this_vm}"
    rm -rf "${this_tmp}"
    mkdir -p "${this_tmp}"
    echo "I am ${this_vm}" > "${this_tmp}"/index.html

    scp_proxy "${this_tmp}/index.html ${MY_USERNAME}@${this_vm}:/tmp/index.html"
    ssh_proxy $this_vm "sudo mv /tmp/index.html /srv/www/htdocs/index.html"
    #ssh_proxy $this_vm "sudo chown ${MY_USERNAME}:users ????/index.html"
  done

  test_step "Disable the nginx service"
  # Pacemaker will take care of it
  ssh_proxy $this_vm \
      sudo systemctl status nginx.service || echo "TODO: handle the result properly"
#ssh_proxy "${MYNAME}-vm-02" \
#    sudo systemctl stop nginx.service || test_die "rc:$? Not able to stop nginx on ${MYNAME}-vm-02"
fi

test_step "[${MYNAME}-vm-01] crm version"
ssh_proxy "${MYNAME}-vm-01" \
    'sudo crm --version' || test_die "Fails in crm version"

ssh_proxy "${MYNAME}-vm-01" \
    'rpm -qf $(sudo which crm)' || test_die "Fails in crm cluster init"

ssh_proxy "${MYNAME}-vm-01" \
    'zypper se -s -i crmsh' || test_die "Fails in crm cluster init"


test_step "[${MYNAME}-vm-01] crm init"
ssh_proxy "${MYNAME}-vm-01" \
    'sudo crm cluster init -y --name DONALDUCK' || test_die "Fails in crm cluster init"

test_step "[${MYNAME}-vm-02] crm join"
if [[ $MY_OS =~ "12-sp5" ]]; then
    NODENAME="${MYNAME}-vm-01"
else
    NODENAME="${MY_USERNAME}@${MYNAME}-vm-01"
fi
ssh_proxy "${MYNAME}-vm-02" \
    "sudo crm cluster join -y -c \"${NODENAME}\"" || test_die "Fails in crm cluster join"

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
    sudo crm configure primitive $MY_MOVE_RES \
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
    rsc_alb_00 rsc_ip_00 $MY_MOVE_RES || test_die "Fails in create group"

maintenance "false"
