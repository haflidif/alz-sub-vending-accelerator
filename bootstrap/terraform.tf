terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.6.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "3.10.0"
    }
    github = {
      source  = "integrations/github"
      version = "6.13.0"
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
