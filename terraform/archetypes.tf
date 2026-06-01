# =============================================================================
# Archetype configuration — declarative defaults & guardrails per archetype
# =============================================================================
# This is the ONLY file that needs to change to:
#   - add a new archetype
#   - tighten/loosen guardrails for an archetype
#   - change archetype-wide defaults (tags, budget thresholds, peering rules)
#
# Adding a new archetype:
#   1. Add an entry to local.archetype_config below
#   2. Add the matching MG ID to terraform.tfvars under management_group_ids
#   3. Create landingzones/<archetype>/ with at least one sub.yaml
# =============================================================================

locals {
  archetype_config = {
    # -------------------------------------------------------------------------
    # corp — internal workloads, mandatory hub peering when networking is on
    # -------------------------------------------------------------------------
    corp = {
      # Workload override; null = honour sub.yaml's workload field
      force_workload = null

      # Networking guardrails
      hub_peering_default     = true  # default if sub.yaml.network.hubPeering is unset
      hub_peering_allow_false = false # if false, attempts to disable peering are forced back on

      # Budget guardrails
      budget_required            = false
      budget_thresholds_actual   = [80]
      budget_thresholds_forecast = [100]

      # Tags appended to every sub in this archetype
      extra_tags = {
        archetype = "corp"
      }
    }

    # -------------------------------------------------------------------------
    # online — internet-facing workloads, hub peering optional
    # -------------------------------------------------------------------------
    online = {
      force_workload          = null
      hub_peering_default     = false
      hub_peering_allow_false = true

      budget_required            = false
      budget_thresholds_actual   = [80]
      budget_thresholds_forecast = [100]

      extra_tags = {
        archetype = "online"
      }
    }

    # -------------------------------------------------------------------------
    # sandbox — isolated dev/test, budget mandatory, never peers to hub
    # -------------------------------------------------------------------------
    # NOTE on workload: defaults to "Production" (always available on EA/MCA).
    # Set `workload: DevTest` in the sub.yaml to opt in to DevTest pricing —
    # this requires your EA/MCA billing scope to be entitled for the
    # Dev/Test offer (MS-AZR-0148P on EA, equivalent on MCA). See
    # docs/onboarding.md → "DevTest entitlement".
    sandbox = {
      force_workload          = null
      hub_peering_default     = false
      hub_peering_allow_false = true

      budget_required            = true
      budget_thresholds_actual   = [50, 90]
      budget_thresholds_forecast = [100]

      extra_tags = {
        archetype = "sandbox"
      }
    }
  }
}
