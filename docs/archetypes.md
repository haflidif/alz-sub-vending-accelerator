# Archetypes

An **archetype** is a class of subscription with shared defaults and
guardrails. Terraform defines the rules in `terraform/archetypes.tf`. Bicep
defines the equivalent rules in the `$archetypes` map in
`bicep/SubscriptionVending.Bicep.psm1`.

## Built-in archetypes

### `corp`

**Internal workloads.** Mandatory hub peering when networking is enabled.
this is the standard pattern for line-of-business systems that need to reach
on-prem or shared services through the platform hub.

| Setting | Value |
|---|---|
| Forced workload | none (caller chooses) |
| Hub peering default | `true` |
| Allow `hubPeering: false` | **no** (forced back to `true`) |
| Budget required | no (recommended) |
| Budget alerts | actual ≥ 80%, forecast ≥ 100% |

Use for: ERP, CRM, internal APIs, data platforms, AD/identity-bound apps.

### `online`

**Internet-facing workloads.** Hub peering is optional. Many online workloads
run isolated and use App Gateway / Front Door / CDN for ingress instead of
traversing the hub.

| Setting | Value |
|---|---|
| Forced workload | none |
| Hub peering default | `false` |
| Allow `hubPeering: false` | yes |
| Budget required | no (recommended) |
| Budget alerts | actual ≥ 80%, forecast ≥ 100% |

Use for: public web apps, customer portals, public APIs, marketing sites.

### `sandbox`

**Short-lived dev/test workloads.** Strict guardrails to prevent runaway cost
and to keep experiments off the production network.

| Setting | Value |
|---|---|
| Workload default | `Production` (always available). Set `workload: DevTest` in sub.yaml to opt in. |
| Hub peering default | `false` |
| Allow `hubPeering: false` | yes (it's never on) |
| Budget required | **yes**. Engine validation fails without it |
| Budget alerts | actual ≥ 50%, actual ≥ 90%, forecast ≥ 100% |

> **DevTest entitlement:** Opting in to `workload: DevTest` requires the
> EA/MCA billing scope to be entitled for the Dev/Test offer (`MS-AZR-0148P`
> on EA). If the enrollment is not enabled, the selected AVM returns
> `EntitlementNotFound`. Defaulting to `Production` works on every billing
> scope.

Use for: spikes, prototypes, training labs, integration tests.
Sub.yaml authors should set an `expiry` tag for cleanup automation.

## Adding a new archetype

The vending repo is the source of truth post-bootstrap. Day-2 archetype
changes are a regular PR. **Do not** re-run the bootstrap module because its state
is one-shot and local to the operator workstation that ran it).

1. Add the new rules to `terraform/archetypes.tf`. If the Bicep starter must
   support the archetype, add the equivalent entry to the `$archetypes` map in
   `bicep/SubscriptionVending.Bicep.psm1`.

   ```hcl
   identity = {
     force_workload          = "Production"
     hub_peering_default     = true
     hub_peering_allow_false = false
     budget_required         = false
     budget_thresholds_actual    = [80]
     budget_thresholds_forecast  = [100]
     extra_tags = { environment = "identity" }
   }
   ```

   The equivalent Bicep compiler entry uses the supported PowerShell keys:

   ```powershell
   identity = @{
     HubPeeringDefault = $true
     HubPeeringAllowFalse = $false
     BudgetRequired = $false
     BudgetActualThresholds = @(80)
     BudgetForecastThresholds = @(100)
   }
   ```

   If the new archetype needs behavior that is not represented in the Bicep
   map, extend the compiler and its tests rather than silently dropping the
   rule.

2. Add the matching MG ID directly to the selected engine configuration:
   `terraform/terraform.auto.tfvars` (`management_group_ids`) or
   `bicep/platform.json` (`managementGroupIds`).

   ```hcl
   management_group_ids = {
     corp     = "..."
     online   = "..."
     sandbox  = "..."
     identity = "/providers/Microsoft.Management/managementGroups/mycompany-identity"
   }
   ```

   ```json
   {
     "managementGroupIds": {
       "corp": "...",
       "online": "...",
       "sandbox": "...",
       "identity": "/providers/Microsoft.Management/managementGroups/mycompany-identity"
     }
   }
   ```

   > The pipeline UAMI must already have the right RBAC at the parent MG
   > scope. If the new archetype lives outside the original
   > `alz_root_management_group_id` from the bootstrap, grant Management
   > Group Contributor and, if needed, User Access Administrator on the new
   > scope **manually**. The bootstrap does
   > the bootstrap will not back-fill these.

3. Create `landingzones/<archetype>/` and add at least one example YAML file.

4. Add the new value to `properties.archetype.enum` in
   [`landingzones/sub.schema.json`](../landingzones/sub.schema.json).

5. Update `.github/CODEOWNERS` with the owners of the new archetype folder.

Open the PR. Merge triggers `apply.yml` for any sub.yaml in the new folder
that the PR also added.

## Modifying an existing archetype

Edit the relevant engine rule. Treat with care because a runtime engine change
selects every request in the repository for preview. After merge, deployment
is intentionally deferred until an operator runs Apply with `mode=all`.

Recommended PR checklist:
- [ ] `workflow_dispatch` of `apply.yml` with `mode=all` in a non-prod tenant first
- [ ] Terraform plan or Bicep what-if reviewed by the platform lead
- [ ] Communicated to subscription owners listed in affected YAML files
