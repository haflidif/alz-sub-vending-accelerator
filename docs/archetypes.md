# Archetypes

An **archetype** is a class of subscription with shared defaults and guardrails.
The set of available archetypes is defined in
[`terraform/archetypes.tf`](../terraform/archetypes.tf) — it's pure data, no code.

## Built-in archetypes

### `corp`

**Internal workloads.** Mandatory hub peering when networking is enabled —
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

**Internet-facing workloads.** Hub peering is optional — many online workloads
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
| Budget required | **yes** — `terraform plan` fails without it |
| Budget alerts | actual ≥ 50%, actual ≥ 90%, forecast ≥ 100% |

> **DevTest entitlement** — Opting in to `workload: DevTest` requires the
> EA/MCA billing scope to be entitled for the Dev/Test offer (`MS-AZR-0148P`
> on EA). If the enrollment isn't enabled the AVM module returns
> `EntitlementNotFound`. Defaulting to `Production` works on every billing
> scope.

Use for: spikes, prototypes, training labs, integration tests.
Sub.yaml authors should set an `expiry` tag for cleanup automation.

## Adding a new archetype

The vending repo is the source of truth post-bootstrap. Day-2 archetype
changes are a regular PR — **do not** re-run the bootstrap module (its state
is one-shot and local to the operator workstation that ran it).

1. Open `terraform/archetypes.tf` and add a new entry to `local.archetype_config`:

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

2. Add the matching MG ID directly to the seeded repo's
   `terraform/terraform.auto.tfvars` (`management_group_ids` map):

   ```hcl
   management_group_ids = {
     corp     = "..."
     online   = "..."
     sandbox  = "..."
     identity = "/providers/Microsoft.Management/managementGroups/mycompany-identity"
   }
   ```

   > The pipeline UAMI must already have the right RBAC at the parent MG
   > scope. If the new archetype lives outside the original
   > `alz_root_management_group_id` from the bootstrap, grant Management
   > Group Contributor (and User Access Administrator if you use
   > `roleAssignments` in sub.yaml files) on the new scope **manually** —
   > the bootstrap will not back-fill these.

3. Create `landingzones/<archetype>/` and add at least one example YAML file.

4. Add the new value to `properties.archetype.enum` in
   [`landingzones/sub.schema.json`](../landingzones/sub.schema.json).

5. Update `.github/CODEOWNERS` with the owners of the new archetype folder.

Open the PR. Merge triggers `apply.yml` for any sub.yaml in the new folder
that the PR also added.

## Modifying an existing archetype

Edit the relevant entry in `terraform/archetypes.tf`. Treat with care: any
change re-plans every existing subscription in that archetype on next apply.

Recommended PR checklist:
- [ ] `workflow_dispatch` of `apply.yml` with `mode=all` in a non-prod tenant first
- [ ] Plan output reviewed by platform lead
- [ ] Communicated to subscription owners listed in affected YAML files
