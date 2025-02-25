# Deploy Bold BI Using Terraform on AKS Cluster

This guide explains how to deploy Bold BI using a Terraform script. The script automates the creation of all necessary Azure resources and the deployment of Bold BI. Once the deployment is complete, you can copy and paste the APP_URL into your browser to start evaluating Bold BI.

---

## Prerequisites

Before proceeding, ensure the following tools and resources are installed and available:

1. **Terraform CLI**  
   Install Terraform from the official guide: [Terraform Installation Guide](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
2. **[Azure Subscription](https://azure.microsoft.com/en-us/pricing/purchase-options/azure-account) with An [Azure Application Registry](https://learn.microsoft.com/en-us/entra/identity-platform/howto-create-service-principal-portal)**
   <br>Ensure your Azure Application Registry has the necessary permissions defined in the [Policy.json](policy.json) file.
   - Client ID
   - Client Secret
   - Tenant ID
   - Subscription ID

---

## Overview of the Script

The Terraform script creates the following resources:

1. **Resource Group** – A dedicated group for managing all resources.
2. **Virtual Network (VNET) and Subnets** – For network configuration.
3. **Azure Kubernetes Service (AKS) Cluster** – The core infrastructure for hosting Bold BI.
4. **PostgreSQL Server** – The database for storing Bold BI configurations and data.
5. **Storage Account with NFS** – To store Required application data.

---

## Deployment Steps

### Step 1: Clone the Terraform Scripts Repository
Clone the Terraform scripts repository using the following command:

```sh
 git clone https://github.com/boldbi/boldbi-terraform-scripts.git
```

### Step 2: Navigate to the Terraform Scripts Directory
```sh
cd boldbi-terraform-scripts/azure-aks
```

### Step 3: Set Environment Variables
To authenticate Terraform with your Azure account, add the following environment variables to your [local system](https://chlee.co/how-to-setup-environment-variables-for-windows-mac-and-linux/) variables.

| Variable Name               |Required| Description                                       |
|-----------------------------|--------|---------------------------------------------------|
| TF_VAR_azure_client_id      | Yes    | Azure Client ID for authentication                |
| TF_VAR_azure_client_secret  | Yes    | Azure Client secret for authentication            |
| TF_VAR_azure_sub_id         | Yes    | Azure Subscription ID for authentication          |
| TF_VAR_azure_tenant_id      | Yes    | Azure Tenant ID for authentication                |

Other than this, we need to add the following environment variables either as a local system variable or in [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/secrets/quick-create-portal) as shown below:

| system variable Name         | Azure Key Vault Variable Name | Required | Description                                       |
|------------------------------|-------------------------------|----------|---------------------------------------------------|
| TF_VAR_db_username           | db-username                   | Yes      | **Database username** <br> - db username must only contain characters and numbers.<br> - db username cannot be 'azure_superuser', 'azure_pg_admin', 'admin', 'administrator', 'root', 'guest', 'public' or start with 'pg_'.                             |
| TF_VAR_db_password           | db-password                   | Yes      | **Database password** <br> - Your password must be at least 8 characters and at most 128 characters.<br> - Your password must contain characters from three of the following categories<br> - English uppercase letters, English lowercase letters, numbers (0-9), and non-alphanumeric characters (!, $, #, %, etc.).<br> - Your password cannot contain all or part of the login name. Part of a login name is defined as three or more consecutive alphanumeric characters.                                 |
| TF_VAR_boldbi_email          | boldbi-email                  | Yes      | Bold BI admin Email                               |
| TF_VAR_boldbi_password       | boldbi-password               | Yes      | **Bold BI admin password**<br> - Your password must be at least 8 characters and at most 128 characters.<br> - Your password must contain characters from three of the following categories<br> - English uppercase letters, English lowercase letters, numbers (0-9), and non-alphanumeric characters (!, $, #, %, etc.)|
| TF_VAR_boldbi_unlock_key     | boldbi-unlock-key             | Yes      | Unlock key for Bold BI                            |
| TF_VAR_app_base_url          | app-base-url                  | No       | The base URL for the Bold BI application (e.g., https://example.com).<br>If left empty, Azure DNS with randomly generated characters will be used for application hosting(e.g., http://abcd.eastus2.cloudapp.azure.com).<p><br> **Note:-**  If app_base_url is left empty, you must install Azure CLI on your machine for Azure DNS mapping.[Azure CLI Installation Guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)                                                |
| TF_VAR_cloudflare_api_token  | cloudflare-api-token          | No       | Cloudflare API Token for DNS mapping on cloudflare|
| TF_VAR_cloudflare_zone_id    | cloudflare-zone-id            | No       | Cloudflare zone ID for DNS mapping on cloudflare  |
| TF_VAR_tls_certificate_path  | tls-certificate-path          | No       |For apply SSL creatificate on AKS cluster <br>Example <br>**windows**<br>D:\\\SSL\\\test\\\domain.crt<br>**Linux**<br>/home/adminuser/ssl/test/domain.crt        | 
| TF_VAR_tls_key_path          | tls-key-path                  | No       | For apply SSL private key on AKS cluster <br>Example <br>**windows**<br>D:\\\SSL\\\test\\\domain.key<br>**Linux**<br>/home/adminuser/ssl/test/domain.key         | 

Variables after setting in system variables:

![system variable](./images/environment.png)

Variables after setting in Azure Key Vault:

![azure key vault](./images/azure_key_vault.png)

If you need to change any infrastructure or application-level settings, refer to the `terraform.tfvars` file.

**Note:**

- If you are using Azure Key Vault, you need to specify the Azure Key Vault name and Azure Key Vault Resource Group name in the `terraform.tfvars` file, as shown below.

![Secret Variable](./images/terraform_tfvars.png)

### Step 4: Initialize Terraform
Open PowerShell or Terminal from the `boldbi-terraform-scripts/azure-aks` directory and run the following command:
```sh
terraform init
```

![terraform init](./images/terraform_init.png)

### Step 5: Validate the Terraform Script
Run the following command to validate the script before applying:
```sh
terraform validate
```
![terraform validate](./images/terraform_validate.png)

### Step 6: Apply the Terraform Script
Execute the following command to apply the Terraform script. When prompted, type "yes" to approve the resource creation.
```sh
terraform apply
```
![terraform apply](./images/apply.gif)

After seeing the following message, you can access Bold BI in your browser:

![URL](./images/url.png)

Please wait until the startup process completes and avoid opening the URL in multiple tabs. The initial startup may take some time. Once the startup configuration is complete, Bold BI will be ready for use.

![terraform apply](./images/boldbi.gif)

## Destroy Bold BI and Resources
To destroy Bold BI and all associated resources, run the following command from the same directory. When prompted, type "yes" to confirm the deletion.
```sh
terraform destroy
```
![terraform destroy](./images/destroy.gif)
