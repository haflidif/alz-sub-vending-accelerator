# Architecture

This document describes how subscription vending works end-to-end in this repo.

## Components

```text
                    ┌─────────────────────────────────────────────┐
                    │            Pull Request opened              │
                    │  Adds/edits landingzones/<archetype>/       │
                    │              <sub-name>.yaml                │
                    └────────────────┬────────────────────────────┘
                                     │
                                     ▼
                    ┌─────────────────────────────────────────────┐
                    │ pr-validate.yml — discover changed subs     │
                    │  → matrix job: terraform plan per sub       │
                    │  → posts plan as PR comment                 │
                    └────────────────┬────────────────────────────┘
                                     │ merge to main
                                     ▼
                    ┌─────────────────────────────────────────────┐
                    │ apply.yml — discover changed subs           │
                    │  → matrix job: terraform apply per sub      │
                    │  → uses GitHub Environment "production"     │
                    │    for required-reviewer approval           │
                    └────────────────┬────────────────────────────┘
                                     │
                                     ▼
                    ┌─────────────────────────────────────────────┐
                    │  Azure/avm-ptn-alz-sub-vending/azure         │
                    │   • creates subscription alias              │
                    │   • associates with management group        │
                    │   • registers resource providers            │
                    │   • peers to hub (corp/online if enabled)   │
                    │   • applies tags, RBAC, budget, UMI         │
                    └─────────────────────────────────────────────┘
```

## Single-folder Terraform layout

```text
terraform/
├── archetypes.tf      # Declarative archetype defaults & guardrails (data only)
├── backend.tf         # azurerm backend, partial config (key set per-sub at init)
├── locals.tf          # Parses the sub YAML + applies archetype guardrails
├── main.tf            # ONE call to Azure/avm-ptn-alz-sub-vending/azure
├── outputs.tf
├── providers.tf
├── variables.tf       # Platform inputs (tenant, billing scope, MG IDs, hub VNet)
└── versions.tf
```

There are **no per-archetype Terraform modules**. All archetype behaviour is
data in `archetypes.tf`; the engine in `locals.tf` and `main.tf` is generic.

### Why this layout

| Goal | How it's achieved |
|---|---|
| DRY | One AVM module call. Archetype rules are data, not code |
| Per-subscription state | `terraform init -backend-config="key=<archetype>/<sub>.tfstate"` per CI job |
| Add new archetype | Append to `local.archetype_config` in `archetypes.tf` + add MG ID |
| Add new sub | New `landingzones/<archetype>/<sub-name>.yaml`, open PR |
| Wide upgrade (e.g. bump module version) | `apply.yml` `workflow_dispatch` with `mode=all` |
| Guardrails | Archetype config can force workload, force hub peering, require budget |

## sub YAML schema

Each subscription is described by a single flat file at
`landingzones/<archetype>/<sub-name>.yaml`. The filename (minus `.yaml`)
becomes the default `aliasName` and `displayName`.

| Key                  | Required | Type       | Notes |
|----------------------|----------|------------|-------|
| `archetype`          | yes      | string     | One of `corp`, `online`, `sandbox` |
| `location`           | yes      | string     | Azure region; **no default** |
| `owner`              | yes      | string     | Email/DL — emitted as `businessowner` tag, used for budget alerts |
| `costAllocationCode` | cond.    | string     | Operator-configurable (see [tagging.md](tagging.md)). Required only when `cost_allocation_required = true` at bootstrap. |
| `displayName`        | no       | string     | Defaults to filename (without `.yaml`) |
| `aliasName`          | no       | string     | Defaults to filename (without `.yaml`); **immutable after creation** |
| `workload`           | no       | string     | `Production` (default — always available) or `DevTest` (requires EA/MCA Dev/Test entitlement) |
| `costCenter`         | no       | string     | Stamped as `costcenter` tag |
| `billingScopeKey`    | no       | string     | Selects an entry from `billing_scopes`; defaults to `default`. See [billing-scopes.md](billing-scopes.md). |
| `tags`                 | no       | map      | Free-form tags merged BELOW mandatory + archetype + identity tags. Reserved keys rejected at plan time. |
| `technicalResponsible` | no       | string   | Email; emitted as `technicalcontact` tag. Defaults to `owner` |
| `workloadName`         | no       | string   | Free-text workload/service name; emitted as `workloadname` tag. Defaults to `aliasName` |
| `network.enabled`      | no       | bool     | Default `false` |
| `network.addressSpace` | no       | list     | CIDRs for the spoke VNet |
| `network.hubPeering`   | no       | bool     | corp forces `true`; online/sandbox default per archetype config |
| `network.subnets`      | no       | map      | Passed through to the AVM module |
| `budget.amount`        | cond.    | number   | Required for sandbox; optional otherwise |
| `budget.contacts`      | no       | list     | Extra emails (owner is added automatically) |
| `roleAssignments`      | no       | map      | Passed straight to AVM `role_assignments` |
| `managedIdentity`      | no       | object   | `{ name, resourceGroupName? }` to create a UMI |

## Tag layering

Tag names match the platform LZ (`alz-core/platform-landing-zone.auto.tfvars`)
so cross-boundary tooling and reporting works seamlessly.

Merged in this order (later wins on conflict — governed tags ALWAYS win):

```
caller tags            (sub YAML `tags` map — free-form, reserved keys rejected)
   ↓
mandatory_tags         managedby, source, deployedby (CAF defaults)
   ↓
archetype.extra_tags   archetype = corp | online | sandbox
   ↓
identity_tags          businessowner, technicalcontact,
                       costcenter, workloadname, environment,
                       <cost_allocation_tag_key> (when set)
```

See [docs/tagging.md](tagging.md) for the full CAF baseline and customization
guide.

## State storage

- **Same storage account** as the platform's Terraform state, **dedicated container** `subvending-tfstate`
- Per-subscription state key: `<archetype>/<sub-name>.tfstate`
- Container-scoped RBAC: pipeline SPN gets **Storage Blob Data Contributor** on this container only
- See [state-storage.md](state-storage.md)

## Module reference

This repo wraps **`Azure/avm-ptn-alz-sub-vending/azure`**, pinned to `0.3.1`
exact in [`terraform/main.tf`](../terraform/main.tf) (no upper-bound
constraint — every bump is an explicit, reviewed change because the AVM
module's input contract is still pre-1.0). The mapping from the sub YAML
to AVM inputs lives in `terraform/locals.tf`. The full upstream input
reference: <https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure/latest>.
