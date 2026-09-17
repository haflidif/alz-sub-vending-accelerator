# Terraform engine

This folder is the **vending engine** — the single Terraform root that
turns one `landingzones/<archetype>/<sub>.yaml` into one Azure
subscription. CI invokes this root once per affected subscription, each
with its own state file.

> ✏️ **You do not need to edit this folder to vend a subscription.**
> Authoring `sub.yaml` files under `landingzones/` is enough. This README
> is the reference for whoever maintains the engine itself.

## How a single run looks

```
                          ┌──────────────────────────────────────┐
sub.yaml ─── locals.tf ───┤ Parse YAML, apply archetype defaults │
                          │ + run all _assert_* guardrails       │
                          └────────────────┬─────────────────────┘
                                           │
                          ┌────────────────▼─────────────────────┐
terraform.auto.tfvars ───▶│  Platform context (tenant, MGs,      │
(rendered by bootstrap)   │  billing scopes, hub VNet, tags)     │
                          └────────────────┬─────────────────────┘
                                           │
                          ┌────────────────▼─────────────────────┐
                          │  ONE module call →                   │
                          │  Azure/avm-ptn-alz-sub-vending/azure │
                          │  pinned to v0.3.1                    │
                          └──────────────────────────────────────┘
```

## File-by-file

