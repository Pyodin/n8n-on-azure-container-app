locals {
  # Secret name, identical in Key Vault and in the Container Apps -> n8n
  # environment variable that receives it.
  secrets = merge(
    {
      "n8n-db-password"    = "DB_POSTGRESDB_PASSWORD"
      "n8n-redis-password" = "QUEUE_BULL_REDIS_PASSWORD"
      "n8n-encryption-key" = "N8N_ENCRYPTION_KEY"
    },
    local.email.enabled ? { "n8n-smtp-password" = "N8N_SMTP_PASS" } : {},
  )
}

# Generated once: a changed key silently makes stored n8n credentials
# unreadable. Do not touch the arguments.
resource "random_password" "n8n_encryption_key" {
  length  = 48
  special = false

  lifecycle {
    ignore_changes = all
  }
}

# Public access with an Allow ACL: Container Apps partly resolves Key Vault
# references through its control plane, which does not go through a VNet, and
# ACA is not a "trusted Azure service". Access control relies on RBAC: every
# read requires an Entra token. In production, put the vault behind a private
# endpoint.
module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.11.0"

  name                = local.names.key_vault
  resource_group_name = module.resource_group.name
  location            = local.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                 = "standard"
  purge_protection_enabled = false

  public_network_access_enabled = true
  network_acls = {
    bypass         = "AzureServices"
    default_action = "Allow"
  }

  role_assignments = {
    deployer = {
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = data.azurerm_client_config.current.object_id
    }
    n8n = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = module.user_assigned_identity.principal_id
      principal_type             = "ServicePrincipal"
    }
  }

  # Without this delay, writing the secrets fails with a 403: it races the Entra
  # propagation of the role assignments above.
  wait_for_rbac_before_secret_operations = {
    create = "60s"
  }

  secrets = {
    for name in keys(local.secrets) : name => {
      name         = name
      content_type = "text/plain"
    }
  }

  secrets_value = merge(
    {
      "n8n-db-password"    = random_password.postgresql_admin.result
      "n8n-redis-password" = azurerm_managed_redis.n8n.default_database[0].primary_access_key
      "n8n-encryption-key" = random_password.n8n_encryption_key.result
    },
    local.email.enabled ? { "n8n-smtp-password" = azuread_application_password.smtp[0].value } : {},
  )

  tags             = local.tags
  enable_telemetry = local.enable_telemetry
}

# The identity's "Key Vault Secrets User" assignment must be effective before
# the Container Apps resolve their references, otherwise they start in error.
# The module only delays its own writes.
resource "time_sleep" "wait_for_kv_rbac" {
  depends_on = [module.key_vault]

  create_duration = "60s"
}
