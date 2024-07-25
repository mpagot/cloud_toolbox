variable "public_key" {
  type = string
}

variable "prefix" {
  type = string
}

variable "os_offer" {
  type    = string
  default = "sles-sap-15-sp5"
}

variable "boot_diagnostics" {
  type    = bool
  default = false
}

variable "enable_package_upgrade" {
  type    = string
  default = "false"
}

variable "admin_user" {
  type    = string
  default = "cloudadmin"
}
