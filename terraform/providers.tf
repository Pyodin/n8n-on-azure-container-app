# azurerm = 4.81.0: the only version satisfying the constraints of all the AVM
# modules used (four cap below 5.0, Key Vault 0.11.0 requires at least 4.81).
# azapi and modtm are dependencies of these modules; azapi also creates the SMTP
# username. azuread creates the Entra application used for SMTP.

terraform {
  required_version = "~> 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.81.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.7"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.4"
    }
    modtm = {
      source  = "Azure/modtm"
      version = "~> 0.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# Subscription: ARM_SUBSCRIPTION_ID, read by both azurerm and azapi. Several AVM
# modules take the subscription from azapi (the resource group module creates
# the group under it): both providers must resolve the same one.
provider "azurerm" {
  resource_provider_registrations = "none"

  features {}
}
