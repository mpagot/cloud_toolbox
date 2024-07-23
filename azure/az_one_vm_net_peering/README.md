# One VM deployment
Create one VM deployment in Azure.

## Prerequisite
This project is provided as set of bash script.
In order to be able to use it you need:
1. az cli installed and available in the path
2. Azure account and the az cli authenticated to it
3. A set of ssh keys. Path of them is needed by configuration `MYSSHKEY`

## Configuration
Scripts in this project get configurations from a set of environment variables
Minimal set of environment variable needed across all the scripts are

```
# mnemonic name used as part of the Azure resource group
# created by one of the script
export MYNAME=<SOMENAME>

# path of the private key. The corresponding public key
# will be provided as argument to the az command to create
# the VM and will be available there.
export MYSSHKEY=<SOMEFOLDER/id_rsa>
```

## Deployment

The first script to be executed and that takes care to create
the deployment in azure is `azure_one_vm_deploy.sh`.

It is mostly implemented as a list of call to various `az` commands.

This script support an optional environment variable `AZ_BOOTLOG`
that allow to enable some diagnostic features.

There's a verification script `azure_one_vm_deploy_sanity.sh`;
it can be executed immediately after the `azure_one_vm_deploy.sh`
and that perform some basic validations of the deployment.


### Additional repository

There are some optional steps that allow to connect the deployment
to a private zypper proxy and eventually add some custom repo to zypper.

This optional step also needs some additional configurations.

```
# Resource group of the proxy
export AZ_NP_RG=<THE_PROXY_RG_NAME>

# Virtual network name of the proxy
export AZ_NP_VNET=<THE_PROXY_VNET_NAME>

# private IPv4 address of the proxy
export AZ_NP_MIRROR_IP=<IP_ADDR>

# hostname of the proxy. It has to be the hostname also used in AZ_NP_REPO url
export AZ_NP_MIRROR_HOSTNAME=<THE_PROXY_HOSTNAME>
```

At this point it is possible to run `azure_one_vm_netpeering.sh`
that create an internal connection between the previously created VM
and the proxy deployment.

At this point it is also possible to add some extra repository.

```
./azure_one_vm_config_ssh.sh

AZ_NP_REPO="http://<THE_PROXY_HOSTNAME>/<EXTRA_REPO_UI>" ./azure_one_vm_config_repos.sh
```

## Update the system

`azure_one_vm_zypper_patch` executes `zypper patch` on the remote VM
```
./azure_one_vm_config_ssh.sh
./azure_one_vm_zypper_patch.sh
```

## Login

It is also possible to ssh to the VM. All the details about how to do it are
provided as output by `azure_one_vm_getvar.sh`.

## Clean up

Run `azure_one_vm_destroy.sh` when you are done with all your test to get
all the cloud resource belonging to the resource group to be deleted.
