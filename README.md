# tf-aks-kv
Terraform template which provisions an AKS Cluster with Key Vault integration using [CSI secrets store driver](https://github.com/Azure/secrets-store-csi-driver-provider-azure). Authentication to the Key Vault is performed using [AAD Pod Identity](https://github.com/Azure/aad-pod-identity). This template is based on the [awesome document](https://github.com/paulbouwer/experiments/blob/master/aks/install-aadpodidentity-and-secretsstoredriver.md) published by my colleague **Paul Bouwer**.

## Requirements
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
- [kubectl](https://docs.microsoft.com/en-us/cli/azure/aks?view=azure-cli-latest#az-aks-install-cli)
- [Terraform](https://www.terraform.io/downloads.html)
- [Terraform authenticated via Service Principal](https://www.terraform.io/docs/providers/azurerm/guides/service_principal_client_secret.html)
>**Note:** This template performs [Azure AD role assignments](https://docs.microsoft.com/en-us/azure/role-based-access-control/overview) required by AAD Pod Identity. Therefore the Service Principal used for Terraform authentication must be created with `Owner` privileges.

## Azure resources
- AKS Cluster
- Key Vault
- User-Assigned Managed Identity

## Smoke Test
Fill the following variables from the Terraform output;
```sh
export aad_pod_id_binding_selector="aad-pod-id-binding-selector"
export aks_cluster_name="aks-xxxxxx"
export key_vault_name="kv-xxxxxx"
export rg_name="rg-xxxxxx"
export tenant_id="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

Set variables for the demo secret in test;
```sh
export SECRET_NAME="demo-secret"
export SECRET_VALUE="demo-value"
```

Then;
```
./smoke_test.sh
```
