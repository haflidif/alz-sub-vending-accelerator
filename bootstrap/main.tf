###############################################################################
# Lookups
###############################################################################

data "azurerm_subscription" "platform" {
  subscription_id = var.platform_subscription_id
}

data "azurerm_resource_group" "uami" {
  name = var.uami_resource_group_name
}

data "azurerm_storage_account" "state" {
  count = var.starter_name == "terraform" ? 1 : 0

  name                = var.state_storage_account_name
  resource_group_name = var.state_storage_account_resource_group_name
}

###############################################################################
# Pipeline identity (UAMI) + federated credentials for GitHub OIDC
###############################################################################

resource "azurerm_user_assigned_identity" "pipeline" {
  name                = var.uami_name
  resource_group_name = data.azurerm_resource_group.uami.name
  location            = var.location
  tags                = var.tags
}

locals {
  github_subject_prefix = "repo:${var.github_owner}/${var.github_repository_name}"

  federated_credentials = {
    branch = {
      display_name = "github-branch-${var.github_default_branch}"
      subject      = "${local.github_subject_prefix}:ref:refs/heads/${var.github_default_branch}"
    }
    pull_request = {
      display_name = "github-pull-request"
      subject      = "${local.github_subject_prefix}:pull_request"
    }
    environment_production = {
      display_name = "github-env-${var.production_environment_name}"
      subject      = "${local.github_subject_prefix}:environment:${var.production_environment_name}"
    }
  }
}

resource "azurerm_federated_identity_credential" "pipeline" {
  for_each = local.federated_credentials

  name                      = each.value.display_name
  user_assigned_identity_id = azurerm_user_assigned_identity.pipeline.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = each.value.subject
}

###############################################################################
# Terraform runtime state container. The platform storage account already
# exists; the Bicep starter skips this resource.
###############################################################################

resource "azurerm_storage_container" "tfstate" {
  count = var.starter_name == "terraform" ? 1 : 0

  name                  = var.state_container_name
  storage_account_id    = data.azurerm_storage_account.state[0].id
  container_access_type = "private"
}

###############################################################################
# Azure RBAC for the pipeline identity
###############################################################################

