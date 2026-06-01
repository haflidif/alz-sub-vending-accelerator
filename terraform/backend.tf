# Backend is intentionally left empty here — partial configuration.
# CI/CD (and local runs) supply the per-subscription state key via:
#   terraform init -backend-config="key=<archetype>/<sub-name>.tfstate" \
#                  -backend-config="resource_group_name=..." \
#                  -backend-config="storage_account_name=..." \
#                  -backend-config="container_name=subvending-tfstate"
terraform {
  backend "azurerm" {
    use_azuread_auth = true
  }
}
