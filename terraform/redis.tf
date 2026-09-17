# Native resource: the AVM module rejects NoCluster and exposes neither
# access_keys_authentication_enabled nor the access key.
resource "azurerm_managed_redis" "n8n" {
  name                = local.names.managed_redis
  resource_group_name = module.resource_group.name
  location            = local.location

  sku_name = local.redis.sku_name

  # PoC: the queue is lost on a node failure.
  high_availability_enabled = false
  public_network_access     = "Enabled"

  default_database {
    # BullMQ drives its queue with atomic multi-key Lua scripts, which a
    # clustered Redis rejects with CROSSSLOT. Default: OSSCluster.
    clustering_policy = "NoCluster"

    # The primary key is only exported when true, and n8n has no other way to
    # authenticate.
    access_keys_authentication_enabled = true

    client_protocol = "Encrypted"

    # A job broker must never evict jobs.
    eviction_policy = "NoEviction"
  }

  tags = local.tags
}