# Terraform-only, container-scoped state read/write
resource "azurerm_role_assignment" "state_blob_contributor" {
  count = var.starter_name == "terraform" ? 1 : 0

  scope                = azurerm_storage_container.tfstate[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.pipeline.principal_id
  principal_type       = "ServicePrincipal"
}

# Management Group Contributor — to vend subs and place them under MGs
resource "azurerm_role_assignment" "mg_contributor" {
  scope                = "/providers/Microsoft.Management/managementGroups/${var.alz_root_management_group_id}"
  role_definition_name = "Management Group Contributor"
  principal_id         = azurerm_user_assigned_identity.pipeline.principal_id
  principal_type       = "ServicePrincipal"
}

# Optional: User Access Administrator at MG scope for sub YAML roleAssignments
resource "azurerm_role_assignment" "mg_uaa" {
  count                = var.grant_user_access_administrator ? 1 : 0
  scope                = "/providers/Microsoft.Management/managementGroups/${var.alz_root_management_group_id}"
  role_definition_name = "User Access Administrator"
  principal_id         = azurerm_user_assigned_identity.pipeline.principal_id
  principal_type       = "ServicePrincipal"
}

# Network Contributor — RG-scoped on the hub VNet's RG when a hub is provided
# (least privilege). Falls back to whole-sub scope only when no hub is set.
locals {
  hub_vnet_id_parts = (
    var.hub_virtual_network_resource_id != null && var.hub_virtual_network_resource_id != ""
    ? regex("^/subscriptions/[^/]+/resourceGroups/[^/]+", var.hub_virtual_network_resource_id)
    : ""
  )

  network_contributor_scope = (
    local.hub_vnet_id_parts != ""
    ? local.hub_vnet_id_parts
    : "/subscriptions/${var.connectivity_subscription_id}"
  )
}

resource "azurerm_role_assignment" "connectivity_network_contributor" {
  scope                = local.network_contributor_scope
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.pipeline.principal_id
  principal_type       = "ServicePrincipal"
}

###############################################################################
# GitHub repository (optional create)
###############################################################################

resource "github_repository" "this" {
  count = var.create_github_repository ? 1 : 0

  name            = var.github_repository_name
  description     = "Azure subscription vending — driven by Azure/avm-ptn-alz-sub-vending/azure"
  visibility      = var.github_repository_visibility
  has_issues      = true
  has_discussions = false
  has_projects    = false
  has_wiki        = false
  auto_init       = true

  delete_branch_on_merge = true
}

data "github_repository" "this" {
  count      = var.create_github_repository ? 0 : 1
  full_name  = "${var.github_owner}/${var.github_repository_name}"
  depends_on = [github_repository.this]
}

locals {
  github_repo_name = (
    var.create_github_repository
    ? github_repository.this[0].name
    : data.github_repository.this[0].name
  )
}

###############################################################################
# GitHub Actions repository variables (consumed by workflows)
###############################################################################

resource "github_actions_variable" "azure_client_id" {
  repository    = local.github_repo_name
  variable_name = "AZURE_CLIENT_ID"
  value         = azurerm_user_assigned_identity.pipeline.client_id
}

resource "github_actions_variable" "azure_tenant_id" {
  repository    = local.github_repo_name
  variable_name = "AZURE_TENANT_ID"
  value         = data.azurerm_subscription.platform.tenant_id
}

resource "github_actions_variable" "azure_subscription_id" {
  repository    = local.github_repo_name
  variable_name = "AZURE_SUBSCRIPTION_ID"
  value         = var.platform_subscription_id
}

resource "github_actions_variable" "vending_engine" {
  repository    = local.github_repo_name
  variable_name = "VENDING_ENGINE"
  value         = var.starter_name
}

resource "github_actions_variable" "alz_root_management_group_id" {
  repository    = local.github_repo_name
  variable_name = "ALZ_ROOT_MANAGEMENT_GROUP_ID"
  value         = var.alz_root_management_group_id
}

resource "github_actions_variable" "azure_deployment_location" {
  repository    = local.github_repo_name
  variable_name = "AZURE_DEPLOYMENT_LOCATION"
  value         = var.location
}

resource "github_actions_variable" "backend_resource_group" {
  count = var.starter_name == "terraform" ? 1 : 0

  repository    = local.github_repo_name
  variable_name = "BACKEND_RESOURCE_GROUP_NAME"
  value         = var.state_storage_account_resource_group_name
}

resource "github_actions_variable" "backend_storage_account" {
  count = var.starter_name == "terraform" ? 1 : 0

  repository    = local.github_repo_name
  variable_name = "BACKEND_STORAGE_ACCOUNT_NAME"
  value         = var.state_storage_account_name
}

resource "github_actions_variable" "backend_container" {
  count = var.starter_name == "terraform" ? 1 : 0

  repository    = local.github_repo_name
  variable_name = "BACKEND_CONTAINER_NAME"
  value         = azurerm_storage_container.tfstate[0].name
}

###############################################################################
# Production environment with required reviewers
###############################################################################

resource "github_repository_environment" "production" {
  repository  = local.github_repo_name
  environment = var.production_environment_name

  prevent_self_review = true

  dynamic "reviewers" {
    for_each = (
      length(var.production_reviewer_user_ids) > 0 || length(var.production_reviewer_team_ids) > 0
      ? [1] : []
    )
    content {
      users = var.production_reviewer_user_ids
      teams = var.production_reviewer_team_ids
    }
  }

  deployment_branch_policy {
    protected_branches     = true
    custom_branch_policies = false
  }
}

###############################################################################
# Branch protection on the default branch
###############################################################################

resource "github_branch_protection" "default" {
  count = var.enforce_branch_protection ? 1 : 0

  repository_id = local.github_repo_name
  pattern       = var.github_default_branch

  enforce_admins          = false
  allows_deletions        = false
  allows_force_pushes     = false
  require_signed_commits  = false
  required_linear_history = true

  required_pull_request_reviews {
    required_approving_review_count = var.branch_protection_required_approving_review_count
    dismiss_stale_reviews           = true
    require_code_owner_reviews      = false
  }

  dynamic "required_status_checks" {
    for_each = length(var.branch_protection_required_status_checks) > 0 ? [1] : []
    content {
      strict   = true
      contexts = var.branch_protection_required_status_checks
    }
  }

  depends_on = [
    github_repository.this,
    github_repository_file.skeleton,
    github_repository_file.platform_auto_tfvars,
    github_repository_file.bicep_platform,
  ]
}
