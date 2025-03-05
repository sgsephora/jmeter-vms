terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
  required_version = ">= 1.0"
}

# Provider configuration - no authentication needed here as we'll use az login
provider "azurerm" {
  features {}
}

# Variables
variable "prj" {
  description = "Project name used for resource naming"
  type        = string
  default     = "jmeter"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "username" {
  description = "Admin username for VMs"
  type        = string
  default     = "jmeteradmin"
}

variable "ssh_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default = {
    Environment = "Test"
    Project     = "JMeter"
  }
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prj}"
  location = var.location
  tags     = var.tags
}

# Virtual Network and Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.prj}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-${var.prj}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${var.prj}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "JMeterPorts"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["1099", "4000-4002", "50000"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# Associate NSG with Subnet
resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Master VM
resource "azurerm_public_ip" "master_pip" {
  name                = "pip-master-${var.prj}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "master_nic" {
  name                = "nic-master-${var.prj}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.master_pip.id
  }

  tags = var.tags
}

resource "azurerm_network_interface_security_group_association" "master_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.master_nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "master" {
  name                  = "vm-master-${var.prj}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = "Standard_D2s_v3"
  admin_username        = var.username
  network_interface_ids = [azurerm_network_interface.master_nic.id]

  admin_ssh_key {
    username   = var.username
    public_key = file(var.ssh_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 100
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOT
    #!/bin/bash
    apt-get update
    
    apt-get install -y \
      ca-certificates \
      curl \
      jq \
      net-tools \
      openjdk-17-jdk \
      wget \
      unzip

    # Install JMeter
    mkdir -p /home/${var.username}/apache-jmeter
    wget -P /tmp https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.6.3.tgz
    
    tar -xzf /tmp/apache-jmeter-5.6.3.tgz -C /home/${var.username}/apache-jmeter
    chown -R ${var.username}:${var.username} /home/${var.username}/apache-jmeter
    
    # Set up environment variables
    echo 'export JMETER_HOME=/home/${var.username}/apache-jmeter/apache-jmeter-5.6.3' >> /home/${var.username}/.bashrc
    echo 'export PATH=$PATH:$JMETER_HOME/bin' >> /home/${var.username}/.bashrc
    
    # Configure JMeter for distributed testing
    echo "remote_hosts=${azurerm_network_interface.slave_nic.private_ip_address}" >> /home/${var.username}/apache-jmeter/apache-jmeter-5.6.3/bin/jmeter.properties
    echo "client.rmi.localport=4000" >> /home/${var.username}/apache-jmeter/apache-jmeter-5.6.3/bin/jmeter.properties
    echo "server.rmi.localport=4001" >> /home/${var.username}/apache-jmeter/apache-jmeter-5.6.3/bin/jmeter.properties
    
    # Create a sample test script
    cat > /home/${var.username}/sample_test.jmx << 'EOF'
    <?xml version="1.0" encoding="UTF-8"?>
    <jmeterTestPlan version="1.2" properties="5.0" jmeter="5.6.3">
      <hashTree>
        <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="Sample Test Plan" enabled="true">
          <stringProp name="TestPlan.comments"></stringProp>
          <boolProp name="TestPlan.functional_mode">false</boolProp>
          <boolProp name="TestPlan.tearDown_on_shutdown">true</boolProp>
          <boolProp name="TestPlan.serialize_threadgroups">false</boolProp>
          <elementProp name="TestPlan.user_defined_variables" elementType="Arguments" guiclass="ArgumentsPanel" testclass="Arguments" testname="User Defined Variables" enabled="true">
            <collectionProp name="Arguments.arguments"/>
          </elementProp>
          <stringProp name="TestPlan.user_define_classpath"></stringProp>
        </TestPlan>
        <hashTree>
          <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="Thread Group" enabled="true">
            <stringProp name="ThreadGroup.on_sample_error">continue</stringProp>
            <elementProp name="ThreadGroup.main_controller" elementType="LoopController" guiclass="LoopControlPanel" testclass="LoopController" testname="Loop Controller" enabled="true">
              <boolProp name="LoopController.continue_forever">false</boolProp>
              <stringProp name="LoopController.loops">10</stringProp>
            </elementProp>
            <stringProp name="ThreadGroup.num_threads">100</stringProp>
            <stringProp name="ThreadGroup.ramp_time">30</stringProp>
            <boolProp name="ThreadGroup.scheduler">false</boolProp>
            <stringProp name="ThreadGroup.duration"></stringProp>
            <stringProp name="ThreadGroup.delay"></stringProp>
            <boolProp name="ThreadGroup.same_user_on_next_iteration">true</boolProp>
          </ThreadGroup>
          <hashTree>
            <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="HTTP Request" enabled="true">
              <elementProp name="HTTPsampler.Arguments" elementType="Arguments" guiclass="HTTPArgumentsPanel" testclass="Arguments" testname="User Defined Variables" enabled="true">
                <collectionProp name="Arguments.arguments"/>
              </elementProp>
              <stringProp name="HTTPSampler.domain">example.com</stringProp>
              <stringProp name="HTTPSampler.port"></stringProp>
              <stringProp name="HTTPSampler.protocol">https</stringProp>
              <stringProp name="HTTPSampler.contentEncoding"></stringProp>
              <stringProp name="HTTPSampler.path">/</stringProp>
              <stringProp name="HTTPSampler.method">GET</stringProp>
              <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
              <boolProp name="HTTPSampler.auto_redirects">false</boolProp>
              <boolProp name="HTTPSampler.use_keepalive">true</boolProp>
              <boolProp name="HTTPSampler.DO_MULTIPART_POST">false</boolProp>
              <stringProp name="HTTPSampler.embedded_url_re"></stringProp>
              <stringProp name="HTTPSampler.connect_timeout"></stringProp>
              <stringProp name="HTTPSampler.response_timeout"></stringProp>
            </HTTPSamplerProxy>
            <hashTree/>
            <ResultCollector guiclass="ViewResultsFullVisualizer" testclass="ResultCollector" testname="View Results Tree" enabled="true">
              <boolProp name="ResultCollector.error_logging">false</boolProp>
              <objProp>
                <name>saveConfig</name>
                <value class="SampleSaveConfiguration">
                  <time>true</time>
                  <latency>true</latency>
                  <timestamp>true</timestamp>
                  <success>true</success>
                  <label>true</label>
                  <code>true</code>
                  <message>true</message>
                  <threadName>true</threadName>
                  <dataType>true</dataType>
                  <encoding>false</encoding>
                  <assertions>true</assertions>
                  <subresults>true</subresults>
                  <responseData>false</responseData>
                  <samplerData>false</samplerData>
                  <xml>false</xml>
                  <fieldNames>true</fieldNames>
                  <responseHeaders>false</responseHeaders>
                  <requestHeaders>false</requestHeaders>
                  <responseDataOnError>false</responseDataOnError>
                  <saveAssertionResultsFailureMessage>true</saveAssertionResultsFailureMessage>
                  <assertionsResultsToSave>0</assertionsResultsToSave>
                  <bytes>true</bytes>
                  <sentBytes>true</sentBytes>
                  <url>true</url>
                  <threadCounts>true</threadCounts>
                  <idleTime>true</idleTime>
                  <connectTime>true</connectTime>
                </value>
              </objProp>
              <stringProp name="filename"></stringProp>
            </ResultCollector>
            <hashTree/>
          </hashTree>
        </hashTree>
      </hashTree>
    </jmeterTestPlan>
    EOF
    
    chown ${var.username}:${var.username} /home/${var.username}/sample_test.jmx
  EOT
  )

  tags = var.tags
}

