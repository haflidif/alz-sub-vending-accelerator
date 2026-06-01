# Landing zones — subscription contracts

This folder is where **consumers** (app/workload teams, or platform
operators acting on their behalf) describe the subscriptions they want
vended. One subscription = one YAML file at
`landingzones/<archetype>/<sub-name>.yaml`.

> ✏️ **Quickstart for consumers:** see
> [`docs/first-vend.md`](../docs/first-vend.md) — the 4-step PR walkthrough.

## What lives here

| Path | What it is |
|---|---|
| [`sub.schema.json`](sub.schema.json) | The JSON Schema (Draft 2020-12) that every sub YAML is validated against — in your editor (via the `# yaml-language-server` directive), in CI (`schema-validate` job), and at `terraform plan` time (`_assert_*` belt-and-suspenders). |
| `corp/`, `online/`, `sandbox/` | One folder per archetype. Each contains the YAML contracts for subscriptions in that archetype. The folder name MUST match the `archetype` field inside each YAML file (and an entry in `terraform/archetypes.tf`). |

## Naming

Subscription YAMLs follow `<env>-<archetype>-<workload>[-<seq>].yaml` —
all lowercase, hyphen-separated. The filename (minus `.yaml`) becomes the
default `aliasName` and `displayName`. Full rules in
[`docs/naming-convention.md`](../docs/naming-convention.md).

Examples in this folder:
- `corp/prod-corp-erp-001.yaml`
- `online/prod-online-web-001.yaml`
- `sandbox/dev-sandbox-platform-001.yaml`

> ⚠️ **`aliasName` is effectively immutable** after the subscription
> exists. Pick carefully — renaming requires recreating the subscription.

## sub.yaml schema (TL;DR)

Required fields:
- `archetype` — must be in the schema's `enum` (`corp` / `online` / `sandbox`) AND a key in `terraform/archetypes.tf`.
- `location` — Azure region (e.g. `westeurope`).
- `owner` — business owner email or DL.

Most-used optional fields:
- `displayName`, `aliasName` — default to the filename stem.
- `technicalResponsible`, `costCenter`, `workloadName` — emitted as tags.
- `costAllocationCode` — emitted as the tag whose KEY the operator set in `cost_allocation_tag_key`. Required when `cost_allocation_required = true`.
- `billingScopeKey` — picks an entry from `billing_scopes` (default key: `default`). See [`docs/billing-scopes.md`](../docs/billing-scopes.md).
- `workload` — `Production` (default) or `DevTest` (requires EA/MCA Dev/Test entitlement).
- `tags` — free-form tag map merged on top of governed layers. **Reserved keys** (identity, mandatory, archetype, cost-allocation) cannot appear here.
- `network` — `{ enabled, addressSpace, hubPeering, subnets }`. When `enabled: true`, `addressSpace` is required.
- `budget` — `{ amount, contacts }`. **Required for `sandbox`** (schema-enforced).
- `roleAssignments` — map of `{ principal_id, role_definition_id_or_name, ... }` passed straight to the AVM module.
- `managedIdentity` — `{ name, resourceGroupName? }` to provision a UAMI alongside the subscription.

Full schema reference: [`docs/schema-validation.md`](../docs/schema-validation.md).

## Validation flow — what catches a typo where

| Stage | How | What you see on failure |
|---|---|---|
| **Editor** | The `# yaml-language-server: $schema=../sub.schema.json` directive at the top of every YAML | Red squiggles + hover hints in VS Code (requires the YAML extension). |
| **Pre-commit (optional)** | `pipx install check-jsonschema && check-jsonschema --schemafile landingzones/sub.schema.json landingzones/*/*.yaml` | Local error before you push. |
| **PR validation (CI)** | `schema-validate` job in `.github/workflows/pr-validate.yml` runs on every PR touching `landingzones/` | PR check fails; `plan` jobs do **not** run on invalid data. |
| **`terraform plan`** | Belt-and-suspenders `_assert_*` checks in `terraform/locals.tf` | Plan fails with a clear missing-field / wrong-archetype / collision message. |

## Per-subscription state isolation

Each YAML produces its own Terraform state at
`<container>/<archetype>/<sub-name>.tfstate`. A broken PR cannot churn
the plan of an unrelated subscription — see
[`docs/state-storage.md`](../docs/state-storage.md).

## Adding a new archetype

`corp` / `online` / `sandbox` are the defaults. Adding e.g. `data` is a
4-file PR — see [`docs/archetypes.md`](../docs/archetypes.md). The
short version:

1. Add the value to the schema's `properties.archetype.enum`.
2. Create `landingzones/<archetype>/`.
3. Append an entry to `local.archetype_config` in `terraform/archetypes.tf`.
4. Add the MG ID to `terraform/terraform.auto.tfvars` `management_group_ids`
   (in the seeded repo).

## See also

- [`docs/first-vend.md`](../docs/first-vend.md) — vend your first sub
- [`docs/naming-convention.md`](../docs/naming-convention.md) — naming rules
- [`docs/schema-validation.md`](../docs/schema-validation.md) — full schema reference
- [`docs/archetypes.md`](../docs/archetypes.md) — archetype concept + add new ones
- [`docs/tagging.md`](../docs/tagging.md) — tag layering rules
- [`docs/billing-scopes.md`](../docs/billing-scopes.md) — per-sub `billingScopeKey`
- [`terraform/README.md`](../terraform/README.md) — what the engine does with this YAML
