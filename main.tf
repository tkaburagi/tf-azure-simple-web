terraform {
  required_version = "~> 0.12"
}

provider "azurerm" {
  client_id = var.client_id
  tenant_id = var.tenant_id
  subscription_id = var.subscription_id
  client_secret = var.client_secret
}

resource "azurerm_resource_group" "my-group" {
  name     = "my-group"
  location = var.location
}
resource "azurerm_virtual_machine" "my-compute" {
  name = "my-vm-${count.index}"
  count = var.web_instance_count
  location = var.location
  resource_group_name = azurerm_resource_group.my-group.name
  network_interface_ids = [azurerm_network_interface.my-nw-interface.*.id[count.index]]
  vm_size = "Standard_DS1_v2"

  os_profile {
    computer_name = "my-compute"
    admin_username = var.admin_username
    admin_password = var.admin_password
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "playground"
  }
  storage_image_reference {
    publisher = "Canonical"
    offer = "UbuntuServer"
    sku = "16.04-LTS"
    version = "latest"
  }
  storage_os_disk {
    name = "my-osdisk-${count.index}"
    caching = "ReadWrite"
    create_option = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  provisioner "remote-exec" {
    connection {
      type = "ssh"
      host = azurerm_public_ip.my-public-ip.ip_address
      user     = var.admin_username
      password = var.admin_password

    }
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y apache2",
      "sudo systemctl start apache2.service"
    ]
  }
}


resource "azurerm_virtual_network" "my-vnet" {
  name                = "my-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name   = azurerm_resource_group.my-group.name
}

resource "azurerm_subnet" "my-subnet" {
  name                 = "my-subnet"
  resource_group_name   = azurerm_resource_group.my-group.name
  virtual_network_name = azurerm_virtual_network.my-vnet.name
  address_prefix       = "10.0.2.0/24"
}

resource "azurerm_network_interface" "my-nw-interface" {
  name                = "my-nw-interface-${count.index}"
  count = var.web_instance_count
  location            = var.location
  resource_group_name   = azurerm_resource_group.my-group.name

  ip_configuration {
    name = "my-ip-config"
    subnet_id = azurerm_subnet.my-subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "my-nw-if-be-addr-pool-association" {
  network_interface_id    = azurerm_network_interface.my-nw-interface.*.id[count.index]
  ip_configuration_name   = "my-ip-config"
  backend_address_pool_id = azurerm_lb_backend_address_pool.my-lb-addr-pool.id
  count = var.web_instance_count
}

resource "azurerm_public_ip" "my-public-ip" {
  name                = "my-public-ip"
  location            = var.location
  resource_group_name = azurerm_resource_group.my-group.name
  allocation_method   = "Static"
}

resource "azurerm_lb" "my-lb" {
  name                = "my-lb"
  location            = var.location
  resource_group_name = azurerm_resource_group.my-group.name

  frontend_ip_configuration {
    name                 = "my-front-public-ip"
    public_ip_address_id = azurerm_public_ip.my-public-ip.id
  }
}

resource "azurerm_lb_backend_address_pool" "my-lb-addr-pool" {
  resource_group_name = azurerm_resource_group.my-group.name
  loadbalancer_id     = azurerm_lb.my-lb.id
  name                = "my-lb-addr-pool"
}

resource "azurerm_lb_nat_rule" "ssh-nat-rule" {
  resource_group_name            = azurerm_resource_group.my-group.name
  loadbalancer_id                = azurerm_lb.my-lb.id
  name                           = "ssh-nat-rule"
  protocol                       = "Tcp"
  frontend_port                  = 22
  backend_port                   = 22
  frontend_ip_configuration_name = azurerm_lb.my-lb.frontend_ip_configuration[0].name
}

resource "azurerm_lb_nat_rule" "http-nat-rule" {
  resource_group_name            = azurerm_resource_group.my-group.name
  loadbalancer_id                = azurerm_lb.my-lb.id
  name                           = "http-nat-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = azurerm_lb.my-lb.frontend_ip_configuration[0].name
}

resource "azurerm_network_interface_nat_rule_association" "ssh-nat-association" {
  count = var.web_instance_count
  network_interface_id  = azurerm_network_interface.my-nw-interface[count.index].id
  ip_configuration_name = "my-ip-config"
  nat_rule_id           = azurerm_lb_nat_rule.ssh-nat-rule.id
}

resource "azurerm_network_interface_nat_rule_association" "http-nat-association" {
  count = var.web_instance_count
  network_interface_id  = azurerm_network_interface.my-nw-interface[count.index].id
  ip_configuration_name = "my-ip-config"
  nat_rule_id           = azurerm_lb_nat_rule.http-nat-rule.id
}

resource "azurerm_network_security_group" "my-sg" {
  name                = "my-sg"
  location            = var.location
  resource_group_name = azurerm_resource_group.my-group.name
}

resource "azurerm_network_security_rule" "ssh-security-rule" {
  name                       = "ssh"
  priority                   = 100
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "22"
  source_address_prefix      = "*"
  destination_address_prefix = "*"
  network_security_group_name = azurerm_network_security_group.my-sg.name
  resource_group_name = azurerm_resource_group.my-group.name
}

resource "azurerm_network_security_rule" "http-security-rule" {
  name                       = "ssh"
  priority                   = 100
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "80"
  source_address_prefix      = "*"
  destination_address_prefix = "*"
  network_security_group_name = azurerm_network_security_group.my-sg.name
  resource_group_name = azurerm_resource_group.my-group.name
}