output "n8n_url" {
  description = "Public URL of the n8n editor."
  value       = local.n8n_public_url
}

output "resource_group_name" {
  description = "Resource group of the PoC."
  value       = module.resource_group.name
}

output "key_vault_name" {
  description = "Key Vault name."
  value       = module.key_vault.name
}

output "postgresql_fqdn" {
  description = "PostgreSQL server FQDN."
  value       = module.postgresql.fqdn
}

output "redis_endpoint" {
  description = "Azure Managed Redis endpoint (host:port), TLS required."
  value       = local.redis_endpoint
}

output "container_app_main_name" {
  description = "Name of the n8n main Container App, for az containerapp commands."
  value       = local.names.container_app_main
}

output "container_app_worker_name" {
  description = "Name of the n8n worker Container App, for az containerapp commands."
  value       = local.names.container_app_worker
}

output "email_sender" {
  description = "Sender address of n8n emails, null when email is disabled."
  value       = local.email_sender
}

output "operator_ip" {
  description = "Public IP allowed on the PostgreSQL firewall."
  value       = local.operator_ip
}

# Readable recap, displayed last after apply. The outputs above are for scripts.
output "summary" {
  description = "Recap of the deployment."
  value       = <<-EOT
    n8n             ${local.n8n_public_url}
    Resource group  ${module.resource_group.name}
    Container Apps  ${local.names.container_app_main}, ${local.names.container_app_worker}
    Key Vault       ${module.key_vault.name}
    PostgreSQL      ${module.postgresql.fqdn} (firewall: ${local.operator_ip})
    Redis           ${local.redis_endpoint}
    Email sender    ${coalesce(local.email_sender, "disabled")}
  EOT
}
