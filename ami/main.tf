provider "azurerm" {
  features {}
  subscription_id = var.SUBSCRIPTION_ID
  tenant_id       = var.TENANT_ID
  client_secret   = var.CLIENT_SECRET
  client_id       = var.CLIENT_ID
}

variable "SUBSCRIPTION_ID" {}
variable "TENANT_ID" {}
variable "CLIENT_ID" {}
variable "CLIENT_SECRET" {}

data "azurerm_resource_group" "it" {
  name = "trail1"
}

locals {
  rg_name     = data.azurerm_resource_group.it.name
  rg_location = data.azurerm_resource_group.it.location
}

resource "azurerm_network_security_group" "main" {
  name                = "packer-allow-all"
  location            = local.rg_location
  resource_group_name = local.rg_name

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

resource "azurerm_virtual_network" "main" {
  name                = "packer-network"
  location            = local.rg_location
  resource_group_name = local.rg_name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "main" {
  name                 = "subnet1"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_public_ip" "main" {
  name                = "packer-public-ip"
  location            = local.rg_location
  resource_group_name = local.rg_name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "main" {
  name                = "packer-nic"
  location            = local.rg_location
  resource_group_name = local.rg_name

  ip_configuration {
    name                          = "packer-nic"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

data "azurerm_shared_image_version" "main" {
  name                = "27.10.2024"
  image_name          = "rhel9-devops-practice"
  gallery_name        = "LDOTrail"
  resource_group_name = local.rg_name
}

resource "azurerm_virtual_machine" "main" {
  name                  = "packer-vm"
  location              = local.rg_location
  resource_group_name   = local.rg_name
  network_interface_ids = [azurerm_network_interface.main.id]
  vm_size               = "Standard_DC1s_v2"

  delete_os_disk_on_termination = true

  storage_image_reference {
    id = data.azurerm_shared_image_version.main.id
  }

  storage_os_disk {
    name              = "packer-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "packer-vm"
    admin_username = "vm-user"
    admin_password = "DevOps123456"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

}

resource "null_resource" "ami-process" {
  depends_on = [azurerm_virtual_machine.main]

  provisioner "remote-exec" {
    connection {
      host = azurerm_public_ip.main.ip_address
      type = "ssh"
      user = "vm-user"
      password = "DevOps123456"
    }

    inline= [
      "sudo dnf install git -y",
      "cd /tmp",
      "git clone https://github.com/learndevopsonline/azure-public-gallery.git",
      "sudo bash /tmp/azure-public-gallery/rhel-9/setup.sh"
    ]
  }
}

resource "null_resource" "vm-genralize" {
  depends_on = [null_resource.ami-process]

  provisioner "local-exec" {
    command = <<EOF
az vm deallocate --resource-group ${local.rg_name}  --name packer-vm
az vm generalize --resource-group ${local.rg_name}  --name packer-vm
EOF
  }
}

resource "azurerm_image" "main" {
  depends_on = [null_resource.ami-process, null_resource.vm-genralize]
  name                      = "rhel9-devops-practice"
  location                  = local.rg_location
  resource_group_name       = local.rg_name
  source_virtual_machine_id = azurerm_virtual_machine.main.id
  hyper_v_generation        = "V2"
}


resource "azurerm_shared_image_version" "main" {
  depends_on = [null_resource.ami-process, null_resource.vm-genralize]
  name                = "30.11.2024"
  gallery_name        = "LDOTrail"
  image_name          = "rhel9-devops-practice"
  resource_group_name = local.rg_name
  location            = local.rg_location
  managed_image_id    = azurerm_image.main.id

  target_region {
    name                   = "East US"
    regional_replica_count = 1
    storage_account_type   = "Standard_LRS"
  }
}
