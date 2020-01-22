variable "client_id" {}

variable "client_secret" {}

variable "tenant_id" {}

variable "subscription_id" {}

variable "location" {
  default = "Japan East"
}

variable "admin_username" {
  default = "vmadmin"
}

variable "admin_password" {
  default = "Password1234!"
}

variable "web_instance_count" {
  default = 1
}
