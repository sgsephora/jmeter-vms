# JMeter Azure Deployment Instructions

This document covers how to deploy the JMeter test environment in Azure using Terraform.

## Prerequisites

1. **Azure CLI** installed and configured
2. **Terraform** installed (version 1.0 or newer)
3. **SSH key pair** generated and available

## Files Structure

- `main.tf` - The main Terraform configuration file with all resources
- `terraform.tfvars` - Variables configuration file

## Deployment Steps

### 1. Prepare SSH Key

Ensure you have an SSH key pair. If not, generate one:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
```

### 2. Login to Azure

```bash

export subscriptionId="30a22b24-d9c0-4873-b8a4-8030b5ac2c71"
# Login to Azure
az login

# List your subscriptions
az account list --output table


# Set your subscription (if you have multiple)
export subscriptionId="30a22b24-d9c0-4873-b8a4-8030b5ac2c71"
az account set --subscription "$subscriptionId"
```

### 3. Prepare the Terraform Files

1. Save `main.tf` and `terraform.tfvars` to a directory
2. Edit `terraform.tfvars` to set your preferred:
   - Project name (`prj`)
   - Azure region (`location`)
   - Admin username (`username`)
   - SSH key path (`ssh_key_path`)
   - Tags

### 4. Initialize and Apply Terraform

```bash
# Initialize Terraform
terraform init

# Preview the changes
terraform plan

# Apply the configuration
terraform apply
```


# Destroy env, when not needed
terraform plan  -destroy
terraform apply -destroy



When prompted, type `yes` to confirm the deployment.

### 5. Connect to the JMeter Environment

After deployment completes, Terraform will output connection information:

- Resource group name
- Master VM details (name, IP, SSH command)
- Slave VM details (name, IP, SSH command)
- JMeter run command
- Complete setup instructions

Example:
```
ssh jmeteradmin@52.123.456.789  # Connect to master
```

### 6. Run a JMeter Test

The master VM comes with a sample test script. To run it:

```bash
# Connect to the master VM
ssh jmeteradmin@[MASTER_IP]

# Run the sample test
cd $JMETER_HOME/bin
./jmeter -n -t /home/jmeteradmin/sample_test.jmx -R[SLAVE_PRIVATE_IP] -l results.jtl -e -o report_folder
```

### 7. Upload Your Own Test Plan

```bash
# From your local machine
scp your-test-plan.jmx jmeteradmin@[MASTER_IP]:/home/jmeteradmin/
```

### 8. Download Test Results

```bash
# From your local machine
scp -r jmeteradmin@[MASTER_IP]:/home/jmeteradmin/apache-jmeter/apache-jmeter-5.6.2/bin/report_folder ./
```

### 9. Cleanup Resources When Done

```bash
terraform destroy
```

When prompted, type `yes` to confirm deletion of resources.

## Customizing the JMeter Environment

### Adding More Slave Nodes

To add more slave nodes, modify the `main.tf` file to duplicate the slave VM resources and adjust the JMeter configuration on the master.

### Testing Against a Specific Target

Edit the sample test script (`sample_test.jmx`) on the master VM to point to your target application:

1. Connect to the master VM
2. Edit the test script:
   ```bash
   nano /home/jmeteradmin/sample_test.jmx
   ```
3. Find the HTTPSamplerProxy section and update:
   - domain
   - port
   - protocol
   - path

Alternatively, upload a completely new test plan with your configuration.

## Troubleshooting

### VM Custom Script Extension Failure

If the VM deployment fails during custom script execution:
1. Check the Azure portal for detailed error messages
2. Connect to the VM and check `/var/log/cloud-init-output.log`

### JMeter Connection Issues

If the master cannot connect to the slave:
1. Verify both VMs are running
2. Check JMeter server on the slave: `systemctl status jmeter-server`
3. Verify network connectivity: `ping [SLAVE_PRIVATE_IP]`
4. Check the JMeter properties file on the master





------
It looks like you're encountering an issue with the rmi_keystore.jks file when setting up JMeter in a master-slave configuration. This error typically occurs because JMeter cannot find the rmi_keystore.jks file, which is required for secure communication between the master and slave nodes.

Here are the steps to resolve this issue:

Generate the rmi_keystore.jks file:

JMeter comes with a script to generate this keystore file. You can find the script in the bin directory of your JMeter installation.
For Windows, use create-rmi-keystore.bat.
For Unix-like systems, use create-rmi-keystore.sh.
Copy the rmi_keystore.jks file: to bin directory


/home/jmeteradmin/apache-jmeter/apache-jmeter-5.6.3/bin

If you prefer to disable SSL for RMI communication, you can set the following property in the jmeter.properties file:
server.rmi.ssl.disable=true
By following these steps, you should be able to resolve the FileNotFoundExc