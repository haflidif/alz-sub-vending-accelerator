# =============================================================================
# Root module variables
# =============================================================================
# This root is invoked once per subscription. CI passes the path to the
# subscription's YAML contract via `-var sub_yaml_path=...`.
# =============================================================================

variable "sub_yaml_path" {
  type        = string
  description = "Relative path to the subscription's YAML contract (e.g. ../landingzones/corp/prod-corp-erp-001.yaml)."
}

# -----------------------------------------------------------------------------
# Platform context — provided per environment, NOT per subscription.
# Set these in GitHub repo variables / a *.tfvars file consumed by CI.
# -----------------------------------------------------------------------------

variable "tenant_id" {
  type        = string
  description = "Microsoft Entra tenant ID."
}

variable "vending_subscription_id" {
  type        = string
  description = "Subscription used as the azurerm provider home (typically the management subscription)."
}

# -----------------------------------------------------------------------------
# Billing scopes — keyed map. Each sub.yaml may pick a key via
# `billingScopeKey: <name>`; default key is `default`. The bootstrap derives
# the agreement-specific path string and writes the resolved map here.
# See docs/billing-scopes.md.
# -----------------------------------------------------------------------------

variable "billing_scopes" {
  type        = map(string)
  description = <<-EOT
    Map of billing scope key -> full Azure billing scope path string.
    Each path starts with `/providers/Microsoft.Billing/billingAccounts/`.
    The map MUST contain a `default` key. Per-sub YAML files can opt into a
    non-default scope via `billingScopeKey: <name>`.
  EOT

  validation {
    condition     = contains(keys(var.billing_scopes), "default")
    error_message = "billing_scopes must contain a 'default' entry."
  }
  validation {
    condition = alltrue([
      for s in values(var.billing_scopes) :
      can(regex("^/providers/Microsoft\\.Billing/billingAccounts/", s))
    ])
    error_message = "Every billing scope must start with /providers/Microsoft.Billing/billingAccounts/ (case-sensitive)."
  }
}

variable "management_group_ids" {
  type        = map(string)
  description = "Map of archetype name -> destination management group ID."
  # Example:
  # {
  #   corp    = "/providers/Microsoft.Management/managementGroups/mycompany-corp"
  #   online  = "/providers/Microsoft.Management/managementGroups/mycompany-online"
  #   sandbox = "/providers/Microsoft.Management/managementGroups/mycompany-sandbox"
  # }
}

variable "hub_virtual_network_resource_id" {
  type        = string
  default     = null
  description = <<-EOT
    Resource ID of the platform hub VNet to peer corp/online subscriptions to.
    Set to null (or omit) if you have no hub VNet — corp/online subs that
    request networking will fail-fast at plan time with a clear error.
  EOT

  validation {
    condition = (
      var.hub_virtual_network_resource_id == null ||
      can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", var.hub_virtual_network_resource_id))
    )
    error_message = "hub_virtual_network_resource_id must be either null or a full Azure VNet resource ID (/subscriptions/<guid>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<name>)."
  }
}

# -----------------------------------------------------------------------------
# Cost allocation tag — operator-configurable cost-attribution tag
# (in addition to the always-on `costcenter` tag).
#
# Examples per organization convention:
#   - Activity-code shop: name="activitycode", required=true, pattern="^[A-Z]{1,4}[0-9]{4,8}$"
#   - SAP shop:           name="wbselement",  required=true, pattern="^[A-Z0-9.\\-]+$"
#   - Generic:            leave defaults (required=false, no extra tag emitted)
# See docs/tagging.md.
# -----------------------------------------------------------------------------

variable "cost_allocation_tag_key" {
  type        = string
  default     = "projectcode"
  description = "Azure tag KEY for the operator-configurable cost-allocation tag. Lowercase, no separators (CAF convention)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,127}$", var.cost_allocation_tag_key))
    error_message = "cost_allocation_tag_key must be lowercase alphanumeric, 2-128 chars, starting with a letter (CAF tag convention)."
  }
}

variable "cost_allocation_required" {
  type        = bool
  default     = false
  description = "If true, every sub YAML MUST set `costAllocationCode`. If false, the field is optional; when omitted no tag is emitted."
}

variable "cost_allocation_pattern" {
  type        = string
  default     = null
  description = "Optional regex (anchors recommended) to validate `costAllocationCode` values. null = any non-empty string."
}

# -----------------------------------------------------------------------------
# Mandatory tags — applied to every vended subscription.
# CAF-aligned defaults (lowercase, no separators).
# -----------------------------------------------------------------------------

variable "mandatory_tags" {
  type        = map(string)
  description = <<-EOT
    Platform-wide tags merged into every vended subscription.
    Tag NAMES align with CAF (lowercase, no separators).
    Per-subscription identity tags (businessowner / costcenter / etc.) are
    layered on top of these — see terraform/locals.tf.
    Caller-supplied `tags:` in a sub YAML CANNOT override reserved keys (the
    keys defined here, the identity keys, or `cost_allocation_tag_key`).
  EOT
  default = {
    managedby  = "terraform"
    source     = "avm-ptn-alz-sub-vending"
    deployedby = "subscription-vending-pipeline"
  }
}
