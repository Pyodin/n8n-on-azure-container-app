data "azurerm_client_config" "current" {}

# Deployer's public IP, for the PostgreSQL firewall.
data "http" "operator_ip" {
  url = "https://api.ipify.org/"

  retry {
    attempts     = 5
    min_delay_ms = 500
    max_delay_ms = 2000
  }
}
