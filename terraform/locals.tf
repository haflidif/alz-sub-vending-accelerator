# =============================================================================
# Parse sub.yaml, select archetype, validate, and compute final module inputs
# =============================================================================

locals {
  # ---------------------------------------------------------------------------
  # Load the subscription contract
  # ---------------------------------------------------------------------------
  sub      = yamldecode(file(var.sub_yaml_path))
  sub_name = trimsuffix(basename(var.sub_yaml_path), ".yaml")

  # ---------------------------------------------------------------------------
  # Required fields — each `_assert_*` will throw a clear error if missing
  # ---------------------------------------------------------------------------
  _assert_archetype = lookup(local.sub, "archetype", null) != null ? null : tobool(
    "${var.sub_yaml_path} is missing required field: archetype"
  )
  _assert_location = lookup(local.sub, "location", null) != null && local.sub.location != "" ? null : tobool(
    "${var.sub_yaml_path} is missing required field: location (no default)"
  )
  _assert_owner = lookup(local.sub, "owner", null) != null ? null : tobool(
    "${var.sub_yaml_path} is missing required field: owner"
  )
  _assert_known_archetype = contains(keys(local.archetype_config), local.sub.archetype) ? null : tobool(
    "Unknown archetype '${local.sub.archetype}' in ${var.sub_yaml_path}. Valid: ${join(", ", keys(local.archetype_config))}"
  )

  # ---------------------------------------------------------------------------
  # Resolve archetype config + sub-level fields
  # ---------------------------------------------------------------------------
  archetype = local.sub.archetype
  arch      = local.archetype_config[local.archetype]

  display_name = lookup(local.sub, "displayName", local.sub_name)
  alias_name   = lookup(local.sub, "aliasName", local.sub_name)
  workload     = local.arch.force_workload != null ? local.arch.force_workload : lookup(local.sub, "workload", "Production")
  location     = local.sub.location
  owner        = local.sub.owner
  cost_center  = lookup(local.sub, "costCenter", null)

  # Optional ownership extensions (with sensible defaults)
  technical_responsible = lookup(local.sub, "technicalResponsible", local.owner)
  workload_name         = lookup(local.sub, "workloadName", local.alias_name)

  # ---------------------------------------------------------------------------
  # Cost allocation code — operator-configurable (operator decides tag KEY,
  # whether it's required, and the validation pattern).
  # ---------------------------------------------------------------------------
  cost_allocation_code = lookup(local.sub, "costAllocationCode", null)

  _assert_cost_alloc_required = (
    var.cost_allocation_required && (local.cost_allocation_code == null || local.cost_allocation_code == "")
    ) ? tobool(
    "${var.sub_yaml_path}: costAllocationCode is required (operator policy: cost_allocation_required=true). Tag key: ${var.cost_allocation_tag_key}."
  ) : null

  _assert_cost_alloc_pattern = (
    local.cost_allocation_code != null && local.cost_allocation_code != "" && var.cost_allocation_pattern != null
    && !can(regex(var.cost_allocation_pattern, local.cost_allocation_code))
    ) ? tobool(
    "${var.sub_yaml_path}: costAllocationCode '${local.cost_allocation_code}' does not match operator-configured pattern: ${coalesce(var.cost_allocation_pattern, "")}"
  ) : null

  # ---------------------------------------------------------------------------
  # Billing scope resolution — sub.yaml may opt into a non-default scope via
  # `billingScopeKey: <name>` (e.g. "sandbox" → EA enrollment account, while
  # "default" → MCA invoice section).
  # ---------------------------------------------------------------------------
  _billing_scope_key = lookup(local.sub, "billingScopeKey", "default")
  _assert_billing_scope_key = contains(keys(var.billing_scopes), local._billing_scope_key) ? null : tobool(
    "${var.sub_yaml_path}: billingScopeKey '${local._billing_scope_key}' not found in billing_scopes. Available: ${join(", ", keys(var.billing_scopes))}"
  )
  billing_scope = var.billing_scopes[local._billing_scope_key]

  # MG ID resolution — must exist for the archetype.
  # Accepts either a bare MG name ("mycompany-sandbox") or a full resource ID
  # ("/providers/Microsoft.Management/managementGroups/mycompany-sandbox") in
  # terraform.tfvars; the AVM sub-vending module wants the bare name.
  _assert_mg = contains(keys(var.management_group_ids), local.archetype) ? null : tobool(
    "management_group_ids has no entry for archetype '${local.archetype}'. Add it to terraform.tfvars."
  )
  _raw_mg_id          = var.management_group_ids[local.archetype]
  management_group_id = element(split("/", local._raw_mg_id), length(split("/", local._raw_mg_id)) - 1)

  # ---------------------------------------------------------------------------
  # Tag layering: caller <- mandatory <- archetype <- identity (governed wins)
  # All tag NAMES align with CAF (lowercase, no separators).
  # The operator-configurable cost-allocation tag overlays last when present.
  # ---------------------------------------------------------------------------
  _base_identity_tags = {
    businessowner    = local.owner
    technicalcontact = local.technical_responsible
    costcenter       = coalesce(local.cost_center, "unassigned")
    workloadname     = local.workload_name
    environment      = local.workload # Production | DevTest
  }

  _cost_alloc_overlay = (
    local.cost_allocation_code != null && local.cost_allocation_code != ""
    ? { (var.cost_allocation_tag_key) = local.cost_allocation_code }
    : {}
  )

  identity_tags = merge(local._base_identity_tags, local._cost_alloc_overlay)

  # Reserved tag keys: caller's `tags:` map MUST NOT contain any of these.
  # Includes identity keys, the cost-allocation key, the archetype tag, and
  # every key declared in mandatory_tags.
  _reserved_tag_keys = toset(concat(
    keys(local._base_identity_tags),
    [var.cost_allocation_tag_key, "archetype"],
    keys(var.mandatory_tags),
  ))

  _caller_tags     = lookup(local.sub, "tags", {})
  _caller_tag_keys = keys(local._caller_tags)
  _caller_collisions = [
    for k in local._caller_tag_keys : k if contains(local._reserved_tag_keys, k)
  ]
  _assert_no_caller_tag_collision = length(local._caller_collisions) == 0 ? null : tobool(
    "${var.sub_yaml_path}: free-form tags map cannot contain reserved keys: ${join(", ", local._caller_collisions)}. Reserved set: ${join(", ", tolist(local._reserved_tag_keys))}."
  )

  # Governed tags win on conflict (caller_tags first, then platform layers).
  effective_tags = merge(
    local._caller_tags,
    var.mandatory_tags,
    local.arch.extra_tags,
    local.identity_tags,
  )

  # ---------------------------------------------------------------------------
  # Networking — apply archetype guardrails on top of caller config
  # ---------------------------------------------------------------------------
  network_input   = lookup(local.sub, "network", { enabled = false })
  network_enabled = try(local.network_input.enabled, false)

  # hub_peering: archetype default if unset; force-on if archetype disallows opt-out
  _hub_peering_requested = try(local.network_input.hubPeering, local.arch.hub_peering_default)
  hub_peering_effective  = local.arch.hub_peering_allow_false ? local._hub_peering_requested : true

  virtual_networks = local.network_enabled ? {
    spoke = {
      name                    = "vnet-${local.alias_name}"
      resource_group_key      = "rg_network"
      address_space           = try(local.network_input.addressSpace, [])
      hub_network_resource_id = local.hub_peering_effective ? var.hub_virtual_network_resource_id : null
      hub_peering_enabled     = local.hub_peering_effective
      hub_peering_direction   = local.hub_peering_effective ? "both" : null
      subnets = {
        for subnet_name, subnet in try(local.network_input.subnets, {}) : subnet_name => merge(
          subnet,
          {
            name = try(subnet.name, subnet_name)
          },
          contains(keys(subnet), "default_outbound_access") ? {
            default_outbound_access_enabled = subnet.default_outbound_access
          } : {},
        )
      }
    }
  } : {}

  resource_groups = local.network_enabled ? {
    rg_network      = { name = "rg-${local.alias_name}-network", location = local.location }
    rg_networkwatch = { name = "NetworkWatcherRG", location = local.location }
  } : {}

  # ---------------------------------------------------------------------------
  # Budget — enforce archetype rules
  # ---------------------------------------------------------------------------
  budget_input = lookup(local.sub, "budget", null)

  _assert_budget = (local.arch.budget_required && local.budget_input == null) ? tobool(
    "Archetype '${local.archetype}' requires a budget block in ${var.sub_yaml_path} (key: budget.amount)."
  ) : null

  _budget_contacts = local.budget_input == null ? [] : concat(
    [local.owner],
    try(local.budget_input.contacts, []),
  )

  _actual_notifications = {
    for t in local.arch.budget_thresholds_actual : "actual${t}" => {
      enabled        = true
      operator       = "GreaterThan"
      threshold      = t
      threshold_type = "Actual"
      contact_emails = local._budget_contacts
    }
  }
  _forecast_notifications = {
    for t in local.arch.budget_thresholds_forecast : "forecast${t}" => {
      enabled        = true
      operator       = "GreaterThan"
      threshold      = t
      threshold_type = "Forecasted"
      contact_emails = local._budget_contacts
    }
  }

  budgets = local.budget_input == null ? {} : {
    monthly = {
      name              = "${local.alias_name}-monthly"
      amount            = local.budget_input.amount
      time_grain        = "Monthly"
      time_period_start = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
      time_period_end   = "2099-12-31T23:59:59Z"
      notifications     = merge(local._actual_notifications, local._forecast_notifications)
    }
  }

  # ---------------------------------------------------------------------------
  # Role assignments + UMI passthrough
  # ---------------------------------------------------------------------------
  role_assignments = {
    for assignment_name, assignment in lookup(local.sub, "roleAssignments", {}) : assignment_name => {
      principal_id              = assignment.principal_id
      definition                = assignment.role_definition_id_or_name
      relative_scope            = try(assignment.relative_scope, "")
      resource_group_scope_key  = try(assignment.resource_group_scope_key, null)
      condition                 = try(assignment.condition, null)
      condition_version         = try(assignment.condition_version, null)
      principal_type            = try(assignment.principal_type, null)
      definition_lookup_enabled = try(assignment.definition_lookup_enabled, false)
      use_random_uuid           = try(assignment.use_random_uuid, false)
    }
  }
  managed_identity = lookup(local.sub, "managedIdentity", null)
  user_managed_identities = local.managed_identity == null ? {} : {
    primary = {
      name                = local.managed_identity.name
      resource_group_name = lookup(local.managed_identity, "resourceGroupName", "rg-${local.alias_name}-identity")
      location            = local.location
    }
  }
}
