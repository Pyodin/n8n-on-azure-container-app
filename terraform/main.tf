module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name     = local.names.resource_group
  location = local.location

  tags             = local.tags
  enable_telemetry = local.enable_telemetry
}

module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  name                = local.names.log_analytics_workspace
  resource_group_name = module.resource_group.name
  location            = local.location

  log_analytics_workspace_sku               = "PerGB2018"
  log_analytics_workspace_retention_in_days = local.log_analytics.retention_in_days

  tags             = local.tags
  enable_telemetry = local.enable_telemetry
}
