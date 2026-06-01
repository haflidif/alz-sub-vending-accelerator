# Provider auth comes from the CI environment via the standard ARM_* env vars
# (set by azure/login@v3 + OIDC), or from `az login` locally.
provider "azurerm" {
  features {}
  storage_use_azuread = true
  subscription_id     = var.vending_subscription_id
  tenant_id           = var.tenant_id
}

provider "azapi" {
  tenant_id = var.tenant_id
}
