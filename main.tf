terraform {
    required_version = "> 1.4.6"
    backend "azurerm" {}
      required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = ">3.59.0"
        }
    }
}

provider "azurerm" {
    features {
        virtual_machine {
            delete_os_disk_on_deletion = true
        }
    }
}

resource "random_id" "resource_id" {
    byte_length = 8
    prefix = "aks-"
}

locals {
  resourceName = substr(random_id.resource_id.hex, 0, 8)
}

resource "azurerm_resource_group" "resource_group" {
  name     = local.resourceName
  location = "West Europe"
}

// Create a managed identity

resource "azurerm_user_assigned_identity" "aks_identity" {
  name                = "${local.resourceName}-identity"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
}

// Create a virtual network

resource "azurerm_virtual_network" "virtual_network" {
  name                = "${local.resourceName}-vnet"
  address_space       = ["10.100.0.0/16"]
  location = "West Europe"
  resource_group_name = azurerm_resource_group.resource_group.name
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "${local.resourceName}-subnet"
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes       = ["10.100.0.0/24"]
}

resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                = local.resourceName
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  dns_prefix          = local.resourceName
  kubernetes_version  = var.cluster_kubernetes_version
  node_resource_group = "${local.resourceName}-node-rg"

  identity {
      type = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.aks_identity.id]
    }

    default_node_pool {
      name       = "sys"
      node_count = 3
      vnet_subnet_id = azurerm_subnet.aks_subnet.id
      vm_size = "Standard_D2s_v3"
      os_sku = "Mariner"
      node_labels = {
        "nodepool-type" = "system"
        "nodepool-kubernetes-version" = var.cluster_kubernetes_version
      }
    }

  network_profile {
    network_plugin = "azure"
    network_plugin_mode = "Overlay"
    dns_service_ip = "10.250.0.10"
    service_cidr = "10.250.0.0/16"
  }
}

// Create a user nodepool

resource "azurerm_kubernetes_cluster_node_pool" "user_node_pool_blue" {
  count = var.blue_active ? 1 : 0
  name                = "userblue"
  node_labels = {
      "nodepool-type" = "user-blue"
      "nodepool-state" = var.blue_state
      "nodepool-kubernetes-version" = var.blue_kubernetes_version
    }
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks_cluster.id
  vm_size             = "Standard_D2s_v3"
  node_count          = 3
  orchestrator_version = var.blue_kubernetes_version
  vnet_subnet_id = azurerm_subnet.aks_subnet.id
  os_type = "Linux"
  os_sku = "Mariner"
}

resource "azurerm_kubernetes_cluster_node_pool" "user_node_pool_green" {
  count = var.green_active ? 1 : 0
  name                = "usergreen"
     node_labels = {
        "nodepool-type" = "user-green"
        "nodepool-state" = var.green_state
        "nodepool-kubernetes-version" = var.green_kubernetes_version
        }
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks_cluster.id
  vm_size             = "Standard_D2s_v3"
  node_count          = 3
  orchestrator_version = var.green_kubernetes_version
  vnet_subnet_id = azurerm_subnet.aks_subnet.id
  os_type = "Linux"
  os_sku = "Mariner"
}