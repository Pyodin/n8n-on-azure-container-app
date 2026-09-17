locals {
  # Deployer's public IP, allowed on the PostgreSQL firewall.
  operator_ip = chomp(data.http.operator_ip.response_body)
}

resource "random_password" "postgresql_admin" {
  length           = 32
  special          = true
  override_special = "!#%*+-_=?"

  min_lower   = 4
  min_upper   = 4
  min_numeric = 4
  min_special = 2
}

# Password for n8n: it reads DB_POSTGRESDB_PASSWORD as a static string, whereas
# an Entra token expires after ~1 h. Entra ID only for the optional human
# administrator.
module "postgresql" {
  source  = "Azure/avm-res-dbforpostgresql-flexibleserver/azurerm"
  version = "0.2.3"

  name                = local.names.postgresql_server
  resource_group_name = module.resource_group.name
  location            = local.location

  server_version    = local.postgresql.version
  sku_name          = local.postgresql.sku_name
  storage_mb        = local.postgresql.storage_mb
  auto_grow_enabled = true # n8n stores binary data in the database in queue mode

  administrator_login    = local.postgresql.admin_login
  administrator_password = random_password.postgresql_admin.result

  # The module defaults to high_availability = { mode = "ZoneRedundant" }, which
  # burstable SKUs (B_ prefix) do not support.
  high_availability = null

  authentication = {
    active_directory_auth_enabled = local.postgresql.entra_admin.object_id != ""
    password_auth_enabled         = true
    tenant_id                     = local.postgresql.entra_admin.object_id != "" ? data.azurerm_client_config.current.tenant_id : null
  }

  ad_administrator = local.postgresql.entra_admin.object_id == "" ? {} : {
    admin = {
      tenant_id      = data.azurerm_client_config.current.tenant_id
      object_id      = local.postgresql.entra_admin.object_id
      principal_name = local.postgresql.entra_admin.principal_name
      principal_type = local.postgresql.entra_admin.principal_type
    }
  }

  databases = {
    n8n = {
      name      = local.postgresql.database
      charset   = "UTF8"
      collation = "en_US.utf8"
    }
  }

  # PoC only: public endpoint. See "Road to production" in the README.
  public_network_access_enabled = true

  # The module defaults to a 0.0.0.0-255.255.255.255 rule, i.e. a server open to
  # the whole Internet. Overridden.
  firewall_rules = {
    operator = {
      name             = "operator-ip"
      start_ip_address = local.operator_ip
      end_ip_address   = local.operator_ip
    }
    # 0.0.0.0-0.0.0.0 is the Azure convention for "allow Azure services" (any
    # Azure-hosted source, including other tenants). Needed because the Container
    # Apps outbound IPs are only known after they are created: referencing them
    # would create a cycle.
    azure_services = {
      name             = "allow-azure-services"
      start_ip_address = "0.0.0.0"
      end_ip_address   = "0.0.0.0"
    }
  }

  tags             = local.tags
  enable_telemetry = local.enable_telemetry
}
