locals {
  resource_group_name = format("%s_lb_rg", var.prefix)
  vnet                = format("%s_vnet", local.resource_group_name)
  snet                = format("%s_snet", local.resource_group_name)
  asg                 = format("%s_asg", local.resource_group_name)
  nsg                 = format("%s_nsg", local.resource_group_name)
  pubip               = format("%s_pubip", var.prefix)
  lb                  = format("%s_lb", local.resource_group_name)
  lbprobe             = format("%s_health", local.resource_group_name)
  lbrule              = format("%s_lbrule_tcp80", local.resource_group_name)
  fip_name            = format("%s_frontend_ip", local.resource_group_name)
  be_pool             = format("%s_backend_pool", local.resource_group_name)
  as                  = format("%s_availability_set", local.resource_group_name)
  vmi                 = format("%s-vm-", var.prefix)
  vmb                 = format("%s-vm-bastion", var.prefix)
  nici                = format("%s-vm-internal-nic-", local.resource_group_name)
  nicb                = format("%s-vm-bastion-nic", local.resource_group_name)
  sa                  = lower(format("%sstorageaccount", var.prefix))
  size                = "Standard_B1s"
  address_space       = "192.168.0.0/16"
}

provider "azurerm" {
  features {
    virtual_machine {
      delete_os_disk_on_deletion = true
    }
  }
}

resource "azurerm_resource_group" "myrg" {
  name     = local.resource_group_name
  location = "northeurope"
}

resource "azurerm_virtual_network" "mynet" {
  name                = local.vnet
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name
  address_space       = [local.address_space]

  subnet {
    name           = local.snet
    address_prefix = "192.168.0.0/24"
  }
}

resource "azurerm_application_security_group" "mysgn" {
  name                = local.asg
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name
}