| File | Purpose | Edit when… |
|---|---|---|
| [`main.tf`](main.tf) | The **single** `module "subscription"` call into `Azure/avm-ptn-alz-sub-vending/azure` (pinned to `0.3.1` exact). All inputs are pulled from `locals.tf`. | Bumping the AVM module version (always test with `mode=all` first), or exposing a new AVM input. |
| [`archetypes.tf`](archetypes.tf) | Declarative table `local.archetype_config` — per-archetype defaults and guardrails: `force_workload`, `hub_peering_default`, `hub_peering_allow_false`, `budget_required`, `budget_thresholds_*`, `extra_tags`. **This is the only file you change to add or tighten an archetype.** | Adding a new archetype, tightening sandbox budget thresholds, forcing corp to peer to hub, etc. See [`docs/archetypes.md`](../docs/archetypes.md). |
| [`locals.tf`](locals.tf) | The heavy lifter: parses `sub.yaml`, runs `_assert_*` guardrails (required fields, known archetype, valid `billingScopeKey`, no caller-tag collisions, sandbox requires budget, cost-allocation regex), resolves archetype config + identity tags, computes the final `module "subscription"` input set. | Adding a new optional YAML field (also update the JSON Schema in `landingzones/sub.schema.json`), changing the tag-layering rules, or adding a new guardrail. |
| [`variables.tf`](variables.tf) | Platform context shared across **every** sub vended from this repo: `tenant_id`, `vending_subscription_id`, `billing_scopes` (map), `management_group_ids` (map per archetype), `hub_virtual_network_resource_id`, `cost_allocation_tag_key` / `_required` / `_pattern`, `mandatory_tags`. Carries validation rules (e.g. `billing_scopes` must contain `default`, hub VNet ID must be a full resource ID). Plus the per-run input `sub_yaml_path`. | Adding a new platform-wide knob (also extend `bootstrap/variables.tf` and `bootstrap/files.tf` so it lands in `terraform.auto.tfvars` automatically). |
| [`outputs.tf`](outputs.tf) | `subscription_id`, `subscription_resource_id`, `archetype`, `alias_name`, `management_group_id`, `effective_tags`. Consumed by downstream automation (e.g. budget dashboards, audit logs). | Exposing a new value from the AVM module to downstream tooling. |
| [`providers.tf`](providers.tf) | `azurerm` (pinned to platform sub) + `azapi` (tenant-pinned, used by the AVM module). `storage_use_azuread = true` so the backend uses Entra-ID auth. | Adding a new provider (rare — the AVM module already imports azapi/azurerm). |
| [`versions.tf`](versions.tf) | Terraform Core `>= 1.10.0, < 2.0.0`, matching the AVM subscription-vending module, with exact provider pins: `azurerm 4.74.0`, `azapi 2.10.0`, and `random 3.9.0`. CI remains pinned to one tested 1.x release for reproducibility. | Bumping Terraform Core or provider versions. Keep the minimum aligned with the selected AVM module. |
| [`backend.tf`](backend.tf) | Partial `backend "azurerm"` (only `use_azuread_auth = true`). Every `terraform init` supplies `resource_group_name`, `storage_account_name`, `container_name`, and **`key`** as `-backend-config=` flags so each subscription has its own state file. | Almost never. |
| `terraform.auto.tfvars` | **Not in the skeleton.** Rendered by `bootstrap/files.tf` and committed to the **seeded** repo only. Carries platform context filled in from operator inputs (tenant ID, billing scopes, MG IDs, hub VNet, cost-allocation tag, mandatory tags). | Day-2 changes — edit it in the seeded repo via PR. The bootstrap is one-shot and is NOT re-run to rotate these values. See [`docs/onboarding.md → "Updating platform inputs after bootstrap"`](../docs/onboarding.md#updating-platform-inputs-after-bootstrap). |

## The AVM module — what we hand it

We call `Azure/avm-ptn-alz-sub-vending/azure` once. The exact inputs we
supply are in `main.tf`; all derivations live in `locals.tf`. Headline
mappings:

| AVM input | Sourced from |
|---|---|
| `subscription_alias_name` / `_display_name` | `aliasName` / `displayName` in `sub.yaml`, defaulting to the filename stem |
| `subscription_workload` | `local.arch.force_workload` (archetype override) **or** `sub.yaml.workload` (default `Production`) |
| `subscription_billing_scope` | `var.billing_scopes[sub.yaml.billingScopeKey]` (default key `default`) |
| `subscription_management_group_id` | `var.management_group_ids[sub.yaml.archetype]`, with full resource IDs auto-stripped to bare MG names |
| `subscription_tags` | `merge(caller_tags, mandatory_tags, archetype.extra_tags, identity_tags)` — governed layers always win |
| `resource_groups` | `{rg-<alias>-network, NetworkWatcherRG}` when networking is enabled; empty otherwise |
| `virtual_networks` | `{spoke: {hub peering applied per archetype}}` when `network.enabled = true`; empty otherwise |
| `budgets` | One `monthly` budget when `sub.yaml.budget` is present, with thresholds + contacts derived from `archetype_config.budget_thresholds_*` |
| `role_assignments` | Passed through from `sub.yaml.roleAssignments` |
| `user_managed_identities` | Single `primary` UMI when `sub.yaml.managedIdentity` is set |

Full upstream input reference:
<https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure/latest>.

## Guardrails enforced at plan time

`locals.tf` runs a series of `_assert_*` checks that throw a clear error
before Terraform reaches the AVM module:

- `_assert_archetype` / `_assert_location` / `_assert_owner` — required fields present.
- `_assert_known_archetype` — value matches a key in `archetype_config`.
- `_assert_cost_alloc_required` — `costAllocationCode` present when operator-required.
- `_assert_cost_alloc_pattern` — value matches the operator-configured regex.
- `_assert_billing_scope_key` — `sub.yaml.billingScopeKey` exists in `billing_scopes`.
- `_assert_mg` — `management_group_ids` has an entry for the archetype.
- `_assert_no_caller_tag_collision` — `sub.yaml.tags` doesn't override a governed key.
- `_assert_budget` — sandbox subs declare a budget.

All errors point at the offending `sub_yaml_path`, name the missing /
conflicting field, and (where helpful) list the valid set of values.

## Running locally

You normally don't need to run this folder by hand — CI handles all
plan/apply via `.github/workflows/*`. Break-glass plan:

```powershell
cd terraform

az login --tenant <your-tenant-id>

terraform init `
  -backend-config="resource_group_name=<BACKEND_RESOURCE_GROUP_NAME>" `
  -backend-config="storage_account_name=<BACKEND_STORAGE_ACCOUNT_NAME>" `
  -backend-config="container_name=subvending-tfstate" `
  -backend-config="key=corp/prod-corp-erp-001.tfstate"

# terraform.auto.tfvars auto-loads platform context
terraform plan -var="sub_yaml_path=../landingzones/corp/prod-corp-erp-001.yaml"
```

> ⚠️ **State** lives at `<container>/<archetype>/<sub>.tfstate`. Each
> subscription has its own blob — running plan/apply for one sub cannot
> touch another's state.

## See also

- [`docs/architecture.md`](../docs/architecture.md) — high-level design
- [`docs/archetypes.md`](../docs/archetypes.md) — adding/modifying an archetype
- [`docs/schema-validation.md`](../docs/schema-validation.md) — what the YAML schema enforces
- [`docs/state-storage.md`](../docs/state-storage.md) — backend container + per-sub key
- [`docs/tagging.md`](../docs/tagging.md) — tag layering rules
- [`docs/billing-scopes.md`](../docs/billing-scopes.md) — `billing_scopes` map and per-sub `billingScopeKey`
- [`landingzones/README.md`](../landingzones/README.md) — consumer-facing reference for `sub.yaml`
