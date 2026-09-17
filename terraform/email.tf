# Emails sent by n8n (invitations, password resets) through the SMTP endpoint of
# Azure Communication Services. SMTP username = a resource linked to an Entra
# application; password = a client secret of that application.
locals {
  email_sender = local.email.enabled ? "DoNotReply@${module.email_communication_service[0].domain_from_sender_domains["azure_managed"]}" : null
}

module "email_communication_service" {
  source  = "Azure/avm-res-communication-emailservice/azurerm"
  version = "0.3.0"
  count   = local.email.enabled ? 1 : 0

  name          = local.names.email_communication_service
  parent_id     = module.resource_group.resource_id
  location      = local.location
  data_location = local.email.data_location

  # Azure managed domain: no DNS to configure, but capped at 5 emails per minute
  # and 10 per hour per subscription.
  email_communication_service_domains = {
    azure_managed = {
      name              = "AzureManagedDomain"
      domain_management = "AzureManaged"
    }
  }

  tags             = local.tags
  enable_telemetry = local.enable_telemetry
}

# No AVM module for Communication Services.
resource "azurerm_communication_service" "n8n" {
  count = local.email.enabled ? 1 : 0

  name                = local.names.communication_service
  resource_group_name = module.resource_group.name
  data_location       = local.email.data_location

  tags = local.tags
}

resource "azurerm_communication_service_email_domain_association" "n8n" {
  count = local.email.enabled ? 1 : 0

  communication_service_id = azurerm_communication_service.n8n[0].id
  email_service_domain_id  = module.email_communication_service[0].domain_resource_ids["azure_managed"]
}

# SMTP credentials: the client secret of this application is the SMTP password.
resource "azuread_application_registration" "smtp" {
  count = local.email.enabled ? 1 : 0

  display_name = local.names.smtp_application
}

# The application's identity in the tenant, which holds the role assignment.
resource "azuread_service_principal" "smtp" {
  count = local.email.enabled ? 1 : 0

  client_id = azuread_application_registration.smtp[0].client_id
}

resource "azuread_application_password" "smtp" {
  count = local.email.enabled ? 1 : 0

  application_id = azuread_application_registration.smtp[0].id
  display_name   = "n8n-smtp"
}

resource "azurerm_role_assignment" "smtp" {
  count = local.email.enabled ? 1 : 0

  scope                = azurerm_communication_service.n8n[0].id
  role_definition_name = "Communication and Email Service Owner"
  principal_id         = azuread_service_principal.smtp[0].object_id
  principal_type       = "ServicePrincipal"
}

# The SMTP username requires the application to hold its role: wait for the
# assignment to propagate.
resource "time_sleep" "wait_for_smtp_rbac" {
  count = local.email.enabled ? 1 : 0

  create_duration = "60s"

  # Waits again whenever the role assignment is replaced.
  triggers = {
    role_assignment_id = azurerm_role_assignment.smtp[0].id
  }
}

# Not supported by azurerm. Azure rejects a username equal to the resource name.
resource "azapi_resource" "smtp_username" {
  count = local.email.enabled ? 1 : 0

  type      = "Microsoft.Communication/communicationServices/smtpUsernames@2025-09-01"
  name      = local.workload
  parent_id = azurerm_communication_service.n8n[0].id

  body = {
    properties = {
      entraApplicationId = azuread_application_registration.smtp[0].client_id
      tenantId           = data.azurerm_client_config.current.tenant_id
      username           = local.names.smtp_username
    }
  }

  depends_on = [
    time_sleep.wait_for_smtp_rbac,
    azurerm_communication_service_email_domain_association.n8n,
  ]
}
