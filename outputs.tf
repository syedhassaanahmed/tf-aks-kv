output rg_name {
    value = azurerm_resource_group.rg.name
}

output aks_cluster_name {
    value = azurerm_kubernetes_cluster.aks.name
}

output aad_pod_id_binding_selector {
    value = var.aad_pod_id_binding_selector
}

output key_vault_name {
    value = azurerm_key_vault.kv.name
}

output tenant_id {
    value = data.azurerm_client_config.current.tenant_id
}
