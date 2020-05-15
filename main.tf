provider "azurerm" {
  version = "=2.10.0"
  features {}
}

resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${random_string.unique.result}"
  location = var.rg_location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${random_string.unique.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kubernetes_version  = var.aks_version
  dns_prefix          = "aks"

  default_node_pool {
    name       = "default"
    node_count = var.aks_node_count
    vm_size    = var.aks_vm_size
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_user_assigned_identity" "mi" {
  name                = "mi-${random_string.unique.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

provider "kubernetes" {
  load_config_file       = false
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  username               = azurerm_kubernetes_cluster.aks.kube_config.0.username
  password               = azurerm_kubernetes_cluster.aks.kube_config.0.password
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    load_config_file       = false
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    username               = azurerm_kubernetes_cluster.aks.kube_config.0.username
    password               = azurerm_kubernetes_cluster.aks.kube_config.0.password
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

resource "kubernetes_namespace" "aad_pod_id" {
  metadata {
    labels = {
      name = var.aad_pod_id_ns
    }
    name = var.aad_pod_id_ns
  }
}

resource "helm_release" "aad_pod_id" {
  name       = "aad-pod-identity"
  repository = "https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts"
  chart      = "aad-pod-identity"
  version    = "1.6.0"
  namespace  = kubernetes_namespace.aad_pod_id.metadata.0.name

  set {
    name  = "azureIdentity.enabled"
    value = true
  }

  set {
    name  = "azureIdentity.resourceID"
    value = azurerm_user_assigned_identity.mi.id
  }

  set {
    name  = "azureIdentity.clientID"
    value = azurerm_user_assigned_identity.mi.client_id
  }

  set {
    name  = "azureIdentityBinding.selector"
    value = var.aad_pod_id_binding_selector
  }
}

data "azurerm_resource_group" "aks_node_rg" {
  name = azurerm_kubernetes_cluster.aks.node_resource_group
}

# Following roles are required by AAD Pod Identity and must be assigned to the Kubelet Identity
# https://github.com/Azure/aad-pod-identity/blob/master/docs/readmes/README.msi.md#pre-requisites---role-assignments
resource "azurerm_role_assignment" "vm_contributor" {
  scope                = data.azurerm_resource_group.aks_node_rg.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity.0.object_id
}

resource "azurerm_role_assignment" "all_mi_operator" {
  scope                = data.azurerm_resource_group.aks_node_rg.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity.0.object_id
}

resource "azurerm_role_assignment" "mi_operator" {
  scope                = azurerm_user_assigned_identity.mi.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity.0.object_id
}

resource "kubernetes_namespace" "kv_csi" {
  metadata {
    labels = {
      name = var.kv_csi_ns
    }
    name = var.kv_csi_ns
  }
}

resource "helm_release" "kv_csi" {
  name       = "csi-secrets-provider-azure"
  repository = "https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts"
  chart      = "csi-secrets-store-provider-azure"
  version    = "0.0.6"
  namespace  = kubernetes_namespace.kv_csi.metadata.0.name
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                = "kv-${random_string.unique.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
}

# Set permissions for currently logged-in Terraform SP to be able to read/modify secrets
resource "azurerm_key_vault_access_policy" "kv" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  secret_permissions = [
    "Get",
    "Set",
    "Delete"
  ]
}

resource "azurerm_role_assignment" "kv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.mi.principal_id
}

resource "azurerm_key_vault_access_policy" "mi" {
  key_vault_id       = azurerm_key_vault.kv.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = azurerm_user_assigned_identity.mi.principal_id
  secret_permissions = ["Get"]
}

resource "azurerm_key_vault_secret" "demo" {
  name         = "demo-secret"
  value        = "demo-value"
  key_vault_id = azurerm_key_vault.kv.id

  # Must wait for Terraform SP policy to kick in before creating secrets
  depends_on = [azurerm_key_vault_access_policy.kv]
}
