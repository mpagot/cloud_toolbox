output "bastion_ip" {
  value = azurerm_public_ip.mypubip.ip_address
}

output "ssh_to_vm1" {
  value = format("ssh %s@%s -oProxyCommand=\"ssh %s@%s -W %%h:%%p\" ",
    var.admin_user,
    azurerm_network_interface.myinternalnic[0].ip_configuration[0].private_ip_address,
    var.admin_user,
  azurerm_public_ip.mypubip.ip_address)
}

output "ssh_to_vm2" {
  value = format("ssh %s@%s -oProxyCommand=\"ssh %s@%s -W %%h:%%p\" ",
    var.admin_user,
    azurerm_network_interface.myinternalnic[1].ip_configuration[0].private_ip_address,
    var.admin_user,
  azurerm_public_ip.mypubip.ip_address)
}