# Slave VM
resource "azurerm_public_ip" "slave_pip" {
  name                = "pip-slave-${var.prj}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "slave_nic" {
  name                = "nic-slave-${var.prj}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.slave_pip.id
  }

  tags = var.tags
}

resource "azurerm_network_interface_security_group_association" "slave_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.slave_nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "slave" {
  name                  = "vm-slave-${var.prj}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = "Standard_D2s_v3"
  admin_username        = var.username
  network_interface_ids = [azurerm_network_interface.slave_nic.id]

  admin_ssh_key {
    username   = var.username
    public_key = file(var.ssh_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  custom_data = base64encode(<<-EOT
    #!/bin/bash
    apt-get update
    apt-get install -y openjdk-11-jdk wget unzip
    
    # Install JMeter
    mkdir -p /home/${var.username}/apache-jmeter
    wget -P /tmp https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.6.3.tgz
    tar -xzf /tmp/apache-jmeter-5.6.3.tgz -C /home/${var.username}/apache-jmeter
    chown -R ${var.username}:${var.username} /home/${var.username}/apache-jmeter
    
    # Set up environment variables
    echo 'export JMETER_HOME=/home/${var.username}/apache-jmeter/apache-jmeter-5.6.3' >> /home/${var.username}/.bashrc
    echo 'export PATH=$PATH:$JMETER_HOME/bin' >> /home/${var.username}/.bashrc
    
    # Configure JMeter server
    PRIVATE_IP=$(hostname -I | awk '{print $1}')
    sed -i "s/#RMI_HOST_DEF=-Djava.rmi.server.hostname=\$(hostname -f)/RMI_HOST_DEF=-Djava.rmi.server.hostname=$PRIVATE_IP/" /home/${var.username}/apache-jmeter/apache-jmeter-5.6.3/bin/jmeter-server
  EOT
  )

  tags = var.tags
}

