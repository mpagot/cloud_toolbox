# SUT description
Pacemaker cluster for highly available web application on Microsoft Azure cloud. 

## Azure resources
### Compute Resources:

- **Virtual Machines (VMs):**
    - Two VMs running a simple web server (Nginx deployed with `cloud-init` script in file `cloud-init-web.txt`).
    - These 2 VMs are deployed in the same availability set.
    - These 2 VMs are configured as a Pacemaker cluster (established in a separate script)
    - A third VM with a public IP for bastion access (management).

### Networking:

- 1 **Virtual Network (VNet)** with 1 **Subnet** (IP range 192.168.1.0/24)
- **Network Security Group (NSG):** A firewall to control inbound and outbound traffic (likely not configured in this script). Only two internal VM belong to it. No rules associated to it.
- **Static Private IPs:** Each web server VM gets a static private IP for internal communication.
- **Public IP:** A single public IP assigned to the bastion VM for remote access. **Allocation Method:** Static

### Azure Load Balancer:

- **Load Balancer (LB):** routes incoming traffic on port 80 across the available web server VMs. It routes the traffic to the node where the Pacemaker `azure-lb` cluster resource is.
- **Frontend IP:** fixed IP on the internal subnet (192.168.1.50). Same IP is also used later when configuring the `IPAddr2` cluster resource.
- **Backend Pool:** A pool containing the two web server VMs as backend resources for the load balancer.
- **Health Probe:** Monitors the health of the VMs by checking a specific port `62500` (port exposed by the Pacemaker cluster agent) on each VM.

## Application

### Web server

Each of the two internal nodes has an Nginx web server installed, listening only on port 80.
Each of them only respond with a static page. Page content is the hostname.
Web server is reachable from the bastion too, both on the static IP of each VM and on the LB frontend IP

```
cloudadmin@vm-bastion:~> curl -s http://192.168.1.41
I am vm-01

cloudadmin@vm-bastion:~> curl -s http://192.168.1.42
I am vm-02

cloudadmin@vm-bastion:~> curl -s http://192.168.1.50
I am vm-01
```

### Pacemaker cluster

2 node cluster. 2 managed resources:
- **IPaddr2**: configured to manually match the Frontend IP `192.168.1.50`
- **azure-lb**: Azure load balancer resource, to reply to the Azure LoadBalancer health probe
Both are bounded in a group

```
# crm status

Status of pacemakerd: 'Pacemaker is running' (last updated 2024-03-28 14:22:39Z)
Cluster Summary:
  * Stack: corosync
  * Current DC: vm-01 (version 2.1.5+20221208.a3f44794f-150500.6.14.4-2.1.5+20221208.a3f44794f) - partition with quorum
  * Last updated: Thu Mar 28 14:22:39 2024
  * Last change:  Thu Mar 28 10:43:35 2024 by root via crm_resource on vm-01
  * 2 nodes configured
  * 2 resource instances configured

Node List:
  * Online: [ vm-01 vm-02 ]

Full List of Resources:
  * Resource Group: rsc_grp_00:
    * rsc_alb_00        (ocf::heartbeat:azure-lb):       Started vm-01
    * rsc_ip_00 (ocf::heartbeat:IPaddr2):        Started vm-01
```

No STONITH device. No RA to manage the web server.

## Deployment Steps:

1. Create a resource group.
2. Create a VNet and subnet.
3. Create an NSG.
4. Create a public IP address.
5. Create a standard SKU load balancer with a frontend IP.
6. Create an availability set for redundancy.
7. Create two VMs with the specified configuration and link them to the load balancer backend pool and the availability set.
8. Configure a static private IP address for each VM within the defined range.
9. Create a health probe for the load balancer.
10. Create a load balancer rule with idle timeout and floating IP enabled.
11. Configure Pacemaker cluster on the VMs.

# Test sequence

1. Test connectivity on the frontend IP by calling `curl` from the bastion.
2. IPaddr2 resource is moved to `vm-02` using `crm resource move rsc_ip_00 vm-02`
3. Wait the cluster to moves the resource to the other node, and to allow the LB health-probe to realize that the resource has been moved
4. Connectivity is evaluated again using curl. It allows to determine that the frontend IP is responding and that (from the HTTP response content) page is served from `vm-02`

