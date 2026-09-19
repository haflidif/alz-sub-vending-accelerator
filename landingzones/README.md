# Landing-zone subscription contracts

This folder is where **consumers** (app/workload teams, or platform
operators acting on their behalf) describe the subscriptions they want
vended. One subscription = one YAML file at
`landingzones/<archetype>/<sub-name>.yaml`.

> ✏️ **Quickstart for consumers:** see
> [`docs/first-vend.md`](../docs/first-vend.md) for the PR walkthrough.

## What lives here

| Path | What it is |
|---|---|
| [`sub.schema.json`](sub.schema.json) | The JSON Schema (Draft 2020-12) used by editors and CI. Both runtime engines add their own validation before deployment. |
| `corp/`, `online/`, `sandbox/` | One folder per archetype. The folder name must match the `archetype` field and the selected engine's archetype rules. |

## Naming

Subscription YAMLs follow `<env>-<archetype>-<workload>[-<seq>].yaml`.
Use lowercase letters and hyphens. The filename without `.yaml` becomes the
default `aliasName` and `displayName`. Full rules in
[`docs/naming-convention.md`](../docs/naming-convention.md).

Examples in this folder:
- `corp/prod-corp-erp-001.yaml`
- `online/prod-online-web-001.yaml`
- `sandbox/dev-sandbox-platform-001.yaml`

> ⚠️ **`aliasName` is effectively immutable** after the subscription
> exists. Pick carefully because renaming requires recreating the subscription.

## sub.yaml schema (TL;DR)

Required fields:
- `archetype`: Must be in the schema's `enum` (`corp`, `online`, or `sandbox`)
  and supported by the selected engine.
- `location`: Azure region, such as `westeurope`.
- `owner`: Business owner email or distribution list.

Most-used optional fields:
- `displayName`, `aliasName` — default to the filename stem.
- `technicalResponsible`, `costCenter`, `workloadName` — emitted as tags.
- `costAllocationCode`: Emitted under the cost-allocation tag configured by
  the platform operator. It can be required by platform policy.
- `billingScopeKey`: Selects a configured billing scope and defaults to
  `default`. See [`docs/billing-scopes.md`](../docs/billing-scopes.md).
- `workload` — `Production` (default) or `DevTest` (requires EA/MCA Dev/Test entitlement).
- `tags` — free-form tag map merged on top of governed layers. **Reserved keys** (identity, mandatory, archetype, cost-allocation) cannot appear here.
- `network` — `{ enabled, addressSpace, hubPeering, subnets }`. When `enabled: true`, `addressSpace` is required.
- `budget` — `{ amount, contacts }`. **Required for `sandbox`** (schema-enforced).
- `roleAssignments`: Map of `{ principal_id, role_definition_id_or_name, ... }`.
  Each runtime normalizes the shared request fields for its pinned AVM.
- `managedIdentity`: `{ name, resourceGroupName? }` to provision a UAMI
  alongside the subscription.

Full schema reference: [`docs/schema-validation.md`](../docs/schema-validation.md).

## Validation flow — what catches a typo where

| Stage | How | What you see on failure |
|---|---|---|
| **Editor** | The `# yaml-language-server: $schema=../sub.schema.json` directive at the top of every YAML | Red squiggles + hover hints in VS Code (requires the YAML extension). |
| **Pre-commit (optional)** | `pipx install check-jsonschema && check-jsonschema --schemafile landingzones/sub.schema.json landingzones/*/*.yaml` | Local error before you push. |
| **PR validation (CI)** | `schema-validate` runs on every PR touching `landingzones/` | The PR check fails and engine previews do not run on invalid data. |
| **Engine validation** | Terraform assertions or Bicep compiler validation | The preview fails with an engine-specific, actionable message. |

## Per-subscription isolation

Each YAML becomes one matrix item. Terraform stores it in an isolated state
key at `<container>/<archetype>/<sub-name>.tfstate`. Bicep uses a separate
management-group deployment for each request and has no Terraform state.
See [`docs/state-storage.md`](../docs/state-storage.md) for the Terraform
backend.

## Adding a new archetype

`corp`, `online`, and `sandbox` are the defaults. Adding `data`, for example,
requires coordinated shared and engine changes. See
[`docs/archetypes.md`](../docs/archetypes.md). The
short version:

1. Add the value to the schema's `properties.archetype.enum`.
2. Create `landingzones/<archetype>/`.
3. Add rules to the selected engine adapter.
4. Add the management-group ID to `terraform/terraform.auto.tfvars` or
   `bicep/platform.json` in the seeded repository.

## See also

- [`docs/first-vend.md`](../docs/first-vend.md) — vend your first sub
- [`docs/naming-convention.md`](../docs/naming-convention.md) — naming rules
- [`docs/schema-validation.md`](../docs/schema-validation.md) — full schema reference
- [`docs/archetypes.md`](../docs/archetypes.md) — archetype concept + add new ones
- [`docs/tagging.md`](../docs/tagging.md) — tag layering rules
- [`docs/billing-scopes.md`](../docs/billing-scopes.md) — per-sub `billingScopeKey`
- The selected engine's README: `terraform/README.md` or `bicep/README.md`
