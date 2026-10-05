# =============================================================================
# Single AVM module call — Azure/avm-ptn-alz-sub-vending/azure
# -----------------------------------------------------------------------------
# All archetype-specific behaviour is computed in locals.tf using the
# declarative config in archetypes.tf. This file is intentionally generic.
# =============================================================================

module "subscription" {
  source  = "Azure/avm-ptn-alz-sub-vending/azure"
  version = "0.3.3"

  # ---- Subscription creation ----
  subscription_alias_enabled = true
  subscription_alias_name    = local.alias_name
  subscription_display_name  = local.display_name
  subscription_workload      = local.workload
  subscription_billing_scope = local.billing_scope

  # ---- Management group association ----
  subscription_management_group_association_enabled = true
  subscription_management_group_id                  = local.management_group_id

  # ---- Tags ----
  subscription_tags = local.effective_tags

  # ---- Resource provider registration ----
  subscription_register_resource_providers_enabled = true

  # ---- Resource groups (incl. NetworkWatcherRG when networking is on) ----
  resource_group_creation_enabled = length(local.resource_groups) > 0
  resource_groups                 = local.resource_groups

  # ---- Networking ----
  virtual_network_enabled = local.network_enabled
  virtual_networks        = local.virtual_networks

  # ---- Role assignments ----
  role_assignment_enabled = length(local.role_assignments) > 0
  role_assignments        = local.role_assignments

  # ---- Budgets ----
  budget_enabled = length(local.budgets) > 0
  budgets        = local.budgets

  # ---- User-assigned managed identity (optional) ----
  umi_enabled             = local.managed_identity != null
  user_managed_identities = local.user_managed_identities

  location = local.location
}
