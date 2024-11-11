provider "azurerm" {
  features {}
  subscription_id = "7b6c642c-6e46-418f-b715-e01b2f871413"
}

variable "prefix" {
  default = "tfvmex"
}

variable "instances" {
  default = [
    "frontend",
    "cart",
    "catalogue",
    "user",
    "payment",
    "shipping",
    "mysql",
    "mongodb",
    "rabbitmq",
    "redis"
  ]
}

resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-resources"
  location = "East US"
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}


resource "azurerm_network_security_group" "main" {
  name                = "${var.prefix}-allow-all"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "allow-all-in"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-all-out"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.internal.id
  network_security_group_id = azurerm_network_security_group.main.id
}


resource "azurerm_public_ip" "main" {
  count               = length(var.instances)
  name                = "${var.instances[count.index]}-public-ip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "main" {
  count               = length(var.instances)
  name                = "${var.instances[count.index]}-private-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "${var.instances[count.index]}-private-ip"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main[count.index].id
  }
}

resource "azurerm_virtual_machine" "main" {
  count                 = length(var.instances)
  name                  = var.instances[count.index]
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  network_interface_ids = [azurerm_network_interface.main[count.index].id]
  vm_size               = "Standard_DC1s_v2"

  delete_os_disk_on_termination = true

  storage_image_reference {
    id = "/subscriptions/7b6c642c-6e46-418f-b715-e01b2f871413/resourceGroups/trail1/providers/Microsoft.Compute/galleries/LDOTrail/images/rhel9-devops-practice/versions/07.11.2024"
  }
  storage_os_disk {
    name              = var.instances[count.index]
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = var.instances[count.index]
    admin_username = "az-user"
    admin_password = "DevOps123456"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
}

resource "null_resource" "ansible" {
  depends_on = [azurerm_virtual_machine.main]
  count                 = length(var.instances)
  provisioner "local-exec" {
    command = <<EOF
cd ${path.root}/ansible
bash run.sh ${azurerm_public_ip.main[count.index].ip_address} ${var.instances[count.index]}
EOF
  }
}
