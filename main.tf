# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {      
      source  = "hashicorp/azurerm"
      version = "=2.46"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {

  }
}

# Create a resource group
resource "azurerm_resource_group" "rg-aula-fs" {
  name     = "aula-fs"
  location = "East US"
}

# cria rede virtualizada
resource "azurerm_virtual_network" "vn-aula-fs" {
  name                = "vn-aula-fs"
  location            = azurerm_resource_group.rg-aula-fs.location
  resource_group_name = azurerm_resource_group.rg-aula-fs.name
  address_space       = ["10.0.0.0/16"]
#   dns_servers         = ["10.0.0.4", "10.0.0.5"]
}

#cria sub-net
resource "azurerm_subnet" "sub-aula-fs" {
  name                 = "sub-aula-fs"
  resource_group_name  = azurerm_resource_group.rg-aula-fs.name
  virtual_network_name = azurerm_virtual_network.vn-aula-fs.name
  address_prefixes     = ["10.0.1.0/24"]
}

#cria ip público
resource "azurerm_public_ip" "ip-aula-fs" {
  name                = "ip-aula-fs"
  resource_group_name = azurerm_resource_group.rg-aula-fs.name
  location            = azurerm_resource_group.rg-aula-fs.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }
}

#essa parte está fora do fluxo criei para pegar o ip public do maquina para executar com o script no final
data "azurerm_public_ip" "data-ip-aula-fs" {
    resource_group_name = azurerm_resource_group.rg-aula-fs.name
    name = azurerm_public_ip.ip-aula-fs.name
}

#criar firewall
resource "azurerm_network_security_group" "nsg-aula-fs" {
  name                = "nsg-aula-fs"
  location            = azurerm_resource_group.rg-aula-fs.location
  resource_group_name = azurerm_resource_group.rg-aula-fs.name


  security_rule {
    name                       = "mysql"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

# esse comando está fora do fluxo aqui estou liberando a porta 80 para instalar o apache
 

  tags = {
    environment = "Production"
  }
}

#criar interface de rede
resource "azurerm_network_interface" "ni-aula-fs" {
  name                = "ni-aula-fs"
  location            = azurerm_resource_group.rg-aula-fs.location
  resource_group_name = azurerm_resource_group.rg-aula-fs.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sub-aula-fs.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip-aula-fs.id     
  }
}

#criar uma associação entre interface de rede e o securety group
resource "azurerm_network_interface_security_group_association" "nisga-aula-fs" {
    network_interface_id = azurerm_network_interface.ni-aula-fs.id
    network_security_group_id = azurerm_network_security_group.nsg-aula-fs.id
}

#criando uma maquina virtual
resource "azurerm_virtual_machine" "vm-aula-fs" {
  name                  = "vm-aula-fs"
  location              = azurerm_resource_group.rg-aula-fs.location
  resource_group_name   = azurerm_resource_group.rg-aula-fs.name
  network_interface_ids = [azurerm_network_interface.ni-aula-fs.id]
  vm_size               = "Standard_DS1_v2"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "dsk-aula-fs"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "vm-aula-fs"
    admin_username = "testadmin"
    admin_password = "Password1234!"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "staging"
  }

}

output "publicip-vm-aula-fs" {
  value = azurerm_public_ip.ip-aula-fs.ip_address
}
# isso vai acontecer depois que a maquina for criada depois de 30 segundos executa esse procedimento
resource "time_sleep" "esperar_30_segundos" {
    depends_on =[
        azurerm_virtual_machine.vm-aula-fs
    ]
    create_duration = "30s"

}

#disparar scripts ou fazer uploads é uma conexão remota
resource "null_resource" "install_mysql" {   
    provisioner "remote-exec" {  #file upload para a maquina virtual /  remote-exec executa um comando na maquina virtual e  local-exec executa na maquina local
        connection {
            type = "ssh"
            user = "testadmin"
            password = "Password1234!"
            host = data.azurerm_public_ip.data-ip-aula-fs.ip_address
        }
        inline =[
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7",
            "sudo service mysql restart",
            "sleep 20",            
        ]
    }
    # executa o time_sleep e depois executa o null_resource
    depends_on =[
        time_sleep.esperar_30_segundos
    ]
}   




