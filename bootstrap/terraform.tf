terraform {
  required_version = "1.15.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.75.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "3.9.0"
    }
    github = {
      source  = "integrations/github"
      version = "6.12.1"
    }
  }
}

provider "azurerm" {
  storage_use_azuread = true
  subscription_id     = var.platform_subscription_id
  features {}
}

provider "azuread" {
  tenant_id = var.tenant_id
}

provider "github" {
  owner = var.github_owner
  # Auth: GITHUB_TOKEN env var (PAT with repo + admin:org scopes if creating repos in an org)
}
