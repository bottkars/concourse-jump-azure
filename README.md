# concourse-jump-azure

This Repo set´s up the "Control Plane" for Pivotal Platform Automation from a JumpHost on Azure

in Addition to the [Documentation](http://docs.pivotal.io/platform-automation/), Azure KeyVault an System managed identities are used to
Store Secrets and Credentials

You will need

- An Azure Subscription
- A Service Principal
- A Pivotal Network Refresh Token 
- local machine with azure az cli

With this Guide you Create

- a Key Vault
- A JumpHost on Azure with [Sytem Managed Identity](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/tutorial-linux-vm-access-nonaad) to Access the Vault
- An PCF Operation Manager

This Repo will Provide

- an Azure (nested) Arm Template to create a Linux JumpBox
- assign System Managed Identities to the JumpHost

## getting started

the next steps are to be performed on your local host

### Prepare Azure Key Vault a key Vault

use your existing or new key-vault to store secrets.
The Template to deploy the JumpBox assumes that the Key-Vault is in the Same subscription but different ResourceGroup

#### create the keyvault

```bash
AZURE_VAULT=<your vaultname, name must be unique fro AZURE_VAULT.vault.azure.com>
VAULT_RG=<your Vault Resource Group>
LOCATION=<azure location, e.g. westus, westeurope>
## Create RG to set your KeyVault
az group create --name ${VAULT_RG} --location ${LOCATION}
## Create keyVault
az keyvault create --name ${AZURE_VAULT} --resource-group ${VAULT_RG} --location ${LOCATION}
```

#### Assign values to the secrets

```bash
## Set temporary Variables
AZURE_CLIENT_ID=<your application ID for the Service Principal>
AZURE_TENANT_ID=<Tenant ID to be used>
AZURE_CLIENT_SECRET=<Client Secret created>
PIVNET_UAA_TOKEN=<your pivnet refresh token>
## SET the Following Secrets from the temporary Variables
az keyvault secret set --vault-name ${AZURE_VAULT} --name "AZURECLIENTID" --value ${AZURE_CLIENT_ID}
az keyvault secret set --vault-name ${AZURE_VAULT} --name "AZURETENANTID" --value ${AZURE_TENANT_ID}
az keyvault secret set --vault-name ${AZURE_VAULT} --name "PIVNETUAATOKEN" --value  ${PIVNET_UAA_TOKEN}
az keyvault secret set --vault-name ${KEY_VAULT} --name "AZURECLIENTSECRET" --value  ${AZURE_CLIENT_SECRET}
## unset the temporary variables
unset AZURE_CLIENT_ID
unset AZURE_TENANT_ID
unset AZURE_CLIENT_SECRET
unset PIVNET_UAA_TOKEN
```

## Prepare local env file 


## start deployment


## clean deployment


