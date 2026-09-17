locals {
  # default_domain is an attribute of the ENVIRONMENT, created before the apps:
  # no dependency cycle.
  n8n_public_fqdn = "${local.names.container_app_main}.${module.container_app_environment.default_domain}"
  n8n_public_url  = "https://${local.n8n_public_fqdn}/"
  redis_endpoint  = "${azurerm_managed_redis.n8n.hostname}:${azurerm_managed_redis.n8n.default_database[0].port}"

  # Shared by main and worker: same database, same Redis and, above all, the
  # SAME encryption key. Secrets are added in the modules.
  n8n_env = {
    EXECUTIONS_MODE = "queue"

    DB_TYPE                   = "postgresdb"
    DB_POSTGRESDB_HOST        = module.postgresql.fqdn
    DB_POSTGRESDB_PORT        = "5432"
    DB_POSTGRESDB_DATABASE    = local.postgresql.database
    DB_POSTGRESDB_USER        = local.postgresql.admin_login
    DB_POSTGRESDB_SSL_ENABLED = "true" # default false, Azure PostgreSQL requires TLS

    QUEUE_BULL_REDIS_HOST = azurerm_managed_redis.n8n.hostname
    QUEUE_BULL_REDIS_PORT = tostring(azurerm_managed_redis.n8n.default_database[0].port) # default 6379
    QUEUE_BULL_REDIS_TLS  = "true"                                                       # default false
    QUEUE_BULL_REDIS_DB   = "0"

    # A worker killed mid-job loses its execution, and autoscaling kills workers.
    N8N_GRACEFUL_SHUTDOWN_TIMEOUT = "30"

    EXECUTIONS_DATA_PRUNE           = "true"
    EXECUTIONS_DATA_MAX_AGE         = tostring(local.n8n.executions_max_age)
    EXECUTIONS_DATA_SAVE_ON_SUCCESS = "none"

    # No N8N_METRICS: /metrics would be served publicly by the main's ingress,
    # unauthenticated, and nothing scrapes it.
    N8N_LOG_LEVEL  = "info"
    N8N_LOG_OUTPUT = "console"

    GENERIC_TIMEZONE = local.n8n.timezone
    TZ               = local.n8n.timezone
  }

  # Main only: the public URLs. Without them, n8n displays webhook URLs that
  # third parties cannot call.
  n8n_env_main = {
    N8N_PORT            = "5678"
    N8N_PROTOCOL        = "https"
    N8N_HOST            = local.n8n_public_fqdn
    N8N_EDITOR_BASE_URL = local.n8n_public_url
    N8N_WEBHOOK_URL     = local.n8n_public_url

    # A single reverse proxy here: the Container Apps Envoy. Behind an
    # Application Gateway, this would likely become 2.
    N8N_PROXY_HOPS = "1"
  }

  # Worker only: disabled by default, serves /healthz for the probes.
  n8n_env_worker = {
    QUEUE_HEALTH_CHECK_ACTIVE = "true"
    QUEUE_HEALTH_CHECK_PORT   = "5678"
  }

  # Azure Communication Services SMTP. The password comes from Key Vault.
  n8n_env_email = local.email.enabled ? {
    N8N_EMAIL_MODE    = "smtp"
    N8N_SMTP_HOST     = "smtp.azurecomm.net"
    N8N_SMTP_PORT     = "587"
    N8N_SMTP_SSL      = "false" # implicit TLS (port 465); port 587 uses STARTTLS
    N8N_SMTP_STARTTLS = "true"
    N8N_SMTP_USER     = local.names.smtp_username
    N8N_SMTP_SENDER   = "n8n <${local.email_sender}>"
  } : {}

  # Key Vault references, identical for both Container Apps. Versionless: a
  # rotated secret is picked up automatically.
  container_app_secrets = {
    for name in keys(local.secrets) : name => {
      name                = name
      key_vault_secret_id = module.key_vault.secrets_resource_ids[name].versionless_id
      identity            = module.user_assigned_identity.resource_id
    }
  }
}

# Identity used by both Container Apps to read their secrets from Key Vault.
# User-assigned rather than system-assigned: a system identity only exists once
# the app is created, too late to resolve Key Vault references set at creation.
module "user_assigned_identity" {
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "0.5.2"

  name                = local.names.user_assigned_identity
  resource_group_name = module.resource_group.name
  location            = local.location

  tags             = local.tags
  enable_telemetry = local.enable_telemetry
}

module "container_app_environment" {
  source  = "Azure/avm-res-app-managedenvironment/azurerm"
  version = "0.5.0"

  name                = local.names.container_app_environment
  resource_group_name = module.resource_group.name
  location            = local.location

  log_analytics_workspace = {
    resource_id = module.log_analytics.resource_id
  }

  # Workload profiles rather than consumption-only: this is the environment type
  # that supports VNet integration, private endpoints and user-defined routes,
  # i.e. the one a production deployment would use.
  workload_profiles = [
    {
      name                  = "Consumption"
      workload_profile_type = "Consumption"
    }
  ]

  # The module defaults to zone_redundant = true, which Azure rejects without
  # infrastructure_subnet_id. This PoC has no VNet.
  zone_redundant = false

  tags             = local.tags
  enable_telemetry = local.enable_telemetry
}

# main: editor, REST API, scheduled triggers, and database schema MIGRATIONS at
# startup.
module "n8n_main" {
  source  = "Azure/avm-res-app-containerapp/azurerm"
  version = "0.9.0"

