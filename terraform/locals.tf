locals {
  location       = "francecentral"
  location_short = "frc"
  environment    = "poc"
  workload       = "n8n"
  instance       = "001"

  suffix = "${local.workload}-${local.environment}-${local.location_short}-${local.instance}"
  unique = substr(sha256(data.azurerm_client_config.current.subscription_id), 0, 5)

  names = {
    resource_group              = "rg-${local.suffix}"
    log_analytics_workspace     = "log-${local.suffix}"
    user_assigned_identity      = "id-${local.suffix}"
    container_app_environment   = "cae-${local.suffix}"
    container_app_main          = "ca-main-${local.suffix}"
    container_app_worker        = "ca-worker-${local.suffix}"
    key_vault                   = "kv-${local.workload}-${local.environment}-${local.location_short}-${local.unique}"
    postgresql_server           = "psql-${local.workload}-${local.environment}-${local.location_short}-${local.unique}"
    managed_redis               = "redis-${local.workload}-${local.environment}-${local.location_short}-${local.unique}"
    email_communication_service = "ecs-${local.workload}-${local.environment}-${local.location_short}-${local.unique}"
    communication_service       = "acs-${local.workload}-${local.environment}-${local.location_short}-${local.unique}"
    smtp_application            = "app-smtp-${local.suffix}"
    smtp_username               = "smtp-${local.suffix}"
  }

  log_analytics = {
    retention_in_days = 30
  }

  postgresql = {
    version     = "16"
    sku_name    = "B_Standard_B1ms"
    storage_mb  = 32768 # grows automatically
    admin_login = "pgadmin"
    database    = "n8n"
    # Optional Entra ID administrator (empty object_id = none).
    # principal_name: UPN of a User or display name of a Group.
    entra_admin = {
      object_id      = ""
      principal_name = ""
      principal_type = "User" # Or "Group"
    }
  }

  redis = {
    sku_name = "Balanced_B0"
  }

  # n8n emails through Azure Communication Services, from an Azure managed domain.
  email = {
    enabled       = true
    data_location = "Europe"
  }

  n8n = {
    image = "ghcr.io/n8n-io/n8n:2.38.7"

    main = {
      cpu    = 1.0
      memory = "2Gi"
    }

    worker = {
      cpu          = 1.0
      memory       = "2Gi"
      max_replicas = 3
      concurrency  = 5
    }

    timezone           = "UTC"
    executions_max_age = 168 # hours
  }

  enable_telemetry = false

  tags = {
    Environment = local.environment
    Workload    = local.workload
    ManagedBy   = "Terraform"
  }
}
