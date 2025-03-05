# Outputs
output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "master_vm" {
  value = {
    name       = azurerm_linux_virtual_machine.master.name
    public_ip  = azurerm_public_ip.master_pip.ip_address
    private_ip = azurerm_network_interface.master_nic.private_ip_address
    ssh        = "ssh ${var.username}@${azurerm_public_ip.master_pip.ip_address}"
  }
}

output "slave_vm" {
  value = {
    name       = azurerm_linux_virtual_machine.slave.name
    public_ip  = azurerm_public_ip.slave_pip.ip_address
    private_ip = azurerm_network_interface.slave_nic.private_ip_address
    ssh        = "ssh ${var.username}@${azurerm_public_ip.slave_pip.ip_address}"
  }
}

output "jmeter_run_command" {
  value = "cd $JMETER_HOME/bin && ./jmeter -n -t /home/${var.username}/sample_test.jmx -R${azurerm_network_interface.slave_nic.private_ip_address} -l results.jtl -e -o report_folder"
}

output "setup_instructions" {
  value = <<-EOT
==============================================
JMeter Distributed Testing Environment Setup
==============================================

Your JMeter environment has been deployed with:
- 1 Master node (controller): ${azurerm_linux_virtual_machine.master.name} (${azurerm_public_ip.master_pip.ip_address})
- 1 Slave node (load generator): ${azurerm_linux_virtual_machine.slave.name} (${azurerm_public_ip.slave_pip.ip_address})

To connect to the master node:
  ssh ${var.username}@${azurerm_public_ip.master_pip.ip_address}

To upload your own test plan to the master:
  scp your-test-plan.jmx ${var.username}@${azurerm_public_ip.master_pip.ip_address}:/home/${var.username}/


Copy rmi_kestore.jks file 

scp rmi_keystore.jks ${var.username}@${azurerm_public_ip.master_pip.ip_address}:/home/${var.username}/apache-jmeter/apache-jmeter-5.6.3/bin
scp rmi_keystore.jks ${var.username}@${azurerm_public_ip.slave_pip.ip_address}:/home/${var.username}/apache-jmeter/apache-jmeter-5.6.3/bin

Disable ssl for RMI
server.rmi.ssl.disable=true


To run a test:
  ${var.username}@${azurerm_linux_virtual_machine.master.name}:~$ cd $JMETER_HOME/bin
  ${var.username}@${azurerm_linux_virtual_machine.master.name}:~$ ./jmeter -n -t /home/${var.username}/sample_test.jmx -R${azurerm_network_interface.slave_nic.private_ip_address} -l results.jtl -e -o report_folder

To download test results:
  scp -r ${var.username}@${azurerm_public_ip.master_pip.ip_address}:/home/${var.username}/apache-jmeter/apache-jmeter-5.6.3/bin/report_folder ./
EOT
}