  name                                  = local.names.container_app_main
  resource_group_name                   = module.resource_group.name
  location                              = local.location
  container_app_environment_resource_id = module.container_app_environment.resource_id

  revision_mode         = "Single"
  workload_profile_name = "Consumption"

  managed_identities = {
    user_assigned_resource_ids = [module.user_assigned_identity.resource_id]
  }

  secrets = local.container_app_secrets

  ingress = {
    external_enabled           = true
    target_port                = 5678
    transport                  = "auto"
    allow_insecure_connections = false

    traffic_weight = [
      {
        percentage      = 100
        latest_revision = true
      }
    ]
  }

  template = {
    # The main runs the scheduler: never 0 replicas, or scheduled triggers stop.
    min_replicas = 1
    max_replicas = 1

    containers = [
      {
        name   = "n8n-main"
        image  = local.n8n.image
        cpu    = local.n8n.main.cpu
        memory = local.n8n.main.memory

        env = concat(
          [for name, value in merge(local.n8n_env, local.n8n_env_email, local.n8n_env_main) : { name = name, value = value }],
          [for secret, variable in local.secrets : { name = variable, secret_name = secret }],
        )

        # Startup: up to ~5 min for schema migrations after an upgrade, before
        # liveness can kill the container.
        startup_probes = [
          {
            transport               = "HTTP"
            port                    = 5678
            path                    = "/healthz"
            initial_delay           = 10
            interval_seconds        = 30
            failure_count_threshold = 10
            timeout                 = 5
          }
        ]

        # Liveness: the process answers. Restarts the container otherwise.
        liveness_probes = [
          {
            transport               = "HTTP"
            port                    = 5678
            path                    = "/healthz"
            interval_seconds        = 10
            failure_count_threshold = 3
            timeout                 = 5
          }
        ]

        # Readiness: the database is connected and migrated. Takes the replica
        # out of the ingress otherwise, without restarting it.
        readiness_probes = [
          {
            transport               = "HTTP"
            port                    = 5678
            path                    = "/healthz/readiness"
            interval_seconds        = 10
            failure_count_threshold = 3
            success_count_threshold = 1
            timeout                 = 5
          }
        ]
      }
    ]
  }

  tags             = local.tags
  enable_telemetry = local.enable_telemetry

  depends_on = [
    # The identity must be able to read the secrets before the app resolves
    # them, otherwise it starts in error.
    time_sleep.wait_for_kv_rbac,
    module.postgresql,
    azurerm_managed_redis.n8n,
  ]
}

# worker: consumes the Redis queue and runs the workflows. No ingress, hence no
# network exposure.
#
# depends_on the main: the main runs the schema migrations, and two instances
# starting together on an empty database fight over them. In production, run
# migrations in a dedicated Container Apps Job: an init container would run once
# per replica and race the same way.
module "n8n_worker" {
  source  = "Azure/avm-res-app-containerapp/azurerm"
  version = "0.9.0"

  name                                  = local.names.container_app_worker
  resource_group_name                   = module.resource_group.name
  location                              = local.location
  container_app_environment_resource_id = module.container_app_environment.resource_id

  revision_mode         = "Single"
  workload_profile_name = "Consumption"

  managed_identities = {
    user_assigned_resource_ids = [module.user_assigned_identity.resource_id]
  }

  secrets = local.container_app_secrets

  template = {
    min_replicas = 0
    max_replicas = local.n8n.worker.max_replicas

    containers = [
      {
        name = "n8n-worker"
        # Same image as the main, different command.
        image  = local.n8n.image
        cpu    = local.n8n.worker.cpu
        memory = local.n8n.worker.memory
        args   = ["worker", "--concurrency=${local.n8n.worker.concurrency}"]

        env = concat(
          [for name, value in merge(local.n8n_env, local.n8n_env_email, local.n8n_env_worker) : { name = name, value = value }],
          [for secret, variable in local.secrets : { name = variable, secret_name = secret }],
        )

        # Served by QUEUE_HEALTH_CHECK_ACTIVE. Without it, a hung worker is never
        # restarted: it has no ingress, hence no default probe.
        startup_probes = [
          {
            transport               = "HTTP"
            port                    = 5678
            path                    = "/healthz"
            initial_delay           = 10
            interval_seconds        = 10
            failure_count_threshold = 10
            timeout                 = 5
          }
        ]

        liveness_probes = [
          {
            transport               = "HTTP"
            port                    = 5678
            path                    = "/healthz"
            interval_seconds        = 30
            failure_count_threshold = 3
            timeout                 = 5
          }
        ]
      }
    ]

    # KEDA autoscaling on the Redis queue depth.
    custom_scale_rules = [
      {
        name             = "redis-queue-depth"
        custom_rule_type = "redis"

        # listName must be the actual BullMQ list: KEDA knows nothing about n8n,
        # it reads the length of a list. A wrong name = a worker that never
        # scales, without any error. See "Validate" in the README.
        metadata = {
          address       = local.redis_endpoint
          listName      = "bull:jobs:wait"
          listLength    = "5"
          enableTLS     = "true"
          databaseIndex = "0"
        }

        authentication = [
          {
            secret_name       = "n8n-redis-password"
            trigger_parameter = "password"
          }
        ]
      }
    ]
  }

  tags             = local.tags
  enable_telemetry = local.enable_telemetry

  depends_on = [
    time_sleep.wait_for_kv_rbac,
    module.postgresql,
    azurerm_managed_redis.n8n,
    module.n8n_main,
  ]
}
