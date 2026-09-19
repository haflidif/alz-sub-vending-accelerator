terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "4.74.0" }
    azapi   = { source = "Azure/azapi", version = "2.12.0" }
    random  = { source = "hashicorp/random", version = "3.9.0" }
  }
}