resource "azurerm_network_security_group" "mysecgroup" {
  name                = local.nsg
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name
  security_rule {
    name                       = "OUTALL"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "LOCAL"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = local.address_space
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.address_space
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "mysubnetsecas" {
  subnet_id                 = azurerm_virtual_network.mynet.subnet.*.id[0]
  network_security_group_id = azurerm_network_security_group.mysecgroup.id
}

resource "azurerm_public_ip" "mypubip" {
  name                = local.pubip
  resource_group_name = azurerm_resource_group.myrg.name
  location            = azurerm_resource_group.myrg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
}

resource "azurerm_lb" "mylb" {
  name                = local.lb
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name               = local.fip_name
    private_ip_address = "192.168.0.50"
    subnet_id          = azurerm_virtual_network.mynet.subnet.*.id[0]
  }
}

resource "azurerm_lb_backend_address_pool" "mybackendpool" {
  loadbalancer_id = azurerm_lb.mylb.id
  name            = local.be_pool
}

resource "azurerm_availability_set" "myas" {
  name                         = local.as
  location                     = azurerm_resource_group.myrg.location
  resource_group_name          = azurerm_resource_group.myrg.name
  platform_update_domain_count = 2
}

# The two NIC for the two internal VM to assigne the two private static IP
resource "azurerm_network_interface" "myinternalnic" {
  count               = 2
  name                = "${local.nici}${format("%02d", count.index + 1)}"
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name

  ip_configuration {
    name                          = "ipconfig-internal"
    subnet_id                     = azurerm_virtual_network.mynet.subnet.*.id[0]
    private_ip_address_allocation = "Static"
    private_ip_address            = "192.168.0.4${format("%1d", count.index + 1)}"
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "mybackpoolassociation" {
  count                   = 2
  network_interface_id    = element(azurerm_network_interface.myinternalnic.*.id, count.index)
  ip_configuration_name   = "ipconfig-internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.mybackendpool.id
}

# Health probe is using the port exposed by the cluster RA azure-lb
# to understand if each of the VM in the cluster is OK
# Is probably eventually the cluster itself that
# cares to monitor the below service (port 80)
resource "azurerm_lb_probe" "myhealthprobe" {
  #resource_group_name = var.resource_group_name
  loadbalancer_id     = azurerm_lb.mylb.id
  name                = local.lbprobe
  protocol            = "Tcp"
  port                = "62500"
  interval_in_seconds = 5
  number_of_probes    = 2
}

# Configure the load balancer behavior
# These two are from qe-sap-deployment
#  - idle_timeout_in_minutes        = 30
#  - enable_floating_ip             = "true"
resource "azurerm_lb_rule" "mylbrules" {
  loadbalancer_id                = azurerm_lb.mylb.id
  name                           = local.lbrule
  protocol                       = "Tcp"
  frontend_ip_configuration_name = local.fip_name
  frontend_port                  = 80
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.mybackendpool.id]
  backend_port                   = 80
  probe_id                       = azurerm_lb_probe.myhealthprobe.id
  idle_timeout_in_minutes        = 30
  enable_floating_ip             = "true"
}

# The NIC for the Bastion, it has a private dynamic IP to talk to the internal VM
# and the public IP
resource "azurerm_network_interface" "mybastionnic" {
  name                = local.nicb
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name

  ip_configuration {
    name                          = "ipconfig-bastion-pub"
    subnet_id                     = azurerm_virtual_network.mynet.subnet.*.id[0]
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mypubip.id
  }
}

resource "azurerm_storage_account" "mystorageacc" {
  count                    = var.boot_diagnostics == true ? 1 : 0
  name                     = local.sa
  location                 = azurerm_resource_group.myrg.location
  resource_group_name      = azurerm_resource_group.myrg.name
  account_replication_type = "LRS"
  account_tier             = "Standard"
}

resource "azurerm_linux_virtual_machine" "mybastionvm" {
  name                = local.vmb
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name
  availability_set_id = azurerm_availability_set.myas.id
  size                = local.size

  admin_username = var.admin_user
  admin_ssh_key {
    username   = var.admin_user
    public_key = file(var.public_key)
  }
  disable_password_authentication = true

  source_image_reference {
    publisher = "SUSE"
    offer     = var.os_offer
    sku       = "gen2"
    version   = "latest"
  }

  network_interface_ids = [
    azurerm_network_interface.mybastionnic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  dynamic "boot_diagnostics" {
    for_each = var.boot_diagnostics ? ["boot_diagnostics"] : []

    content {
      storage_account_uri = azurerm_storage_account.mystorageacc[0].primary_blob_endpoint
    }
  }
}

locals {
  cloud_init_script = yamlencode(
    {
      "package_upgrade" : var.enable_package_upgrade,
      "packages" : ["nginx"],
      "runcmd" : [
        "echo \"I am $(hostname)\" > /srv/www/htdocs/index.html",
        "sudo systemctl enable nginx.service",
        "sudo systemctl start nginx.service"
  ] })
}

resource "azurerm_linux_virtual_machine" "myinternalvm" {
  count               = 2
  name                = "${local.vmi}${format("%02d", count.index + 1)}"
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name
  availability_set_id = azurerm_availability_set.myas.id
  size                = local.size

  admin_username = var.admin_user
  admin_ssh_key {
    username   = var.admin_user
    public_key = file(var.public_key)
  }
  disable_password_authentication = true

  source_image_reference {
    publisher = "SUSE"
    offer     = var.os_offer
    sku       = "gen2"
    version   = "latest"
  }

  network_interface_ids = [
    azurerm_network_interface.myinternalnic[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  custom_data = base64encode(local.cloud_init_script)

  dynamic "boot_diagnostics" {
    for_each = var.boot_diagnostics ? ["boot_diagnostics"] : []

    content {
      storage_account_uri = azurerm_storage_account.mystorageacc[0].primary_blob_endpoint
    }
  }

  # TODO
  # --nsg $MY_NSG
}
